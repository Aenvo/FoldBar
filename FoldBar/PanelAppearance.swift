import SwiftUI

enum PanelAppearance: String, CaseIterable, Identifiable {
    case currentMaterial
    case dark
    case liquidGlass

    static let defaultsKey = "panelAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentMaterial: "浅色模式"
        case .dark: "暗色模式"
        case .liquidGlass: "高透明 Liquid Glass"
        }
    }

    var detail: String {
        switch self {
        case .currentMaterial:
            "使用透明度更低的浅色系统毛玻璃背景，并兼容 macOS 14 及更高版本。"
        case .dark:
            "使用更通透的深色模糊背景，在保留壁纸质感的同时维持清晰。"
        case .liquidGlass:
            "在 macOS 26 及更高版本使用原生高透明玻璃，图标区域带有增强模糊；较低版本自动回退到浅色模式。"
        }
    }

    static func decode(_ rawValue: String?) -> PanelAppearance {
        guard let rawValue, let appearance = PanelAppearance(rawValue: rawValue) else {
            return .currentMaterial
        }
        return appearance
    }
}
