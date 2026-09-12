import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 45
    private static let collapsedItemPollMilliseconds = 600
    private static let maximumAutomaticPlacementBatch = 2
    private static let automaticPlacementStabilizationMilliseconds = 10_000
    private static let automaticPlacementRetryDelaysMilliseconds = [2_000]
    private static let promotionConfirmationPolls = 3
    private static let toggleAutosaveName = "foldbar_toggle"
    private static let separatorAutosaveName = "foldbar_separator"
    private static let combinedPermissionRequestKey = "didRequestCombinedPermissionsV1"

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = OverflowPanel()
    private let expandedMenuBarPanel = ExpandedMenuBarPanel()
    private let settingsPanel = AppearanceSettingsPanel()

    private var initialCollapseTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var autoCollapseMonitor: Any?
    private var cacheCaptureTask: Task<Void, Never>?
    private var importCandidateRefreshTask: Task<Void, Never>?
    private var externalDragCaptureTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var promotionTask: Task<Void, Never>?
    private var collapsedItemMonitorTask: Task<Void, Never>?
    private var automaticPlacementTask: Task<Void, Never>?
    private var externalDragItemID: CGWindowID?
    private var cachedItems: [CapturedItem] = []
    private var knownManagedWindowIDs: Set<CGWindowID> = []
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

        // Create the always-visible trigger first, then the separator to its left.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = Self.toggleAutosaveName
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = Self.separatorAutosaveName

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "FoldBar"
        }
        separatorItem.button?.image = symbol("chevron.left.to.line")
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
        // Promotion and proxy activation can temporarily reduce FoldBar's own
        // status-item lengths beside a notch. Quitting restores both immediately.
        separatorItem.length = NSStatusItem.variableLength
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

        let windows: [MenuBarItemWindow]
        if let separatorFrame = separatorItem.button?.window?.frame {
            windows = MenuBarItemScanner.itemsLeft(of: separatorFrame.minX)
        } else {
            windows = []
        }
        let knownIDs = Set(windows.map(\.id))

        guard IconCapturer.hasPermission(), !windows.isEmpty else {
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

    private func completeCollapse(knownManagedWindowIDs: Set<CGWindowID>) {
        preparingCollapse = false
        cacheCaptureTask = nil
        _ = MenuBarArrangement.captureAndSave()
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        self.knownManagedWindowIDs = knownManagedWindowIDs
        updateToggleIcon()
        armCollapsedItemMonitor()
    }

    private func expandRealMenuBar() {
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
        separatorItem.length = NSStatusItem.variableLength
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
            onExpand: { [weak self] in self?.showExpandedMenuBar() },
            onSettings: { [weak self] in self?.settingsPanel.show() },
            onDismiss: { [weak self] in self?.disarmMenuBarImport() }
        )
        armMenuBarImport()
    }

    private func currentManagedItems() -> (
        hidden: [MenuBarItemWindow],
        captured: [CapturedItem]
    ) {
        let hidden = MenuBarItemScanner.hiddenItems()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })
        let items = MenuBarItemScanner.panelDisplayOrder(hidden).compactMap {
            cachedByID[$0.id]
        }
        return (hidden, items)
    }

    private func showExpandedMenuBar() {
        guard isCollapsed else { return }
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

                let hidden = MenuBarItemScanner.hiddenItems()
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
        guard requireAccessibility() else { return }
        guard activationTask == nil, promotionTask == nil else { return }
        expandRealMenuBar()

        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performActivation(item)
            self.activationTask = nil
        }
    }

    private func performActivation(_ item: CapturedItem) async {
        let originalToggleLength = toggleItem.length
        let originalSeparatorLength = separatorItem.length
        defer {
            separatorItem.length = originalSeparatorLength
            toggleItem.length = originalToggleLength
        }

        // A far-left managed item can remain partly behind the notch even after
        // expanding the separator. Temporarily reclaim our trigger's width,
        // then the separator's width if needed, before forwarding any click.
        // This preserves the real item order and mirrors the space-making path
        // used by promotion without performing a Command-drag.
        let visibleSegments = Self.activeVisibleMenuBarSegments()
        toggleItem.length = 0
        var frame = await waitForStableMenuBarFrame(of: item.id)

        if frame.flatMap({
            Self.activationPoint(itemFrame: $0, visibleSegments: visibleSegments)
        }) == nil {
            separatorItem.length = 0
            frame = await waitForStableMenuBarFrame(of: item.id)
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

        EventForwarder.click(at: point)
        // Let the target app establish its menu or popover before restoring
        // FoldBar's own widths and reflowing the status bar again.
        guard (try? await Task.sleep(for: .milliseconds(140))) != nil,
              !Task.isCancelled else { return }
        armAutoCollapse()
    }

    private func promoteToMenuBar(_ item: CapturedItem) {
        guard requireAccessibility() else { return }
        guard promotionTask == nil else { return }
        expandRealMenuBar()

        promotionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPromotion(item)
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
        guard let originalToggleFrame = toggleItem.button?.window?.frame else {
            if reportsFailure { showPromotionUnavailableAlert() }
            return false
        }

        let originalToggleLength = toggleItem.length
        let originalSeparatorLength = separatorItem.length
        defer {
            separatorItem.length = originalSeparatorLength
            toggleItem.length = originalToggleLength
        }

        // macOS can keep otherwise valid status-item windows under the notch,
        // where a synthetic mouse-down cannot begin AppKit's reorder gesture.
        // Temporarily remove our trigger's footprint so WindowServer can move the
        // requested item into the real, interactive right-hand menu-bar area.
        toggleItem.length = 0
        var frame = await waitForStableMenuBarFrame(of: item.id)

        // On a crowded bar the trigger alone may not free enough room. The
        // separator can also be reduced safely because its original order and
        // length are restored immediately after the mouse-up.
        let visibleSegments = Self.activeVisibleMenuBarSegments()
        if frame.map({
            !Self.isInVisibleMenuBarSegment($0, segments: visibleSegments)
        }) ?? true {
            separatorItem.length = 0
            frame = await waitForStableMenuBarFrame(of: item.id)
        }

        guard !Task.isCancelled else { return false }
        guard let frame,
              Self.isInVisibleMenuBarSegment(frame, segments: visibleSegments),
              let targetX = Self.promotionTargetX(
                itemFrame: frame,
                toggleFrame: originalToggleFrame,
                visibleSegments: visibleSegments
              ) else {
            if reportsFailure { showPromotionUnavailableAlert() }
            return false
        }

        let posted = await EventForwarder.commandDrag(
            from: CGPoint(x: frame.midX, y: frame.midY),
            to: CGPoint(x: targetX, y: frame.midY)
        )

        // Put FoldBar's own items back before checking which side of the
        // separator now owns the promoted window.
        separatorItem.length = originalSeparatorLength
        toggleItem.length = originalToggleLength
        guard (try? await Task.sleep(for: .milliseconds(140))) != nil,
              !Task.isCancelled else { return false }

        guard posted, await waitForPromotion(of: item.id) else {
            guard !Task.isCancelled else { return false }
            if reportsFailure {
                showAlert(
                    title: "图标没有移动成功",
                    message: "macOS 没有把这个图标放到 FoldBar 箭头左侧。菜单栏已保持展开，请按住 ⌘ 将它拖到箭头左侧并紧靠箭头。"
                )
            }
            return false
        }
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
        guard menuBarImportMonitor.start(
            candidates: currentImportCandidates(),
            panelTargetFrame: panelTargetFrame,
            toggleTargetFrame: toggleTargetFrame
        ) else { return }

        importCandidateRefreshTask = Task { @MainActor [weak self] in
            while let self, self.panel.isVisible, self.menuBarImportMonitor.isRunning {
                guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
                guard self.panel.isVisible else { return }
                self.menuBarImportMonitor.updateCandidates(self.currentImportCandidates())
            }
        }
    }

    private func disarmMenuBarImport() {
        importCandidateRefreshTask?.cancel()
        importCandidateRefreshTask = nil
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = nil
        externalDragItemID = nil
        menuBarImportMonitor.stop()
        setImportTargetingToggle(false)
    }

    private func currentImportCandidates() -> [MenuBarItemWindow] {
        guard isCollapsed,
              let separatorFrame = separatorItem.button?.window?.frame else { return [] }
        let ownWindows = [
            toggleItem.button?.window,
            separatorItem.button?.window
        ].compactMap { $0 }
        let ownWindowIDs = Self.validWindowIDs(ownWindows.map(\.windowNumber))
        let ownWindowFrames = ownWindows.map(\.frame)

        return MenuBarItemScanner.statusWindows().filter { window in
            !ownWindowIDs.contains(window.id)
                && !Self.matchesOwnStatusItem(window.frame, ownFrames: ownWindowFrames)
                && window.frame.width < 500
                && Self.isInMenuBarStrip(window.frame)
                && Self.isOnVisibleSide(window.frame, separatorFrame: separatorFrame)
        }
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
        panel.beginExternalDrag(image: nil, atQuartzPoint: point)
        externalDragCaptureTask?.cancel()
        externalDragCaptureTask = Task { @MainActor [weak self] in
            let captured = await IconCapturer.capture([item])
            guard let self,
                  !Task.isCancelled,
                  self.externalDragItemID == item.id,
                  let image = captured.first?.image else { return }
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

            guard self.isCollapsed,
                  let frame = MenuBarItemScanner.frame(of: item.id),
                  let separatorFrame = self.separatorItem.button?.window?.frame,
                  Self.isInMenuBarStrip(frame),
                  Self.isOnVisibleSide(frame, separatorFrame: separatorFrame),
                  frame.insetBy(dx: -2, dy: -2).contains(point)
            else { return }

            EventForwarder.click(
                at: point,
                eventUserData: MenuBarCommandDragMonitor.replayedClickEventMarker
            )
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

        // Defer teardown until the event-tap callback has returned the consumed
        // mouse-up. Invalidating a tap from inside its own callback is fragile.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.panel.close()
            self.importIntoFoldBar(item)
        }
    }

    private func importIntoFoldBar(_ item: MenuBarItemWindow) {
        guard requireAccessibility() else { return }
        expandRealMenuBar()

        Task { @MainActor [weak self] in
            guard let self else { return }
            var sourceFrame: CGRect?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(140))
                if let found = MenuBarItemScanner.frame(of: item.id),
                   Self.isInMenuBarStrip(found) {
                    sourceFrame = found
                    break
                }
            }

            guard let sourceFrame,
                  let separatorFrame = separatorItem.button?.window?.frame,
                  Self.isOnVisibleSide(sourceFrame, separatorFrame: separatorFrame),
                  let targetX = Self.importTargetX(
                    itemFrame: sourceFrame,
                    separatorFrame: separatorFrame,
                    displays: Self.activeDisplayBounds()
                  )
            else {
                showAlert(
                    title: "无法收纳这个图标",
                    message: "真实图标或 FoldBar 分隔符没有出现在可安全拖动的菜单栏区域。菜单栏已保持展开，你可以手动按住 ⌘ 调整。"
                )
                return
            }

            let posted = await EventForwarder.commandDrag(
                from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                to: CGPoint(x: targetX, y: sourceFrame.midY)
            )
            guard posted, await self.waitForImport(of: item.id) else {
                showAlert(
                    title: "图标没有收纳成功",
                    message: "macOS 没有接受这次自动拖动。菜单栏已保持展开，请按住 ⌘ 将这个真实图标拖到 FoldBar 分隔符左侧。"
                )
                return
            }
            // Re-capture the newly managed item before the enlarged separator
            // parks the managed side off-screen again.
            collapse()
        }
    }

    // MARK: - Event safety

    static func isInStrip(_ frame: CGRect, displays: [CGRect]) -> Bool {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return displays.contains { display in
            display.contains(midpoint)
                && frame.minX >= display.minX
                && frame.maxX <= display.maxX
                && abs(frame.minY - display.minY) <= 2
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

    static func isOnVisibleSide(_ frame: CGRect, separatorFrame: CGRect) -> Bool {
        frame.minX >= separatorFrame.maxX - 1
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
        toggleFrame: CGRect,
        visibleSegments: [CGRect]
    ) -> CGFloat? {
        guard itemFrame.width > 0,
              itemFrame.width.isFinite,
              toggleFrame.minX.isFinite,
              let segment = visibleSegments.first(where: {
                Self.isInVisibleMenuBarSegment(itemFrame, segments: [$0])
                    && toggleFrame.midX >= $0.minX
                    && toggleFrame.midX <= $0.maxX
              }) else { return nil }

        // Stop just before the trigger's left edge. This crosses every item
        // currently between the separator and the trigger, so AppKit inserts
        // the promoted item in the nearest slot on the trigger's left instead
        // of placing it among the ordinary items on the trigger's right.
        let targetX = toggleFrame.minX - 2
        let finalSlotMinX = toggleFrame.minX - itemFrame.width
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

    private func waitForPromotion(of id: CGWindowID) async -> Bool {
        var stablePolls = 0

        for _ in 0..<20 {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return false }
            guard let frame = MenuBarItemScanner.frame(of: id),
                  let separatorFrame = separatorItem.button?.window?.frame,
                  let toggleFrame = toggleItem.button?.window?.frame,
                  Self.isInMenuBarStrip(frame) else {
                stablePolls = 0
                continue
            }
            if Self.isOnVisibleSide(frame, separatorFrame: separatorFrame),
               Self.isImmediatelyLeftOfToggle(frame, toggleFrame: toggleFrame) {
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

    private func waitForImport(of id: CGWindowID) async -> Bool {
        for _ in 0..<12 {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return false }
            guard let frame = MenuBarItemScanner.frame(of: id),
                  let separatorFrame = separatorItem.button?.window?.frame,
                  Self.isInMenuBarStrip(frame) else { continue }
            if Self.isOnHiddenSide(frame, separatorFrame: separatorFrame) {
                return true
            }
        }
        return false
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
                self.autoCollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
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
                message: "屏幕录制用于显示图标；辅助功能只用于你主动发起的点击、收纳或拖动操作。"
            )
            return
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.combinedPermissionRequestKey) {
            let response = runAlert(
                title: "FoldBar 需要两项权限",
                message: "屏幕录制：读取菜单栏小图标。\n辅助功能：转发你主动执行的点击和拖动。\n\n点击一次后，macOS 会分别显示两个系统级确认；FoldBar 不会在后续操作中反复请求。",
                buttons: ["一次性请求两项权限", "稍后"]
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
        let response = runAlert(
            title: "需要重新启动 FoldBar",
            message: "屏幕录制权限已经可用，但这一进程启动时还没有建立图标缓存。重新启动后会在折叠前预先采集，面板即可直接出现。",
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
        ) { _, error in
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
