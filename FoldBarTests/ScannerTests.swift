import ApplicationServices
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

    @Test("macOS 27 selects Accessibility discovery")
    func accessibilityBackendSelection() {
        #expect(!MenuBarItemScanner.usesAccessibilityBackend(for: 26))
        #expect(MenuBarItemScanner.usesAccessibilityBackend(for: 27))
        #expect(MenuBarItemScanner.usesAccessibilityBackend(for: 28))
        #expect(StatusBarController.registersLegacySeparator(for: 26))
        #expect(!StatusBarController.registersLegacySeparator(for: 27))
        #expect(!StatusBarController.registersLegacySeparator(for: 28))
    }

    @Test("Accessibility identities produce stable reserved IDs")
    func accessibilitySyntheticIDs() {
        let identity = MenuBarAccessibilityIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.item",
            ordinal: 0
        )
        let same = MenuBarAccessibilityIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.item",
            ordinal: 0
        )
        let other = MenuBarAccessibilityIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.item",
            ordinal: 1
        )

        let id = MenuBarAccessibility.syntheticID(for: identity)
        #expect(id == MenuBarAccessibility.syntheticID(for: same))
        #expect(id != MenuBarAccessibility.syntheticID(for: other))
        #expect((id & 0x8000_0000) != 0)
    }

    @Test("A timed-out AXPress can still be a validated dispatch")
    func accessibilityPressDispatchResult() {
        #expect(MenuBarAccessibility.pressResultIndicatesDispatch(.success))
        #expect(MenuBarAccessibility.pressResultIndicatesDispatch(.cannotComplete))
        #expect(!MenuBarAccessibility.pressResultIndicatesDispatch(.actionUnsupported))
        #expect(!MenuBarAccessibility.pressResultIndicatesDispatch(.invalidUIElement))
    }

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

    @Test("macOS 27 native overflow boundary separates hidden and visible apps")
    func nativeOverflowBoundary() {
        let overflow = CGRect(x: 994.5, y: 1, width: 17.5, height: 31)
        let hidden = [
            Self.window(2, x: 976, width: 36),
            Self.window(3, x: 980, width: 24),
            Self.window(4, x: 981, width: 18)
        ]
        let visible = [
            Self.window(5, x: 1027, width: 22),
            Self.window(6, x: 1064, width: 24)
        ]

        #expect(MenuBarItemScanner.systemOverflowHiddenItems(
            among: hidden + visible,
            overflowFrame: overflow
        ).map(\.id) == [2, 3, 4])
        #expect(MenuBarItemScanner.systemOverflowVisibleItems(
            among: hidden + visible,
            overflowFrame: overflow
        ).map(\.id) == [5, 6])
    }

    @Test("Missing native overflow boundary fails closed without duplicates")
    func missingNativeOverflowBoundary() {
        let windows = [Self.window(2, x: 976, width: 36)]
        #expect(MenuBarItemScanner.systemOverflowHiddenItems(
            among: windows,
            overflowFrame: nil
        ).isEmpty)
        #expect(MenuBarItemScanner.systemOverflowVisibleItems(
            among: windows,
            overflowFrame: nil
        ).isEmpty)
    }

    @Test("Native overflow expansion is detected from non-overlapping geometry")
    func nativeOverflowExpansionGeometry() {
        let overflow = CGRect(x: 994.5, y: 1, width: 17.5, height: 31)
        let collapsed = [
            Self.window(2, x: 976, width: 36),
            Self.window(3, x: 980, width: 24),
            Self.window(4, x: 981, width: 18)
        ]
        let expanded = [
            Self.window(2, x: 627, width: 36),
            Self.window(3, x: 669, width: 24),
            Self.window(4, x: 712, width: 18)
        ]

        #expect(!MenuBarItemScanner.systemOverflowItemsAreExpanded(
            collapsed,
            overflowFrame: overflow
        ))
        #expect(MenuBarItemScanner.systemOverflowItemsAreExpanded(
            expanded,
            overflowFrame: overflow
        ))
        #expect(!MenuBarItemScanner.systemOverflowItemsAreExpanded(
            [],
            overflowFrame: overflow
        ))
        #expect(!MenuBarItemScanner.systemOverflowItemsAreExpanded(
            expanded,
            overflowFrame: nil
        ))
    }

    @Test("Panel preserves the real menu bar's left-to-right order")
    func panelDisplayOrder() {
        let farthestLeft = Self.window(2, x: 700, width: 30)
        let middle = Self.window(3, x: 740, width: 30)
        let nearestRight = Self.window(4, x: 780, width: 30)

        let found = MenuBarItemScanner.panelDisplayOrder([
            middle,
            farthestLeft,
            nearestRight
        ])

        #expect(found.map(\.id) == [2, 3, 4])
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
                label: "Clash Verge",
                processIdentifier: 101
            ),
            MenuBarItemAccessibilityMetadata(
                frame: CGRect(x: -3980, y: 5, width: 24, height: 24),
                label: "PixPin",
                processIdentifier: 202
            )
        ]

        let labels = MenuBarItemMetadataResolver.match(
            windows: [first, second],
            metadata: metadata
        )

        #expect(labels[first.id] == "Clash Verge")
        #expect(labels[second.id] == "PixPin")

        let resolved = MenuBarItemMetadataResolver.matchMetadata(
            windows: [first, second],
            metadata: metadata
        )
        #expect(resolved[first.id]?.processIdentifier == 101)
        #expect(resolved[second.id]?.processIdentifier == 202)
    }

    @Test("Activation detects only a newly visible target-owned auxiliary window")
    func activationWindowDetection() {
        let display = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        let windows = [
            ActivationWindowRecord(
                id: 1,
                ownerProcessIdentifier: 77,
                layer: 101,
                frame: CGRect(x: 937, y: 35, width: 767, height: 197),
                alpha: 1
            ),
            ActivationWindowRecord(
                id: 2,
                ownerProcessIdentifier: 77,
                layer: 25,
                frame: CGRect(x: 1235, y: 0, width: 38, height: 34),
                alpha: 1
            ),
            ActivationWindowRecord(
                id: 3,
                ownerProcessIdentifier: 77,
                layer: 101,
                frame: CGRect(x: -3769, y: 35, width: 767, height: 197),
                alpha: 1
            ),
            ActivationWindowRecord(
                id: 4,
                ownerProcessIdentifier: 88,
                layer: 101,
                frame: CGRect(x: 900, y: 35, width: 300, height: 200),
                alpha: 1
            )
        ]

        #expect(ActivationWindowScanner.candidateIDs(
            ownerProcessIdentifier: 77,
            on: display,
            statusWindowLayer: 25,
            among: windows
        ) == [1])
    }

    @Test("Quartz and accessibility status frames match by their centers")
    func synchronizedStatusItemFrames() {
        let quartz = CGRect(x: 1235, y: 0, width: 38, height: 34)
        let synchronizedAccessibility = CGRect(x: 1242, y: 5, width: 24, height: 24)
        let staleAccessibility = CGRect(x: -3758, y: 5, width: 24, height: 24)

        #expect(MenuBarItemMetadataResolver.framesReferToSameStatusItem(
            synchronizedAccessibility,
            quartz
        ))
        #expect(!MenuBarItemMetadataResolver.framesReferToSameStatusItem(
            staleAccessibility,
            quartz
        ))
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
