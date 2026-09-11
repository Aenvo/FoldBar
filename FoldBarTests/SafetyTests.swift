import AppKit
import Testing

@testable import FoldBar

@Suite("Synthetic event safety")
@MainActor
struct SafetyTests {
    static let main = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    static let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    @Test("A normal status item inside the strip is accepted")
    func normalItem() {
        let item = CGRect(x: 1300, y: 0, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("Negative X is valid on a display left of the primary")
    func leftDisplay() {
        let item = CGRect(x: -500, y: 0, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main, Self.left]))
    }

    @Test("Promotion sources must fit inside a visible menu-bar segment")
    func visibleMenuBarSegment() {
        let rightOfNotch = CGRect(x: 948, y: 0, width: 762, height: 40)

        #expect(StatusBarController.isInVisibleMenuBarSegment(
            CGRect(x: 963, y: 0, width: 38, height: 24),
            segments: [rightOfNotch]
        ))
        #expect(!StatusBarController.isInVisibleMenuBarSegment(
            CGRect(x: 929, y: 0, width: 38, height: 24),
            segments: [rightOfNotch]
        ))
    }

    @Test("A different display with overlapping X does not authorize promotion")
    func visibleMenuBarSegmentMatchesDisplay() {
        let upperDisplay = CGRect(x: 0, y: -1080, width: 1920, height: 40)

        #expect(!StatusBarController.isInVisibleMenuBarSegment(
            CGRect(x: 929, y: 0, width: 38, height: 24),
            segments: [upperDisplay]
        ))
    }

    @Test("Proxy clicks reject status items that still overlap the notch")
    func proxyClickRequiresVisibleSegment() {
        let rightOfNotch = CGRect(x: 948, y: 0, width: 762, height: 40)

        #expect(StatusBarController.activationPoint(
            itemFrame: CGRect(x: 928, y: 0, width: 34, height: 34),
            visibleSegments: [rightOfNotch]
        ) == nil)
        #expect(StatusBarController.activationPoint(
            itemFrame: CGRect(x: 962, y: 0, width: 38, height: 34),
            visibleSegments: [rightOfNotch]
        ) == CGPoint(x: 981, y: 17))
    }

    @Test("A same-layer window below the menu bar is rejected")
    func belowStrip() {
        let item = CGRect(x: 800, y: 400, width: 24, height: 24)
        #expect(!StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("Promotion targets the slot immediately left of the app trigger")
    func promotionTarget() {
        let item = CGRect(x: 900, y: 0, width: 24, height: 24)
        let trigger = CGRect(x: 1400, y: 1080, width: 24, height: 24)
        let x = StatusBarController.promotionTargetX(
            itemFrame: item,
            toggleFrame: trigger,
            visibleSegments: [Self.main]
        )
        #expect(x == 1398)
    }

    @Test("Promotion requires the item to cross the separator and touch the trigger's left edge")
    func promotionVerification() {
        let separator = CGRect(x: 900, y: 0, width: 18, height: 24)
        let trigger = CGRect(x: 956, y: 1080, width: 24, height: 24)
        let adjacent = CGRect(x: 918, y: 0, width: 38, height: 24)
        #expect(StatusBarController.isOnVisibleSide(
            adjacent,
            separatorFrame: separator
        ))
        #expect(StatusBarController.isImmediatelyLeftOfToggle(
            adjacent,
            toggleFrame: trigger
        ))
        #expect(!StatusBarController.isOnVisibleSide(
            CGRect(x: 880, y: 0, width: 38, height: 24),
            separatorFrame: separator
        ))
        #expect(!StatusBarController.isImmediatelyLeftOfToggle(
            CGRect(x: 920, y: 0, width: 24, height: 24),
            toggleFrame: trigger
        ))
    }

    @Test("Promotion fails closed when the trigger has no full slot on its left")
    func impossiblePromotionTarget() {
        let item = CGRect(x: 970, y: 0, width: 40, height: 24)
        let trigger = CGRect(x: 975, y: 1080, width: 24, height: 24)
        let rightOfNotch = CGRect(x: 948, y: 0, width: 762, height: 40)

        #expect(StatusBarController.promotionTargetX(
            itemFrame: item,
            toggleFrame: trigger,
            visibleSegments: [rightOfNotch]
        ) == nil)
    }

    @Test("Import target puts the entire item on the managed side")
    func importTarget() {
        let item = CGRect(x: 1200, y: 0, width: 24, height: 24)
        let separator = CGRect(x: 900, y: 0, width: 18, height: 24)
        let targetX = StatusBarController.importTargetX(
            itemFrame: item,
            separatorFrame: separator,
            displays: [Self.main]
        )
        #expect(targetX == 884)
        let movedFrame = CGRect(
            x: (targetX ?? 0) - item.width / 2,
            y: 0,
            width: item.width,
            height: item.height
        )
        #expect(StatusBarController.isOnHiddenSide(movedFrame, separatorFrame: separator))

        let wideItem = CGRect(x: 1100, y: 0, width: 220, height: 24)
        let wideTargetX = StatusBarController.importTargetX(
            itemFrame: wideItem,
            separatorFrame: separator,
            displays: [Self.main]
        )
        #expect(wideTargetX == 786)
        #expect((separator.minX - ((wideTargetX ?? 0) + wideItem.width / 2)) == 4)
    }

    @Test("Import fails closed when there is no room left of the separator")
    func impossibleImportTarget() {
        let item = CGRect(x: 20, y: 0, width: 40, height: 24)
        let separator = CGRect(x: 30, y: 0, width: 18, height: 24)
        #expect(StatusBarController.importTargetX(
            itemFrame: item,
            separatorFrame: separator,
            displays: [Self.main]
        ) == nil)
    }

    @Test("Command-drag source resolution chooses the tightest matching window")
    func commandDragSourceResolution() {
        let background = MenuBarItemWindow(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1710, height: 24),
            ownerName: "Window Server",
            windowName: ""
        )
        let item = MenuBarItemWindow(
            id: 2,
            frame: CGRect(x: 1300, y: 0, width: 28, height: 24),
            ownerName: "Example",
            windowName: "Item-0"
        )
        #expect(MenuBarCommandDragMonitor.sourceWindow(
            at: CGPoint(x: 1310, y: 12),
            among: [background, item]
        )?.id == item.id)
        #expect(MenuBarCommandDragMonitor.sourceWindow(
            at: CGPoint(x: 900, y: 400),
            among: [item]
        ) == nil)
    }

    @Test("Out-of-range AppKit window numbers are ignored safely")
    func safeWindowIDConversion() {
        let ids = StatusBarController.validWindowIDs([
            -1,
            0,
            42,
            Int(UInt32.max),
            Int(UInt32.max) + 1
        ])

        #expect(ids == Set([CGWindowID(42), CGWindowID.max]))
    }

    @Test("Own status items are excluded when AppKit has no usable window ID")
    func ownStatusItemFrameFallback() {
        let candidate = CGRect(x: 1450, y: 0, width: 28, height: 24)

        #expect(StatusBarController.matchesOwnStatusItem(
            candidate,
            ownFrames: [CGRect(x: 1450.5, y: 1083, width: 27.5, height: 24)]
        ))
        #expect(!StatusBarController.matchesOwnStatusItem(
            candidate,
            ownFrames: [CGRect(x: 1400, y: 1083, width: 28, height: 24)]
        ))
    }

    @Test("Panel and Quartz coordinate conversion round trips")
    func panelCoordinateConversion() {
        let appKitFrame = CGRect(x: 1300, y: 800, width: 280, height: 220)
        let quartzFrame = MenuBarCommandDragMonitor.quartzFrame(
            fromAppKit: appKitFrame,
            mainDisplayBounds: Self.main
        )
        #expect(quartzFrame == CGRect(x: 1300, y: 87, width: 280, height: 220))
        let appKitPoint = MenuBarCommandDragMonitor.appKitPoint(
            fromQuartz: CGPoint(x: 1400, y: 100),
            mainDisplayBounds: Self.main
        )
        #expect(appKitPoint == CGPoint(x: 1400, y: 1007))
    }
}

