import CoreGraphics
import Testing

@testable import MenuBarOverflow

@Suite("Overflow discovery")
struct ScannerTests {
    static func window(_ id: CGWindowID, x: CGFloat, width: CGFloat) -> MenuBarItemWindow {
        MenuBarItemWindow(
            id: id,
            frame: CGRect(x: x, y: 0, width: width, height: 24),
            ownerName: "Control Center",
            windowName: "Item-\(id)"
        )
    }

    static let separator = window(1, x: -4200, width: 5016)

    @Test("No oversized separator means no managed overflow")
    func noSeparator() {
        let windows = [Self.window(2, x: 700, width: 24), Self.window(3, x: 730, width: 24)]
        #expect(MenuBarItemScanner.hiddenItems(among: windows).isEmpty)
    }

    @Test("The contiguous run left of the separator is returned in display order")
    func contiguousRun() {
        let left = Self.window(2, x: -4300, width: 30)
        let right = Self.window(3, x: -4260, width: 30)
        let visible = Self.window(4, x: 900, width: 24)
        let found = MenuBarItemScanner.hiddenItems(among: [visible, Self.separator, right, left])
        #expect(found.map(\.id) == [2, 3])
    }

    @Test("A large gap ends the overflow run")
    func largeGap() {
        let adjacent = Self.window(2, x: -4240, width: 30)
        let unrelated = Self.window(3, x: -4400, width: 30)
        let found = MenuBarItemScanner.hiddenItems(among: [Self.separator, adjacent, unrelated])
        #expect(found.map(\.id) == [2])
    }
}
