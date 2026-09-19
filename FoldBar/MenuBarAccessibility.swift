import AppKit
@preconcurrency import ApplicationServices

/// Public Accessibility-backed status-item discovery for macOS 27.
///
/// macOS 27 no longer exposes third-party menu extras as individual status-layer
/// windows through Core Graphics or ScreenCaptureKit. Accessibility still
/// publishes each owning application's AXMenuExtra, including its live frame.
/// Keep AXUIElement values local to each scan and pass only Sendable identities
/// through the rest of the app.
enum MenuBarAccessibility {
    struct Snapshot: Equatable, Sendable {
        let identity: MenuBarAccessibilityIdentity
        let id: CGWindowID
        let frame: CGRect
        let ownerName: String
        let label: String
    }

    private struct RunningApplicationIdentity: Sendable {
        let processIdentifier: pid_t
        let bundleIdentifier: String
        let ownerName: String
    }

    private struct ScanResult: Sendable {
        let snapshots: [Snapshot]
        let systemOverflowFrame: CGRect?
    }

    @MainActor private static var cachedSnapshots: [Snapshot] = []
    @MainActor private static var cachedSystemOverflowFrame: CGRect?
    @MainActor private static var refreshTask: Task<ScanResult, Never>?
    @MainActor private static var lastRefresh = ContinuousClock.Instant.now
        .advanced(by: .seconds(-10))
    private static let minimumRefreshInterval = Duration.milliseconds(500)

    @MainActor
    static func snapshots() -> [Snapshot] {
        cachedSnapshots
    }

    /// The public Accessibility frame of macOS 27's native `«` overflow
    /// control. MenuBarAgent exposes it as the only direct AXButton child of
    /// its full-width menu-bar window; app-owned menu extras are nested below
    /// separate host containers.
    @MainActor
    static func systemOverflowFrame() -> CGRect? {
        cachedSystemOverflowFrame
    }

    @MainActor
    @discardableResult
    static func refresh(force: Bool = false) async -> [Snapshot] {
        guard AXIsProcessTrusted() else {
            refreshTask?.cancel()
            refreshTask = nil
            cachedSnapshots = []
            cachedSystemOverflowFrame = nil
            return []
        }
        if !force,
           ContinuousClock.Instant.now - lastRefresh < minimumRefreshInterval {
            return cachedSnapshots
        }
        let task: Task<ScanResult, Never>
        if let inFlight = refreshTask {
            task = inFlight
        } else {
            let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
            let applications = NSWorkspace.shared.runningApplications
                .filter {
                    !$0.isTerminated
                        && $0.processIdentifier != ownProcessIdentifier
                }
                .map {
                    RunningApplicationIdentity(
                        processIdentifier: $0.processIdentifier,
                        bundleIdentifier: $0.bundleIdentifier ?? "",
                        ownerName: $0.localizedName ?? ""
                    )
                }
            task = Task.detached(priority: .utility) {
                scan(applications: applications)
            }
            refreshTask = task
        }

        let result = await task.value
        if AXIsProcessTrusted() {
            cachedSnapshots = result.snapshots
            cachedSystemOverflowFrame = result.systemOverflowFrame
            lastRefresh = .now
        } else {
            cachedSnapshots = []
            cachedSystemOverflowFrame = nil
        }
        refreshTask = nil
        return cachedSnapshots
    }

    private nonisolated static func scan(
        applications: [RunningApplicationIdentity]
    ) -> ScanResult {
        var snapshots: [Snapshot] = []
        var usedIDs: Set<CGWindowID> = []
        var systemOverflowFrame: CGRect?

        for application in applications {
            guard !Task.isCancelled else { break }
            let appElement = AXUIElementCreateApplication(
                application.processIdentifier
            )
            if application.bundleIdentifier == "com.apple.MenuBarAgent" {
                systemOverflowFrame = nativeOverflowButtonFrame(
                    in: appElement
                )
            }
            for (ordinal, element) in menuExtras(in: appElement).enumerated() {
                guard let frame = frame(of: element),
                      frame.width > 0,
                      frame.height > 0 else { continue }
                let identity = MenuBarAccessibilityIdentity(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    ordinal: ordinal
                )
                var id = syntheticID(for: identity)
                while usedIDs.contains(id) {
                    id = 0x8000_0000 | ((id &+ 1) & 0x7fff_ffff)
                }
                usedIDs.insert(id)
                snapshots.append(Snapshot(
                    identity: identity,
                    id: id,
                    frame: frame,
                    ownerName: application.ownerName,
                    label: preferredLabel(
                        help: stringAttribute(element, kAXHelpAttribute),
                        description: stringAttribute(element, kAXDescriptionAttribute),
                        title: stringAttribute(element, kAXTitleAttribute),
                        appName: application.ownerName
                    )
                ))
            }
        }
        return ScanResult(
            snapshots: snapshots,
            systemOverflowFrame: systemOverflowFrame
        )
    }

