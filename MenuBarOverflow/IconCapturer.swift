import AppKit
import ScreenCaptureKit

@MainActor
enum IconCapturer {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    private static func scale(for frame: CGRect) -> CGFloat {
        let midX = frame.midX
        let screen = NSScreen.screens.first { $0.frame.minX <= midX && midX < $0.frame.maxX }
        return (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
    }

    static func capture(_ windows: [MenuBarItemWindow]) async -> [CapturedItem] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [] }
        var result: [CapturedItem] = []

        for window in windows {
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }

            let configuration = SCStreamConfiguration()
            let scale = scale(for: window.frame)
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)

            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) {
                result.append(CapturedItem(
                    window: window,
                    image: NSImage(cgImage: image, size: normalizedSize(for: window.frame))
                ))
            }
        }
        return result
    }

    /// Keep text-based meters useful without letting one wide item destroy the grid.
    private static func normalizedSize(for frame: CGRect) -> NSSize {
        let height = min(max(frame.height, 18), 28)
        let width = min(max(frame.width, 18), 36)
        return NSSize(width: width, height: height)
    }
}
