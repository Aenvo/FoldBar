import SwiftUI

private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension PanelAppearance {
    var renderedForCurrentOS: PanelAppearance {
        guard self == .liquidGlass else { return self }
        if #available(macOS 26.0, *) {
            return .liquidGlass
        }
        return .currentMaterial
    }
}

/// The panel cell and both drag previews render the same surface. Dragging
/// changes only its position, preserving the artwork's scale and cell style.
private struct OverflowIconCellSurface: View {
    let image: NSImage
    let width: CGFloat
    let appearance: PanelAppearance

    private var renderedAppearance: PanelAppearance {
        appearance.renderedForCurrentOS
    }

    private var cellFill: Color {
        switch renderedAppearance {
        case .currentMaterial:
            Color.black.opacity(0.16)
        case .dark:
            Color.white.opacity(0.07)
        case .liquidGlass:
            Color.black.opacity(0.22)
        }
    }

    var body: some View {
        let iconSize = OverflowIconCellLayout.iconSize(
            for: image.size,
            cellWidth: width
        )
        return ZStack {
            let shape = RoundedRectangle(cornerRadius: OverflowIconCellLayout.cornerRadius)
            if renderedAppearance == .liquidGlass {
                shape
                    .fill(.thinMaterial)
                    .opacity(0.56)
                    .overlay { shape.fill(Color.black.opacity(0.12)) }
            } else {
                shape.fill(cellFill)
            }
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize.width, height: iconSize.height)
                .foregroundStyle(.primary)
        }
        .frame(width: width, height: OverflowIconCellLayout.cellSize)
        .preferredColorScheme(
            renderedAppearance == .dark || renderedAppearance == .liquidGlass
                ? .dark
                : nil
        )
    }
}

@MainActor
final class ExternalDragPreviewPanel {
    private var panel: NSPanel?
    private var lastPoint = CGPoint.zero
    private var isDragging = false
    private var sourceFrame: CGRect?
    private var appearance = PanelAppearance.currentMaterial

