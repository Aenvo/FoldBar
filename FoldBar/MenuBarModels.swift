import AppKit

struct MenuBarItemWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
    let ownerName: String
    let windowName: String

    var displayName: String {
        let trimmed = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "Item-0" { return trimmed }

        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericHosts = ["Control Center", "控制中心", "Status menu", "状态菜单"]
        if !owner.isEmpty, !genericHosts.contains(owner) { return owner }
        return "菜单栏图标"
    }
}

struct CapturedItem: Identifiable {
    let window: MenuBarItemWindow
    let image: NSImage
    let hoverText: String
    let ownerProcessIdentifier: pid_t?
    var id: CGWindowID { window.id }

    init(
        window: MenuBarItemWindow,
        image: NSImage,
        hoverText: String? = nil,
        ownerProcessIdentifier: pid_t? = nil
    ) {
        self.window = window
        self.image = image
        self.ownerProcessIdentifier = ownerProcessIdentifier
        let resolved = hoverText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.hoverText = resolved.isEmpty ? window.displayName : resolved
    }
}
