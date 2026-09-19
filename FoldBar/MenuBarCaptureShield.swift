import AppKit
import ScreenCaptureKit

/// Freezes the visible menu-bar pixels while FoldBar briefly exposes native
/// overflow artwork for an in-memory capture.
///
/// The shield is excluded from screen sharing, so ScreenCaptureKit continues
/// to see the real status items underneath it. Users keep seeing the original
/// collapsed bar until the native overflow control has been restored.
@MainActor
final class MenuBarCaptureShield {
    private var panel: NSPanel?

    private init(panel: NSPanel) {
        self.panel = panel
    }

    static func present(covering overflowFrame: CGRect) async -> MenuBarCaptureShield? {
        guard #available(macOS 15.2, *),
              let (screen, displayBounds) = display(containing: overflowFrame),
              let menuBarFrame = menuBarFrame(
                  on: screen,
                  displayBounds: displayBounds,
                  including: overflowFrame
              ),
              let snapshot = try? await SCScreenshotManager.captureImage(
                  in: menuBarFrame.quartz
              ) else { return nil }

        let image = NSImage(cgImage: snapshot, size: menuBarFrame.appKit.size)
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: menuBarFrame.appKit.size))
        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently

        let panel = NSPanel(
            contentRect: menuBarFrame.appKit,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = imageView
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        panel.isOpaque = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        panel.isReleasedWhenClosed = false
        // The user sees the shield, but both screenshots and FoldBar's own
        // region capture see the live menu bar beneath it.
        panel.sharingType = .none
        panel.orderFrontRegardless()

        // Give WindowServer one display interval to present the frozen strip
        // before the native overflow control is clicked behind it.
        guard (try? await Task.sleep(for: .milliseconds(34))) != nil,
              !Task.isCancelled else {
            panel.orderOut(nil)
            return nil
        }
        return MenuBarCaptureShield(panel: panel)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private static func display(
        containing frame: CGRect
    ) -> (screen: NSScreen, bounds: CGRect)? {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                continue
            }
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            if bounds.contains(midpoint) {
                return (screen, bounds)
            }
        }
        return nil
    }

    private static func menuBarFrame(
        on screen: NSScreen,
        displayBounds: CGRect,
        including overflowFrame: CGRect
    ) -> (quartz: CGRect, appKit: CGRect)? {
        guard displayBounds.width > 0,
              displayBounds.height > 0,
              overflowFrame.minY >= displayBounds.minY - 2,
              overflowFrame.maxY <= displayBounds.minY + 42 else { return nil }

        let visibleInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let requiredHeight = overflowFrame.maxY - displayBounds.minY + 2
        let height = min(42, max(1, max(visibleInset, requiredHeight)))
        return (
            quartz: CGRect(
                x: displayBounds.minX,
                y: displayBounds.minY,
                width: displayBounds.width,
                height: height
            ),
            appKit: CGRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - height,
                width: screen.frame.width,
                height: height
            )
        )
    }
}
