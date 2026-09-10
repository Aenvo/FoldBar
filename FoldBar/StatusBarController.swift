import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 45
    private static let toggleAutosaveName = "foldbar_toggle"
    private static let separatorAutosaveName = "foldbar_separator"
    private static let combinedPermissionRequestKey = "didRequestCombinedPermissionsV1"

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = OverflowPanel()
    private let settingsPanel = AppearanceSettingsPanel()

    private var initialCollapseTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var autoCollapseMonitor: Any?
    private var cacheCaptureTask: Task<Void, Never>?
    private var cachedItems: [CapturedItem] = []
    private var preparingCollapse = false
    private var permissionFlowActive = false
    private(set) var isCollapsed = false

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
        preparingCollapse = false
        disarmAutoCollapse()
        panel.close()
        guard isCollapsed else { return }
        separatorItem.length = NSStatusItem.variableLength
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
            panel.isVisible ? panel.close() : openPanel()
        } else {
            collapse()
        }
    }

    private func collapse() {
        guard !isCollapsed, !preparingCollapse else { return }
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        panel.close()

        guard IconCapturer.hasPermission(),
              let separatorFrame = separatorItem.button?.window?.frame else {
            completeCollapse()
            return
        }

        // Capture while the real items are already visible. The panel can then
        // open from memory with no flash-expand and no ScreenCaptureKit wait.
        preparingCollapse = true
        let windows = MenuBarItemScanner.itemsLeft(of: separatorFrame.minX)
        cacheCaptureTask?.cancel()
        cacheCaptureTask = Task { @MainActor [weak self] in
            let captured = await IconCapturer.capture(windows)
            guard let self, !Task.isCancelled, !self.isCollapsed else { return }
            if !captured.isEmpty || windows.isEmpty {
                self.cachedItems = captured
            }
            self.completeCollapse()
        }
    }

    private func completeCollapse() {
        preparingCollapse = false
        cacheCaptureTask = nil
        _ = MenuBarArrangement.captureAndSave()
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        updateToggleIcon()
    }

    private func expand() {
        guard isCollapsed else { return }
        cacheCaptureTask?.cancel()
        cacheCaptureTask = nil
        preparingCollapse = false
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        panel.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        toggleItem.button?.image = symbol(isCollapsed ? "chevron.down" : "chevron.up")
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

        let hidden = MenuBarItemScanner.hiddenItems()
        let hiddenIDs = Set(hidden.map(\.id))
        let items = cachedItems.filter { hiddenIDs.contains($0.id) }
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
            onExpand: { [weak self] in self?.expand() },
            onSettings: { [weak self] in self?.settingsPanel.show() }
        )
    }

    private func activate(_ item: CapturedItem) {
        guard requireAccessibility() else { return }
        expand()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let toggleMinX = toggleItem.button?.window?.frame.minX ?? -.infinity
            var target: CGRect?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(140))
                if let frame = MenuBarItemScanner.frame(of: item.id),
                   Self.isInMenuBarStrip(frame),
                   Self.isOnManagedSide(frame, toggleMinX: toggleMinX) {
                    target = frame
                    break
                }
            }
            guard let target else {
                showAlert(
                    title: "图标暂时无法点击",
                    message: "macOS 没有把这个真实图标放回可点击区域。菜单栏已保持展开，你可以直接操作它。"
                )
                armAutoCollapse()
                return
            }
            EventForwarder.click(at: CGPoint(x: target.midX, y: target.midY))
            armAutoCollapse()
        }
    }

    private func promoteToMenuBar(_ item: CapturedItem) {
        guard requireAccessibility() else { return }
        expand()

        Task { @MainActor [weak self] in
            guard let self else { return }
            var frame: CGRect?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(140))
                if let found = MenuBarItemScanner.frame(of: item.id), Self.isInMenuBarStrip(found) {
                    frame = found
                    break
                }
            }
            guard let frame,
                  let toggleFrame = toggleItem.button?.window?.frame,
                  let targetX = Self.promotionTargetX(
                    itemFrame: frame,
                    toggleFrame: toggleFrame,
                    displays: Self.activeDisplayBounds()
                  ) else {
                showAlert(
                    title: "无法移动这个图标",
                    message: "真实图标没有出现在可拖动的菜单栏区域。菜单栏已保持展开，请手动按住 ⌘ 拖动。"
                )
                return
            }

            let posted = await EventForwarder.commandDrag(
                from: CGPoint(x: frame.midX, y: frame.midY),
                to: CGPoint(x: targetX, y: frame.midY)
            )
            guard posted, await self.waitForPromotion(of: item.id) else {
                showAlert(
                    title: "图标没有移动成功",
                    message: "macOS 没有接受这次自动拖动。菜单栏已保持展开，请按住 ⌘ 将这个真实图标拖到 FoldBar 图标右侧。"
                )
                return
            }
            // collapse() snapshots the newly ordered bar before parking the
            // remaining overflow items again.
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

    static func isOnManagedSide(_ frame: CGRect, toggleMinX: CGFloat) -> Bool {
        frame.maxX <= toggleMinX
    }

    static func isOnVisibleSide(_ frame: CGRect, separatorFrame: CGRect) -> Bool {
        frame.minX >= separatorFrame.maxX - 1
    }

    static func promotionTargetX(
        itemFrame: CGRect,
        toggleFrame: CGRect,
        displays: [CGRect]
    ) -> CGFloat? {
        guard let display = displays.first(where: { $0.contains(CGPoint(x: itemFrame.midX, y: itemFrame.midY)) }) else {
            return nil
        }
        // Cross the midpoint of the neighboring status item instead of ending
        // directly on its button center. The latter can be handled as a click
        // target rather than a stable insertion boundary on macOS 26.
        let proposed = toggleFrame.maxX + max(12, itemFrame.width)
        let lower = display.minX + itemFrame.width / 2
        let upper = display.maxX - itemFrame.width / 2
        guard lower <= upper else { return nil }
        return min(max(proposed, lower), upper)
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map(CGDisplayBounds)
    }

    private static func isInMenuBarStrip(_ frame: CGRect) -> Bool {
        isInStrip(frame, displays: activeDisplayBounds())
    }

    private func waitForPromotion(of id: CGWindowID) async -> Bool {
        for _ in 0..<12 {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return false }
            guard let frame = MenuBarItemScanner.frame(of: id),
                  let separatorFrame = separatorItem.button?.window?.frame,
                  Self.isInMenuBarStrip(frame) else { continue }
            if Self.isOnVisibleSide(frame, separatorFrame: separatorFrame) {
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
                message: "屏幕录制用于显示图标；辅助功能只在你点击或拖动代理图标时使用。"
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