    @MainActor
    static func performPress(
        on identity: MenuBarAccessibilityIdentity,
        expectedLabel: String,
        expectedFrame: CGRect
    ) -> Bool {
        guard let element = resolvedElement(
            for: identity,
            expectedLabel: expectedLabel,
            expectedFrame: expectedFrame
        ) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @MainActor
    static func matchesCurrentItem(
        _ identity: MenuBarAccessibilityIdentity,
        expectedLabel: String,
        expectedFrame: CGRect
    ) -> Bool {
        resolvedElement(
            for: identity,
            expectedLabel: expectedLabel,
            expectedFrame: expectedFrame
        ) != nil
    }

    @MainActor
    private static func resolvedElement(
        for identity: MenuBarAccessibilityIdentity,
        expectedLabel: String,
        expectedFrame: CGRect
    ) -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let application = NSRunningApplication(
                  processIdentifier: identity.processIdentifier
              ),
              !application.isTerminated,
              (application.bundleIdentifier ?? "") == identity.bundleIdentifier else {
            return nil
        }
        let elements = menuExtras(
            in: AXUIElementCreateApplication(identity.processIdentifier)
        )
        guard elements.indices.contains(identity.ordinal) else { return nil }
        let element = elements[identity.ordinal]
        guard let liveFrame = frame(of: element),
              abs(liveFrame.midX - expectedFrame.midX) <= 3,
              abs(liveFrame.midY - expectedFrame.midY) <= 3 else { return nil }

        // Ordinal is sufficient for the common one-item-per-app case. For an
        // app with multiple extras, require the live semantic label to agree so
        // a child-order change cannot target the wrong status item.
        if elements.count > 1 {
            let liveLabel = preferredLabel(
                help: stringAttribute(element, kAXHelpAttribute),
                description: stringAttribute(element, kAXDescriptionAttribute),
                title: stringAttribute(element, kAXTitleAttribute),
                appName: application.localizedName ?? ""
            )
            guard liveLabel == expectedLabel else { return nil }
        }
        return element
    }

    nonisolated static func syntheticID(
        for identity: MenuBarAccessibilityIdentity
    ) -> CGWindowID {
        // FNV-1a gives a deterministic per-session identifier without relying on
        // Swift's randomized Hasher. The high bit separates AX-backed IDs from
        // ordinary WindowServer IDs on the macOS 27 backend.
        var hash: UInt32 = 2_166_136_261
        let value = "\(identity.bundleIdentifier)|\(identity.processIdentifier)|\(identity.ordinal)"
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return 0x8000_0000 | (hash & 0x7fff_ffff)
    }

    private nonisolated static func menuExtras(
        in application: AXUIElement
    ) -> [AXUIElement] {
        children(of: application)
            .filter { stringAttribute($0, kAXRoleAttribute) == "AXMenuBar" }
            .flatMap(children)
            .filter { stringAttribute($0, kAXSubroleAttribute) == "AXMenuExtra" }
    }

    private nonisolated static func nativeOverflowButtonFrame(
        in application: AXUIElement
    ) -> CGRect? {
        let menuBarWindows = children(of: application).filter {
            stringAttribute($0, kAXRoleAttribute) == "AXWindow"
                && frame(of: $0).map {
                    $0.minY <= 1 && $0.height >= 30 && $0.height <= 40
                } == true
        }
        return menuBarWindows
            .flatMap(children)
            .filter {
                stringAttribute($0, kAXRoleAttribute) == "AXButton"
                    && stringAttribute($0, kAXSubroleAttribute).isEmpty
            }
            .compactMap(frame)
            .first {
                $0.minY <= 2
                    && $0.width >= 8
                    && $0.width <= 30
                    && $0.height >= 28
                    && $0.height <= 36
            }
    }

    private nonisolated static func preferredLabel(
        help: String,
        description: String,
        title: String,
        appName: String
    ) -> String {
        let genericLabels = Set([
            "Control Center",
            "控制中心",
            "Menu bar item",
            "菜单栏图标",
            "Status menu",
            "状态菜单"
        ])
        return [help, description, title, appName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !genericLabels.contains($0) }
            ?? "菜单栏图标"
    }

    private nonisolated static func attribute(
        _ element: AXUIElement,
        _ name: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else { return nil }
        return value
    }

    private nonisolated static func stringAttribute(
        _ element: AXUIElement,
        _ name: String
    ) -> String {
        attribute(element, name) as? String ?? ""
    }

    private nonisolated static func children(
        of element: AXUIElement
    ) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}
