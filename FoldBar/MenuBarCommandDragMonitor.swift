import AppKit
@preconcurrency import CoreGraphics

enum MenuBarDragSettings {
    static let directDragDefaultsKey = "directMenuBarDragEnabled"
}

enum MenuBarImportDropTarget: Equatable {
    case panel
    case toggle
}

/// Converts a user-initiated drag from a real menu-bar item into a private
/// FoldBar drag session. Command-drag always works. When direct drag is enabled,
/// a plain click is held until it either crosses the drag threshold or is safely
/// replayed as a click. The original drag events are consumed before
/// SystemUIServer can interpret a downward drag as removing the status item.
///
/// The event tap is installed only while the overflow panel is visible and only
/// claims a mouse-down that begins inside a recently scanned, explicitly
/// allowed status-item window. Every other event passes through unchanged.
@MainActor
final class MenuBarCommandDragMonitor {
    typealias BeginHandler = @MainActor (MenuBarItemWindow, CGPoint) -> Void
    typealias UpdateHandler = @MainActor (CGPoint, MenuBarImportDropTarget?) -> Void
    typealias EndHandler = @MainActor (MenuBarItemWindow, CGPoint, MenuBarImportDropTarget?) -> Void
    typealias ClickHandler = @MainActor (MenuBarItemWindow, CGPoint) -> Void

    private struct PendingDirectDrag {
        let item: MenuBarItemWindow
        let startPoint: CGPoint
    }

    static let replayedClickEventMarker: Int64 = 0x46_4F_4C_44_42_41_52
    static let directDragThreshold: CGFloat = 5

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var candidates: [MenuBarItemWindow] = []
    private var panelTargetFrame = CGRect.zero
    private var toggleTargetFrame = CGRect.zero
    private var pendingDirectDrag: PendingDirectDrag?
    private var activeItem: MenuBarItemWindow?

    private let onBegin: BeginHandler
    private let onUpdate: UpdateHandler
    private let onEnd: EndHandler
    private let onClick: ClickHandler

    init(
        onBegin: @escaping BeginHandler,
        onUpdate: @escaping UpdateHandler,
        onEnd: @escaping EndHandler,
        onClick: @escaping ClickHandler
    ) {
        self.onBegin = onBegin
        self.onUpdate = onUpdate
        self.onEnd = onEnd
        self.onClick = onClick
    }

    var isRunning: Bool { eventTap != nil }

    func start(
        candidates: [MenuBarItemWindow],
        panelTargetFrame: CGRect,
        toggleTargetFrame: CGRect
    ) -> Bool {
        stop()
        self.candidates = candidates
        self.panelTargetFrame = panelTargetFrame
        self.toggleTargetFrame = toggleTargetFrame

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
            self.panelTargetFrame = .zero
            self.toggleTargetFrame = .zero
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
        pendingDirectDrag = nil
        candidates = []
        panelTargetFrame = .zero
        toggleTargetFrame = .zero
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

    static func acceptsDirectDragMouseDown(
        flags: CGEventFlags,
        allowsDirectDrag: Bool
    ) -> Bool {
        guard allowsDirectDrag else { return false }
        let applicationModifiers: CGEventFlags = [
            .maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate
        ]
        return flags.intersection(applicationModifiers).isEmpty
    }

    static func exceedsDirectDragThreshold(
        from start: CGPoint,
        to current: CGPoint,
        threshold: CGFloat = directDragThreshold
    ) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return dx * dx + dy * dy >= threshold * threshold
    }

    static func dropTarget(
        at point: CGPoint,
        panelFrame: CGRect,
        toggleFrame: CGRect
    ) -> MenuBarImportDropTarget? {
        if toggleFrame.contains(point) { return .toggle }
        if panelFrame.contains(point) { return .panel }
        return nil
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
            activeItem = nil
            pendingDirectDrag = nil
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.replayedClickEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let point = event.location
        switch type {
        case .leftMouseDown:
            guard let source = Self.sourceWindow(at: point, among: candidates) else {
                return Unmanaged.passUnretained(event)
            }
            if event.flags.contains(.maskCommand) {
                activeItem = source
                onBegin(source, point)
                return nil
            }
            guard Self.acceptsDirectDragMouseDown(
                flags: event.flags,
                allowsDirectDrag: UserDefaults.standard.bool(
                    forKey: MenuBarDragSettings.directDragDefaultsKey
                )
            ) else {
                return Unmanaged.passUnretained(event)
            }
            pendingDirectDrag = PendingDirectDrag(item: source, startPoint: point)
            return nil

        case .leftMouseDragged:
            if activeItem != nil {
                onUpdate(point, currentDropTarget(at: point))
                return nil
            }
            guard let pendingDirectDrag else {
                return Unmanaged.passUnretained(event)
            }
            guard Self.exceedsDirectDragThreshold(
                from: pendingDirectDrag.startPoint,
                to: point
            ) else { return nil }

            self.pendingDirectDrag = nil
            activeItem = pendingDirectDrag.item
            onBegin(pendingDirectDrag.item, pendingDirectDrag.startPoint)
            onUpdate(point, currentDropTarget(at: point))
            return nil

        case .leftMouseUp:
            if let source = activeItem {
                activeItem = nil
                onEnd(source, point, currentDropTarget(at: point))
                return nil
            }
            guard let pendingDirectDrag else {
                return Unmanaged.passUnretained(event)
            }
            self.pendingDirectDrag = nil
            if pendingDirectDrag.item.frame.insetBy(dx: -2, dy: -2).contains(point) {
                onClick(pendingDirectDrag.item, pendingDirectDrag.startPoint)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func currentDropTarget(at point: CGPoint) -> MenuBarImportDropTarget? {
        Self.dropTarget(
            at: point,
            panelFrame: panelTargetFrame,
            toggleFrame: toggleTargetFrame
        )
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
