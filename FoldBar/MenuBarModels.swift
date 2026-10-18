import AppKit

struct MenuBarAccessibilityIdentity: Equatable, Hashable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let ordinal: Int
}

struct MenuBarItemWindow: Identifiable, Equatable, Sendable {
    // Native identity matching keeps these stable across language changes.
    static let genericItemLabels: Set<String> = ["Menu bar item", "菜单栏图标"]
    let id: CGWindowID
    let frame: CGRect
    let ownerName: String
    let windowName: String
    let nativeWindowID: CGWindowID?
    let accessibilityIdentity: MenuBarAccessibilityIdentity?
    let ownerProcessIdentifier: pid_t?
    let bundleIdentifier: String

    init(
        id: CGWindowID,
        frame: CGRect,
        ownerName: String,
        windowName: String,
        nativeWindowID: CGWindowID? = nil,
        accessibilityIdentity: MenuBarAccessibilityIdentity? = nil,
        ownerProcessIdentifier: pid_t? = nil,
        bundleIdentifier: String = ""
    ) {
        self.id = id
        self.frame = frame
        self.ownerName = ownerName
        self.windowName = windowName
        self.nativeWindowID = nativeWindowID ?? (accessibilityIdentity == nil ? id : nil)
        self.accessibilityIdentity = accessibilityIdentity
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.bundleIdentifier = bundleIdentifier
    }

    var displayName: String {
        let trimmed = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "Item-0", !Self.genericItemLabels.contains(trimmed) {
            return trimmed
        }

        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericHosts = ["Control Center", "控制中心", "Status menu", "状态菜单"]
        if !owner.isEmpty, !genericHosts.contains(owner) { return owner }
        return L10n.text(.menuBarItem)
    }
}

struct CapturedItem: Identifiable {
    let window: MenuBarItemWindow
    let image: NSImage
    private let nativeHoverText: String?
    var hoverText: String { nativeHoverText ?? window.displayName }
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
        self.ownerProcessIdentifier = ownerProcessIdentifier ?? window.ownerProcessIdentifier
        let resolved = hoverText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.nativeHoverText = resolved.isEmpty || MenuBarItemWindow.genericItemLabels.contains(resolved)
            ? nil : resolved
    }
}
