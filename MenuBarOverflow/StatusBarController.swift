import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 45
    private static let toggleAutosaveName = "menuBarOverflow_toggle"
    private static let separatorAutosaveName = "menuBarOverflow_separator"

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = OverflowPanel()

    private var initialCollapseTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var autoCollapseMonitor: Any?
    private var openingPanel = false
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
            button.toolTip = "MenuBarOverflow"
        }
        separatorItem.button?.image = symbol("chevron.left.to.line")
        updateToggleIcon()
        scheduleInitialCollapse()
    }

    static func isSanePair(toggle: Double, separator: Double) -> Bool {
        MenuBarArrangement.isValid(toggle)
            && MenuBarArrangement.isValid(separator)
            && toggle > 0
            && separator > toggle
    }

    func expandForQuit() {
        initialCollapseTask?.cancel()
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
        guard !isCollapsed else { return }
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        panel.close()
        _ = MenuBarArrangement.captureAndSave()
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        updateToggleIcon()
    }

    private func expand() {
        guard isCollapsed else { return }
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
        panel.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        toggleItem.button?.image = symbol(isCollapsed ? "square.grid.3x3.fill" : "chevron.up")
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
        guard !openingPanel else { return }
        guard IconCapturer.hasPermission() else {
            showPermissionAlert(
                title: "需要屏幕录制权限",
                message: "此权限只用于截取菜单栏中各个小图标并显示在浮动面板里。macOS 授权后需要重新打开 MenuBarOverflow。",
                settingsAnchor: "Privacy_ScreenCapture",
                beforeOpeningSettings: IconCapturer.requestPermission
            )
            return
        }

        openingPanel = true
        let hidden = MenuBarItemScanner.hiddenItems()
        let anchor = toggleItem.button?.window?.frame ?? .zero

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.openingPanel = false }

            // Off-screen windows cannot be captured by either supported API.
            // Briefly restore the real bar, refresh the same window IDs, capture,
            // then collapse again without changing the logical state.
            separatorItem.length = NSStatusItem.variableLength
            try? await Task.sleep(for: .milliseconds(320))
            let refreshed = MenuBarItemScanner.refreshed(hidden)
            let captured = await IconCapturer.capture(refreshed)
            if isCollapsed { separatorItem.length = Self.collapsedLength }

            guard isCollapsed else { return }
            let latestAnchor = toggleItem.button?.window?.frame ?? anchor
            panel.show(
                items: captured,
                below: latestAnchor,
                onClick: { [weak self] item in self?.activate(item) },
                onPromote: { [weak self] item in self?.promoteToMenuBar(item) },
                onManage: { [weak self] in self?.beginManualArrangement() }
            )
        }
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
                    message: "macOS 没有把这个真实图标放回可点击区域。菜单栏已保持展开，你可以直接点击或重新整理它。"
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
                    message: "真实图标没有出现在可拖动的菜单栏区域。可以点“整理”后手动按住 ⌘ 拖动。"
                )
                return
            }

            EventForwarder.commandDrag(
                from: CGPoint(x: frame.midX, y: frame.midY),
                to: CGPoint(x: targetX, y: frame.midY)
            )
            try? await Task.sleep(for: .milliseconds(650))
            // collapse() snapshots the newly ordered bar before parking the
            // remaining overflow items again.
            collapse()
        }
    }

    private func beginManualArrangement() {
        expand()
        showAlert(
            title: "整理菜单栏图标",
            message: "按住 ⌘，把要收纳的图标拖到分隔符左侧；拖到右侧则保持可见。完成后点击上方的 MenuBarOverflow 图标即可重新收起。"
        )
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

    static func promotionTargetX(
        itemFrame: CGRect,
        toggleFrame: CGRect,
        displays: [CGRect]
    ) -> CGFloat? {
        guard let display = displays.first(where: { $0.contains(CGPoint(x: itemFrame.midX, y: itemFrame.midY)) }) else {
            return nil
        }
        let proposed = toggleFrame.maxX + max(6, itemFrame.width / 2)
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

    private func requireAccessibility() -> Bool {
        guard EventForwarder.isTrusted() else {
            showPermissionAlert(
                title: "需要辅助功能权限",
                message: "此权限用于把你的点击或拖动转发给真实菜单栏图标。",
                settingsAnchor: "Privacy_Accessibility",
                beforeOpeningSettings: EventForwarder.promptForAccessibility
            )
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

        let arrange = NSMenuItem(title: "整理图标…", action: #selector(arrangeFromMenu), keyEquivalent: "")
        arrange.target = self
        menu.addItem(arrange)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let about = NSMenuItem(title: "关于 MenuBarOverflow", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func openFromMenu() { openPanel() }
    @objc private func arrangeFromMenu() { beginManualArrangement() }

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

    private func showPermissionAlert(
        title: String,
        message: String,
        settingsAnchor: String,
        beforeOpeningSettings: () -> Void
    ) {
        let response = runAlert(title: title, message: message, buttons: ["打开系统设置", "取消"])
        guard response == .alertFirstButtonReturn else { return }
        beforeOpeningSettings()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
            NSWorkspace.shared.open(url)
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
