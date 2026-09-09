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
                    // Preserve the real logical size. Replacing it with a
                    // fixed width changes the image aspect ratio and visibly
                    // squeezes text meters such as temperatures and battery.
                    image: NSImage(cgImage: image, size: window.frame.size)
                ))
            }
        }
        return result
    }
}
