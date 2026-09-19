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

    @Test("Accessibility menu extras may be inset from the strip origin")
    func accessibilityItem() {
        let item = CGRect(x: 1300, y: 5, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("Negative X is valid on a display left of the primary")
    func leftDisplay() {
        let item = CGRect(x: -500, y: 0, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main, Self.left]))
    }

    @Test("Quartz and AppKit menu-bar frame conversion round-trips")
    func menuBarFrameConversion() {
        let quartz = CGRect(x: 1204, y: 5, width: 320, height: 24)
        let appKit = MenuBarCommandDragMonitor.appKitFrame(
            fromQuartz: quartz,
            mainDisplayBounds: Self.main
        )
        #expect(appKit == CGRect(x: 1204, y: 1078, width: 320, height: 24))
        #expect(MenuBarCommandDragMonitor.quartzFrame(
            fromAppKit: appKit,
            mainDisplayBounds: Self.main
        ) == quartz)
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
            liveToggleFrame: trigger,
            finalToggleFrame: trigger,
            visibleSegments: [Self.main]
        )
        #expect(x == 1398)
    }

    @Test("Promotion follows the live trigger after it moves in the layout")
    func promotionTracksLiveTrigger() {
        let item = CGRect(x: 1000, y: 0, width: 24, height: 24)
        let shiftedTrigger = CGRect(x: 1427, y: 1080, width: 0, height: 24)
        let restoredTrigger = CGRect(x: 1373, y: 1080, width: 24, height: 24)

        let x = StatusBarController.promotionTargetX(
            itemFrame: item,
            liveToggleFrame: shiftedTrigger,
            finalToggleFrame: restoredTrigger,
            visibleSegments: [Self.main]
        )

        #expect(x == 1425)
    }

    @Test("A zero-width live trigger remains a valid promotion anchor")
    func promotionUsesReducedTrigger() {
        let item = CGRect(x: 1000, y: 0, width: 24, height: 24)
        let reducedTrigger = CGRect(x: 1400, y: 1080, width: 0, height: 24)
        let restoredTrigger = CGRect(x: 1373, y: 1080, width: 24, height: 24)

        let x = StatusBarController.promotionTargetX(
            itemFrame: item,
            liveToggleFrame: reducedTrigger,
            finalToggleFrame: restoredTrigger,
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

    @Test("macOS 27 managed separator uses its leading edge as the boundary")
    func managedSeparatorVisibleBoundary() {
        let separator = CGRect(x: 1178, y: 5, width: 5002, height: 24)
        let promoted = CGRect(x: 1205, y: 5, width: 24, height: 24)
        let hidden = CGRect(x: 1129, y: 5, width: 24, height: 24)

        #expect(StatusBarController.isOnVisibleSide(
            promoted,
            separatorFrame: separator,
            usesManagedSceneGeometry: true
        ))
        #expect(!StatusBarController.isOnVisibleSide(
            hidden,
            separatorFrame: separator,
            usesManagedSceneGeometry: true
        ))
        #expect(!StatusBarController.isOnVisibleSide(
            promoted,
            separatorFrame: separator,
            usesManagedSceneGeometry: false
        ))
    }

    @Test("Promotion fails closed when the trigger has no full slot on its left")
    func impossiblePromotionTarget() {
        let item = CGRect(x: 970, y: 0, width: 40, height: 24)
        let trigger = CGRect(x: 975, y: 1080, width: 24, height: 24)
        let rightOfNotch = CGRect(x: 948, y: 0, width: 762, height: 40)

        #expect(StatusBarController.promotionTargetX(
            itemFrame: item,
            liveToggleFrame: trigger,
            finalToggleFrame: trigger,
            visibleSegments: [rightOfNotch]
        ) == nil)
    }

    @Test("Automatic placement measures free space beside the collapsed trigger")
    func automaticPlacementCapacity() {
        let rightOfNotch = CGRect(x: 948, y: 0, width: 762, height: 40)
        let trigger = CGRect(x: 1359, y: 1073, width: 31, height: 34)
        let visibleItem = MenuBarItemWindow(
            id: 7,
            frame: CGRect(x: 1291, y: 0, width: 68, height: 34),
            ownerName: "Example",
            windowName: "Item-0"
        )

        #expect(StatusBarController.availableAutomaticPlacementWidth(
            toggleFrame: trigger,
            visibleSegments: [rightOfNotch],
            statusItems: [visibleItem]
        ) == 343)

        let alreadyOverflowing = MenuBarItemWindow(
            id: 8,
            frame: CGRect(x: 928, y: 0, width: 34, height: 34),
            ownerName: "Example",
            windowName: "Item-0"
        )
        #expect(StatusBarController.availableAutomaticPlacementWidth(
            toggleFrame: trigger,
            visibleSegments: [rightOfNotch],
            statusItems: [visibleItem, alreadyOverflowing]
        ) == 0)
    }

    @Test("Expanded proxies anchor to the trigger and stay inside the usable menu bar")
    func expandedMenuBarFrame() {
        let visibleArea = CGRect(x: 948, y: 1073, width: 762, height: 34)
        let trigger = CGRect(x: 1359, y: 1073, width: 31, height: 34)

        #expect(ExpandedMenuBarLayout.frame(
            beside: trigger,
            inside: visibleArea,
            contentWidth: 334
        ) == CGRect(x: 1025, y: 1073, width: 334, height: 34))
        #expect(ExpandedMenuBarLayout.frame(
            beside: trigger,
            inside: visibleArea,
            contentWidth: 600
        ) == CGRect(x: 948, y: 1073, width: 411, height: 34))
    }

    @Test("Expanded proxies stop before visible status items")
    func expandedMenuBarAvoidsVisibleItems() {
        let visibleArea = CGRect(x: 948, y: 1073, width: 762, height: 34)
        let trigger = CGRect(x: 1359, y: 1073, width: 31, height: 34)
        let visibleItem = CGRect(x: 1291, y: 0, width: 68, height: 34)
        let systemItem = CGRect(x: 1390, y: 0, width: 71, height: 34)
        let separator = CGRect(x: -3725, y: 0, width: 5016, height: 34)

        #expect(ExpandedMenuBarLayout.frame(
            beside: trigger,
            inside: visibleArea,
            contentWidth: 334,
            avoiding: [visibleItem, systemItem, separator],
            trailingInset: ExpandedMenuBarLayout.zeroLengthStatusItemSlotWidth
        ) == CGRect(x: 948, y: 1073, width: 327, height: 34))
    }

    @Test("Expanded proxies reserve the zero-length separator slot")
    func expandedMenuBarMatchesActivationLayout() {
        let visibleArea = CGRect(x: 948, y: 1073, width: 762, height: 34)
        let trigger = CGRect(x: 1359, y: 1073, width: 31, height: 34)

        #expect(ExpandedMenuBarLayout.frame(
            beside: trigger,
            inside: visibleArea,
            contentWidth: 334,
            trailingInset: ExpandedMenuBarLayout.zeroLengthStatusItemSlotWidth
        ) == CGRect(x: 1009, y: 1073, width: 334, height: 34))
    }

    @Test("Auto-collapse ignores FoldBar's own forwarded click")
    func autoCollapseIgnoresForwardedClick() {
        #expect(!StatusBarController.shouldFinishAutoCollapse(
            eventUserData: MenuBarCommandDragMonitor.syntheticClickEventMarker
        ))
        #expect(StatusBarController.shouldFinishAutoCollapse(eventUserData: 0))
    }

    @Test("Clicking the FoldBar trigger is left for its toggle action")
    func overflowPanelTriggerClickDoesNotDismissEarly() {
        let panel = CGRect(x: 100, y: 100, width: 300, height: 240)
        let trigger = CGRect(x: 360, y: 350, width: 32, height: 34)

        #expect(!OverflowPanelDismissal.shouldClose(
            for: CGPoint(x: trigger.midX, y: trigger.midY),
            panelFrame: panel,
            anchorFrame: trigger,
            isCommandClick: false
        ))
        #expect(OverflowPanelDismissal.shouldClose(
            for: CGPoint(x: 20, y: 20),
            panelFrame: panel,
            anchorFrame: trigger,
            isCommandClick: false
        ))
    }

    @Test("Expanded proxies fail closed when visible items leave no room")
    func expandedMenuBarRejectsOccupiedArea() {
        let visibleArea = CGRect(x: 948, y: 1073, width: 762, height: 34)
        let trigger = CGRect(x: 1359, y: 1073, width: 31, height: 34)
        let visibleItems = [CGRect(x: 970, y: 0, width: 389, height: 34)]

        #expect(ExpandedMenuBarLayout.frame(
            beside: trigger,
            inside: visibleArea,
            contentWidth: 334,
            avoiding: visibleItems
        ) == nil)
    }

    @Test("Expanded proxies consider status items only on the trigger display")
    func expandedMenuBarFiltersOtherDisplays() {
        let display = CGRect(x: 0, y: 0, width: 1712, height: 1107)
        let currentDisplay = MenuBarItemWindow(
            id: 1,
            frame: CGRect(x: 1291, y: 0, width: 68, height: 34),
            ownerName: "Example",
            windowName: "Current"
        )
        let otherDisplay = MenuBarItemWindow(
            id: 2,
            frame: CGRect(x: 1200, y: -1200, width: 68, height: 34),
            ownerName: "Example",
            windowName: "Other"
        )
        let hidden = MenuBarItemWindow(
            id: 3,
            frame: CGRect(x: -3763, y: 0, width: 38, height: 34),
            ownerName: "Example",
            windowName: "Hidden"
        )

        #expect(ExpandedMenuBarLayout.statusItemFrames(
            on: display,
            among: [currentDisplay, otherDisplay, hidden]
        ) == [currentDisplay.frame])
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

    @Test("macOS 27 import targets the hidden side of native overflow")
    func systemOverflowImportTarget() {
        let item = CGRect(x: 1094, y: 5, width: 40, height: 24)
        let overflow = CGRect(x: 994.5, y: 1, width: 17.5, height: 31)
        let targetX = StatusBarController.systemOverflowImportTargetX(
            itemFrame: item,
            overflowFrame: overflow,
            displays: [Self.main]
        )
        #expect(targetX == 970.5)

        let movedFrame = CGRect(
            x: (targetX ?? 0) - item.width / 2,
            y: item.minY,
            width: item.width,
            height: item.height
        )
        #expect(movedFrame.maxX < overflow.minX)
        #expect(MenuBarItemScanner.isHiddenBySystemOverflow(
            movedFrame,
            overflowFrame: overflow
        ))
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

    @Test("Direct drag only claims an unmodified left mouse gesture when enabled")
    func directDragMouseDownEligibility() {
        #expect(MenuBarCommandDragMonitor.acceptsDirectDragMouseDown(
            flags: [],
            allowsDirectDrag: true
        ))
        #expect(!MenuBarCommandDragMonitor.acceptsDirectDragMouseDown(
            flags: [],
            allowsDirectDrag: false
        ))
        #expect(!MenuBarCommandDragMonitor.acceptsDirectDragMouseDown(
            flags: .maskAlternate,
            allowsDirectDrag: true
        ))
        #expect(!MenuBarCommandDragMonitor.acceptsDirectDragMouseDown(
            flags: .maskShift,
            allowsDirectDrag: true
        ))
    }

    @Test("Direct drag waits for deliberate pointer movement")
    func directDragThreshold() {
        let start = CGPoint(x: 1200, y: 12)
        #expect(!MenuBarCommandDragMonitor.exceedsDirectDragThreshold(
            from: start,
            to: CGPoint(x: 1203, y: 15)
        ))
        #expect(MenuBarCommandDragMonitor.exceedsDirectDragThreshold(
            from: start,
            to: CGPoint(x: 1205, y: 12)
        ))
    }

    @Test("External menu-bar drags can target either the panel or FoldBar arrow")
    func menuBarImportDropTargets() {
        let panel = CGRect(x: 1200, y: 50, width: 280, height: 220)
        let toggle = CGRect(x: 1480, y: 0, width: 30, height: 34)

        #expect(MenuBarCommandDragMonitor.dropTarget(
            at: CGPoint(x: 1300, y: 100),
            panelFrame: panel,
            toggleFrame: toggle
        ) == .panel)
        #expect(MenuBarCommandDragMonitor.dropTarget(
            at: CGPoint(x: 1495, y: 17),
            panelFrame: panel,
            toggleFrame: toggle
        ) == .toggle)
        #expect(MenuBarCommandDragMonitor.dropTarget(
            at: CGPoint(x: 1000, y: 400),
            panelFrame: panel,
            toggleFrame: toggle
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

    @Test("Panel icons keep their native menu-bar size")
    func nativeIconSize() {
        #expect(OverflowIconLayout.displaySize(
            sourceSize: CGSize(width: 36, height: 24),
            availableWidth: 40
        ) == CGSize(width: 36, height: 24))
    }

    @Test("Oversized fallback artwork is reduced without changing aspect ratio")
    func oversizedFallbackSize() {
        #expect(OverflowIconLayout.displaySize(
            sourceSize: CGSize(width: 512, height: 256),
            availableWidth: 40
        ) == CGSize(width: 40, height: 20))
    }

    @Test("Template conversion preserves detail contrast")
    func templateDetailContrast() {
        let colouredSurface = IconCapturer.templateAlpha(forColorDistance: 100)
        let lightDetail = IconCapturer.templateAlpha(forColorDistance: 130)

        #expect(colouredSurface > 0)
        #expect(colouredSurface < lightDetail)
        #expect(lightDetail < 255)
    }

    @Test("Fallback templates retain app-icon detail without a solid block")
    func fallbackTemplateDetailContrast() {
        let surface = IconCapturer.fallbackTemplateAlpha(
            colorDistance: 0,
            sourceAlpha: 255,
            hasOpaqueSurface: true
        )
        let detail = IconCapturer.fallbackTemplateAlpha(
            colorDistance: 120,
            sourceAlpha: 255,
            hasOpaqueSurface: true
        )

        #expect(surface > 0)
        #expect(surface < detail)
        #expect(IconCapturer.fallbackTemplateAlpha(
            colorDistance: 120,
            sourceAlpha: 0,
            hasOpaqueSurface: true
        ) == 0)
        #expect(IconCapturer.fallbackTemplateAlpha(
            colorDistance: 0,
            sourceAlpha: 180,
            hasOpaqueSurface: false
        ) == 180)
    }

    @Test("Template content bounds remove asymmetric transparent margins")
    func templateContentBounds() {
        var alphaValues = Array(repeating: UInt8.zero, count: 8 * 6)
        alphaValues[2 * 8 + 5] = 200
        alphaValues[3 * 8 + 6] = 220

        #expect(IconCapturer.templateContentBounds(
            alphaValues: alphaValues,
            pixelWidth: 8,
            pixelHeight: 6,
            padding: 1
        ) == CGRect(x: 4, y: 1, width: 4, height: 4))
    }

    @Test("Square template artwork is optically centred without clipping")
    func opticallyCenteredTemplateContentBounds() {
        var alphaValues = Array(repeating: UInt8.zero, count: 9 * 7)
        alphaValues[3 * 9 + 4] = 64
        alphaValues[3 * 9 + 5] = 255

        #expect(IconCapturer.templateContentBounds(
            alphaValues: alphaValues,
            pixelWidth: 9,
            pixelHeight: 7,
            padding: 1,
            opticallyCentered: true
        ) == CGRect(x: 3, y: 2, width: 5, height: 3))
    }

    @Test("Template capture rejects foreground clipped by a capture edge")
    func templateCaptureEdgeSafety() {
        #expect(IconCapturer.templateContentIsSafelyInsideCapture(
            CGRect(x: 2, y: 1, width: 4, height: 4),
            pixelWidth: 8,
            pixelHeight: 6
        ))
        #expect(!IconCapturer.templateContentIsSafelyInsideCapture(
            CGRect(x: 4, y: 1, width: 4, height: 4),
            pixelWidth: 8,
            pixelHeight: 6
        ))
    }

    @Test("Blank captures do not invent template content")
    func blankTemplateContentBounds() {
        #expect(IconCapturer.templateContentBounds(
            alphaValues: Array(repeating: 0, count: 8 * 6),
            pixelWidth: 8,
            pixelHeight: 6
        ) == nil)
    }
}
