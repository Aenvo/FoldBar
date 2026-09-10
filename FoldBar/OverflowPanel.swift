import SwiftUI

private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverflowPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private static let edgeInset: CGFloat = 6

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        items: [CapturedItem],
        below anchorFrame: NSRect,
        onClick: @escaping @MainActor (CapturedItem) -> Void,
        onPromote: @escaping @MainActor (CapturedItem) -> Void,
        onExpand: @escaping @MainActor () -> Void,
        onSettings: @escaping @MainActor () -> Void
    ) {
        close()

        let content = OverflowPanelView(
            items: items,
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
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
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
        panel?.orderOut(nil)
        panel = nil
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
    let onClick: (CapturedItem) -> Void
    let onPromote: (CapturedItem) -> Void
    let onExpand: () -> Void
    let onSettings: () -> Void

    @State private var isPromoteTargeted = false
    @AppStorage(PanelAppearance.defaultsKey)
    private var storedAppearance = PanelAppearance.currentMaterial.rawValue
    private let cellSize: CGFloat = 46
    private let iconMaxHeight: CGFloat = 26
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

            if items.isEmpty {
                ContentUnavailableView(
                    "没有收纳的图标",
                    systemImage: "square.grid.3x3",
                    description: Text("点“展开”，按住 ⌘ 将图标拖到分隔符左侧。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                .background(.regularMaterial, in: shape)
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
                    .background(.regularMaterial, in: shape)
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
            Image(systemName: "menubar.arrow.up.rectangle")
            Text(isPromoteTargeted ? "松开放回菜单栏" : "拖到这里：在菜单栏中保持可见")
                .font(.caption)
        }
        .foregroundStyle(isPromoteTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background { dropZoneBackground }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isPromoteTargeted ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
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
        .help(item.window.displayName)
        .draggable(String(item.id)) {
            iconCellSurface(item, width: width)
        }
    }

    private func iconCellSurface(_ item: CapturedItem, width: CGFloat) -> some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: 9)
            if renderedAppearance == .liquidGlass {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.52)
                    .overlay { shape.fill(Color.black.opacity(0.12)) }
            } else {
                shape.fill(iconCellFill)
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
                        isPromoteTargeted
                            ? Color.accentColor.opacity(0.16)
                            : Color.black.opacity(0.10)
                    )
                }
        } else {
            shape.fill(
                isPromoteTargeted ? Color.accentColor.opacity(0.16) : passiveDropZoneFill
            )
        }
    }
}
