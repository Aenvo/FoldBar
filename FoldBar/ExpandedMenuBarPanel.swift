import AppKit

enum ExpandedMenuBarLayout {
    static let minimumItemWidth: CGFloat = 24
    static let maximumItemWidth: CGFloat = 220

    static func itemWidth(for frame: CGRect) -> CGFloat {
        min(maximumItemWidth, max(minimumItemWidth, frame.width))
    }

    static func frame(
        beside anchor: CGRect,
        inside visibleArea: CGRect,
        contentWidth: CGFloat
    ) -> CGRect? {
        guard anchor.width > 0,
              anchor.height > 0,
              contentWidth > 0,
              visibleArea.width > 0,
              visibleArea.height > 0,
              anchor.midX >= visibleArea.minX,
              anchor.midX <= visibleArea.maxX else { return nil }

        let availableWidth = anchor.minX - visibleArea.minX
        guard availableWidth >= minimumItemWidth else { return nil }
        let width = min(contentWidth, availableWidth)
        return CGRect(
            x: anchor.minX - width,
            y: anchor.minY,
            width: width,
            height: min(anchor.height, visibleArea.height)
        )
    }
}

private final class ExpandedMenuBarWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ExpandedMenuBarButton: NSButton {
    private let handler: () -> Void

    init(item: CapturedItem, frame: CGRect, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: frame)
        image = item.image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        toolTip = item.hoverText
        setAccessibilityLabel(item.hoverText)
        target = self
        action = #selector(pressed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pressed() {
        handler()
    }
}

/// Displays captured menu-item proxies directly in the usable menu-bar strip.
///
/// The panel sits above ordinary status-item windows, so proxies temporarily
/// replace whatever already occupies the area immediately left of FoldBar's
/// trigger without changing another application's persistent item order.
@MainActor
final class ExpandedMenuBarPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var onDismiss: (@MainActor () -> Void)?
    private var anchorFrame = CGRect.zero

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: CGRect? { panel?.frame }

    @discardableResult
    func show(
        items: [CapturedItem],
        beside anchor: CGRect,
        onClick: @escaping @MainActor (CapturedItem) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) -> Bool {
        close()
        guard !items.isEmpty,
              let visibleArea = Self.visibleMenuBarArea(containing: anchor) else { return false }

        // The panel's left-to-right view order is the reverse of the overflow
        // panel order: the item nearest FoldBar remains nearest its trigger.
        let arrangedItems = Array(items.reversed())
        let widths = arrangedItems.map { ExpandedMenuBarLayout.itemWidth(for: $0.window.frame) }
        let contentWidth = widths.reduce(0, +)
        guard let panelFrame = ExpandedMenuBarLayout.frame(
            beside: anchor,
            inside: visibleArea,
            contentWidth: contentWidth
        ) else { return false }

        let panel = ExpandedMenuBarWindow(
            contentRect: CGRect(origin: .zero, size: panelFrame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: panelFrame.size))
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.76)
            .cgColor

        let scrollView = NSScrollView(frame: background.bounds)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none

        let document = NSView(frame: CGRect(
            x: 0,
            y: 0,
            width: max(contentWidth, panelFrame.width),
            height: panelFrame.height
        ))
        var x: CGFloat = 0
        for (index, item) in arrangedItems.enumerated() {
            let width = widths[index]
            let button = ExpandedMenuBarButton(
                item: item,
                frame: CGRect(x: x, y: 0, width: width, height: panelFrame.height)
            ) { [weak self] in
                self?.close()
                onClick(item)
            }
            document.addSubview(button)
            x += width
        }
        scrollView.documentView = document
        background.addSubview(scrollView)

        panel.contentView = background
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.setFrameOrigin(panelFrame.origin)

        self.panel = panel
        self.anchorFrame = anchor
        self.onDismiss = onDismiss
        panel.orderFrontRegardless()
        panel.makeKey()

        let trailingOffset = max(0, contentWidth - panelFrame.width)
        scrollView.contentView.scroll(to: CGPoint(x: trailingOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        installMonitors()
        return true
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        anchorFrame = .zero
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    static func visibleMenuBarArea(
        containing anchor: CGRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> CGRect? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = screens.first(where: { $0.frame.contains(point) }) ?? screens.first else {
            return nil
        }
        if let area = screen.auxiliaryTopRightArea, area.width > 0, area.height > 0 {
            return area
        }
        return CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - anchor.height,
            width: screen.frame.width,
            height: anchor.height
        )
    }

    private func installMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    let location = NSEvent.mouseLocation
                    // Let the trigger's own action close the strip. Closing on
                    // mouse-down would otherwise let its mouse-up reopen the grid.
                    if panel.frame.contains(location) || self.anchorFrame.contains(location) { return }
                    self.close()
                }
            }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                if event.keyCode == 53 {
                    self?.close()
                    return nil
                }
                return event
            }
        ) {
            monitors.append(monitor)
        }
    }
}
