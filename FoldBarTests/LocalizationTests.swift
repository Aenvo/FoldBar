import Foundation
import Testing

@testable import FoldBar

@Suite("Chinese and English localization")
struct LocalizationTests {
    private let concreteLanguages: [AppLanguage] = [.simplifiedChinese, .english]

    @Test("Saved language choices decode without assuming a system language")
    func savedLanguageDecoding() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage.decode(language.rawValue) == language)
        }
        for invalid in [nil, "", "fr", "unknown"] as [String?] {
            #expect(AppLanguage.decode(invalid) == .system)
        }
    }

    @Test("System language matching accepts Chinese regions and scripts")
    func chineseSystemLanguages() {
        for identifier in ["zh", "zh-Hans", "zh-Hans-CN", "zh-Hant", "zh-Hant-TW", "zh_Hant", "zh_CN"] {
            #expect(AppLanguage.resolve(.system, preferredLanguages: [identifier]) == .simplifiedChinese)
        }
    }

    @Test("System language matching accepts regional English")
    func englishSystemLanguages() {
        for identifier in ["en", "en-US", "en-GB", "en_AU"] {
            #expect(AppLanguage.resolve(.system, preferredLanguages: [identifier]) == .english)
        }
    }

    @Test("System selection follows the first supported preference and has an English fallback")
    func orderedLanguageFallback() {
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["zh-Hans", "en-US"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["en-GB", "zh-Hans"]) == .english)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["fr-FR", "zh-Hant"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["fr-FR", "de-DE"]) == .english)
        #expect(AppLanguage.resolve(.system, preferredLanguages: []) == .english)
    }

    @Test("An explicit app language overrides the system language")
    func explicitPreference() {
        #expect(AppLanguage.resolve(.english, preferredLanguages: ["zh-Hans"]) == .english)
        #expect(AppLanguage.resolve(.simplifiedChinese, preferredLanguages: ["en-US"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(.simplifiedChinese, preferredLanguages: []) == .simplifiedChinese)
    }

    @Test("Language preferences survive storage without touching the installed app's defaults")
    func isolatedPreferencePersistence() throws {
        let suiteName = "local.foldbar.tests.localization.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguage.decode(defaults.string(forKey: AppLanguage.defaultsKey)) == .system)
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            let reloaded = try #require(UserDefaults(suiteName: suiteName))
            #expect(AppLanguage.decode(reloaded.string(forKey: AppLanguage.defaultsKey)) == language)
        }
    }

    @Test("Both built language bundles contain the complete translation table")
    func bundledResourceCoverage() throws {
        let expectedKeys = Set(L10n.Key.allCases.map(\.rawValue))
        #expect(!expectedKeys.isEmpty)
        for language in concreteLanguages {
            let strings = try table(for: language)
            #expect(Set(strings.keys) == expectedKeys)
            for key in L10n.Key.allCases {
                let value = try #require(strings[key.rawValue])
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(value != key.rawValue)
                #expect(L10n.text(key, language: language) == value)
            }
        }
    }

    @Test("Chinese and English preserve the same formatting arguments")
    func translationFormatParity() throws {
        let chinese = try table(for: .simplifiedChinese)
        let english = try table(for: .english)
        for key in L10n.Key.allCases {
            let chineseValue = try #require(chinese[key.rawValue])
            let englishValue = try #require(english[key.rawValue])
            #expect(try placeholders(in: chineseValue) == placeholders(in: englishValue))
        }
    }

    @Test("Permission statuses keep their order and literal percent signs when formatted")
    func permissionStatusFormatting() {
        for language in concreteLanguages {
            let message = L10n.format(
                .permissionsStatus, "SCREEN-100%", "ACCESS-50%", language: language
            )
            let lines = message.components(separatedBy: "\n")
            #expect(lines.count >= 2)
            #expect(lines.first?.contains("SCREEN-100%") == true)
            #expect(lines.dropFirst().first?.contains("ACCESS-50%") == true)
            #expect(!message.contains("%1$@"))
            #expect(!message.contains("%2$@"))
        }
    }

    @Test("The About message includes the actual version and build in either language")
    func aboutFormatting() {
        for language in concreteLanguages {
            let message = L10n.format(.aboutMessage, "0.2.0", "BUILD-42", language: language)
            #expect(message.contains("0.2.0"))
            #expect(message.contains("BUILD-42"))
            #expect(message.contains("MenubarHide"))
            #expect(message.contains("MIT"))
            #expect(message.contains("Ice"))
            #expect(!message.contains("%1$@"))
            #expect(!message.contains("%2$@"))
        }
    }

    @Test("Legacy macOS messages retain manual recovery guidance in both languages")
    func legacyRecoveryMessages() {
        let manualDragKeys: [L10n.Key] = [
            .legacyMoveFailed,
            .legacyMoveUnavailable,
            .legacyImportUnavailable,
            .legacyImportFailed
        ]
        for language in concreteLanguages {
            for key in manualDragKeys {
                let message = L10n.text(key, language: language)
                #expect(message.contains("⌘"))
                #expect(message.contains(language == .english ? "expanded" : "展开"))
                #expect(!message.contains("macOS 27"))
            }
            let clickMessage = L10n.text(.legacyClickUnavailable, language: language)
            #expect(clickMessage.contains(language == .english ? "expanded" : "展开"))
            let restartMessage = L10n.text(.restartLegacyCache, language: language)
            #expect(restartMessage.contains(language == .english ? "Screen Recording" : "屏幕录制"))
            #expect(!restartMessage.contains("macOS 27"))
        }
    }

    private func table(for language: AppLanguage) throws -> [String: String] {
        let bundle = try #require(L10n.bundle(for: language))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    private func placeholders(in string: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?[@diuoxXfFeEgGaAcCsSpn%]"#
        )
        return expression.matches(in: string, range: NSRange(string.startIndex..., in: string))
            .compactMap { Range($0.range, in: string).map { String(string[$0]) } }
            .filter { $0 != "%%" }
            .sorted()
    }
}
