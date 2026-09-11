import SwiftUI

private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class ExternalDragPreviewPanel {
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var lastPoint = CGPoint.zero

    func show(image: NSImage?, atQuartzPoint point: CGPoint) {
        close()
        lastPoint = point

        let previewImage = image
            ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
        let ratio = max(0.8, min(3, (previewImage?.size.width ?? 24) / max(1, previewImage?.size.height ?? 24)))
        let size = NSSize(width: max(46, min(96, 14 + 28 * ratio)), height: 46)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.72).cgColor

        let imageView = NSImageView(frame: background.bounds.insetBy(dx: 7, dy: 7))
        imageView.image = previewImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        background.addSubview(imageView)

        panel.contentView = background
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        self.imageView = imageView
        move(toQuartzPoint: point)
        panel.orderFrontRegardless()
    }

    func update(image: NSImage) {
        show(image: image, atQuartzPoint: lastPoint)
    }

    func move(toQuartzPoint point: CGPoint) {
        lastPoint = point
        guard let panel else { return }
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let appKitPoint = MenuBarCommandDragMonitor.appKitPoint(
            fromQuartz: point,
            mainDisplayBounds: mainBounds
        )
        let proposed = NSPoint(
            x: appKitPoint.x + 12,
            y: appKitPoint.y - panel.frame.height - 12
        )
        let screen = NSScreen.screens.first { $0.frame.contains(appKitPoint) }
        let origin = screen.map { screen in
            NSPoint(
                x: min(max(proposed.x, screen.frame.minX), screen.frame.maxX - panel.frame.width),
                y: min(max(proposed.y, screen.frame.minY), screen.frame.maxY - panel.frame.height)
            )
        } ?? proposed
        panel.setFrameOrigin(origin)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
    }
}

@MainActor
private final class OverflowDragState: ObservableObject {
    @Published private(set) var isDraggingItem = false
    @Published private(set) var isDraggingExternalItem = false
    @Published private(set) var isExternalItemInsidePanel = false
    private var releaseTask: Task<Void, Never>?

    func beginDragging() {
        releaseTask?.cancel()
        isDraggingItem = true
        releaseTask = Task { @MainActor [weak self] in
            while (NSEvent.pressedMouseButtons & 1) == 1 {
                do {
                    try await Task.sleep(for: .milliseconds(8))
                } catch {
                    return
                }
            }
            self?.isDraggingItem = false
            self?.releaseTask = nil
        }
    }

    func beginExternalDragging() {
        isDraggingExternalItem = true
        isExternalItemInsidePanel = false
    }

    func updateExternalDragging(isInsidePanel: Bool) {
        isExternalItemInsidePanel = isInsidePanel
    }

    func endExternalDragging() {
        isDraggingExternalItem = false
        isExternalItemInsidePanel = false
    }

    func cancelAllDragging() {
        releaseTask?.cancel()
        releaseTask = nil
        isDraggingItem = false
        endExternalDragging()
    }
}

@MainActor
final class OverflowPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var dragState: OverflowDragState?
    private let externalPreview = ExternalDragPreviewPanel()
    private var onDismiss: (@MainActor () -> Void)?
    private static let edgeInset: CGFloat = 6

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: CGRect? { panel?.frame }

    func show(
        items: [CapturedItem],
        below anchorFrame: NSRect,
        onClick: @escaping @MainActor (CapturedItem) -> Void,
        onPromote: @escaping @MainActor (CapturedItem) -> Void,
        onExpand: @escaping @MainActor () -> Void,
        onSettings: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        close()
        self.onDismiss = onDismiss

        let dragState = OverflowDragState()
        self.dragState = dragState
        let content = OverflowPanelView(
            items: items,
            dragState: dragState,
            onClick: { [weak self] item in
                Task { @MainActor in
                    self?.close()
                    onClick(item)
                }
            },
            onPromote: { [weak self] item in
                Task { @MainActor in
                    self?.close()
                    onPromote(item)
                }
            },
            onExpand: { [weak self] in
                self?.close()
                onExpand()
            },
            onSettings: { [weak self] in
                self?.close()
                onSettings()
            }
        )
        let hosting = FirstMouseHostingView(rootView: content)
        hosting.setFrameSize(hosting.fittingSize)

        let screen = Self.screenFrame(
            containing: anchorFrame,
            screens: NSScreen.screens.map(\.visibleFrame)
        )
        var size = hosting.frame.size
        size.width = min(size.width, screen.width - 2 * Self.edgeInset)
        size.height = min(size.height, screen.height - 2 * Self.edgeInset)
        hosting.setFrameSize(size)

        let panel = ClickablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false

        let x = max(
            screen.minX + Self.edgeInset,
            min(anchorFrame.maxX - size.width, screen.maxX - size.width - Self.edgeInset)
        )
        let y = max(screen.minY + Self.edgeInset, anchorFrame.minY - size.height - 7)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                let isCommandClick = event.modifierFlags.contains(.command)
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    if isCommandClick { return }
                    if panel.frame.contains(NSEvent.mouseLocation) { return }
                    self.close()
                }
            }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    static func screenFrame(containing anchor: NSRect, screens: [NSRect]) -> NSRect {
        let midpoint = NSPoint(x: anchor.midX, y: anchor.midY)
        return screens.first { $0.minX <= midpoint.x && midpoint.x < $0.maxX }
            ?? screens.first
            ?? .zero
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        dragState?.cancelAllDragging()
        dragState = nil
        externalPreview.close()
        panel?.orderOut(nil)
        panel = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    func beginExternalDrag(image: NSImage?, atQuartzPoint point: CGPoint) {
        guard isVisible else { return }
        dragState?.beginExternalDragging()
        externalPreview.show(image: image, atQuartzPoint: point)
    }

    func updateExternalDrag(atQuartzPoint point: CGPoint, isInsidePanel: Bool) {
        guard isVisible else { return }
        dragState?.updateExternalDragging(isInsidePanel: isInsidePanel)
        externalPreview.move(toQuartzPoint: point)
    }

    func updateExternalDragImage(_ image: NSImage) {
        externalPreview.update(image: image)
    }

    func endExternalDrag() {
        dragState?.endExternalDragging()
        externalPreview.close()
    }
}

