import AppKit
import ApplicationServices

@MainActor
enum EventForwarder {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func click(at point: CGPoint, eventUserData: Int64? = nil) {
        let previous = CGEvent(source: nil)?.location
        postMouse(.mouseMoved, at: point, eventUserData: eventUserData)
        postMouse(.leftMouseDown, at: point, clickState: 1, eventUserData: eventUserData)
        postMouse(.leftMouseUp, at: point, clickState: 1, eventUserData: eventUserData)
        if let previous { postMouse(.mouseMoved, at: previous, eventUserData: eventUserData) }
    }

    /// Reorders a real NSStatusItem using the same Command-drag gesture the
    /// user would perform. There is no public API for cross-app item order.
    static func commandDrag(from start: CGPoint, to end: CGPoint) async -> Bool {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
              let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let previous = CGEvent(source: source)?.location
        let dragFlags: CGEventFlags = [.maskCommand, .maskNonCoalesced]
        var lastPoint = start
        var mouseIsDown = false

        defer {
            if mouseIsDown {
                _ = postMouse(.leftMouseUp, at: lastPoint, source: source, flags: dragFlags, clickState: 1)
            }
            if let previous {
                _ = postMouse(.mouseMoved, at: previous, source: source, flags: .maskNonCoalesced)
            }
        }

        guard postMouse(.mouseMoved, at: start, source: source, flags: dragFlags) else { return false }
        try? await Task.sleep(for: .milliseconds(45))
        guard !Task.isCancelled,
              postMouse(.leftMouseDown, at: start, source: source, flags: dragFlags, clickState: 1)
        else { return false }
        mouseIsDown = true

        // Give AppKit time to establish its menu-bar drag session, then send
        // non-coalesced movement at a human-scale cadence. Posting every point
        // synchronously can collapse the path into too little movement for the
        // status bar's reorder gesture recognizer.
        try? await Task.sleep(for: .milliseconds(80))
        let stepCount = 24
        for step in 1...stepCount {
            guard !Task.isCancelled else { return false }
            let fraction = CGFloat(step) / CGFloat(stepCount)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            guard postMouse(
                .leftMouseDragged,
                at: point,
                source: source,
                flags: dragFlags,
                clickState: 1
            ) else { return false }
            lastPoint = point
            try? await Task.sleep(for: .milliseconds(12))
        }
        guard postMouse(.leftMouseUp, at: end, source: source, flags: dragFlags, clickState: 1) else {
            return false
        }
        mouseIsDown = false
        try? await Task.sleep(for: .milliseconds(40))
        return true
    }

    @discardableResult
    private static func postMouse(
        _ type: CGEventType,
        at point: CGPoint,
        source: CGEventSource? = nil,
        flags: CGEventFlags = [],
        clickState: Int64? = nil,
        eventUserData: Int64? = nil
    ) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return false }
        event.flags = flags
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        if let eventUserData {
            event.setIntegerValueField(.eventSourceUserData, value: eventUserData)
        }
        event.post(tap: .cghidEventTap)
        return true
    }
}
