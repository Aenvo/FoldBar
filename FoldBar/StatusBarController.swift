import AppKit
import OSLog
import ServiceManagement

@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 45
    private static var collapsedItemPollMilliseconds: Int {
        MenuBarItemScanner.usesAccessibilityBackend ? 5_000 : 600
    }
    private static let maximumAutomaticPlacementBatch = 2
    private static let automaticPlacementStabilizationMilliseconds = 10_000
    private static let automaticPlacementRetryDelaysMilliseconds = [2_000]
    private static let promotionConfirmationPolls = 3
    private static let activationPresentationPolls = 60
    private static let privateActivationSettleMilliseconds = 200
    private static let toggleAutosaveName = "foldbar_toggle"
    private static let separatorAutosaveName = "foldbar_separator"
    private static let combinedPermissionRequestKey = "didRequestCombinedPermissionsV1"
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
    private var importPreviewImages: [CGWindowID: NSImage] = [:]
    private var importPreviewRequestedIDs: Set<CGWindowID> = []
    private var cachedItems: [CapturedItem] = []
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
        guard isCollapsed else { return }
        isCollapsed = false
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
            windows = MenuBarItemScanner.itemsLeft(of: separatorFrame.minX)
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
        let knownIDs = Set(windows.map(\.id))

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
                        return liveIdentity.bundleIdentifier
                            == cachedIdentity.bundleIdentifier
                            && liveIdentity.ordinal == cachedIdentity.ordinal
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
            let newlyCaptured = missing.isEmpty
                ? []
                : await IconCapturer.capture(missing)
            guard !Task.isCancelled, !self.isCollapsed else { return }
            let applied = await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: self.managedBundleIdentifiers
            )
            guard !Task.isCancelled else { return }
            guard applied else {
                self.preparingCollapse = false
                self.cacheCaptureTask = nil
                self.isCollapsed = false
                self.updateToggleIcon()
                return
            }
            let byID = Dictionary(
                uniqueKeysWithValues: (reusable + newlyCaptured).map {
                    ($0.id, $0)
                }
            )
            self.cachedItems = windows.compactMap { byID[$0.id] }
            self.completeCollapse(knownManagedWindowIDs: knownIDs)
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
        isCollapsed = false
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        guard let button = toggleItem.button else { return }
        if isImportTargetingToggle {
            // Keep the same symbol while targeting so the status item's frame
            // cannot shift underneath the fixed drop-target geometry.
            button.image = symbol("chevron.down")
            button.contentTintColor = .controlAccentColor
            button.toolTip = "松手以收进 FoldBar"
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
            onDismiss: { [weak self] in self?.disarmMenuBarImport() }
        )
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
        guard let separatorMinX = separatorItem.button?.window?.frame.minX else {
            return []
        }
        return MenuBarItemScanner.itemsLeft(of: separatorMinX)
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
                title: "无法展开菜单栏代理",
                message: "FoldBar 箭头左侧没有可安全使用的菜单栏空间。你仍可在溢出面板中操作这些图标。"
            )
        }
    }

    // MARK: - Newly launched status items

    private func armCollapsedItemMonitor() {
        disarmCollapsedItemMonitor()
        guard isCollapsed else { return }

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

                await MenuBarItemScanner.refreshStatusWindows()
                if MenuBarItemScanner.usesAccessibilityBackend {
                    self.refreshPrivateManagedIdentities()
                    continue
                }
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

    private func refreshPrivateManagedIdentities() {
        let liveItems = MenuBarItemScanner.statusWindows().filter {
            managedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        guard !liveItems.isEmpty else { return }

        let existingByIdentity = Dictionary(
            uniqueKeysWithValues: cachedItems.compactMap { item in
                item.window.accessibilityIdentity.map { ($0, item) }
            }
        )
        cachedItems = MenuBarItemScanner.panelDisplayOrder(liveItems).compactMap {
            window in
            guard let identity = window.accessibilityIdentity,
                  let existing = existingByIdentity[identity]
                    ?? cachedItems.first(where: {
                        $0.window.bundleIdentifier == window.bundleIdentifier
                    }) else { return nil }
            return CapturedItem(
                window: window,
                image: existing.image,
                hoverText: window.displayName,
                ownerProcessIdentifier: window.ownerProcessIdentifier
            )
        }
        knownManagedWindowIDs = Set(liveItems.map(\.id))
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
        guard activationTask == nil, promotionTask == nil else {
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

        let temporarilyHidden = managedBundleIdentifiers.subtracting([
            bundleIdentifier
        ])
        guard await visibilityRestriction.apply(
            hiddenBundleIdentifiers: temporarilyHidden
        ) else {
            showAlert(
                title: "图标暂时无法点击",
                message: "macOS 27 没有接受这次临时显示请求。FoldBar 已保持原收纳状态。"
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
                hiddenBundleIdentifiers: managedBundleIdentifiers
            )
            isCollapsed = true
            updateToggleIcon()
            showAlert(
                title: "图标暂时无法点击",
                message: "真实菜单栏图标没有在可点击区域稳定出现。FoldBar 已恢复收纳，没有点击其他程序。"
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
                title: "图标暂时无法点击",
                message: "为刘海腾出空间后，这个真实图标仍未完整进入可点击区域。菜单栏已保持展开，请直接操作它。"
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
                    title: "图标暂时无法点击",
                    message: "macOS 更新了这个菜单栏图标的身份或位置。为避免点错应用，FoldBar 已停止操作并保持菜单栏展开。"
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
              promotionTask == nil else { return }
        promotionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let updated = self.managedBundleIdentifiers.subtracting([
                bundleIdentifier
            ])
            if await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: updated
            ) {
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
                    title: "无法移出这个应用",
                    message: "macOS 27 没有接受可见性更新。FoldBar 已保留原收纳状态。"
                )
            }
            self.promotionTask = nil
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
                    title: "图标身份已经变化",
                    message: "macOS 在操作前更新了这个菜单栏图标。为避免移动错误的项目，FoldBar 已停止操作并保持菜单栏展开。"
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
                    title: "图标没有移动成功",
                    message: "macOS 没有把这个图标放到 FoldBar 箭头左侧。菜单栏已保持展开，请按住 ⌘ 将它拖到箭头左侧并紧靠箭头。"
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
            title: "无法移动这个图标",
            message: "为刘海腾出空间后，真实图标仍没有进入可拖动的菜单栏区域。菜单栏已保持展开，请手动按住 ⌘ 拖动。"
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
        let candidates = currentImportCandidates()
        guard menuBarImportMonitor.start(
            candidates: candidates,
            panelTargetFrame: panelTargetFrame,
            toggleTargetFrame: toggleTargetFrame
        ) else { return }
        prefetchImportPreviewImages(for: candidates)

        importCandidateRefreshTask = Task { @MainActor [weak self] in
            while let self, self.panel.isVisible, self.menuBarImportMonitor.isRunning {
                guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
                guard self.panel.isVisible else { return }
                await MenuBarItemScanner.refreshStatusWindows()
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
        importPreviewImages = [:]
        importPreviewRequestedIDs = []
        menuBarImportMonitor.stop()
        setImportTargetingToggle(false)
    }

    private func prefetchImportPreviewImages(for candidates: [MenuBarItemWindow]) {
        guard importPreviewPrefetchTask == nil else { return }
        let missing = candidates.filter { !importPreviewRequestedIDs.contains($0.id) }
        guard !missing.isEmpty else { return }
        importPreviewRequestedIDs.formUnion(missing.map(\.id))

        importPreviewPrefetchTask = Task { @MainActor [weak self] in
            let images = await IconCapturer.captureImages(missing)
            guard let self, !Task.isCancelled, self.panel.isVisible else { return }
            self.importPreviewImages.merge(images) { _, fresh in fresh }
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
            // The system `«` may still hide unrelated items when the strip is
            // crowded, but it is not FoldBar's storage boundary. Only accept
            // real, currently visible items that are not in FoldBar's set.
            let systemOverflowFrame = MenuBarItemScanner.systemOverflowFrame()
            candidates = MenuBarItemScanner.statusWindows().filter { window in
                !managedBundleIdentifiers.contains(window.bundleIdentifier)
                    && Self.isInVisibleMenuBarSegment(
                        window.frame,
                        segments: Self.activeVisibleMenuBarSegments()
                    )
                    && (systemOverflowFrame.map { overflowFrame in
                        MenuBarItemScanner.isVisibleBySystemOverflow(
                            window.frame,
                            overflowFrame: overflowFrame
                        )
                    } ?? true)
            }
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
        externalDragItemID = item.id
        setImportTargetingToggle(false)
        panel.beginExternalDrag(
            image: importPreviewImages[item.id],
            atQuartzPoint: point
        )
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = Task { @MainActor [weak self] in
            let captured = await IconCapturer.captureImages([item])
            guard let self,
                  !Task.isCancelled,
                  self.externalDragItemID == item.id,
                  let image = captured[item.id] else { return }
            self.importPreviewImages[item.id] = image
            self.panel.updateExternalDragImage(image)
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
            await MenuBarItemScanner.refreshStatusWindows()

            guard self.isCollapsed,
                  let frame = MenuBarItemScanner.frame(of: item.id),
                  Self.isInMenuBarStrip(frame),
                  self.isCurrentlyVisibleMenuBarItem(frame),
                  frame.insetBy(dx: -2, dy: -2).contains(point)
            else { return }

            if let identity = item.accessibilityIdentity {
                guard MenuBarAccessibility.performPress(
                    on: identity,
                    expectedLabel: item.windowName,
                    expectedFrame: frame
                ) else {
                    self.showAlert(
                        title: "图标身份已经变化",
                        message: "macOS 在点击前更新了这个菜单栏图标。为避免打开错误的项目，FoldBar 已停止操作。"
                    )
                    return
                }
            } else {
                EventForwarder.click(
                    at: point,
                    eventUserData: MenuBarCommandDragMonitor.syntheticClickEventMarker
                )
            }
        }
    }

    private func finishExternalDrag(
        _ item: MenuBarItemWindow,
        at point: CGPoint,
        target: MenuBarImportDropTarget?
    ) {
        guard externalDragItemID == item.id else { return }
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = nil
        externalDragItemID = nil
        panel.updateExternalDrag(atQuartzPoint: point, isInsidePanel: target == .panel)
        panel.endExternalDrag()
        setImportTargetingToggle(false)
        guard target != nil else { return }
        let previewImage = importPreviewImages[item.id]

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
                    title: "无法收纳这个图标",
                    message: "真实图标或 FoldBar 分隔符没有出现在可安全拖动的菜单栏区域。菜单栏已保持展开，你可以手动按住 ⌘ 调整。"
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
                    title: "图标身份已经变化",
                    message: "macOS 在操作前更新了这个菜单栏图标。为避免移动错误的项目，FoldBar 已停止操作并保持菜单栏展开。"
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
                    title: "图标没有收纳成功",
                    message: "macOS 没有接受这次自动拖动。菜单栏已保持展开，请按住 ⌘ 将这个真实图标拖到 FoldBar 分隔符左侧。"
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
        let bundleIdentifier = item.bundleIdentifier
        guard !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            showAlert(
                title: "无法收纳这个图标",
                message: "macOS 27 没有提供这个菜单栏项目的应用标识。FoldBar 没有修改菜单栏。"
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
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
                  liveItems.contains(where: {
                      $0.accessibilityIdentity == item.accessibilityIdentity
                          || $0.windowName == item.windowName
                  }) else {
                self.showAlert(
                    title: "图标身份已经变化",
                    message: "macOS 在收纳前重建了这个菜单栏项目。FoldBar 没有隐藏任何程序，请重新拖入。"
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

            let updated = self.managedBundleIdentifiers.union([
                bundleIdentifier
            ])
            guard await self.visibilityRestriction.apply(
                hiddenBundleIdentifiers: updated
            ) else {
                self.showAlert(
                    title: "图标没有收纳成功",
                    message: "macOS 27 的菜单栏服务没有接受 FoldBar 的独立收纳请求；真实图标保持可见。"
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

    private static func activeVisibleMenuBarSegments() -> [CGRect] {
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

        let open = NSMenuItem(title: "打开溢出面板", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        open.isEnabled = isCollapsed
        menu.addItem(open)

        let settings = NSMenuItem(title: "设置", action: #selector(settingsFromMenu), keyEquivalent: "")
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

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let about = NSMenuItem(title: "关于 FoldBar", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
                title: "无法更改登录启动",
                message: "请先把应用移动到“应用程序”文件夹，或在系统设置 › 通用 › 登录项中管理。"
            )
        }
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Based in part on MenubarHide (MIT).\nNo Ice source code is included.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private var permissionMenuTitle: String {
        if IconCapturer.hasPermission(), EventForwarder.isTrusted() {
            return "权限：已完整授权"
        }
        return "权限设置…"
    }

    private func schedulePermissionOnboarding() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.combinedPermissionRequestKey),
              !IconCapturer.hasPermission() || !EventForwarder.isTrusted() else { return }

        Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(900))) != nil else { return }
            self?.presentPermissionCenter()
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
        if screenGranted, accessibilityGranted {
            showAlert(
                title: "权限已完整授权",
                message: "屏幕录制用于显示图标和折叠区域；辅助功能用于识别菜单栏项目，以及你主动发起的点击、收纳或拖动操作。"
            )
            return
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.combinedPermissionRequestKey) {
            let response = runAlert(
                title: "FoldBar 需要两项权限",
                message: "屏幕录制：读取菜单栏小图标和折叠区域。\n辅助功能：识别菜单栏项目，并转发你主动执行的点击和拖动。\n\n点击一次后，macOS 会分别显示两个系统级确认；FoldBar 不会在后续操作中反复请求。",
                buttons: [
                    "一次性请求两项权限",
                    "稍后"
                ]
            )
            guard response == .alertFirstButtonReturn else { return }
            defaults.set(true, forKey: Self.combinedPermissionRequestKey)
            if !screenGranted { IconCapturer.requestPermission() }
            if !accessibilityGranted { EventForwarder.promptForAccessibility() }
            return
        }

        let screenStatus = screenGranted ? "已授权" : "未授权"
        let accessibilityStatus = accessibilityGranted ? "已授权" : "未授权"
        let response = runAlert(
            title: "FoldBar 权限设置",
            message: "屏幕录制：\(screenStatus)\n辅助功能：\(accessibilityStatus)\n\n系统提示已经请求过，不会再次自动弹出。请在系统设置中打开缺少的权限。",
            buttons: ["打开系统设置", "取消"]
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
            ? "权限已经可用，但这一进程启动时还没有建立代理缓存。重新启动后会在折叠前截取真实图标并生成白色模板。"
            : "屏幕录制权限已经可用，但这一进程启动时还没有建立图标缓存。重新启动后会在折叠前预先采集，面板即可直接出现。"
        let response = runAlert(
            title: "需要重新启动 FoldBar",
            message: message,
            buttons: ["重新启动", "稍后"]
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
                if let error {
                    self?.showAlert(title: "无法重新启动 FoldBar", message: error.localizedDescription)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        _ = runAlert(title: title, message: message, buttons: ["好"])
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
