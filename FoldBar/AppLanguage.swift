import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let defaultsKey = "appLanguage"
    var id: String { rawValue }

    // Keep the choices readable even when the current language is unfamiliar.
    var title: String {
        switch self {
        case .system: L10n.text(.languageSystem)
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    static func decode(_ rawValue: String?) -> AppLanguage {
        rawValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    static var current: AppLanguage {
        decode(UserDefaults.standard.string(forKey: defaultsKey))
    }

    static func resolve(
        _ selection: AppLanguage,
        preferredLanguages: [String]
    ) -> AppLanguage {
        guard selection == .system else { return selection }
        for identifier in preferredLanguages {
            let base = identifier.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first?.lowercased()
            if base == "zh" { return .simplifiedChinese }
            if base == "en" { return .english }
        }
        return .english
    }

    var locale: Locale {
        let language = Self.resolve(self, preferredLanguages: Locale.preferredLanguages)
        return Locale(identifier: language.rawValue)
    }
}

/// Explicit bundle lookup supports live changes without changing AppleLanguages,
/// recreating status items, touching permissions, or invalidating native AX labels.
enum L10n {
    enum Key: String, CaseIterable {
        // Keys are shared by every supported macOS branch.
        case languageSystem
        case settingsTitle
        case languageSection
        case languagePicker
        case languageDetail
        case appearanceSection
        case appearancePicker
        case appearanceLight
        case appearanceDark
        case appearanceGlass
        case appearanceLightDetail
        case appearanceDarkDetail
        case appearanceGlassDetail
        case dragSection
        case directDragToggle
        case directDragEnabledDetail
        case directDragDisabledDetail
        case privateMembershipDetail
        case settings
        case settingsHelp
        case keepVisibleDrop
        case collectRelease
        case collectDrop
        case collectTooltip
        case menuBarItem
        case expandUnavailableTitle
        case expandUnavailableMessage
        case clickUnavailableTitle
        case privateRevealFailed
        case liveIconUnavailable
        case legacyClickUnavailable
        case clickIdentityChanged
        case removeAppFailedTitle
        case privateUpdateFailed
        case identityChangedTitle
        case moveIdentityChanged
        case moveFailedTitle
        case legacyMoveFailed
        case moveUnavailableTitle
        case legacyMoveUnavailable
        case replayIdentityChanged
        case importUnavailableTitle
        case legacyImportUnavailable
        case importFailedTitle
        case legacyImportFailed
        case privateMissingIdentity
        case importIdentityChanged
        case captureUnavailableTitle
        case captureUnavailableMessage
        case privateImportFailed
        case openPanel
        case launchAtLogin
        case aboutTitle
        case quit
        case loginFailedTitle
        case loginFailedMessage
        case aboutMessage
        case permissionsGrantedMenu
        case permissionsMenu
        case permissionsGrantedTitle
        case permissionsGrantedMessage
        case permissionsOnboardingTitle
        case permissionsOnboardingMessage
        case requestPermissions
        case later
        case permissionGranted
        case permissionDenied
        case permissionsTitle
        case permissionsStatus
        case openSystemSettings
        case cancel
        case restartPrivateCache
        case restartLegacyCache
        case restartTitle
        case restart
        case restartFailedTitle
        case restartFailedMessage
        case ok
    }

    private static let resourceBundle = Bundle(for: LocalizationBundleToken.self)

    static func bundle(for language: AppLanguage) -> Bundle? {
        let resolved = AppLanguage.resolve(language, preferredLanguages: Locale.preferredLanguages)
        guard let path = resourceBundle.path(forResource: resolved.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    static func text(_ key: Key, language: AppLanguage? = nil) -> String {
        let fallback = bundle(for: .english)?.localizedString(
            forKey: key.rawValue, value: key.rawValue, table: nil
        ) ?? key.rawValue
        return bundle(for: language ?? .current)?.localizedString(
            forKey: key.rawValue, value: fallback, table: nil
        ) ?? fallback
    }

    static func format(
        _ key: Key,
        _ arguments: CVarArg...,
        language: AppLanguage? = nil
    ) -> String {
        String(
            format: text(key, language: language),
            locale: (language ?? .current).locale,
            arguments: arguments
        )
    }
}

private final class LocalizationBundleToken: NSObject {}
