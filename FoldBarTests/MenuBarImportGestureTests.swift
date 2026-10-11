import AppKit
@preconcurrency import CoreGraphics
import Testing

@testable import FoldBar

@Suite("Menu-bar import gesture sequences")
@MainActor
struct MenuBarImportGestureTests {
    private enum Callback: Equatable {
        case begin(CGWindowID, CGPoint)
        case update(CGPoint, MenuBarImportDropTarget?)
        case end(CGWindowID, CGPoint, MenuBarImportDropTarget?)
        case click(CGWindowID, CGPoint)
    }

    @MainActor
    private final class Recorder {
        var callbacks: [Callback] = []
    }

    @MainActor
    private struct Gesture {
        let recorder: Recorder
        let monitor: MenuBarCommandDragMonitor

        init() {
            let recorder = Recorder()
            self.recorder = recorder
            monitor = MenuBarCommandDragMonitor(
                onBegin: { item, point in recorder.callbacks.append(.begin(item.id, point)) },
                onUpdate: { point, target in recorder.callbacks.append(.update(point, target)) },
                onEnd: { item, point, target in recorder.callbacks.append(.end(item.id, point, target)) },
                onClick: { item, point in recorder.callbacks.append(.click(item.id, point)) }
            )
            // Exercise state transitions directly. No event tap, synthetic
            // input, UserDefaults changes, or permission prompts are involved.
            monitor.updateCandidates([MenuBarImportGestureTests.candidate])
        }

        @discardableResult
        func send(
            _ type: CGEventType,
            at point: CGPoint = MenuBarImportGestureTests.start,
            flags: CGEventFlags = [],
            allowsDirectDrag: Bool = true
        ) -> Bool {
            monitor.processMouseEvent(
                type: type,
                at: point,
                flags: flags,
                allowsDirectDrag: allowsDirectDrag
            )
        }
    }

    private static let candidate = MenuBarItemWindow(
        id: 41,
        frame: CGRect(x: 1200, y: 4, width: 24, height: 24),
        ownerName: "Example",
        windowName: "Item-0"
    )
    private static let start = CGPoint(x: 1212, y: 16)
    private static let outside = CGPoint(x: 900, y: 100)

