import SwiftUI

@MainActor
final class AppearanceSettingsPanel {
    private var panel: NSPanel?

    func show() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(rootView: AppearanceSettingsView())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "FoldBar 设置"
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.center()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(PanelAppearance.defaultsKey)
    private var storedAppearance = PanelAppearance.currentMaterial.rawValue
    @AppStorage(MenuBarDragSettings.directDragDefaultsKey)
    private var directMenuBarDragEnabled = false

    private var appearance: PanelAppearance {
        PanelAppearance.decode(storedAppearance)
    }

    var body: some View {
        Form {
            Section("悬浮面板外观") {
                Picker("外观", selection: $storedAppearance) {
                    ForEach(PanelAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(appearance.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("菜单栏图标拖动") {
                Toggle(
                    "直接拖动菜单栏图标（无需 Command）",
                    isOn: $directMenuBarDragEnabled
                )

                Text(
                    directMenuBarDragEnabled
                        ? "打开 FoldBar 面板后，直接把可见菜单栏图标拖到面板或箭头即可收纳；普通单击仍会打开原图标。"
                        : "关闭时保持 macOS 原有方式：打开 FoldBar 面板后，按住 Command 再拖动菜单栏图标。"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(4)
        .frame(width: 430, height: 390)
    }
}
