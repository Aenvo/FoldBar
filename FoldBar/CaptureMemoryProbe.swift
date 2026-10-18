import AppKit
import Darwin
import ScreenCaptureKit

/// Explicit, bounded developer diagnostics. Normal launches never enter this
/// mode. It creates no status items, assertions or synthetic input, and writes
/// no captured pixels or preferences. Run only from the installed signed app.
@MainActor
enum CaptureMemoryProbe {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--capture-memory-probe")
            || ProcessInfo.processInfo.arguments.contains("--inventory-performance-probe")
    }

    static func run() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--inventory-performance-probe") {
            await compareInventoryRefreshes()
            return
        }
        guard let index = arguments.firstIndex(of: "--capture-memory-probe"),
              arguments.indices.contains(index + 1),
              ["legacy", "current"].contains(arguments[index + 1]),
              #available(macOS 26.0, *),
              IconCapturer.hasPermission(), EventForwarder.isTrusted() else {
            print("capture-probe unavailable: mode, OS or existing permissions")
            return
        }
        let mode = arguments[index + 1]
        let requestedID = arguments.first(where: {
            $0.hasPrefix("--capture-probe-item=")
        }).flatMap { CGWindowID($0.dropFirst("--capture-probe-item=".count)) }
        // Let MenuBarAgent settle after releasing the previous app connection.
        guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
        await MenuBarItemScanner.refreshStatusWindows(force: true)
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        let segments = StatusBarController.activeVisibleMenuBarSegments()
        let overflow = MenuBarItemScanner.systemOverflowFrame()
        let candidates = MenuBarItemScanner.statusWindows().filter { window in
            window.accessibilityIdentity != nil
                && window.bundleIdentifier != Bundle.main.bundleIdentifier
                && (requestedID == nil || requestedID == window.id)
                && StatusBarController.isInStrip(window.frame, displays: displays)
                && StatusBarController.isSafePrivateCaptureFrame(
                    window.frame, visibleSegments: segments, overflowFrame: overflow
                )
        }
        guard let target = candidates.first else {
            print("capture-probe unavailable: no verified visible target")
            return
        }
        var successful = 0
        var dimensions: Set<String> = []
        for _ in 0..<100 {
            guard !Task.isCancelled,
                  let live = MenuBarItemScanner.refreshStatusWindow(target),
                  StatusBarController.isInStrip(live.frame, displays: displays),
                  StatusBarController.isSafePrivateCaptureFrame(
                      live.frame,
                      visibleSegments: StatusBarController.activeVisibleMenuBarSegments(),
                      overflowFrame: MenuBarItemScanner.refreshSystemOverflowFrame()
                  ) else { break }
            let image = await IconCapturer.captureRegionImage(
                in: live.frame,
                useLegacyAPI: mode == "legacy"
            )
            if let image {
                successful += 1
                dimensions.insert("\(image.width)x\(image.height)")
            }
            guard (try? await Task.sleep(for: .milliseconds(30))) != nil else { break }
        }
        print("capture-probe finished mode=\(mode) successful=\(successful)/100 pixels=\(dimensions.sorted())")
        fflush(nil)
    }

    /// Compares full and scoped discovery in one process without screenshots,
    /// visibility assertions, input forwarding, or preference writes. Keeping
    /// the same process and inventory avoids image-cache differences in a
    /// normal-launch CPU comparison. It uses existing AX permission only.
    private static func compareInventoryRefreshes() async {
        guard EventForwarder.isTrusted() else {
            print("inventory-probe unavailable: existing Accessibility permission required")
            fflush(nil)
            return
        }
        await MenuBarAccessibility.refresh(force: true)
        // Let ordinary processes leave their 30-second discovery grace period.
        guard (try? await Task.sleep(for: .seconds(31))) != nil else { return }
        for pair in 0..<10 {
            var fullIdentities: Set<MenuBarAccessibilityIdentity> = []
            for force in [true, false] {
                guard !Task.isCancelled,
                      (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                let started = ContinuousClock.now
                let initialCPU = processCPUSeconds()
                let snapshots = await MenuBarAccessibility.refresh(force: force)
                let cpu = processCPUSeconds() - initialCPU
                let elapsed = started.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let identities = Set(snapshots.map(\.identity))
                if force { fullIdentities = identities }
                guard let stats = MenuBarAccessibility.lastRefreshStatistics else { return }
                print("inventory-probe pair=\(pair) full=\(force) scanned=\(stats.scannedApplications) running=\(stats.runningApplications) items=\(identities.count) sameItems=\(identities == fullIdentities) seconds=\(seconds) cpuSeconds=\(cpu)")
                fflush(nil)
            }
        }
        print("inventory-probe finished pairs=10")
        fflush(nil)
    }

    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
