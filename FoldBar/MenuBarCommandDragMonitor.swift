import AppKit
@preconcurrency import CoreGraphics

/// Converts a user-initiated Command-drag from a real menu-bar item into a
/// private FoldBar drag session. The original mouse events are consumed before
/// SystemUIServer can interpret a downward drag as removing the status item.
///
/// The event tap is installed only while the overflow panel is visible and only
/// claims a mouse-down that begins inside a recently scanned, explicitly
/// allowed status-item window. Every other event passes through unchanged.
@MainActor
final class MenuBarCommandDragMonitor {
    typealias BeginHandler = @MainActor (MenuBarItemWindow, CGPoint) -> Void
    typealias UpdateHandler = @MainActor (CGPoint, Bool) -> Void
    typealias EndHandler = @MainActor (MenuBarItemWindow, CGPoint, Bool) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var candidates: [MenuBarItemWindow] = []
    private var targetFrame = CGRect.zero
    private var activeItem: MenuBarItemWindow?

    private let onBegin: BeginHandler
    private let onUpdate: UpdateHandler
    private let onEnd: EndHandler

    init(
        onBegin: @escaping BeginHandler,
        onUpdate: @escaping UpdateHandler,
        onEnd: @escaping EndHandler
    ) {
        self.onBegin = onBegin
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    var isRunning: Bool { eventTap != nil }

    func start(candidates: [MenuBarItemWindow], targetFrame: CGRect) -> Bool {
        stop()
        self.candidates = candidates
        self.targetFrame = targetFrame

        let mask = Self.mask(for: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: menuBarCommandDragEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.candidates = []
            self.targetFrame = .zero
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    func updateCandidates(_ candidates: [MenuBarItemWindow]) {
        self.candidates = candidates
    }

    func stop() {
        activeItem = nil
        candidates = []
        targetFrame = .zero
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    static func sourceWindow(
        at point: CGPoint,
        among candidates: [MenuBarItemWindow]
    ) -> MenuBarItemWindow? {
        candidates
            .filter { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
            .min { lhs, rhs in
                lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
            }
    }

    static func quartzFrame(fromAppKit frame: CGRect, mainDisplayBounds: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: mainDisplayBounds.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func appKitPoint(fromQuartz point: CGPoint, mainDisplayBounds: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayBounds.maxY - point.y)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let point = event.location
        switch type {
        case .leftMouseDown:
            guard event.flags.contains(.maskCommand),
                  let source = Self.sourceWindow(at: point, among: candidates)
            else {
                return Unmanaged.passUnretained(event)
            }
            activeItem = source
            onBegin(source, point)
            return nil

        case .leftMouseDragged:
            guard activeItem != nil else { return Unmanaged.passUnretained(event) }
            onUpdate(point, targetFrame.contains(point))
            return nil

        case .leftMouseUp:
            guard let source = activeItem else { return Unmanaged.passUnretained(event) }
            activeItem = nil
            onEnd(source, point, targetFrame.contains(point))
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func mask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }
    }
}

private func menuBarCommandDragEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard Thread.isMainThread, let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MenuBarCommandDragMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
}