    @Test("Holding a direct mouse-down does not activate its item")
    func heldDirectMouseDown() {
        let gesture = Gesture()
        #expect(!gesture.monitor.isRunning)
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.recorder.callbacks.isEmpty)
        #expect(gesture.send(.leftMouseDragged, at: CGPoint(x: 1213, y: 17)))
        #expect(gesture.send(.leftMouseDragged, at: CGPoint(x: 1211, y: 16)))
        #expect(gesture.recorder.callbacks.isEmpty)
    }

    @Test("A released click with small pointer jitter activates exactly once")
    func directClickAfterJitter() {
        let gesture = Gesture()
        let release = CGPoint(x: 1215, y: 18)
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.send(.leftMouseDragged, at: release))
        #expect(gesture.recorder.callbacks.isEmpty)
        #expect(gesture.send(.leftMouseUp, at: release))
        #expect(gesture.recorder.callbacks == [.click(Self.candidate.id, Self.start)])
        // A duplicate release cannot replay the same click again.
        #expect(!gesture.send(.leftMouseUp, at: release))
        #expect(gesture.recorder.callbacks.count == 1)
    }

    @Test("Crossing the drag threshold cannot activate the source on release")
    func directDragThenRelease() {
        let gesture = Gesture()
        let threshold = CGPoint(x: 1217, y: 16)
        let destination = CGPoint(x: 1219, y: 42)
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.send(.leftMouseDragged, at: threshold))
        #expect(gesture.send(.leftMouseDragged, at: destination))
        #expect(gesture.send(.leftMouseUp, at: destination))
        #expect(gesture.recorder.callbacks == [
            .begin(Self.candidate.id, Self.start),
            .update(threshold, nil),
            .update(destination, nil),
            .end(Self.candidate.id, destination, nil)
        ])
    }

    @Test("A coalesced fast drag is resolved from its release position")
    func fastDragWithoutDraggedEvent() {
        let gesture = Gesture()
        // This is still inside the real item frame, reproducing the case
        // where testing only release containment accidentally opens its menu.
        let release = CGPoint(x: 1217, y: 16)
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.recorder.callbacks.isEmpty)
        #expect(gesture.send(.leftMouseUp, at: release))
        #expect(gesture.recorder.callbacks == [
            .begin(Self.candidate.id, Self.start),
            .update(release, nil),
            .end(Self.candidate.id, release, nil)
        ])
    }

    @Test("Unrelated, modified, and disabled direct gestures pass through")
    func ineligibleGesturesPassThrough() {
        let cases: [(point: CGPoint, flags: CGEventFlags, enabled: Bool)] = [
            (Self.outside, [], true),
            (Self.start, .maskAlternate, true),
            (Self.start, .maskControl, true),
            (Self.start, .maskShift, true),
            (Self.start, [], false)
        ]
        for testCase in cases {
            let gesture = Gesture()
            #expect(!gesture.send(
                .leftMouseDown, at: testCase.point,
                flags: testCase.flags, allowsDirectDrag: testCase.enabled
            ))
            #expect(!gesture.send(
                .leftMouseDragged, at: Self.start,
                flags: testCase.flags, allowsDirectDrag: testCase.enabled
            ))
            #expect(!gesture.send(
                .leftMouseUp, at: Self.start,
                flags: testCase.flags, allowsDirectDrag: testCase.enabled
            ))
            #expect(gesture.recorder.callbacks.isEmpty)
        }
    }

    @Test("Command-drag never becomes a click even when direct drag is disabled")
    func commandDragDoesNotClick() {
        let gesture = Gesture()
        #expect(gesture.send(.leftMouseDown, flags: .maskCommand, allowsDirectDrag: false))
        #expect(gesture.recorder.callbacks == [.begin(Self.candidate.id, Self.start)])
        #expect(gesture.send(.leftMouseUp, flags: .maskCommand, allowsDirectDrag: false))
        #expect(gesture.recorder.callbacks == [
            .begin(Self.candidate.id, Self.start),
            .end(Self.candidate.id, Self.start, nil)
        ])
    }

    @Test("A timed-out pending gesture cancels and consumes its remaining events")
    func pendingGestureTimeout() {
        let gesture = Gesture()
        #expect(gesture.send(.leftMouseDown))
        gesture.send(.tapDisabledByTimeout)
        #expect(gesture.recorder.callbacks.isEmpty)
        #expect(gesture.send(.leftMouseDragged, at: CGPoint(x: 1220, y: 22)))
        #expect(gesture.send(.leftMouseUp))
        #expect(gesture.recorder.callbacks.isEmpty)

        #expect(!gesture.send(.leftMouseDown, at: Self.outside))
        #expect(!gesture.send(.leftMouseUp, at: Self.outside))
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.send(.leftMouseUp))
        #expect(gesture.recorder.callbacks == [.click(Self.candidate.id, Self.start)])
    }

    @Test("A timed-out active drag ends with no target and cannot activate its item")
    func activeGestureTimeout() {
        let gesture = Gesture()
        let moved = CGPoint(x: 1217, y: 16)
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.send(.leftMouseDragged, at: moved))
        gesture.send(.tapDisabledByTimeout, at: moved)
        #expect(gesture.recorder.callbacks.count == 3)
        #expect(Array(gesture.recorder.callbacks.prefix(2)) == [
            .begin(Self.candidate.id, Self.start), .update(moved, nil)
        ])
        if let callback = gesture.recorder.callbacks.last,
           case let .end(itemID, _, target) = callback {
            #expect(itemID == Self.candidate.id)
            #expect(target == nil)
        } else {
            Issue.record("A cancelled active drag must call onEnd with no drop target")
        }
        #expect(gesture.send(.leftMouseDragged, at: CGPoint(x: 1221, y: 25)))
        #expect(gesture.send(.leftMouseUp))
        #expect(gesture.recorder.callbacks.count == 3)

        #expect(!gesture.send(.leftMouseDown, at: Self.outside))
        #expect(!gesture.send(.leftMouseUp, at: Self.outside))
        #expect(gesture.send(.leftMouseDown))
        #expect(gesture.send(.leftMouseUp))
        #expect(gesture.recorder.callbacks.last == .click(Self.candidate.id, Self.start))
        #expect(gesture.recorder.callbacks.count == 4)
    }
}
