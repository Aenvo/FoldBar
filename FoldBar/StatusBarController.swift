import AppKit
import OSLog
import ServiceManagement

@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 45
    private static var collapsedItemPollMilliseconds: Int {
        MenuBarPollingPolicy.collapsedIntervalMilliseconds(
            usesAccessibilityBackend: MenuBarItemScanner.usesAccessibilityBackend
        )
    }
    private static let maximumAutomaticPlacementBatch = 2
    private static let automaticPlacementStabilizationMilliseconds = 10_000
    private static let automaticPlacementRetryDelaysMilliseconds = [2_000]
    private static let promotionConfirmationPolls = 3
    private static let activationPresentationPolls = 60
    private static let privateActivationSettleMilliseconds = 200
    private static let toggleAutosaveName = "foldbar_toggle"
    private static let separatorAutosaveName = "foldbar_separator"
    private static let promotionLogger = Logger(
        subsystem: "local.foldbar.app",
        category: "Promotion"
    )
    private static let importLogger = Logger(
        subsystem: "local.foldbar.app",
        category: "Import"
    )

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = OverflowPanel()
    private let expandedMenuBarPanel = ExpandedMenuBarPanel()
    private let settingsPanel = AppearanceSettingsPanel()
    private let visibilityRestriction = MenuBarVisibilityRestriction()

    private var initialCollapseTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var autoCollapseMonitor: Any?
    private var cacheCaptureTask: Task<Void, Never>?
    private var importCandidateRefreshTask: Task<Void, Never>?
    private var importPreviewPrefetchTask: Task<Void, Never>?
    private var externalDragCaptureTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var promotionTask: Task<Void, Never>?
    private var collapsedItemMonitorTask: Task<Void, Never>?
    private var automaticPlacementTask: Task<Void, Never>?
    private var externalDragItemID: CGWindowID?
    private var importPreviewCache = MenuBarImportPreviewCache<NSImage>()
    private var backgroundCaptureRetryPolicy = MenuBarCaptureRetryPolicy()
    private var cachedItems: [CapturedItem] = []
    private var cachedPrivateBundleIdentifiers: Set<String> {
        Set(cachedItems.map { $0.window.bundleIdentifier })
            .intersection(managedBundleIdentifiers)
    }
    private var knownManagedWindowIDs: Set<CGWindowID> = []
    private var managedBundleIdentifiers = ManagedMenuBarBundles.load()
    private var isImportTargetingToggle = false
    private var preparingCollapse = false
    private var permissionFlowActive = false
    private(set) var isCollapsed = false

    private lazy var menuBarImportMonitor = MenuBarCommandDragMonitor(
        onBegin: { [weak self] item, point in
            self?.beginExternalDrag(item, at: point)
        },
        onUpdate: { [weak self] point, target in
            self?.updateExternalDrag(at: point, target: target)
        },
        onEnd: { [weak self] item, point, target in
            self?.finishExternalDrag(item, at: point, target: target)
        },
        onClick: { [weak self] item, point in
            self?.replayExternalClick(item, at: point)
        }
    )

    init() {
        if let saved = MenuBarArrangement.saved() {
            _ = MenuBarArrangement.restore(saved)
        }

        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position \(Self.toggleAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(Self.separatorAutosaveName)"
        let storedToggle = defaults.object(forKey: toggleKey) as? Double
        let storedSeparator = defaults.object(forKey: separatorKey) as? Double

        let positions: (toggle: Double, separator: Double)
        if let toggle = storedToggle,
           let separator = storedSeparator,
           Self.isSanePair(toggle: toggle, separator: separator) {
            positions = (toggle, separator)
        } else if let toggle = MenuBarArrangement.savedOwnPosition(toggleKey),
                  let separator = MenuBarArrangement.savedOwnPosition(separatorKey),
                  Self.isSanePair(toggle: toggle, separator: separator) {
            positions = (toggle, separator)
        } else {
            positions = (250, 265)
        }
        defaults.set(positions.toggle, forKey: toggleKey)
        defaults.set(positions.separator, forKey: separatorKey)

        let registersLegacySeparator = Self.registersLegacySeparator(
            for: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )

        // Create the always-visible trigger first, then the legacy separator to
        // its left. macOS 27 supplies its own overflow boundary, so unregister
        // the second scene before the first run-loop presentation instead of
        // leaving Control Center's unavoidable 16-point outer slot behind.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = Self.toggleAutosaveName
        separatorItem = NSStatusBar.system.statusItem(
            withLength: registersLegacySeparator ? NSStatusItem.variableLength : 0
        )
        separatorItem.autosaveName = Self.separatorAutosaveName

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "FoldBar"
        }
        if registersLegacySeparator {
            // The separator is a layout boundary, not a user-facing control.
            // Keep its image as the variable-length sizing reference, but do
            // not render the K-like glyph in the menu bar.
            separatorItem.button?.image = symbol("chevron.left.to.line")
            separatorItem.button?.alphaValue = 0
        } else {
            NSStatusBar.system.removeStatusItem(separatorItem)
        }
        settingsPanel.onLanguageChange = { [weak self] in
            self?.updateToggleIcon()
            self?.expandedMenuBarPanel.refreshLocalizedText()
        }
        updateToggleIcon()
        scheduleInitialCollapse()
        schedulePermissionOnboarding()
    }

    static func isSanePair(toggle: Double, separator: Double) -> Bool {
        MenuBarArrangement.isValid(toggle)
            && MenuBarArrangement.isValid(separator)
            && toggle > 0
            && separator > toggle
    }

    nonisolated static func registersLegacySeparator(for majorVersion: Int) -> Bool {
        !MenuBarItemScanner.usesAccessibilityBackend(for: majorVersion)
    }

    nonisolated static func usesPrivateVisibilityRestriction(
        for majorVersion: Int
    ) -> Bool {
        MenuBarVisibilityRestriction.isSupported(on: majorVersion)
    }

    func expandForQuit() {
        initialCollapseTask?.cancel()
        cacheCaptureTask?.cancel()
        collapsedItemMonitorTask?.cancel()
        collapsedItemMonitorTask = nil
        automaticPlacementTask?.cancel()
        automaticPlacementTask = nil
        activationTask?.cancel()
        activationTask = nil
        promotionTask?.cancel()
        promotionTask = nil
        preparingCollapse = false
        isCollapsed = false
        disarmAutoCollapse()
        disarmMenuBarImport()
        panel.close()
        expandedMenuBarPanel.close()
        visibilityRestriction.invalidate()
        // Promotion and proxy activation can temporarily reduce FoldBar's own
        // status-item lengths beside a notch. Quitting restores both immediately.
        if !MenuBarItemScanner.usesAccessibilityBackend {
            separatorItem.length = NSStatusItem.variableLength
        }
        toggleItem.length = NSStatusItem.variableLength
    }

    private func scheduleInitialCollapse() {
        initialCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(700))) != nil else { return }
            var last = Set<String>()
            var stable = 0

            for _ in 0..<Self.initialMaxPolls {
                guard let self, !self.isCollapsed, !Task.isCancelled else { return }
                await MenuBarItemScanner.refreshStatusWindows()
                let current = MenuBarItemScanner.statusItemFingerprint()
                if current == last {
                    stable += 1
                    if stable >= Self.initialStablePolls {
                        self.collapse()
                        return
                    }
                } else {
                    last = current
                    stable = 0
                }
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            }
            self?.collapse()
        }
    }

    private func toggle() {
        // Do not start a second visibility transition while a click or
        // membership change is still resolving its live target.
        guard activationTask == nil, promotionTask == nil else { return }
        if isCollapsed {
            if expandedMenuBarPanel.isVisible {
                expandedMenuBarPanel.close()
                updateToggleIcon()
            } else {
                panel.isVisible ? panel.close() : openPanel()
            }
        } else {
            automaticPlacementTask?.cancel()
            automaticPlacementTask = nil
            collapse()
        }
    }

    private func collapse() {
        guard !isCollapsed, !preparingCollapse else { return }
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        disarmCollapsedItemMonitor()
        panel.close()
        expandedMenuBarPanel.close()

        if MenuBarItemScanner.usesAccessibilityBackend {
            collapseUsingPrivateVisibilityRestriction()
            return
        }

        let windows: [MenuBarItemWindow]
        if let separatorFrame = separatorItem.button?.window?.frame {
            windows = MenuBarItemScanner.itemsLeft(of: MenuBarCommandDragMonitor.quartzFrame(
                fromAppKit: separatorFrame,
                mainDisplayBounds: CGDisplayBounds(CGMainDisplayID())
            ))
        } else {
            windows = []
        }
        let knownIDs = Set(windows.map(\.id))

        guard IconCapturer.hasPermission() else {
            if MenuBarItemScanner.usesAccessibilityBackend {
                cachedItems = []
                separatorItem.length = NSStatusItem.variableLength
                isCollapsed = false
                updateToggleIcon()
                return
            }
            completeCollapse(knownManagedWindowIDs: knownIDs)
            return
        }
        guard !windows.isEmpty else {
            if windows.isEmpty { cachedItems = [] }
            completeCollapse(knownManagedWindowIDs: knownIDs)
            return
        }

        // Capture while the real items are already visible. The panel can then
        // open from memory with no flash-expand and no ScreenCaptureKit wait.
        preparingCollapse = true
        cacheCaptureTask?.cancel()
        cacheCaptureTask = Task { @MainActor [weak self] in
            let captured = await IconCapturer.capture(windows)
            guard let self, !Task.isCancelled, !self.isCollapsed else { return }
            if !captured.isEmpty || windows.isEmpty {
                self.cachedItems = captured
            }
            self.completeCollapse(knownManagedWindowIDs: knownIDs)
        }
    }

    private func collapseUsingPrivateVisibilityRestriction() {
        let windows = MenuBarItemScanner.panelDisplayOrder(
            MenuBarItemScanner.statusWindows().filter {
                managedBundleIdentifiers.contains($0.bundleIdentifier)
            }
        )
        guard managedBundleIdentifiers.isEmpty || IconCapturer.hasPermission() else {
            cachedItems = []
            isCollapsed = false
            updateToggleIcon()
            return
        }

        preparingCollapse = true
        cacheCaptureTask?.cancel()
        cacheCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let reusable = windows.compactMap { window -> CapturedItem? in
                let existing = self.cachedItems.first { cached in
                    if let liveIdentity = window.accessibilityIdentity,
                       let cachedIdentity = cached.window.accessibilityIdentity {
                        return liveIdentity == cachedIdentity
                    }
                    return cached.window.bundleIdentifier == window.bundleIdentifier
                }
                guard let existing else { return nil }
                return CapturedItem(
                    window: window,
                    image: existing.image,
                    hoverText: window.displayName,
                    ownerProcessIdentifier: window.ownerProcessIdentifier
                )
            }
            let reusableIDs = Set(reusable.map(\.id))
            let missing = windows.filter { !reusableIDs.contains($0.id) }
            var newlyCaptured: [CapturedItem] = []
            var uncaptured = missing
            for attempt in 0..<3 where !uncaptured.isEmpty {
                if attempt > 0 {
                    guard (try? await Task.sleep(for: .milliseconds(250))) != nil,
                          !Task.isCancelled else { return }
                }
                let capturable = Self.capturablePrivateItems(uncaptured)
                guard !capturable.isEmpty else { break }
                let captured = await IconCapturer.capture(capturable)
                newlyCaptured.append(contentsOf: captured)
                let capturedIDs = Set(captured.map(\.id))
                uncaptured.removeAll { capturedIDs.contains($0.id) }
            }
            guard !Task.isCancelled, !self.isCollapsed else { return }
            // The assertion is application-granular. Only hide a bundle when
            // every observed menu extra from that bundle has real pixels.
            let captured = reusable + newlyCaptured
            let completeBundles = Self.completeCapturedBundles(
                among: windows,
                captured: captured
            )
            let applied = await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: completeBundles
            )
            guard !Task.isCancelled else { return }
            guard applied else {
                self.visibilityRestriction.releaseActiveRestriction()
                self.preparingCollapse = false
                self.cacheCaptureTask = nil
                self.isCollapsed = false
                self.updateToggleIcon()
                return
            }
            let byID = Dictionary(
                uniqueKeysWithValues: captured.map {
                    ($0.id, $0)
                }
            )
            self.cachedItems = windows.compactMap { window in
                completeBundles.contains(window.bundleIdentifier)
                    ? byID[window.id]
                    : nil
            }
            self.completeCollapse(
                knownManagedWindowIDs: Set(self.cachedItems.map(\.id))
            )
        }
    }

    private func completeCollapse(
        knownManagedWindowIDs: Set<CGWindowID>
    ) {
        preparingCollapse = false
        cacheCaptureTask = nil
        _ = MenuBarArrangement.captureAndSave()
        if MenuBarItemScanner.usesAccessibilityBackend {
            // macOS 27 hides FoldBar-managed bundles through MenuBarAgent. No
            // separator slot is registered, so FoldBar cannot leave a blank gap
            // and remains independent from the system `«` overflow control.
            separatorItem.length = 0
        } else {
            separatorItem.length = Self.collapsedLength
        }
        isCollapsed = true
        self.knownManagedWindowIDs = knownManagedWindowIDs
        updateToggleIcon()
        armCollapsedItemMonitor()
    }

    private func expandRealMenuBar(removingSeparatorGap: Bool = false) {
        guard isCollapsed else { return }
        isCollapsed = false
        disarmCollapsedItemMonitor()
        cacheCaptureTask?.cancel()
        cacheCaptureTask = nil
        preparingCollapse = false
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        panel.close()
        expandedMenuBarPanel.close()
        // A transparent separator still reserves its variable-width slot. A
        // proxy click removes that slot up front so revealing the real items
        // produces one layout, without the visible blank gap and second shift.
        separatorItem.length = MenuBarItemScanner.usesAccessibilityBackend
            || removingSeparatorGap
            ? 0
            : NSStatusItem.variableLength
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        guard let button = toggleItem.button else { return }
        if isImportTargetingToggle {
            // Keep the same symbol while targeting so the status item's frame
            // cannot shift underneath the fixed drop-target geometry.
            button.image = symbol("chevron.down")
            button.contentTintColor = .controlAccentColor
            button.toolTip = L10n.text(.collectTooltip)
            return
        }

        let showsManagedItems = expandedMenuBarPanel.isVisible || !isCollapsed
        button.image = symbol(showsManagedItems ? "chevron.up" : "chevron.down")
        button.contentTintColor = nil
        button.toolTip = "FoldBar"
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    // MARK: - Overflow panel

    private func openPanel() {
        guard IconCapturer.hasPermission() else {
            presentPermissionCenter()
            return
        }

        expandedMenuBarPanel.close()
        let (hidden, items) = currentManagedItems()
        let anchor = toggleItem.button?.window?.frame ?? .zero

        guard !items.isEmpty || hidden.isEmpty else {
            showRestartForCacheAlert()
            return
        }
        panel.show(
            items: items,
            below: anchor,
            onClick: { [weak self] item in self?.activate(item) },
            onPromote: { [weak self] item in self?.promoteToMenuBar(item) },
            onSettings: { [weak self] in self?.settingsPanel.show() },
            shouldDeferDismissalForExternalMouseDown: { [weak self] event in
                self?.shouldDeferPanelDismissal(for: event) ?? false
            },
            onDismiss: { [weak self] in
                self?.disarmMenuBarImport()
                self?.armCollapsedItemMonitor()
            }
        )
        // A suspended reconciliation must not publish an older visibility set
        // after the user starts an import or activation from this panel.
        disarmCollapsedItemMonitor()
        armMenuBarImport()
    }

    private func currentManagedItems() -> (
        hidden: [MenuBarItemWindow],
        captured: [CapturedItem]
    ) {
        if MenuBarItemScanner.usesAccessibilityBackend {
            let items = cachedItems.filter {
                managedBundleIdentifiers.contains($0.window.bundleIdentifier)
            }
            return (items.map(\.window), items)
        }
        let hidden = currentHiddenItems()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })
        let items = MenuBarItemScanner.panelDisplayOrder(hidden).compactMap {
            cachedByID[$0.id]
        }
        return (hidden, items)
    }

    private func currentHiddenItems() -> [MenuBarItemWindow] {
        if MenuBarItemScanner.usesAccessibilityBackend {
            return cachedItems.compactMap {
                managedBundleIdentifiers.contains($0.window.bundleIdentifier)
                    ? $0.window
                    : nil
            }
        }
        guard let separatorFrame = separatorItem.button?.window?.frame else {
            return []
        }
        return MenuBarItemScanner.itemsLeft(of: MenuBarCommandDragMonitor.quartzFrame(
            fromAppKit: separatorFrame,
            mainDisplayBounds: CGDisplayBounds(CGMainDisplayID())
        ))
    }

    private func showExpandedMenuBar() {
        guard isCollapsed else { return }
        if MenuBarItemScanner.usesAccessibilityBackend {
            // macOS 27 uses FoldBar's independent managed set. The title action
            // closes the panel; it must not drive the unrelated system `«`.
            panel.close()
            return
        }
        let (hidden, items) = currentManagedItems()
        guard items.count == hidden.count,
              !items.isEmpty,
              let anchor = toggleItem.button?.window?.frame else {
            showRestartForCacheAlert()
            return
        }

        panel.close()
        let shown = expandedMenuBarPanel.show(
            items: items,
            beside: anchor,
            avoiding: currentImportCandidates(),
            onClick: { [weak self] item in self?.activate(item) },
            onDismiss: { [weak self] in self?.updateToggleIcon() }
        )
        if shown {
            updateToggleIcon()
        } else {
            showAlert(
                title: L10n.text(.expandUnavailableTitle),
                message: L10n.text(.expandUnavailableMessage)
            )
        }
    }

    // MARK: - Newly launched status items

    private func armCollapsedItemMonitor() {
        disarmCollapsedItemMonitor()
        guard isCollapsed,
              MenuBarPollingPolicy.shouldMonitorCollapsedItems(
                usesAccessibilityBackend: MenuBarItemScanner.usesAccessibilityBackend,
                hasManagedApplications: !managedBundleIdentifiers.isEmpty
              ) else { return }

        collapsedItemMonitorTask = Task { @MainActor [weak self] in
            while let self, self.isCollapsed, !Task.isCancelled {
                guard (try? await Task.sleep(
                    for: .milliseconds(Self.collapsedItemPollMilliseconds)
                )) != nil else { return }
                guard self.isCollapsed,
                      !self.preparingCollapse,
                      !self.panel.isVisible,
                      !self.expandedMenuBarPanel.isVisible,
                      self.activationTask == nil,
                      self.promotionTask == nil,
                      self.automaticPlacementTask == nil else { continue }

                if MenuBarItemScanner.usesAccessibilityBackend {
                    // The macOS 27 assertion is an application allowlist, not
                    // only a denylist. Reconcile it while collapsed so a newly
                    // launched, un-managed status item is admitted instead of
                    // being parked outside both the real menu bar and FoldBar.
                    await MenuBarItemScanner.refreshStatusWindows()
                    await self.reconcilePrivateManagedImages()
                    continue
                }
                await MenuBarItemScanner.refreshStatusWindows()
                let hidden = self.currentHiddenItems()
                let currentIDs = Set(hidden.map(\.id))
                self.knownManagedWindowIDs.formIntersection(currentIDs)
                let added = MenuBarItemScanner.newlyManagedItems(
                    among: hidden,
                    excluding: self.knownManagedWindowIDs
                )
                guard !added.isEmpty else { continue }
                self.knownManagedWindowIDs.formUnion(added.map(\.id))
                self.beginAutomaticPlacement(of: added)
                return
            }
        }
    }

    private func disarmCollapsedItemMonitor() {
        collapsedItemMonitorTask?.cancel()
        collapsedItemMonitorTask = nil
    }

    private func reconcilePrivateManagedImages() async {
        guard !Task.isCancelled, isCollapsed, !panel.isVisible else { return }
        let liveItems = MenuBarItemScanner.statusWindows().filter {
            managedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let existingByIdentity = Dictionary(
            uniqueKeysWithValues: cachedItems.compactMap { item in
                item.window.accessibilityIdentity.map { ($0, item) }
            }
        )
        let reusable: [CapturedItem] = MenuBarItemScanner
            .panelDisplayOrder(liveItems).compactMap { window -> CapturedItem? in
            guard let identity = window.accessibilityIdentity,
                  let existing = existingByIdentity[identity] else { return nil }
            return CapturedItem(
                window: window,
                image: existing.image,
                hoverText: window.displayName,
                ownerProcessIdentifier: window.ownerProcessIdentifier
            )
        }
        let reusableIDs = Set(reusable.map(\.id))
        let missing = liveItems.filter { !reusableIDs.contains($0.id) }
        let retryable = backgroundCaptureRetryPolicy.retryableItems(
            among: missing,
            now: ProcessInfo.processInfo.systemUptime
        )
        let attempted = Self.capturablePrivateItems(retryable)
        // Background recovery already has a per-item cooldown. One attempt
        // avoids a three-shot burst; explicit imports/startup keep their retries.
        let newlyCaptured = await IconCapturer.capture(attempted, maximumAttempts: 1)
        guard !Task.isCancelled, isCollapsed, !panel.isVisible else { return }
        backgroundCaptureRetryPolicy.recordResults(
            for: attempted,
            capturedIDs: Set(newlyCaptured.map(\.id)),
            now: ProcessInfo.processInfo.systemUptime
        )
        let candidate: [CapturedItem] = reusable + newlyCaptured
        let completeBundles = Self.completeCapturedBundles(
            among: liveItems,
            captured: candidate
        )
        guard await visibilityRestriction.apply(
            hiddenBundleIdentifiers: completeBundles
        ), !Task.isCancelled else { return }
        cachedItems = MenuBarItemScanner.panelDisplayOrder(candidate.map(\.window))
            .compactMap { window in
                completeBundles.contains(window.bundleIdentifier)
                    ? candidate.first(where: { $0.id == window.id })
                    : nil
            }
        knownManagedWindowIDs = Set(cachedItems.map(\.id))
    }

    nonisolated static func completeCapturedBundles(
        among liveItems: [MenuBarItemWindow],
        captured: [CapturedItem]
    ) -> Set<String> {
        let capturedIdentities = Set(captured.compactMap {
            $0.window.accessibilityIdentity
        })
        let groups = Dictionary(grouping: liveItems, by: \.bundleIdentifier)
        return Set(groups.compactMap { bundleIdentifier, items in
            guard !bundleIdentifier.isEmpty,
                  items.allSatisfy({ item in
                      item.accessibilityIdentity.map(capturedIdentities.contains)
                          ?? false
                  }) else { return nil }
            return bundleIdentifier
        })
    }

    private static func capturablePrivateItems(
        _ items: [MenuBarItemWindow]
    ) -> [MenuBarItemWindow] {
        let segments = activeVisibleMenuBarSegments()
        let overflowFrame = MenuBarItemScanner.systemOverflowFrame()
        return items.filter {
            // The system control is only an occlusion check for screenshot
            // pixels; it never defines FoldBar's managed membership.
            isSafePrivateCaptureFrame(
                $0.frame,
                visibleSegments: segments,
                overflowFrame: overflowFrame
            )
        }
    }

    static func isSafePrivateCaptureFrame(
        _ frame: CGRect,
        visibleSegments: [CGRect],
        overflowFrame: CGRect?
    ) -> Bool {
        isInVisibleMenuBarSegment(frame, segments: visibleSegments)
            && !(overflowFrame.map { frame.intersects($0) } ?? false)
    }

    private func beginAutomaticPlacement(of items: [MenuBarItemWindow]) {
        guard isCollapsed, automaticPlacementTask == nil else { return }
        automaticPlacementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.reconcileNewManagedItems(items)
            self.automaticPlacementTask = nil
        }
    }

    private func reconcileNewManagedItems(_ items: [MenuBarItemWindow]) async {
        guard isCollapsed else { return }

        // A newly registered NSStatusItem can already have a stable window
        // frame while its hosting app is not yet ready to participate in a
        // Command-drag reorder session. Give that session a short grace period
        // before deciding whether the item belongs in the available space.
        guard (try? await Task.sleep(
            for: .milliseconds(Self.automaticPlacementStabilizationMilliseconds)
        )) != nil,
        !Task.isCancelled,
        isCollapsed else { return }

        await MenuBarItemScanner.refreshStatusWindows()

        var automaticallyVisibleIDs: Set<CGWindowID> = []

        if items.count <= Self.maximumAutomaticPlacementBatch,
           EventForwarder.isTrusted(),
           let toggleFrame = toggleItem.button?.window?.frame {
            var availableWidth = Self.availableAutomaticPlacementWidth(
                toggleFrame: toggleFrame,
                visibleSegments: Self.activeVisibleMenuBarSegments(),
                statusItems: MenuBarItemScanner.statusWindows()
            )
            for item in items where item.frame.width <= availableWidth {
                automaticallyVisibleIDs.insert(item.id)
                availableWidth -= item.frame.width
            }
        }

        expandRealMenuBar()

        // Several simultaneous ID replacements usually mean Control Center
        // rebuilt the hosted status windows. Refresh their proxies, but do not
        // reinterpret a bulk host rebuild as several newly launched apps.
        if !automaticallyVisibleIDs.isEmpty {
            for item in items where automaticallyVisibleIDs.contains(item.id) {
                guard !Task.isCancelled else { return }
                for attempt in 0...Self.automaticPlacementRetryDelaysMilliseconds.count {
                    if await moveToVisibleSide(item, reportsFailure: false) {
                        break
                    }
                    guard attempt < Self.automaticPlacementRetryDelaysMilliseconds.count,
                          (try? await Task.sleep(
                            for: .milliseconds(
                                Self.automaticPlacementRetryDelaysMilliseconds[attempt]
                            )
                          )) != nil,
                          !Task.isCancelled else { break }
                }
            }
        }

        guard !Task.isCancelled else { return }
        // Whether an item was promoted or remained overflow, recapture the
        // expanded managed section so a restarted app's new window ID cannot
        // disappear from the proxy cache.
        collapse()
    }

    private func activate(_ item: CapturedItem) {
        let closesExpandedProxies = expandedMenuBarPanel.isVisible
        guard requireAccessibility() else {
            if closesExpandedProxies { expandedMenuBarPanel.close() }
            return
        }
        guard !preparingCollapse, activationTask == nil, promotionTask == nil else {
            if closesExpandedProxies { expandedMenuBarPanel.close() }
            return
        }
        if MenuBarItemScanner.usesAccessibilityBackend {
            activationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performPrivateActivation(item)
                self.activationTask = nil
            }
            return
        }
        // Remove the transparent proxies before asking Control Center to reveal
        // the real status windows. Keeping both alive across async layout polls
        // creates the visibly doubled row reported during acceptance.
        if closesExpandedProxies { expandedMenuBarPanel.close() }
        expandRealMenuBar(removingSeparatorGap: true)

        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performActivation(item)
            self.activationTask = nil
        }
    }

    private func performPrivateActivation(_ item: CapturedItem) async {
        let bundleIdentifier = item.window.bundleIdentifier
        guard !bundleIdentifier.isEmpty,
              managedBundleIdentifiers.contains(bundleIdentifier) else { return }

        let previouslyHidden = cachedPrivateBundleIdentifiers
        let temporarilyHidden = previouslyHidden.subtracting([
            bundleIdentifier
        ])
        let applied = await visibilityRestriction.apply(
            hiddenBundleIdentifiers: temporarilyHidden
        )
        guard !Task.isCancelled else { return }
        guard applied else {
            showAlert(
                title: L10n.text(.clickUnavailableTitle),
                message: L10n.text(.privateRevealFailed)
            )
            return
        }

        isCollapsed = false
        updateToggleIcon()

        // MenuBarAgent publishes the revealed AX frame before the hosted item
        // is ready to receive mouse input. In live testing, a Tauri menu extra
        // ignored a click at 50 ms but handled the same click at 200 ms. Keep
        // this bounded settling interval before resolving the final target.
        guard (try? await Task.sleep(
            for: .milliseconds(Self.privateActivationSettleMilliseconds)
        )) != nil,
        !Task.isCancelled else { return }

        var liveItem: MenuBarItemWindow?
        for poll in 0..<20 {
            if poll > 0 {
                guard (try? await Task.sleep(for: .milliseconds(25))) != nil,
                      !Task.isCancelled else { return }
            }
            liveItem = MenuBarItemScanner.refreshStatusWindow(item.window)
            if let liveItem,
               Self.isInVisibleMenuBarSegment(
                   liveItem.frame,
                   segments: Self.activeVisibleMenuBarSegments()
               ) { break }
            liveItem = nil
        }

        guard let liveItem,
              let identity = liveItem.accessibilityIdentity,
              let point = Self.activationPoint(
                  itemFrame: liveItem.frame,
                  visibleSegments: Self.activeVisibleMenuBarSegments()
              ),
              MenuBarAccessibility.matchesCurrentItem(
                  identity,
                  expectedLabel: liveItem.windowName,
                  expectedFrame: liveItem.frame
              ) else {
            _ = await visibilityRestriction.apply(
                hiddenBundleIdentifiers: previouslyHidden
            )
            isCollapsed = true
            updateToggleIcon()
            showAlert(
                title: L10n.text(.clickUnavailableTitle),
                message: L10n.text(.liveIconUnavailable)
            )
            return
        }

        // AXPress is not equivalent to a real primary click for every hosted
        // menu extra. Clash Verge's Tauri status item accepts AXPress without
        // presenting its window, while the validated mouse sequence follows
        // the app's normal click handler. Identity and geometry are rechecked
        // immediately above so the synthetic input remains fail-closed.
        EventForwarder.click(
            at: point,
            eventUserData: MenuBarCommandDragMonitor.syntheticClickEventMarker
        )
        armAutoCollapse()
    }

    private func performActivation(_ item: CapturedItem) async {
        let originalToggleLength = toggleItem.length
        let originalSeparatorLength = separatorItem.length
        defer {
            separatorItem.length = originalSeparatorLength
            toggleItem.length = originalToggleLength
        }

        // A far-left managed item can remain partly behind the notch even after
        // expanding with a zero-width separator. First try that final layout,
        // then reclaim only our trigger's width if needed. This avoids exposing
        // an intermediate variable-width separator layout to the user.
        let visibleSegments = Self.activeVisibleMenuBarSegments()
        var frame = await waitForActivationFrame(of: item)

        if frame.flatMap({
            Self.activationPoint(itemFrame: $0, visibleSegments: visibleSegments)
        }) == nil {
            toggleItem.length = 0
            frame = await waitForActivationFrame(of: item)
        }

        guard !Task.isCancelled else { return }
        guard let frame,
              let point = Self.activationPoint(
                itemFrame: frame,
                visibleSegments: visibleSegments
              ) else {
            showAlert(
                title: L10n.text(.clickUnavailableTitle),
                message: L10n.text(.legacyClickUnavailable)
            )
            armAutoCollapse()
            return
        }

        let targetDisplay = Self.activeDisplayBounds().first { $0.contains(point) }
        let baselineAuxiliaryWindows = item.ownerProcessIdentifier.flatMap { owner in
            targetDisplay.map {
                ActivationWindowScanner.visibleAuxiliaryWindowIDs(
                    ownerProcessIdentifier: owner,
                    on: $0
                )
            }
        }

        if let identity = item.window.accessibilityIdentity {
            guard MenuBarAccessibility.performPress(
                on: identity,
                expectedLabel: item.window.windowName,
                expectedFrame: frame
            ) else {
                showAlert(
                    title: L10n.text(.clickUnavailableTitle),
                    message: L10n.text(.clickIdentityChanged)
                )
                armAutoCollapse()
                return
            }
        } else {
            EventForwarder.click(
                at: point,
                eventUserData: MenuBarCommandDragMonitor.syntheticClickEventMarker
            )
        }

        // Keep the real anchor in place until the owning application actually
        // presents its menu/popover on this display. A fixed delay can collapse
        // a slow target first, causing the new window to inherit an off-screen
        // anchor. Items that do not present a window use the bounded fallback.
        if let owner = item.ownerProcessIdentifier,
           let display = targetDisplay,
           let baseline = baselineAuxiliaryWindows {
            _ = await waitForTargetPresentation(
                ownerProcessIdentifier: owner,
                on: display,
                excluding: baseline
            )
        } else {
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil,
                  !Task.isCancelled else { return }
        }
        armAutoCollapse()
    }

    private func promoteToMenuBar(_ item: CapturedItem) {
        if MenuBarItemScanner.usesAccessibilityBackend {
            promotePrivateBundleToMenuBar(item.window.bundleIdentifier)
            return
        }
        guard requireAccessibility() else { return }
        guard promotionTask == nil else { return }
        expandRealMenuBar()

        promotionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPromotion(item)
            self.promotionTask = nil
        }
    }

    private func promotePrivateBundleToMenuBar(_ bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty,
              managedBundleIdentifiers.contains(bundleIdentifier),
              !preparingCollapse,
              activationTask == nil,
              promotionTask == nil else { return }
        promotionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let updated = self.managedBundleIdentifiers.subtracting([
                bundleIdentifier
            ])
            let applied = await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: self.cachedPrivateBundleIdentifiers
                    .subtracting([bundleIdentifier])
            )
            guard !Task.isCancelled else { return }
            if applied {
                self.managedBundleIdentifiers = updated
                ManagedMenuBarBundles.save(updated)
                self.cachedItems.removeAll {
                    $0.window.bundleIdentifier == bundleIdentifier
                }
                self.knownManagedWindowIDs = Set(self.cachedItems.map(\.id))
                self.isCollapsed = true
                self.updateToggleIcon()
            } else {
                self.showAlert(
                    title: L10n.text(.removeAppFailedTitle),
                    message: L10n.text(.privateUpdateFailed)
                )
            }
            self.promotionTask = nil
            self.armCollapsedItemMonitor()
        }
    }

    private func performPromotion(_ item: CapturedItem) async {
        guard await moveToVisibleSide(item.window, reportsFailure: true) else { return }
        // collapse() snapshots the newly ordered bar before parking the
        // remaining overflow items again.
        collapse()
    }

    private func moveToVisibleSide(
        _ item: MenuBarItemWindow,
        reportsFailure: Bool
    ) async -> Bool {
        let diagnosticID = String(UUID().uuidString.prefix(8))
        Self.promotionLogger.notice(
            "promotion[\(diagnosticID, privacy: .public)] begin item=\(item.id, privacy: .public) cached=\(Self.frameDescription(item.frame), privacy: .public)"
        )
        guard let originalToggleFrame = toggleItem.button?.window?.frame else {
            Self.promotionLogger.error(
                "promotion[\(diagnosticID, privacy: .public)] unavailable: toggle frame missing"
            )
            if reportsFailure { showPromotionUnavailableAlert() }
            return false
        }

        let originalToggleLength = toggleItem.length
        let originalSeparatorLength = separatorItem.length
        Self.promotionLogger.notice(
            "promotion[\(diagnosticID, privacy: .public)] own-items toggle=\(Self.frameDescription(originalToggleFrame), privacy: .public) toggleLength=\(originalToggleLength, privacy: .public) separatorLength=\(originalSeparatorLength, privacy: .public)"
        )
        defer {
            separatorItem.length = originalSeparatorLength
            toggleItem.length = originalToggleLength
        }

        var frame = await waitForStableMenuBarFrame(of: item.id)
        Self.promotionLogger.notice(
            "promotion[\(diagnosticID, privacy: .public)] expanded-layout item=\(Self.frameDescription(frame), privacy: .public)"
        )

        let visibleSegments = Self.activeVisibleMenuBarSegments()
        // Preserve the live trigger as the placement anchor whenever the source
        // is already interactive. Removing it unnecessarily shifts the
        // separator into the saved target coordinate, which makes AppKit snap
        // the promoted item back onto the managed side.
        if frame.map({
            !Self.isInVisibleMenuBarSegment($0, segments: visibleSegments)
        }) ?? true {
            toggleItem.length = 0
            frame = await waitForStableMenuBarFrame(of: item.id)
            Self.promotionLogger.notice(
                "promotion[\(diagnosticID, privacy: .public)] after-toggle-zero item=\(Self.frameDescription(frame), privacy: .public)"
            )
        }

        // On a crowded bar the trigger alone may not free enough room. The
        // separator can also be reduced safely because its original order and
        // length are restored immediately after the mouse-up.
        if frame.map({
            !Self.isInVisibleMenuBarSegment($0, segments: visibleSegments)
        }) ?? true {
            separatorItem.length = 0
            frame = await waitForStableMenuBarFrame(of: item.id)
            Self.promotionLogger.notice(
                "promotion[\(diagnosticID, privacy: .public)] after-separator-zero item=\(Self.frameDescription(frame), privacy: .public)"
            )
        }

        guard !Task.isCancelled else {
            Self.promotionLogger.notice(
                "promotion[\(diagnosticID, privacy: .public)] cancelled during preparation"
            )
            return false
        }
        let liveBoundaryFrame = MenuBarItemScanner.usesAccessibilityBackend
            ? MenuBarItemScanner.systemOverflowFrame()
            : separatorItem.button?.window?.frame
        guard let frame,
              let liveBoundaryFrame,
              let liveToggleFrame = toggleItem.button?.window?.frame,
              Self.isInVisibleMenuBarSegment(frame, segments: visibleSegments),
              let targetX = Self.promotionTargetX(
                itemFrame: frame,
                liveToggleFrame: liveToggleFrame,
                finalToggleFrame: originalToggleFrame,
                visibleSegments: visibleSegments
              ) else {
            Self.promotionLogger.error(
                "promotion[\(diagnosticID, privacy: .public)] unavailable: item=\(Self.frameDescription(frame), privacy: .public) visibleSegments=\(Self.frameDescriptions(visibleSegments), privacy: .public)"
            )
            if reportsFailure { showPromotionUnavailableAlert() }
            return false
        }

        Self.promotionLogger.notice(
            "promotion[\(diagnosticID, privacy: .public)] dispatch item=\(Self.frameDescription(frame), privacy: .public) boundary=\(Self.frameDescription(liveBoundaryFrame), privacy: .public) toggle=\(Self.frameDescription(liveToggleFrame), privacy: .public) targetX=\(targetX, privacy: .public)"
        )
        if let identity = item.accessibilityIdentity,
           !MenuBarAccessibility.matchesCurrentItem(
               identity,
               expectedLabel: item.windowName,
               expectedFrame: frame
           ) {
            Self.promotionLogger.error(
                "promotion[\(diagnosticID, privacy: .public)] cancelled: accessibility identity changed"
            )
            if reportsFailure {
                showAlert(
                    title: L10n.text(.identityChangedTitle),
                    message: L10n.text(.moveIdentityChanged)
                )
            }
            return false
        }
        let posted = await EventForwarder.commandDrag(
            from: CGPoint(x: frame.midX, y: frame.midY),
            to: CGPoint(x: targetX, y: frame.midY),
            diagnosticID: diagnosticID
        )

        // Put FoldBar's own items back before checking which side of the
        // separator now owns the promoted window.
        separatorItem.length = originalSeparatorLength
        toggleItem.length = originalToggleLength
        guard (try? await Task.sleep(for: .milliseconds(140))) != nil,
              !Task.isCancelled else {
            Self.promotionLogger.notice(
                "promotion[\(diagnosticID, privacy: .public)] cancelled after dispatch"
            )
            return false
        }

        let verified = posted
            ? await waitForPromotion(of: item.id, diagnosticID: diagnosticID)
            : false
        guard posted, verified else {
            Self.promotionLogger.error(
                "promotion[\(diagnosticID, privacy: .public)] failed posted=\(posted, privacy: .public) verified=\(verified, privacy: .public)"
            )
            guard !Task.isCancelled else { return false }
            if reportsFailure {
                showAlert(
                    title: L10n.text(.moveFailedTitle),
                    message: L10n.text(.legacyMoveFailed)
                )
            }
            return false
        }
        Self.promotionLogger.notice(
            "promotion[\(diagnosticID, privacy: .public)] succeeded"
        )
        return true
    }

    private func showPromotionUnavailableAlert() {
        showAlert(
            title: L10n.text(.moveUnavailableTitle),
            message: L10n.text(.legacyMoveUnavailable)
        )
    }

    // MARK: - Import from the real menu bar

    private func armMenuBarImport() {
        disarmMenuBarImport()
        guard panel.isVisible,
              EventForwarder.isTrusted(),
              let panelFrame = panel.frame,
              let toggleFrame = toggleItem.button?.window?.frame else { return }

        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let panelTargetFrame = MenuBarCommandDragMonitor.quartzFrame(
            fromAppKit: panelFrame,
            mainDisplayBounds: mainDisplayBounds
        )
        let toggleTargetFrame = MenuBarCommandDragMonitor.quartzFrame(
            fromAppKit: toggleFrame,
            mainDisplayBounds: mainDisplayBounds
        )
        // A private empty collection can remain idle without an AX scan for
        // hours. Never publish those old coordinates to the input tap. The
        // first explicit panel refresh below supplies its allowed candidates.
        let candidates = MenuBarItemScanner.usesAccessibilityBackend
            ? [] : currentImportCandidates()
        guard menuBarImportMonitor.start(
            candidates: candidates,
            panelTargetFrame: panelTargetFrame,
            toggleTargetFrame: toggleTargetFrame
        ) else {
            Self.importLogger.error("menu-bar import monitor could not start")
            return
        }
        Self.importLogger.notice(
            "menu-bar import armed candidates=\(candidates.count, privacy: .public) cachedBundles=\(self.cachedPrivateBundleIdentifiers.count, privacy: .public) persistedBundles=\(self.managedBundleIdentifiers.count, privacy: .public)"
        )
        prefetchImportPreviewImages(for: candidates)

        importCandidateRefreshTask = Task { @MainActor [weak self] in
            if MenuBarItemScanner.usesAccessibilityBackend {
                await MenuBarItemScanner.refreshStatusWindows(force: true)
                guard let self, !Task.isCancelled, self.panel.isVisible,
                      self.menuBarImportMonitor.isRunning else { return }
                let candidates = self.currentImportCandidates()
                self.menuBarImportMonitor.updateCandidates(candidates)
                self.prefetchImportPreviewImages(for: candidates)
            }
            while let self, self.panel.isVisible, self.menuBarImportMonitor.isRunning {
                guard (try? await Task.sleep(
                    for: .milliseconds(MenuBarPollingPolicy.panelIntervalMilliseconds)
                )) != nil else { return }
                guard self.panel.isVisible else { return }
                await MenuBarItemScanner.refreshStatusWindows()
                guard !Task.isCancelled,
                      self.panel.isVisible,
                      self.menuBarImportMonitor.isRunning else { return }
                let candidates = self.currentImportCandidates()
                self.menuBarImportMonitor.updateCandidates(candidates)
                self.prefetchImportPreviewImages(for: candidates)
            }
        }
    }

    private func disarmMenuBarImport() {
        importCandidateRefreshTask?.cancel()
        importCandidateRefreshTask = nil
        importPreviewPrefetchTask?.cancel()
        importPreviewPrefetchTask = nil
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = nil
        externalDragItemID = nil
        importPreviewCache.reset()
        // Closing or reopening the panel is an explicit opportunity to retry
        // a previously unavailable real icon without changing managed state.
        backgroundCaptureRetryPolicy.reset()
        menuBarImportMonitor.stop()
        setImportTargetingToggle(false)
    }

    private func prefetchImportPreviewImages(for candidates: [MenuBarItemWindow]) {
        let candidateIDs = Set(candidates.map(\.id))
        importPreviewCache.retain(
            candidateIDs: candidateIDs,
            activeDragItemID: externalDragItemID
        )
        guard importPreviewPrefetchTask == nil else { return }
        guard let request = importPreviewCache.request(for: candidateIDs) else { return }
        let missing = candidates.filter { request.itemIDs.contains($0.id) }

        importPreviewPrefetchTask = Task { @MainActor [weak self] in
            let images = await IconCapturer.captureImages(
                missing,
                includeFallback: !MenuBarItemScanner.usesAccessibilityBackend,
                diagnostics: true
            )
            guard let self, !Task.isCancelled, self.panel.isVisible,
                  self.importPreviewCache.generation == request.generation else { return }
            self.importPreviewCache.merge(
                images,
                for: request,
                candidateIDs: Set(self.currentImportCandidates().map(\.id)),
                activeDragItemID: self.externalDragItemID
            )
            self.importPreviewPrefetchTask = nil
        }
    }

    private func currentImportCandidates() -> [MenuBarItemWindow] {
        guard isCollapsed else { return [] }
        let ownWindows = [
            toggleItem.button?.window,
            separatorItem.button?.window
        ].compactMap { $0 }
        let ownWindowIDs = Self.validWindowIDs(ownWindows.map(\.windowNumber))
        let ownWindowFrames = ownWindows.map(\.frame)

        let candidates: [MenuBarItemWindow]
        if MenuBarItemScanner.usesAccessibilityBackend {
            // Failed captures leave persisted bundles visible. They must remain
            // importable: only bundles represented by the active panel cache
            // are already hidden by FoldBar.
            candidates = Self.privateImportCandidates(
                among: MenuBarItemScanner.statusWindows(),
                hiddenBundleIdentifiers: cachedPrivateBundleIdentifiers,
                visibleSegments: Self.activeVisibleMenuBarSegments(),
                overflowFrame: MenuBarItemScanner.systemOverflowFrame()
            )
        } else {
            guard let separatorFrame = separatorItem.button?.window?.frame else {
                return []
            }
            candidates = MenuBarItemScanner.statusWindows().filter {
                Self.isOnVisibleSide($0.frame, separatorFrame: separatorFrame)
            }
        }

        return candidates.filter { window in
            window.bundleIdentifier != Bundle.main.bundleIdentifier
                && !ownWindowIDs.contains(window.id)
                && !Self.matchesOwnStatusItem(window.frame, ownFrames: ownWindowFrames)
                && window.frame.width < 500
                && Self.isInMenuBarStrip(window.frame)
        }
    }

    static func privateImportCandidates(
        among windows: [MenuBarItemWindow],
        hiddenBundleIdentifiers: Set<String>,
        visibleSegments: [CGRect],
        overflowFrame: CGRect?
    ) -> [MenuBarItemWindow] {
        windows.filter { window in
            !hiddenBundleIdentifiers.contains(window.bundleIdentifier)
                && isSafePrivateCaptureFrame(
                    window.frame,
                    visibleSegments: visibleSegments,
                    overflowFrame: overflowFrame
                )
        }
    }

    private func shouldDeferPanelDismissal(for event: NSEvent) -> Bool {
        guard menuBarImportMonitor.isRunning,
              let cgEvent = event.cgEvent else { return false }
        return MenuBarCommandDragMonitor.acceptsImportMouseDown(
            at: cgEvent.location,
            among: currentImportCandidates(),
            flags: cgEvent.flags,
            allowsDirectDrag: UserDefaults.standard.bool(
                forKey: MenuBarDragSettings.directDragDefaultsKey
            )
        )
    }

    static func validWindowIDs(_ windowNumbers: [Int]) -> Set<CGWindowID> {
        Set(windowNumbers.compactMap { number in
            guard number > 0 else { return nil }
            return CGWindowID(exactly: number)
        })
    }

    static func matchesOwnStatusItem(_ candidate: CGRect, ownFrames: [CGRect]) -> Bool {
        ownFrames.contains { ownFrame in
            abs(candidate.minX - ownFrame.minX) <= 1
                && abs(candidate.width - ownFrame.width) <= 1
        }
    }

    private func beginExternalDrag(_ item: MenuBarItemWindow, at point: CGPoint) {
        Self.importLogger.notice("external drag began item=\(item.id, privacy: .public)")
        externalDragItemID = item.id
        setImportTargetingToggle(false)
        panel.beginExternalDrag(
            image: importPreviewCache[item.id],
            sourceFrame: item.frame,
            atQuartzPoint: point
        )
        Self.importLogger.notice(
            "external drag preview ready=\(self.importPreviewCache[item.id] != nil, privacy: .public)"
        )
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = Task { @MainActor [weak self] in
            let captured = await IconCapturer.captureImages(
                [item],
                includeFallback: !MenuBarItemScanner.usesAccessibilityBackend,
                diagnostics: true
            )
            guard let self,
                  !Task.isCancelled,
                  self.externalDragItemID == item.id else { return }
            guard let image = captured[item.id] else {
                Self.importLogger.notice("external drag screenshot unavailable")
                return
            }
            self.importPreviewCache.store(image, for: item.id)
            self.panel.updateExternalDragImage(image)
            Self.importLogger.notice("external drag screenshot ready")
        }
    }

    private func updateExternalDrag(
        at point: CGPoint,
        target: MenuBarImportDropTarget?
    ) {
        panel.updateExternalDrag(
            atQuartzPoint: point,
            isInsidePanel: target == .panel
        )
        setImportTargetingToggle(target == .toggle)
    }

    private func setImportTargetingToggle(_ isTargeted: Bool) {
        guard isImportTargetingToggle != isTargeted else { return }
        isImportTargetingToggle = isTargeted
        updateToggleIcon()
    }

    private func replayExternalClick(_ item: MenuBarItemWindow, at point: CGPoint) {
        // The event tap consumed the original plain mouse-down. Wait for its
        // callback to return before closing the panel and replaying one marked
        // click that the import monitor will never claim again.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.panel.close()
            await Task.yield()

            // The candidate already supplies a validated identity. Re-resolve
            // only that owner rather than waiting for every application's AX
            // tree before replaying an ordinary click.
            let frame: CGRect?
            if MenuBarItemScanner.usesAccessibilityBackend {
                frame = MenuBarItemScanner.refreshStatusWindow(item)?.frame
            } else {
                frame = MenuBarItemScanner.frame(of: item.id)
            }

            guard self.isCollapsed,
                  let frame,
                  Self.isInMenuBarStrip(frame),
                  self.isCurrentlyVisibleMenuBarItem(frame),
                  frame.insetBy(dx: -2, dy: -2).contains(point)
            else { return }

            if let identity = item.accessibilityIdentity {
                guard MenuBarAccessibility.matchesCurrentItem(
                    identity,
                    expectedLabel: item.windowName,
                    expectedFrame: frame
                ) else {
                    self.showAlert(
                        title: L10n.text(.identityChangedTitle),
                        message: L10n.text(.replayIdentityChanged)
                    )
                    return
                }
            }
            // Hosted menu extras may acknowledge AXPress without opening their
            // UI. Use the same validated primary-click path as proxy activation.
            EventForwarder.click(
                at: point,
                eventUserData: MenuBarCommandDragMonitor.syntheticClickEventMarker
            )
        }
    }

    private func finishExternalDrag(
        _ item: MenuBarItemWindow,
        at point: CGPoint,
        target: MenuBarImportDropTarget?
    ) {
        guard externalDragItemID == item.id else { return }
        Self.importLogger.notice(
            "external drag ended item=\(item.id, privacy: .public) acceptedTarget=\(target != nil, privacy: .public)"
        )
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = nil
        externalDragItemID = nil
        panel.updateExternalDrag(atQuartzPoint: point, isInsidePanel: target == .panel)
        panel.endExternalDrag()
        setImportTargetingToggle(false)
        guard target != nil else { return }
        let previewImage = importPreviewCache[item.id]

        // Defer teardown until the event-tap callback has returned the consumed
        // mouse-up. Invalidating a tap from inside its own callback is fragile.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.panel.close()
            self.importIntoFoldBar(item, previewImage: previewImage)
        }
    }

    private func importIntoFoldBar(
        _ item: MenuBarItemWindow,
        previewImage: NSImage?
    ) {
        guard requireAccessibility() else { return }
        if MenuBarItemScanner.usesAccessibilityBackend {
            importUsingPrivateVisibilityRestriction(
                item,
                previewImage: previewImage
            )
            return
        }
        expandRealMenuBar()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let diagnosticID = String(UUID().uuidString.prefix(8))
            let startedAt = ProcessInfo.processInfo.systemUptime
            Self.importLogger.notice(
                "import[\(diagnosticID, privacy: .public)] begin item=\(item.id, privacy: .public) source=\(Self.frameDescription(item.frame), privacy: .public)"
            )

            var sourceFrame: CGRect?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(140))
                await MenuBarItemScanner.refreshStatusWindows()
                if let found = MenuBarItemScanner.frame(of: item.id),
                   Self.isInMenuBarStrip(found) {
                    sourceFrame = found
                    break
                }
            }

            guard let sourceFrame,
                  self.isCurrentlyVisibleMenuBarItem(sourceFrame),
                  let targetX = self.currentImportTargetX(for: sourceFrame) else {
                Self.importLogger.error(
                    "import[\(diagnosticID, privacy: .public)] unavailable source=\(Self.frameDescription(sourceFrame), privacy: .public)"
                )
                showAlert(
                    title: L10n.text(.importUnavailableTitle),
                    message: L10n.text(.legacyImportUnavailable)
                )
                return
            }

            if let identity = item.accessibilityIdentity,
               !MenuBarAccessibility.matchesCurrentItem(
                   identity,
                   expectedLabel: item.windowName,
                   expectedFrame: sourceFrame
               ) {
                Self.importLogger.error(
                    "import[\(diagnosticID, privacy: .public)] cancelled: accessibility identity changed"
                )
                showAlert(
                    title: L10n.text(.identityChangedTitle),
                    message: L10n.text(.moveIdentityChanged)
                )
                return
            }

            let posted = await EventForwarder.commandDrag(
                from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                to: CGPoint(x: targetX, y: sourceFrame.midY),
                diagnosticID: diagnosticID
            )
            guard posted, await self.waitForLegacyImport(of: item.id) else {
                Self.importLogger.error(
                    "import[\(diagnosticID, privacy: .public)] failed posted=\(posted, privacy: .public)"
                )
                showAlert(
                    title: L10n.text(.importFailedTitle),
                    message: L10n.text(.legacyImportFailed)
                )
                return
            }

            // macOS 14–26 still needs the separator collapse to park the newly
            // ordered item and refresh the managed snapshot.
            self.collapse()
            let elapsedMilliseconds = Int(
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
            Self.importLogger.notice(
                "import[\(diagnosticID, privacy: .public)] succeeded elapsedMs=\(elapsedMilliseconds, privacy: .public)"
            )
        }
    }

    private func importUsingPrivateVisibilityRestriction(
        _ item: MenuBarItemWindow,
        previewImage: NSImage?
    ) {
        guard !preparingCollapse, activationTask == nil, promotionTask == nil else { return }
        let bundleIdentifier = item.bundleIdentifier
        guard !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            showAlert(
                title: L10n.text(.importUnavailableTitle),
                message: L10n.text(.privateMissingIdentity)
            )
            return
        }

        backgroundCaptureRetryPolicy.reset(bundleIdentifier: bundleIdentifier)
        promotionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.promotionTask = nil }
            // The open-panel monitor already owns a fresh full inventory. Only
            // re-resolve the dragged AX identity here; another all-application
            // scan made a simple drop take several seconds on busy systems.
            let refreshedDraggedItem = MenuBarItemScanner.refreshStatusWindow(item)
            var sameBundleItems = MenuBarItemScanner.statusWindows().filter {
                $0.bundleIdentifier == bundleIdentifier
            }
            if let refreshedDraggedItem,
               let index = sameBundleItems.firstIndex(where: {
                   $0.accessibilityIdentity == item.accessibilityIdentity
               }) {
                sameBundleItems[index] = refreshedDraggedItem
            }
            let liveItems = MenuBarItemScanner.panelDisplayOrder(sameBundleItems)
            guard refreshedDraggedItem != nil,
                  !liveItems.isEmpty,
                  Self.capturablePrivateItems(liveItems).count == liveItems.count,
                  liveItems.contains(where: {
                      $0.accessibilityIdentity == item.accessibilityIdentity
                          || $0.windowName == item.windowName
                  }) else {
                self.showAlert(
                    title: L10n.text(.identityChangedTitle),
                    message: L10n.text(.importIdentityChanged)
                )
                return
            }

            var captured: [CapturedItem]
            if liveItems.count == 1, let previewImage {
                captured = [CapturedItem(
                    window: liveItems[0],
                    image: previewImage,
                    hoverText: liveItems[0].displayName,
                    ownerProcessIdentifier: liveItems[0].ownerProcessIdentifier
                )]
            } else {
                captured = await IconCapturer.capture(liveItems)
                if let previewImage,
                   let index = captured.firstIndex(where: {
                       $0.window.accessibilityIdentity == item.accessibilityIdentity
                   }) {
                    let window = captured[index].window
                    captured[index] = CapturedItem(
                        window: window,
                        image: previewImage,
                        hoverText: window.displayName,
                        ownerProcessIdentifier: window.ownerProcessIdentifier
                    )
                }
            }

            guard !Task.isCancelled else { return }
            guard captured.count == liveItems.count else {
                self.showAlert(
                    title: L10n.text(.captureUnavailableTitle),
                    message: L10n.text(.captureUnavailableMessage)
                )
                return
            }

            let updated = self.managedBundleIdentifiers.union([
                bundleIdentifier
            ])
            let applied = await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: self.cachedPrivateBundleIdentifiers
                    .union([bundleIdentifier])
            )
            guard !Task.isCancelled else { return }
            guard applied else {
                self.showAlert(
                    title: L10n.text(.importFailedTitle),
                    message: L10n.text(.privateImportFailed)
                )
                return
            }

            self.managedBundleIdentifiers = updated
            ManagedMenuBarBundles.save(updated)
            self.cachedItems.removeAll {
                $0.window.bundleIdentifier == bundleIdentifier
            }
            self.cachedItems.append(contentsOf: captured)
            self.cachedItems = self.cachedItems.sorted {
                $0.window.frame.minX < $1.window.frame.minX
            }
            self.completeCollapse(
                knownManagedWindowIDs: Set(self.cachedItems.map(\.id))
            )
        }
    }

    // MARK: - Event safety

    static func isInStrip(_ frame: CGRect, displays: [CGRect]) -> Bool {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return displays.contains { display in
            display.contains(midpoint)
                && frame.minX >= display.minX
                && frame.maxX <= display.maxX
                && frame.minY >= display.minY - 2
                && frame.maxY <= display.minY + 42
                && frame.height <= 40
        }
    }

    static func isInVisibleMenuBarSegment(
        _ frame: CGRect,
        segments: [CGRect]
    ) -> Bool {
        segments.contains { segment in
            frame.minY >= segment.minY - 2
                && frame.maxY <= segment.maxY + 2
                && frame.minX >= segment.minX - 1
                && frame.maxX <= segment.maxX + 1
        }
    }

    static func activationPoint(
        itemFrame: CGRect,
        visibleSegments: [CGRect]
    ) -> CGPoint? {
        guard isInVisibleMenuBarSegment(itemFrame, segments: visibleSegments) else {
            return nil
        }
        return CGPoint(x: itemFrame.midX, y: itemFrame.midY)
    }

    static func isOnVisibleSide(
        _ frame: CGRect,
        separatorFrame: CGRect,
        usesManagedSceneGeometry: Bool = MenuBarItemScanner.usesAccessibilityBackend
    ) -> Bool {
        let boundary: CGFloat
        if usesManagedSceneGeometry,
           separatorFrame.width >= 2_500 {
            // macOS 27 scene-hosted status items report the oversized separator
            // as extending to the right across other menu extras. Its leading
            // edge remains the actual managed/visible ordering boundary.
            boundary = separatorFrame.minX
        } else {
            boundary = separatorFrame.maxX
        }
        return frame.minX >= boundary - 1
    }

    static func isOnHiddenSide(_ frame: CGRect, separatorFrame: CGRect) -> Bool {
        frame.maxX <= separatorFrame.minX + 1
    }

    static func importTargetX(
        itemFrame: CGRect,
        separatorFrame: CGRect,
        displays: [CGRect]
    ) -> CGFloat? {
        guard let display = displays.first(where: {
            $0.contains(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
        }) else { return nil }

        let lower = display.minX + itemFrame.width / 2
        let upper = min(
            display.maxX - itemFrame.width / 2,
            separatorFrame.minX - itemFrame.width / 2 - 2
        )
        guard lower <= upper else { return nil }

        // Move the pointer far enough past the separator that the entire item,
        // not just its center, lands on FoldBar's managed side.
        let proposed = separatorFrame.minX - itemFrame.width / 2 - 4
        return min(max(proposed, lower), upper)
    }

    static func promotionTargetX(
        itemFrame: CGRect,
        liveToggleFrame: CGRect,
        finalToggleFrame: CGRect,
        visibleSegments: [CGRect]
    ) -> CGFloat? {
        guard itemFrame.width > 0,
              itemFrame.width.isFinite,
              liveToggleFrame.minX.isFinite,
              finalToggleFrame.minX.isFinite,
              let segment = visibleSegments.first(where: {
                Self.isInVisibleMenuBarSegment(itemFrame, segments: [$0])
                    && finalToggleFrame.midX >= $0.minX
                    && finalToggleFrame.midX <= $0.maxX
              }) else { return nil }

        // Stop at the live trigger rather than the separator. When earlier
        // promotions already occupy the visible section, this crosses all of
        // them and inserts the new item directly beside the trigger. The live
        // frame also tracks any temporary width reduction used to clear the
        // notch, avoiding a stale pre-layout coordinate.
        let targetX = liveToggleFrame.minX - 2
        let finalSlotMinX = finalToggleFrame.minX - itemFrame.width
        guard finalSlotMinX >= segment.minX - 1,
              targetX >= segment.minX,
              targetX <= segment.maxX else { return nil }
        return targetX
    }

    static func availableAutomaticPlacementWidth(
        toggleFrame: CGRect,
        visibleSegments: [CGRect],
        statusItems: [MenuBarItemWindow]
    ) -> CGFloat {
        guard let segment = visibleSegments.first(where: {
            toggleFrame.midX >= $0.minX && toggleFrame.midX <= $0.maxX
        }) else { return 0 }

        let itemsLeftOfToggle = statusItems.filter { item in
            item.frame.width > 0
                && item.frame.width < 500
                && item.frame.height <= 40
                && item.frame.maxX <= toggleFrame.minX + 1
                && item.frame.maxX >= segment.minX - 1
                && item.frame.minY >= segment.minY - 2
                && item.frame.maxY <= segment.maxY + 2
        }
        let occupiedMinX = itemsLeftOfToggle.map(\.frame.minX).min() ?? toggleFrame.minX
        guard occupiedMinX >= segment.minX else { return 0 }
        return max(0, occupiedMinX - segment.minX)
    }

    static func isImmediatelyLeftOfToggle(
        _ frame: CGRect,
        toggleFrame: CGRect
    ) -> Bool {
        let gap = toggleFrame.minX - frame.maxX
        return gap >= -1 && gap <= 2
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map(CGDisplayBounds)
    }

    static func activeVisibleMenuBarSegments() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                return nil
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let rightArea = screen.auxiliaryTopRightArea.flatMap {
                $0.width > 0 ? $0 : nil
            }
            let minX = rightArea?.minX ?? displayBounds.minX
            let width = rightArea?.width ?? displayBounds.width
            return CGRect(
                x: minX,
                y: displayBounds.minY,
                width: width,
                height: 40
            )
        }
    }

    private static func isInMenuBarStrip(_ frame: CGRect) -> Bool {
        isInStrip(frame, displays: activeDisplayBounds())
    }

    private func waitForStableMenuBarFrame(of id: CGWindowID) async -> CGRect? {
        var previous: CGRect?

        for _ in 0..<8 {
            guard (try? await Task.sleep(for: .milliseconds(70))) != nil,
                  !Task.isCancelled else { return nil }
            await MenuBarItemScanner.refreshStatusWindows()
            guard let frame = MenuBarItemScanner.frame(of: id),
                  Self.isInMenuBarStrip(frame) else {
                previous = nil
                continue
            }
            if previous == frame { return frame }
            previous = frame
        }
        return previous
    }

    /// Proxy activation waits for both the visible Quartz frame and the owning
    /// application's AX anchor. Poll at roughly one display refresh instead of
    /// holding a visual transition layer through this synchronization window.
    private func waitForActivationFrame(of item: CapturedItem) async -> CGRect? {
        var previous: CGRect?
        var stablePolls = 0

        for poll in 0..<20 {
            if poll > 0 {
                guard (try? await Task.sleep(for: .milliseconds(16))) != nil,
                      !Task.isCancelled else { return nil }
            }
            await MenuBarItemScanner.refreshStatusWindows()
            guard let frame = MenuBarItemScanner.frame(of: item.id),
                  Self.isInMenuBarStrip(frame) else {
                previous = nil
                stablePolls = 0
                continue
            }
            if previous == frame {
                stablePolls += 1
                if let owner = item.ownerProcessIdentifier {
                    if MenuBarItemMetadataResolver.hasSynchronizedMenuExtra(
                        ownerProcessIdentifier: owner,
                        matching: frame
                    ) {
                        return frame
                    }
                } else if stablePolls >= 8 {
                    // Metadata is optional. Without an owner process, retain a
                    // bounded settling interval so the target's internal anchor
                    // can catch up with its already-stable Quartz window.
                    return frame
                }
            } else {
                stablePolls = 0
            }
            previous = frame
        }
        // AX metadata can be absent or stale for otherwise clickable status
        // items. The full poll window is the bounded fallback in that case.
        return previous
    }

    private func waitForTargetPresentation(
        ownerProcessIdentifier: pid_t,
        on displayBounds: CGRect,
        excluding baselineWindowIDs: Set<CGWindowID>
    ) async -> Bool {
        for poll in 0..<Self.activationPresentationPolls {
            if poll > 0 {
                guard (try? await Task.sleep(for: .milliseconds(20))) != nil,
                      !Task.isCancelled else { return false }
            }
            let current = ActivationWindowScanner.visibleAuxiliaryWindowIDs(
                ownerProcessIdentifier: ownerProcessIdentifier,
                on: displayBounds
            )
            if !current.subtracting(baselineWindowIDs).isEmpty { return true }
        }
        return false
    }

    private func waitForPromotion(
        of id: CGWindowID,
        diagnosticID: String
    ) async -> Bool {
        var stablePolls = 0

        for poll in 1...20 {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return false }
            await MenuBarItemScanner.refreshStatusWindows()
            guard let frame = MenuBarItemScanner.frame(of: id) else {
                Self.promotionLogger.notice(
                    "promotion[\(diagnosticID, privacy: .public)] verify poll=\(poll, privacy: .public) item-window-missing"
                )
                stablePolls = 0
                continue
            }
            guard let toggleFrame = toggleItem.button?.window?.frame else {
                Self.promotionLogger.notice(
                    "promotion[\(diagnosticID, privacy: .public)] verify poll=\(poll, privacy: .public) own-window-missing item=\(Self.frameDescription(frame), privacy: .public)"
                )
                stablePolls = 0
                continue
            }

            let inStrip = Self.isInMenuBarStrip(frame)
            let boundaryFrame: CGRect?
            let visible: Bool
            if MenuBarItemScanner.usesAccessibilityBackend {
                boundaryFrame = MenuBarItemScanner.systemOverflowFrame()
                visible = boundaryFrame.map {
                    MenuBarItemScanner.isVisibleBySystemOverflow(
                        frame,
                        overflowFrame: $0
                    )
                } ?? false
            } else {
                boundaryFrame = separatorItem.button?.window?.frame
                visible = boundaryFrame.map {
                    Self.isOnVisibleSide(frame, separatorFrame: $0)
                } ?? false
            }
            let adjacent = Self.isImmediatelyLeftOfToggle(frame, toggleFrame: toggleFrame)
            let gap = toggleFrame.minX - frame.maxX
            Self.promotionLogger.notice(
                "promotion[\(diagnosticID, privacy: .public)] verify poll=\(poll, privacy: .public) item=\(Self.frameDescription(frame), privacy: .public) boundary=\(Self.frameDescription(boundaryFrame), privacy: .public) toggle=\(Self.frameDescription(toggleFrame), privacy: .public) inStrip=\(inStrip, privacy: .public) visible=\(visible, privacy: .public) adjacent=\(adjacent, privacy: .public) gap=\(gap, privacy: .public) stableBefore=\(stablePolls, privacy: .public)"
            )

            if inStrip, visible, adjacent {
                stablePolls += 1
                if stablePolls >= Self.promotionConfirmationPolls {
                    return true
                }
            } else {
                stablePolls = 0
            }
        }
        return false
    }

    private static func frameDescription(_ frame: CGRect?) -> String {
        guard let frame else { return "nil" }
        return String(
            format: "x=%.1f,y=%.1f,w=%.1f,h=%.1f",
            frame.minX,
            frame.minY,
            frame.width,
            frame.height
        )
    }

    private static func frameDescriptions(_ frames: [CGRect]) -> String {
        frames.map { frameDescription($0) }.joined(separator: ";")
    }

    private func waitForLegacyImport(of id: CGWindowID) async -> Bool {
        for _ in 0..<12 {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else {
                return false
            }
            await MenuBarItemScanner.refreshStatusWindows()
            guard let window = MenuBarItemScanner.statusWindows().first(where: {
                $0.id == id
            }), Self.isInMenuBarStrip(window.frame),
            let separatorFrame = separatorItem.button?.window?.frame else { continue }
            if Self.isOnHiddenSide(window.frame, separatorFrame: separatorFrame) {
                return true
            }
        }
        return false
    }

    private func isCurrentlyVisibleMenuBarItem(_ frame: CGRect) -> Bool {
        if MenuBarItemScanner.usesAccessibilityBackend {
            guard let overflowFrame = MenuBarItemScanner.systemOverflowFrame() else {
                return Self.isInMenuBarStrip(frame)
            }
            return MenuBarItemScanner.isVisibleBySystemOverflow(
                frame,
                overflowFrame: overflowFrame
            )
        }
        guard let separatorFrame = separatorItem.button?.window?.frame else {
            return false
        }
        return Self.isOnVisibleSide(frame, separatorFrame: separatorFrame)
    }

    private func currentImportTargetX(for itemFrame: CGRect) -> CGFloat? {
        guard let separatorFrame = separatorItem.button?.window?.frame else {
            return nil
        }
        return Self.importTargetX(
            itemFrame: itemFrame,
            separatorFrame: separatorFrame,
            displays: Self.activeDisplayBounds()
        )
    }

    private func requireAccessibility() -> Bool {
        guard EventForwarder.isTrusted() else {
            presentPermissionCenter()
            return false
        }
        return true
    }

    private func armAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(450))) != nil else { return }
            guard let self, !self.isCollapsed else { return }
            if self.autoCollapseMonitor == nil {
                self.autoCollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                    let userData = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
                    guard Self.shouldFinishAutoCollapse(eventUserData: userData) else { return }
                    MainActor.assumeIsolated { self?.finishAutoCollapse() }
                }
            }
            guard (try? await Task.sleep(for: .seconds(15))) != nil else { return }
            self.finishAutoCollapse()
        }
    }

    private func finishAutoCollapse() {
        disarmAutoCollapse()
        if !isCollapsed { collapse() }
    }

    static func shouldFinishAutoCollapse(eventUserData: Int64) -> Bool {
        eventUserData != MenuBarCommandDragMonitor.syntheticClickEventMarker
    }

    private func disarmAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        if let monitor = autoCollapseMonitor {
            NSEvent.removeMonitor(monitor)
            autoCollapseMonitor = nil
        }
    }

    // MARK: - Menu and dialogs

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: L10n.text(.openPanel), action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        open.isEnabled = isCollapsed
        menu.addItem(open)

        let settings = NSMenuItem(title: L10n.text(.settings), action: #selector(settingsFromMenu), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(
            title: permissionMenuTitle,
            action: #selector(permissionFromMenu),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())

        let login = NSMenuItem(title: L10n.text(.launchAtLogin), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let about = NSMenuItem(title: L10n.text(.aboutTitle), action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.text(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func openFromMenu() { openPanel() }
    @objc private func settingsFromMenu() { settingsPanel.show() }
    @objc private func permissionFromMenu() { presentPermissionCenter() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            showAlert(
                title: L10n.text(.loginFailedTitle),
                message: L10n.text(.loginFailedMessage)
            )
        }
    }

    @objc private func openAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        showAlert(
            title: L10n.text(.aboutTitle),
            message: L10n.format(.aboutMessage, version, build)
        )
    }

    private var permissionMenuTitle: String {
        if IconCapturer.hasPermission(), EventForwarder.isTrusted() {
            return L10n.text(.permissionsGrantedMenu)
        }
        return L10n.text(.permissionsMenu)
    }

    private func schedulePermissionOnboarding() {
        guard PermissionOnboardingPolicy().shouldPresentAutomatically(
            screenGranted: IconCapturer.hasPermission(),
            accessibilityGranted: EventForwarder.isTrusted()
        ) else { return }

        Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(900))) != nil else { return }
            guard let self,
                  !self.permissionFlowActive,
                  PermissionOnboardingPolicy().shouldPresentAutomatically(
                    screenGranted: IconCapturer.hasPermission(),
                    accessibilityGranted: EventForwarder.isTrusted()
                  ) else { return }
            self.presentPermissionCenter()
        }
    }

    /// macOS owns the two privacy prompts and cannot combine them into one
    /// system sheet. FoldBar uses one explanatory action to request both once,
    /// then stops re-triggering the OS prompts on every icon interaction.
    private func presentPermissionCenter() {
        guard !permissionFlowActive else { return }
        permissionFlowActive = true
        defer { permissionFlowActive = false }

        let screenGranted = IconCapturer.hasPermission()
        let accessibilityGranted = EventForwarder.isTrusted()
        let policy = PermissionOnboardingPolicy()
        let destination = policy.destination(
            screenGranted: screenGranted,
            accessibilityGranted: accessibilityGranted
        )
        if destination == .allGranted {
            showAlert(
                title: L10n.text(.permissionsGrantedTitle),
                message: L10n.text(.permissionsGrantedMessage)
            )
            return
        }

        if destination == .requestPermissions {
            let response = runAlert(
                title: L10n.text(.permissionsOnboardingTitle),
                message: L10n.text(.permissionsOnboardingMessage),
                buttons: [
                    L10n.text(.requestPermissions),
                    L10n.text(.later)
                ]
            )
            let requestsPermissions = response == .alertFirstButtonReturn
            policy.recordDecision(requestPermissions: requestsPermissions)
            guard requestsPermissions else { return }
            if !screenGranted { IconCapturer.requestPermission() }
            if !accessibilityGranted { EventForwarder.promptForAccessibility() }
            return
        }

        let screenStatus = screenGranted ? L10n.text(.permissionGranted) : L10n.text(.permissionDenied)
        let accessibilityStatus = accessibilityGranted ? L10n.text(.permissionGranted) : L10n.text(.permissionDenied)
        let response = runAlert(
            title: L10n.text(.permissionsTitle),
            message: L10n.format(.permissionsStatus, screenStatus, accessibilityStatus),
            buttons: [L10n.text(.openSystemSettings), L10n.text(.cancel)]
        )
        guard response == .alertFirstButtonReturn else { return }
        openPrivacySettings(anchor: screenGranted ? "Privacy_Accessibility" : "Privacy_ScreenCapture")
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showRestartForCacheAlert() {
        let message = MenuBarItemScanner.usesAccessibilityBackend
            ? L10n.text(.restartPrivateCache)
            : L10n.text(.restartLegacyCache)
        let response = runAlert(
            title: L10n.text(.restartTitle),
            message: message,
            buttons: [L10n.text(.restart), L10n.text(.later)]
        )
        guard response == .alertFirstButtonReturn else { return }
        relaunch()
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if error != nil {
                    self?.showAlert(
                        title: L10n.text(.restartFailedTitle),
                        message: L10n.text(.restartFailedMessage)
                    )
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        _ = runAlert(title: title, message: message, buttons: [L10n.text(.ok)])
    }

    private func runAlert(
        title: String,
        message: String,
        buttons: [String]
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
