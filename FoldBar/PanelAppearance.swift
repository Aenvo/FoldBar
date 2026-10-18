import SwiftUI

enum PanelAppearance: String, CaseIterable, Identifiable {
    case currentMaterial
    case dark
    case liquidGlass

    static let defaultsKey = "panelAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentMaterial: L10n.text(.appearanceLight)
        case .dark: L10n.text(.appearanceDark)
        case .liquidGlass: L10n.text(.appearanceGlass)
        }
    }

    var detail: String {
        switch self {
        case .currentMaterial:
            L10n.text(.appearanceLightDetail)
        case .dark:
            L10n.text(.appearanceDarkDetail)
        case .liquidGlass:
            L10n.text(.appearanceGlassDetail)
        }
    }

    static func decode(_ rawValue: String?) -> PanelAppearance {
        guard let rawValue, let appearance = PanelAppearance(rawValue: rawValue) else {
            return .currentMaterial
        }
        return appearance
    }
}
