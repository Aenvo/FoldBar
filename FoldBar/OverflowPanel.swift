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
        onManage: @escaping @MainActor () -> Void
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
            onManage: { [weak self] in
                self?.close()
                onManage()
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
    let onManage: () -> Void

    @State private var isPromoteTargeted = false
    private let baseCellWidth: CGFloat = 42
    private let cellSpacing: CGFloat = 8

    private var rows: [[OverflowGridCell]] {
        OverflowGridLayout.rows(for: items)
    }

    private var panelHeight: CGFloat {
        min(370, CGFloat(max(1, rows.count) * 50 + 126))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("菜单栏溢出")
                        .font(.headline)
                    Text("FoldBar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("展开", action: onExpand)
                .buttonStyle(.borderless)
                .help("展开左侧真实菜单栏图标，并保持展开")
                Button("整理", action: onManage)
                    .buttonStyle(.borderless)
                    .help("展开真实菜单栏，然后按住 ⌘ 拖动图标")
            }

            promoteDropZone

            if items.isEmpty {
                ContentUnavailableView(
                    "没有收纳的图标",
                    systemImage: "square.grid.3x3",
                    description: Text("点“整理”，按住 ⌘ 将图标拖到分隔符左侧。")
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

            Text("点击打开图标；拖到上方可放回菜单栏")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .frame(width: 286, height: panelHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.16))
        }
    }

    private var promoteDropZone: some View {
        HStack(spacing: 7) {
            Image(systemName: "menubar.arrow.up.rectangle")
            Text(isPromoteTargeted ? "松开放回菜单栏" : "拖到这里：在菜单栏中保持可见")
                .font(.caption)
        }
        .foregroundStyle(isPromoteTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            isPromoteTargeted ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 8)
        )
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
        let width = baseCellWidth * CGFloat(entry.span) + cellSpacing * CGFloat(entry.span - 1)
        return Button {
            onClick(item)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.quaternary.opacity(0.45))
                Image(nsImage: item.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: width - 12, maxHeight: 24)
            }
            .frame(width: width, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.window.displayName)
        .draggable(String(item.id)) {
            Image(nsImage: item.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: width - 12, maxHeight: 24)
                .padding(7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}
