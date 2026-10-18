import AppKit

enum ExpandedMenuBarLayout {
    static let minimumItemWidth: CGFloat = 24
    static let maximumItemWidth: CGFloat = 220
    // Control Center keeps this outer slot even when NSStatusItem.length is 0.
    // Reserve it in the proxy layout so activation does not shift every item.
    static let zeroLengthStatusItemSlotWidth: CGFloat = 16

    static func itemWidth(for frame: CGRect) -> CGFloat {
        min(maximumItemWidth, max(minimumItemWidth, frame.width))
    }

    static func statusItemFrames(
        on displayBounds: CGRect,
        among windows: [MenuBarItemWindow]
    ) -> [CGRect] {
        windows.compactMap { window in
            let frame = window.frame
            guard frame.minY >= displayBounds.minY - 2,
                  frame.maxY <= displayBounds.minY + 42,
                  frame.height <= 40,
                  frame.minX >= displayBounds.minX,
                  frame.maxX <= displayBounds.maxX else { return nil }
            return frame
        }
    }

    static func frame(
        beside anchor: CGRect,
        inside visibleArea: CGRect,
        contentWidth: CGFloat,
        avoiding occupiedFrames: [CGRect] = [],
        trailingInset: CGFloat = 0
    ) -> CGRect? {
        guard anchor.width > 0,
              anchor.height > 0,
              contentWidth > 0,
              trailingInset >= 0,
              visibleArea.width > 0,
              visibleArea.height > 0,
              anchor.midX >= visibleArea.minX,
              anchor.midX <= visibleArea.maxX else { return nil }

        let trailingEdge = occupiedFrames
            .filter {
                $0.width > 0
                    && $0.minX >= visibleArea.minX
                    && $0.minX < anchor.minX
                    && $0.maxX <= anchor.minX + 1
            }
            .map(\.minX)
            .min() ?? anchor.minX
        let alignedTrailingEdge = trailingEdge - trailingInset
        let availableWidth = alignedTrailingEdge - visibleArea.minX
        guard availableWidth >= minimumItemWidth else { return nil }
        let width = min(contentWidth, availableWidth)
        return CGRect(
            x: alignedTrailingEdge - width,
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
    private let item: CapturedItem

    init(item: CapturedItem, frame: CGRect, handler: @escaping () -> Void) {
        self.handler = handler
        self.item = item
        super.init(frame: frame)
        image = item.image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        refreshLocalizedText()
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

    func refreshLocalizedText() {
        toolTip = item.hoverText
        setAccessibilityLabel(item.hoverText)
    }
}

/// Displays captured menu-item proxies directly in the usable menu-bar strip.
///
/// The panel sits above ordinary status-item windows but stops before visible
/// status items to keep its transparent proxies from drawing over real icons.
@MainActor
final class ExpandedMenuBarPanel {
    private var panel: NSPanel?
    private var buttons: [ExpandedMenuBarButton] = []
    private var monitors: [Any] = []
    private var onDismiss: (@MainActor () -> Void)?
    private var anchorFrame = CGRect.zero

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: CGRect? { panel?.frame }

    @discardableResult
    func show(
        items: [CapturedItem],
        beside anchor: CGRect,
        avoiding visibleItems: [MenuBarItemWindow],
        onClick: @escaping @MainActor (CapturedItem) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) -> Bool {
        close()
        guard !items.isEmpty,
              let screen = Self.screen(containing: anchor),
              let visibleArea = Self.visibleMenuBarArea(containing: anchor, screens: [screen])
        else { return false }

        // The panel's left-to-right view order is the reverse of the overflow
        // panel order: the item nearest FoldBar remains nearest its trigger.
        let arrangedItems = Array(items.reversed())
        let widths = arrangedItems.map { ExpandedMenuBarLayout.itemWidth(for: $0.window.frame) }
        let contentWidth = widths.reduce(0, +)
        guard let panelFrame = ExpandedMenuBarLayout.frame(
            beside: anchor,
            inside: visibleArea,
            contentWidth: contentWidth,
            avoiding: Self.visibleStatusItemFrames(
                on: screen,
                among: visibleItems
            ),
            trailingInset: ExpandedMenuBarLayout.zeroLengthStatusItemSlotWidth
        ) else { return false }

        let panel = ExpandedMenuBarWindow(
            contentRect: CGRect(origin: .zero, size: panelFrame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Keep the expanded strip visually native to the menu bar: only the
        // captured item proxies should be visible, with no rectangular panel
        // material behind them.
        let contentView = NSView(frame: CGRect(origin: .zero, size: panelFrame.size))

        let scrollView = NSScrollView(frame: contentView.bounds)
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
            ) {
                onClick(item)
            }
            document.addSubview(button)
            buttons.append(button)
            x += width
        }
        scrollView.documentView = document
        contentView.addSubview(scrollView)

        panel.contentView = contentView
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
        removeMonitors()
        buttons.removeAll()
        panel?.orderOut(nil)
        panel = nil
        anchorFrame = .zero
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    func refreshLocalizedText() {
        buttons.forEach { $0.refreshLocalizedText() }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    static func visibleMenuBarArea(
        containing anchor: CGRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> CGRect? {
        guard let screen = screen(containing: anchor, screens: screens) else { return nil }
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

    private static func screen(
        containing anchor: CGRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        return screens.first(where: { $0.frame.contains(point) }) ?? screens.first
    }

    private static func visibleStatusItemFrames(
        on screen: NSScreen,
        among windows: [MenuBarItemWindow]
    ) -> [CGRect] {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return []
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        return ExpandedMenuBarLayout.statusItemFrames(on: displayBounds, among: windows)
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
