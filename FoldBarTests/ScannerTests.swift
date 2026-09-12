import CoreGraphics
import Testing

@testable import FoldBar

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

    @Test("Expanded items can be found before collapse for flash-free caching")
    func expandedManagedSection() {
        let left = Self.window(2, x: 700, width: 30)
        let right = Self.window(3, x: 740, width: 30)
        let unrelated = Self.window(4, x: 500, width: 30)
        let found = MenuBarItemScanner.itemsLeft(
            of: 780,
            among: [unrelated, right, left]
        )
        #expect(found.map(\.id) == [2, 3])
    }

    @Test("Panel presents the status items nearest the menu-bar right first")
    func panelDisplayOrder() {
        let farthestLeft = Self.window(2, x: 700, width: 30)
        let middle = Self.window(3, x: 740, width: 30)
        let nearestRight = Self.window(4, x: 780, width: 30)

        let found = MenuBarItemScanner.panelDisplayOrder([
            middle,
            farthestLeft,
            nearestRight
        ])

        #expect(found.map(\.id) == [4, 3, 2])
    }

    @Test("Only new managed window IDs are reconciled after collapse")
    func newlyManagedItems() {
        let oldLeft = Self.window(2, x: -4300, width: 30)
        let oldRight = Self.window(3, x: -4260, width: 30)
        let launchedLater = Self.window(9, x: -4340, width: 34)

        let found = MenuBarItemScanner.newlyManagedItems(
            among: [oldLeft, launchedLater, oldRight],
            excluding: [oldLeft.id, oldRight.id]
        )

        #expect(found.map(\.id) == [launchedLater.id])
    }

    @Test("Generic Control Center ownership is not presented as item identity")
    func genericDisplayName() {
        let item = MenuBarItemWindow(
            id: 2,
            frame: CGRect(x: 700, y: 0, width: 30, height: 24),
            ownerName: "控制中心",
            windowName: "Item-0"
        )

        #expect(item.displayName == "菜单栏图标")
    }

    @Test("Accessibility metadata matches status windows by their shared center")
    func accessibilityMetadataMatching() {
        let first = Self.window(2, x: -3797, width: 34)
        let second = Self.window(3, x: -3987, width: 38)
        let metadata = [
            MenuBarItemAccessibilityMetadata(
                frame: CGRect(x: -3798, y: 5, width: 36, height: 24),
                label: "Clash Verge"
            ),
            MenuBarItemAccessibilityMetadata(
                frame: CGRect(x: -3980, y: 5, width: 24, height: 24),
                label: "PixPin"
            )
        ]

        let labels = MenuBarItemMetadataResolver.match(
            windows: [first, second],
            metadata: metadata
        )

        #expect(labels[first.id] == "Clash Verge")
        #expect(labels[second.id] == "PixPin")
    }

    @Test("Native hover help wins and app identity is the final fallback")
    func accessibilityLabelPriority() {
        #expect(MenuBarItemMetadataResolver.preferredLabel(
            help: "PixPin v3.4.3",
            description: "截图工具",
            title: "",
            appName: "PixPin"
        ) == "PixPin v3.4.3")
        #expect(MenuBarItemMetadataResolver.preferredLabel(
            help: "",
            description: "",
            title: "",
            appName: "AlDente"
        ) == "AlDente")
        #expect(MenuBarItemMetadataResolver.preferredLabel(
            help: "",
            description: "控制中心",
            title: "Item-0",
            appName: "控制中心"
        ) == nil)
    }
}
