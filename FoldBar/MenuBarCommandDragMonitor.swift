import AppKit
import OSLog
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

    static let syntheticClickEventMarker: Int64 = 0x46_4F_4C_44_42_41_52
    static let directDragThreshold: CGFloat = 5

    private static let logger = Logger(subsystem: "local.foldbar.app", category: "ImportGesture")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var candidates: [MenuBarItemWindow] = []
    private var panelTargetFrame = CGRect.zero
    private var toggleTargetFrame = CGRect.zero
    private var pendingDirectDrag: PendingDirectDrag?
    private var activeItem: MenuBarItemWindow?
    private var lastGesturePoint = CGPoint.zero
    private var consumesUntilMouseUp = false

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
        // Intercept before WindowServer's menu-bar handling sees the original
        // press. A session tap may be too late for a mouse-down driven menu.
        var createdTap: CFMachPort?
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            createdTap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: menuBarCommandDragEventCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            if createdTap != nil {
                Self.logger.notice("import tap created location=\(location.rawValue, privacy: .public)")
                if location == .cgSessionEventTap {
                    Self.logger.notice("early HID tap unavailable; using session fallback")
                }
                break
            }
        }
        guard let eventTap = createdTap else {
            self.candidates = []
            self.panelTargetFrame = .zero
            self.toggleTargetFrame = .zero
            Self.logger.error("import tap unavailable")
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
        consumesUntilMouseUp = false
        lastGesturePoint = .zero
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

    static func acceptsImportMouseDown(
        at point: CGPoint,
        among candidates: [MenuBarItemWindow],
        flags: CGEventFlags,
        allowsDirectDrag: Bool
    ) -> Bool {
        guard sourceWindow(at: point, among: candidates) != nil else {
            return false
        }
        return flags.contains(.maskCommand)
            || acceptsDirectDragMouseDown(
                flags: flags,
                allowsDirectDrag: allowsDirectDrag
            )
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

    static func appKitFrame(fromQuartz frame: CGRect, mainDisplayBounds: CGRect) -> CGRect {
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
        if type != .tapDisabledByTimeout, type != .tapDisabledByUserInput,
           event.getIntegerValueField(.eventSourceUserData) == Self.syntheticClickEventMarker {
            return Unmanaged.passUnretained(event)
        }
        let consumed = processMouseEvent(
            type: type,
            at: event.location,
            flags: event.flags,
            allowsDirectDrag: UserDefaults.standard.bool(
                forKey: MenuBarDragSettings.directDragDefaultsKey
            )
        )
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    /// Runs the gesture decision independently of tap creation or posted input.
    /// A claimed press stays private until release; callbacks describe its
    /// result and never send the original press to the owning application.
    func processMouseEvent(
        type: CGEventType,
        at point: CGPoint,
        flags: CGEventFlags,
        allowsDirectDrag: Bool
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let source = activeItem
            let hadClaimedPress = source != nil || pendingDirectDrag != nil || consumesUntilMouseUp
            activeItem = nil
            pendingDirectDrag = nil
            // The down was already swallowed. Do not turn its eventual up
            // into a click or send a partial gesture to the real application.
            consumesUntilMouseUp = hadClaimedPress
            if let source { onEnd(source, lastGesturePoint, nil) }
            Self.logger.notice("import tap disabled type=\(type.rawValue, privacy: .public) claimedPress=\(hadClaimedPress, privacy: .public)")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        if consumesUntilMouseUp {
            if type == .leftMouseUp {
                consumesUntilMouseUp = false
                return true
            }
            if type == .leftMouseDragged { return true }
            // A new press means the old release was lost while the tap was
            // disabled. Evaluate the new gesture with the normal strict gates.
            if type == .leftMouseDown { consumesUntilMouseUp = false }
        }

        switch type {
        case .leftMouseDown:
            guard let source = Self.sourceWindow(at: point, among: candidates) else {
                return false
            }
            guard Self.acceptsImportMouseDown(
                at: point,
                among: candidates,
                flags: flags,
                allowsDirectDrag: allowsDirectDrag
            ) else {
                Self.logger.notice("candidate press passed through item=\(source.id, privacy: .public) flags=\(flags.rawValue, privacy: .public)")
                return false
            }
            lastGesturePoint = point
            if flags.contains(.maskCommand) {
                activeItem = source
                Self.logger.notice("command press claimed item=\(source.id, privacy: .public)")
                onBegin(source, point)
                return true
            }
            pendingDirectDrag = PendingDirectDrag(item: source, startPoint: point)
            Self.logger.notice("direct press held item=\(source.id, privacy: .public)")
            return true

        case .leftMouseDragged:
            if activeItem != nil {
                lastGesturePoint = point
                onUpdate(point, currentDropTarget(at: point))
                return true
            }
            guard let pendingDirectDrag else { return false }
            lastGesturePoint = point
            guard Self.exceedsDirectDragThreshold(
                from: pendingDirectDrag.startPoint,
                to: point
            ) else { return true }

            self.pendingDirectDrag = nil
            activeItem = pendingDirectDrag.item
            Self.logger.notice("held press became drag item=\(pendingDirectDrag.item.id, privacy: .public)")
            onBegin(pendingDirectDrag.item, pendingDirectDrag.startPoint)
            onUpdate(point, currentDropTarget(at: point))
            return true

        case .leftMouseUp:
            lastGesturePoint = point
            if let source = activeItem {
                activeItem = nil
                onEnd(source, point, currentDropTarget(at: point))
                return true
            }
            guard let pendingDirectDrag else { return false }
            self.pendingDirectDrag = nil
            // Fast/coalesced gestures may deliver no dragged event. A release
            // beyond the threshold is still a drag, even inside the old frame.
            if Self.exceedsDirectDragThreshold(from: pendingDirectDrag.startPoint, to: point) {
                Self.logger.notice("release resolved coalesced drag item=\(pendingDirectDrag.item.id, privacy: .public)")
                onBegin(pendingDirectDrag.item, pendingDirectDrag.startPoint)
                onUpdate(point, currentDropTarget(at: point))
                onEnd(pendingDirectDrag.item, point, currentDropTarget(at: point))
            } else if pendingDirectDrag.item.frame.insetBy(dx: -2, dy: -2).contains(point) {
                Self.logger.notice("held press resolved click item=\(pendingDirectDrag.item.id, privacy: .public)")
                onClick(pendingDirectDrag.item, pendingDirectDrag.startPoint)
            }
            return true

        default:
            return false
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
