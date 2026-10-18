import SwiftUI

@MainActor
final class AppearanceSettingsPanel {
    private var panel: NSPanel?
    var onLanguageChange: (() -> Void)?

    func show() {
        if let panel {
            panel.title = L10n.text(.settingsTitle)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(rootView: AppearanceSettingsView { [weak self] in
            self?.panel?.title = L10n.text(.settingsTitle)
            self?.onLanguageChange?()
        })
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 690) - 100
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: min(590, max(300, availableHeight))),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text(.settingsTitle)
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.center()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(AppLanguage.defaultsKey)
    private var storedLanguage = AppLanguage.system.rawValue
    @AppStorage(PanelAppearance.defaultsKey)
    private var storedAppearance = PanelAppearance.currentMaterial.rawValue
    @AppStorage(MenuBarDragSettings.directDragDefaultsKey)
    private var directMenuBarDragEnabled = false

    let onLanguageChange: () -> Void

    private var language: AppLanguage {
        AppLanguage.decode(storedLanguage)
    }

    private var appearance: PanelAppearance {
        PanelAppearance.decode(storedAppearance)
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.text(.languagePicker), selection: $storedLanguage) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }

                Text(L10n.text(.languageDetail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.text(.languageSection))
            }

            Section {
                Picker(L10n.text(.appearancePicker), selection: $storedAppearance) {
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
            } header: {
                Text(L10n.text(.appearanceSection))
            }

            Section {
                Toggle(
                    L10n.text(.directDragToggle),
                    isOn: $directMenuBarDragEnabled
                )

                Text(
                    directMenuBarDragEnabled
                        ? L10n.text(.directDragEnabledDetail)
                        : L10n.text(.directDragDisabledDetail)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                    Text(L10n.text(.privateMembershipDetail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(L10n.text(.dragSection))
            }
        }
        .formStyle(.grouped)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, language.locale)
        .onChange(of: storedLanguage) { _, _ in
            onLanguageChange()
        }
    }
}
