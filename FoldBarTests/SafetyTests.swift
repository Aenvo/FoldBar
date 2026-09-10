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

    @Test("A same-layer window below the menu bar is rejected")
    func belowStrip() {
        let item = CGRect(x: 800, y: 400, width: 24, height: 24)
        #expect(!StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("Promotion lands just to the right of the app trigger")
    func promotionTarget() {
        let item = CGRect(x: 900, y: 0, width: 24, height: 24)
        let trigger = CGRect(x: 1400, y: 1080, width: 24, height: 24)
        let x = StatusBarController.promotionTargetX(
            itemFrame: item,
            toggleFrame: trigger,
            displays: [Self.main]
        )
        #expect(x == 1448)
    }

    @Test("Promotion succeeds only after the entire item crosses the separator")
    func promotionVerification() {
        let separator = CGRect(x: 900, y: 0, width: 18, height: 24)
        #expect(StatusBarController.isOnVisibleSide(
            CGRect(x: 918, y: 0, width: 38, height: 24),
            separatorFrame: separator
        ))
        #expect(!StatusBarController.isOnVisibleSide(
            CGRect(x: 880, y: 0, width: 38, height: 24),
            separatorFrame: separator
        ))
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
