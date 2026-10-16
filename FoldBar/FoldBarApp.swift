import SwiftUI

@main
struct FoldBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var captureProbeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The tests are app-hosted. They must never create real status items or
        // modify the user's menu bar while the test runner starts the host app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if CaptureMemoryProbe.requested {
            captureProbeTask = Task { await CaptureMemoryProbe.run() }
            return
        }
        controller = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureProbeTask?.cancel()
        // Expand the legacy separator or invalidate the macOS 27 visibility
        // assertion so an ordinary quit always gives the real menu bar back.
        controller?.expandForQuit()
    }
}
