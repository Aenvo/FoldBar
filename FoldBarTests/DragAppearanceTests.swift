import AppKit
import Testing

@testable import FoldBar

@Suite("Drag appearance parity")
@MainActor
struct DragAppearanceTests {
    @Test("Square drag cards use the panel cell size and native artwork scale")
    func squarePreviewMatchesPanelCell() throws {
        let image = NSImage(size: CGSize(width: 16, height: 16))
        let sourceFrame = CGRect(x: 300, y: 5, width: 24, height: 24)
        let span = OverflowGridLayout.columnSpan(for: sourceFrame)
        let width = OverflowIconCellLayout.width(forSpan: span)
        let preview = ExternalDragPreviewPanel()
        defer { preview.close() }

        preview.show(
            image: image,
            sourceFrame: sourceFrame,
            atQuartzPoint: CGPoint(x: 300, y: 150)
        )

        let frame = try #require(preview.frame)
        #expect(frame.size == CGSize(width: width, height: OverflowIconCellLayout.cellSize))
        #expect(OverflowIconCellLayout.iconSize(for: image.size, cellWidth: width) == image.size)
    }

    @Test("Cropped wide artwork keeps its original panel grid span while dragging")
    func widePreviewUsesOriginalFrame() throws {
        let sourceFrame = CGRect(x: 300, y: 5, width: 89, height: 24)
        let preview = ExternalDragPreviewPanel()
        defer { preview.close() }

        preview.show(
            image: NSImage(size: CGSize(width: 40, height: 16)),
            sourceFrame: sourceFrame,
            atQuartzPoint: CGPoint(x: 300, y: 150)
        )

        let frame = try #require(preview.frame)
        #expect(frame.width == OverflowIconCellLayout.width(forSpan: 2))
        #expect(frame.height == OverflowIconCellLayout.cellSize)
    }

    @Test("A late screenshot retains the original wide cell dimensions")
    func lateScreenshotKeepsSourceSpan() throws {
        let sourceFrame = CGRect(x: 300, y: 5, width: 151, height: 24)
        let preview = ExternalDragPreviewPanel()
        defer { preview.close() }

        preview.show(
            image: nil,
            sourceFrame: sourceFrame,
            atQuartzPoint: CGPoint(x: 300, y: 150)
        )
        #expect(preview.frame == nil)
        preview.move(toQuartzPoint: CGPoint(x: 400, y: 250))
        preview.update(image: NSImage(size: CGSize(width: 30, height: 16)))

        let frame = try #require(preview.frame)
        #expect(frame.width == OverflowIconCellLayout.width(forSpan: 3))
        #expect(frame.height == OverflowIconCellLayout.cellSize)
    }

    @Test("Wide drag artwork uses the same proportional fitting as panel artwork")
    func wideArtworkKeepsPanelScale() {
        let sourceSize = CGSize(width: 180, height: 24)
        let width = OverflowIconCellLayout.width(forSpan: 3)
        let size = OverflowIconCellLayout.iconSize(for: sourceSize, cellWidth: width)

        #expect(abs(size.width / size.height - sourceSize.width / sourceSize.height) < 0.0001)
        #expect(size.height <= OverflowIconLayout.menuBarHeight)
        #expect(size.width == width - 6)
    }
}