struct OverflowGridCell: Identifiable {
    let item: CapturedItem
    let span: Int
    var id: CGWindowID { item.id }
}

enum OverflowGridLayout {
    static let columnCount = 5

    /// A normal icon is roughly square. Text meters keep their original aspect
    /// ratio and receive two or three slots instead of being squeezed into one.
    static func columnSpan(for frame: CGRect) -> Int {
        let width = max(frame.width, frame.height)
        return min(3, max(1, Int(ceil(width / 50))))
    }

    static func rows(for items: [CapturedItem]) -> [[OverflowGridCell]] {
        var rows: [[OverflowGridCell]] = []
        var row: [OverflowGridCell] = []
        var occupied = 0

        for item in items {
            let span = columnSpan(for: item.window.frame)
            if occupied + span > columnCount, !row.isEmpty {
                rows.append(row)
                row = []
                occupied = 0
            }
            row.append(OverflowGridCell(item: item, span: span))
            occupied += span
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

private struct OverflowPanelView: View {
    let items: [CapturedItem]
    @ObservedObject var dragState: OverflowDragState
    let onClick: (CapturedItem) -> Void
    let onPromote: (CapturedItem) -> Void
    let onExpand: () -> Void
    let onSettings: () -> Void

    @State private var isPromoteTargeted = false
    @AppStorage(PanelAppearance.defaultsKey)
    private var storedAppearance = PanelAppearance.currentMaterial.rawValue
    private let cellSize: CGFloat = 46
    private let iconMaxHeight: CGFloat = 28
    private let cellSpacing: CGFloat = 8
    private let panelPadding: CGFloat = 16
    private let panelChromeHeight: CGFloat = 102

    private var contentWidth: CGFloat {
        cellSize * CGFloat(OverflowGridLayout.columnCount)
            + cellSpacing * CGFloat(OverflowGridLayout.columnCount - 1)
    }

    private var panelWidth: CGFloat {
        contentWidth + 2 * panelPadding
    }

    private var appearance: PanelAppearance {
        PanelAppearance.decode(storedAppearance)
    }

    private var rows: [[OverflowGridCell]] {
        OverflowGridLayout.rows(for: items)
    }

    private var panelHeight: CGFloat {
        let rowCount = CGFloat(max(1, rows.count))
        let gridHeight = rowCount * cellSize + (rowCount - 1) * cellSpacing
        return min(366, gridHeight + panelChromeHeight + 2 * panelPadding)
    }

    private var renderedAppearance: PanelAppearance {
        if appearance == .liquidGlass {
            if #available(macOS 26.0, *) {
                return .liquidGlass
            }
            return .currentMaterial
        }
        return appearance
    }

    private var usesDarkForeground: Bool {
        renderedAppearance == .dark || renderedAppearance == .liquidGlass
    }

    private var iconCellFill: Color {
        switch renderedAppearance {
        case .currentMaterial:
            Color.black.opacity(0.16)
        case .dark:
            Color.white.opacity(0.07)
        case .liquidGlass:
            Color.black.opacity(0.22)
        }
    }

    private var passiveDropZoneFill: Color {
        switch renderedAppearance {
        case .currentMaterial:
            Color.black.opacity(0.07)
        case .dark:
            Color.white.opacity(0.04)
        case .liquidGlass:
            Color.black.opacity(0.16)
        }
    }

    private var isDropZoneActive: Bool {
        dragState.isDraggingItem || isPromoteTargeted || dragState.isDraggingExternalItem
    }

    private var dropZoneBlueOpacity: Double {
        if dragState.isExternalItemInsidePanel || isPromoteTargeted { return 0.24 }
        return isDropZoneActive ? 0.12 : 0
    }

    var body: some View {
        styledPanel
            .preferredColorScheme(usesDarkForeground ? .dark : nil)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FoldBar")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("展开", action: onExpand)
                .buttonStyle(.borderless)
                .help("展开左侧真实菜单栏图标，并保持展开")
                Button("设置", action: onSettings)
                    .buttonStyle(.borderless)
                    .help("选择悬浮面板外观")
            }
            .padding(.bottom, 4)

            promoteDropZone

            if !items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: cellSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: cellSpacing) {
                                ForEach(row) { entry in
                                    iconCell(entry)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(panelPadding)
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private var styledPanel: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch appearance {
        case .currentMaterial:
            panelContent
                .background {
                    shape
                        .fill(.regularMaterial)
                        .overlay { shape.fill(Color.white.opacity(0.10)) }
                }
                .overlay { panelBorder(shape, opacity: 0.16) }
        case .dark:
            panelContent
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay { shape.fill(Color.black.opacity(0.34)) }
                }
                .overlay { panelBorder(shape, color: .black, opacity: 0.18) }
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                panelContent
                    .glassEffect(.clear.tint(Color.black.opacity(0.20)), in: shape)
                    .overlay { panelBorder(shape, opacity: 0.10) }
            } else {
                panelContent
                    .background {
                        shape
                            .fill(.regularMaterial)
                            .overlay { shape.fill(Color.white.opacity(0.10)) }
                    }
                    .overlay { panelBorder(shape, opacity: 0.16) }
            }
        }
    }