@Suite("Panel appearance")
struct PanelAppearanceTests {
    @Test("Unknown saved appearances fall back to the compatible material")
    func unknownAppearanceFallback() {
        #expect(PanelAppearance.decode(nil) == .currentMaterial)
        #expect(PanelAppearance.decode("future-style") == .currentMaterial)
        #expect(PanelAppearance.decode(PanelAppearance.dark.rawValue) == .dark)
    }
}

@Suite("Arrangement backup")
struct ArrangementTests {
    @Test("Fresh valid positions win while missing values retain the backup")
    func merge() {
        let merged = MenuBarArrangement.merge(
            saved: ["app.a": ["Item-0": 5, "Item-1": 7]],
            fresh: ["app.a": ["Item-1": 8]],
            liveDomains: ["app.a"]
        )
        #expect(merged == ["app.a": ["Item-0": 5, "Item-1": 8]])
    }

    @Test("Parked off-screen positions are invalid")
    func offscreenInvalid() {
        #expect(!MenuBarArrangement.isValid(-4220))
        #expect(MenuBarArrangement.isValid(250))
    }

    @Test("Restore only accepts status keys in app preference domains")
    func restoreFilter() {
        #expect(MenuBarArrangement.isRestorable(
            domain: "com.example.app",
            key: "NSStatusItem Preferred Position Item-0",
            home: "/Users/example"
        ))
        #expect(!MenuBarArrangement.isRestorable(
            domain: ".GlobalPreferences",
            key: "NSStatusItem Preferred Position Item-0",
            home: "/Users/example"
        ))
        #expect(!MenuBarArrangement.isRestorable(
            domain: "/Library/Preferences/example.plist",
            key: "NSStatusItem Preferred Position Item-0",
            home: "/Users/example"
        ))
    }
}

@Suite("Adaptive overflow grid")
struct OverflowGridTests {
    @Test("Ordinary square icons occupy one slot")
    func squareIcon() {
        #expect(OverflowGridLayout.columnSpan(for: CGRect(x: 0, y: 0, width: 34, height: 34)) == 1)
    }

    @Test("A temperature-style meter occupies two slots")
    func wideMeter() {
        #expect(OverflowGridLayout.columnSpan(for: CGRect(x: 0, y: 0, width: 89, height: 34)) == 2)
    }

    @Test("Extremely wide status items are capped at three slots")
    func veryWideItem() {
        #expect(OverflowGridLayout.columnSpan(for: CGRect(x: 0, y: 0, width: 220, height: 34)) == 3)
    }
}
