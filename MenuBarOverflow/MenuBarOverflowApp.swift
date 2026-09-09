import SwiftUI

@main
struct MenuBarOverflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The tests are app-hosted. They must never create real status items or
        // modify the user's menu bar while the test runner starts the host app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        controller = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A collapsed separator parks other apps' status items off-screen.
        // Always give the real menu bar back, including on an ordinary quit.
        controller?.expandForQuit()
    }
}
