import AppKit

struct MenuBarItemWindow: Identifiable, Equatable {
    let id: CGWindowID
    let frame: CGRect
    let ownerName: String
    let windowName: String

    var displayName: String {
        let trimmed = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "Item-0" { return trimmed }
        return ownerName.isEmpty ? "Menu bar item" : ownerName
    }
}

struct CapturedItem: Identifiable {
    let window: MenuBarItemWindow
    let image: NSImage
    var id: CGWindowID { window.id }
}
