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
        async let accessibilityMetadata = MenuBarItemMetadataResolver.metadata(for: windows)
        async let images = captureImages(windows)
        let (resolvedMetadata, resolvedImages) = await (accessibilityMetadata, images)

        return windows.compactMap { window in
            guard let image = resolvedImages[window.id] else { return nil }
            return CapturedItem(
                window: window,
                image: image,
                hoverText: resolvedMetadata[window.id]?.label,
                ownerProcessIdentifier: resolvedMetadata[window.id]?.processIdentifier
            )
        }
    }

    /// Captures only window images, without waiting for Accessibility metadata.
    /// The menu-bar drag monitor uses this for a warm preview cache so the first
    /// drag frame can show the real icon instead of a generic placeholder.
    static func captureImages(
        _ windows: [MenuBarItemWindow]
    ) async -> [CGWindowID: NSImage] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }
        var result: [CGWindowID: NSImage] = [:]

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
                // Preserve the real logical size. Replacing it with a fixed
                // width changes the image aspect ratio and visibly squeezes
                // text meters such as temperatures and battery.
                result[window.id] = NSImage(cgImage: image, size: window.frame.size)
            }
        }
        return result
    }
}
