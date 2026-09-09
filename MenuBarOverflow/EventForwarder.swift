import AppKit
import ApplicationServices

@MainActor
enum EventForwarder {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func click(at point: CGPoint) {
        let previous = CGEvent(source: nil)?.location
        postMouse(.mouseMoved, at: point)
        postMouse(.leftMouseDown, at: point, clickState: 1)
        postMouse(.leftMouseUp, at: point, clickState: 1)
        if let previous { postMouse(.mouseMoved, at: previous) }
    }

    /// Reorders a real NSStatusItem using the same Command-drag gesture the
    /// user would perform. There is no public API for cross-app item order.
    static func commandDrag(from start: CGPoint, to end: CGPoint) {
        let previous = CGEvent(source: nil)?.location
        postMouse(.mouseMoved, at: start, flags: .maskCommand)
        postMouse(.leftMouseDown, at: start, flags: .maskCommand, clickState: 1)
        for step in 1...12 {
            let fraction = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            postMouse(.leftMouseDragged, at: point, flags: .maskCommand, clickState: 1)
        }
        postMouse(.leftMouseUp, at: end, flags: .maskCommand, clickState: 1)
        if let previous { postMouse(.mouseMoved, at: previous) }
    }

    private static func postMouse(
        _ type: CGEventType,
        at point: CGPoint,
        flags: CGEventFlags = [],
        clickState: Int64? = nil
    ) {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.flags = flags
        if let clickState {
            event?.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        event?.post(tap: .cghidEventTap)
    }
}