    var frame: CGRect? { panel?.frame }
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        image: NSImage?,
        sourceFrame: CGRect? = nil,
        appearance: PanelAppearance? = nil,
        atQuartzPoint point: CGPoint
    ) {
        close()
        isDragging = true
        lastPoint = point
        self.sourceFrame = sourceFrame
        self.appearance = appearance ?? PanelAppearance.decode(
            UserDefaults.standard.string(forKey: PanelAppearance.defaultsKey)
        )
        guard let image else { return }
        render(image: image)
    }

    private func render(image: NSImage) {
        panel?.orderOut(nil)
        let frame = sourceFrame ?? CGRect(origin: .zero, size: image.size)
        let span = OverflowGridLayout.columnSpan(for: frame)
        let size = NSSize(
            width: OverflowIconCellLayout.width(forSpan: span),
            height: OverflowIconCellLayout.cellSize
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let content = OverflowIconCellSurface(
            image: image,
            width: size.width,
            appearance: appearance
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // This translucent card already matches the grid cell. A separate
        // WindowServer shadow makes its rounded edge look like a black border.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        move(toQuartzPoint: lastPoint)
        panel.orderFrontRegardless()
    }

    func update(image: NSImage) {
        guard isDragging else { return }
        render(image: image)
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
        isDragging = false
        panel?.orderOut(nil)
        panel = nil
        sourceFrame = nil
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
        onSettings: @escaping @MainActor () -> Void,
        shouldDeferDismissalForExternalMouseDown: @escaping @MainActor (NSEvent) -> Bool,
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
            onSettings: { [weak self] in
                self?.close()
                onSettings()
            }
        )
        let hosting = FirstMouseHostingView(rootView: content)
        hosting.setFrameSize(hosting.fittingSize)

        let screen = Self.screenFrame(
            containing: anchorFrame,
            screens: NSScreen.screens.map {
                (frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
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
                    let isImportMouseDown = shouldDeferDismissalForExternalMouseDown(
                        event
                    )
                    // Let the status item's mouse-up reach `toggleClicked()`.
                    // Closing here on mouse-down would make that action see a
                    // hidden panel and immediately reopen it.
                    guard OverflowPanelDismissal.shouldClose(
                        for: NSEvent.mouseLocation,
                        panelFrame: panel.frame,
                        anchorFrame: anchorFrame,
                        isCommandClick: isCommandClick,
                        isImportMouseDown: isImportMouseDown
                    ) else { return }
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

    static func screenFrame(
        containing anchor: NSRect,
        screens: [(frame: NSRect, visibleFrame: NSRect)]
    ) -> NSRect {
        let midpoint = NSPoint(x: anchor.midX, y: anchor.midY)
        // A status item's anchor is in the menu bar, outside visibleFrame.
        // Resolve its display using the full bounds before applying the usable
        // area; matching only X chooses the wrong display in stacked layouts.
        if let screen = screens.first(where: { $0.frame.contains(midpoint) }) {
            return screen.visibleFrame
        }

        // Display reconfiguration can briefly leave the old anchor off-screen.
        // Keep the panel on the nearest display in both coordinate axes.
        func distanceSquared(to frame: NSRect) -> CGFloat {
            let dx = max(frame.minX - midpoint.x, 0, midpoint.x - frame.maxX)
            let dy = max(frame.minY - midpoint.y, 0, midpoint.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return screens.min {
            distanceSquared(to: $0.frame) < distanceSquared(to: $1.frame)
        }?.visibleFrame ?? .zero
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

    func beginExternalDrag(
        image: NSImage?,
        sourceFrame: CGRect? = nil,
        atQuartzPoint point: CGPoint
    ) {
        guard isVisible else { return }
        dragState?.beginExternalDragging()
        // Preserve the active point even if a cold screenshot arrives later.
        // Render only real artwork in the shared preview surface.
        externalPreview.show(
            image: image,
            sourceFrame: sourceFrame,
            appearance: PanelAppearance.decode(
                UserDefaults.standard.string(forKey: PanelAppearance.defaultsKey)
            ),
            atQuartzPoint: point
        )
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

enum OverflowPanelDismissal {
    static func shouldClose(
        for location: CGPoint,
        panelFrame: CGRect,
        anchorFrame: CGRect,
        isCommandClick: Bool,
        isImportMouseDown: Bool = false
    ) -> Bool {
        !isCommandClick
            && !isImportMouseDown
            && !panelFrame.contains(location)
            && !anchorFrame.contains(location)
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

enum OverflowIconLayout {
    /// AX menu extras on current macOS releases use a 24-point content frame.
    /// Preserve that native logical size in the panel instead of enlarging
    /// every capture to fill its cell. Wide text meters may still shrink when
    /// their grid span is narrower than the original menu-bar item.
    static let menuBarHeight: CGFloat = 24

    static func displaySize(
        sourceSize: CGSize,
        availableWidth: CGFloat,
        maximumHeight: CGFloat = menuBarHeight
    ) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              availableWidth > 0,
              maximumHeight > 0 else { return .zero }

        let scale = min(
            1,
            availableWidth / sourceSize.width,
            maximumHeight / sourceSize.height
        )
        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }
}

/// Shared dimensions for panel cells and drag previews. The span is resolved
/// from the status item's original frame, rather than the cropped artwork.
enum OverflowIconCellLayout {
    static let cellSize: CGFloat = 46
    static let cellSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 9

    static func width(forSpan span: Int) -> CGFloat {
        let span = min(3, max(1, span))
        return cellSize * CGFloat(span) + cellSpacing * CGFloat(span - 1)
    }

    static func iconSize(for imageSize: CGSize, cellWidth: CGFloat) -> CGSize {
        OverflowIconLayout.displaySize(
            sourceSize: imageSize,
            availableWidth: cellWidth - 6
        )
    }
}

private struct OverflowPanelView: View {
    @AppStorage(AppLanguage.defaultsKey)
    private var storedLanguage = AppLanguage.system.rawValue
    let items: [CapturedItem]
    @ObservedObject var dragState: OverflowDragState
    let onClick: (CapturedItem) -> Void
    let onPromote: (CapturedItem) -> Void
    let onSettings: () -> Void

    @State private var isPromoteTargeted = false
    @AppStorage(PanelAppearance.defaultsKey)
    private var storedAppearance = PanelAppearance.currentMaterial.rawValue
    private let cellSize = OverflowIconCellLayout.cellSize
    private let cellSpacing = OverflowIconCellLayout.cellSpacing
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
        appearance.renderedForCurrentOS
    }

    private var usesDarkForeground: Bool {
        renderedAppearance == .dark || renderedAppearance == .liquidGlass
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
            .environment(\.locale, AppLanguage.decode(storedLanguage).locale)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FoldBar")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(L10n.text(.settings), systemImage: "gearshape", action: onSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(L10n.text(.settingsHelp))
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
            return L10n.text(.keepVisibleDrop)
        }
        return dragState.isExternalItemInsidePanel
            ? L10n.text(.collectRelease)
            : L10n.text(.collectDrop)
    }

    private func iconCell(_ entry: OverflowGridCell) -> some View {
        let item = entry.item
        let width = OverflowIconCellLayout.width(forSpan: entry.span)
        return Button {
            onClick(item)
        } label: {
            iconCellSurface(item, width: width)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.hoverText)
        .accessibilityLabel(item.hoverText)
        .onDrag {
            dragState.beginDragging()
            return NSItemProvider(object: String(item.id) as NSString)
        } preview: {
            iconCellSurface(item, width: width)
        }
    }

    private func iconCellSurface(
        _ item: CapturedItem,
        width: CGFloat
    ) -> some View {
        OverflowIconCellSurface(
            image: item.image,
            width: width,
            appearance: appearance
        )
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