    private func panelBorder<S: InsettableShape>(
        _ shape: S,
        color: Color = .white,
        opacity: Double
    ) -> some View {
        shape
            .strokeBorder(color.opacity(opacity), lineWidth: 1)
            .allowsHitTesting(false)
    }

    private var promoteDropZone: some View {
        HStack(spacing: 7) {
            Image(systemName: dragState.isDraggingExternalItem ? "tray.and.arrow.down" : "menubar.arrow.up.rectangle")
            Text(dropZoneTitle)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            maxHeight: items.isEmpty ? .infinity : nil
        )
        .background { dropZoneBackground }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropZoneActive ? Color.blue.opacity(0.90) : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isDropZoneActive ? 1.5 : 1, dash: [4, 3])
                )
        }
        .dropDestination(for: String.self) { payloads, _ in
            guard let rawID = payloads.first,
                  let id = CGWindowID(rawID),
                  let item = items.first(where: { $0.id == id })
            else { return false }
            onPromote(item)
            return true
        } isTargeted: { isPromoteTargeted = $0 }
    }

    private var dropZoneTitle: String {
        guard dragState.isDraggingExternalItem else {
            return "拖到这里：在菜单栏中保持可见"
        }
        return dragState.isExternalItemInsidePanel
            ? "松手：收进 FoldBar"
            : "拖进面板：收进 FoldBar"
    }

    private func iconCell(_ entry: OverflowGridCell) -> some View {
        let item = entry.item
        let width = cellSize * CGFloat(entry.span) + cellSpacing * CGFloat(entry.span - 1)
        return Button {
            onClick(item)
        } label: {
            iconCellSurface(item, width: width)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.hoverText)
        .onDrag {
            dragState.beginDragging()
            return NSItemProvider(object: String(item.id) as NSString)
        } preview: {
            iconCellSurface(item, width: width, isDragging: true)
        }
    }

    private func iconCellSurface(
        _ item: CapturedItem,
        width: CGFloat,
        isDragging: Bool = false
    ) -> some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: 9)
            if renderedAppearance == .liquidGlass {
                shape
                    .fill(.thinMaterial)
                    .opacity(0.56)
                    .overlay { shape.fill(Color.black.opacity(0.12)) }
            } else {
                shape.fill(iconCellFill)
            }
            if isDragging {
                shape
                    .fill(Color.blue.opacity(0.22))
                    .overlay {
                        shape.strokeBorder(Color.blue.opacity(0.65), lineWidth: 1)
                    }
            }
            Image(nsImage: item.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: width - 12, maxHeight: iconMaxHeight)
        }
        .frame(width: width, height: cellSize)
    }

    @ViewBuilder
    private var dropZoneBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if renderedAppearance == .liquidGlass {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(
                        isDropZoneActive
                            ? Color.blue.opacity(dropZoneBlueOpacity)
                            : Color.black.opacity(0.10)
                    )
                }
        } else {
            shape.fill(
                isDropZoneActive ? Color.blue.opacity(dropZoneBlueOpacity) : passiveDropZoneFill
            )
        }
    }
}
