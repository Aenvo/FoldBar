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
    struct RefreshStatistics: Sendable {
        let scannedApplications: Int
        let runningApplications: Int
        let isFullSweep: Bool
    }

    @MainActor private(set) static var lastRefreshStatistics: RefreshStatistics?
    struct Snapshot: Equatable, Sendable {
        let identity: MenuBarAccessibilityIdentity
        let id: CGWindowID
        let frame: CGRect
        let ownerName: String
        let label: String
    }

    private typealias Application = MenuBarInventoryRefreshPolicy.Application

    private struct RunningApplicationIdentity: Sendable {
        let generation: Application
        let ownerName: String
    }

    private struct ScanResult: Sendable {
        let inventory: [Application: [Snapshot]]
        let systemOverflowApplication: Application?
        let systemOverflowFrame: CGRect?
        let wasCancelled: Bool
    }

    private struct PendingRefresh {
        let id: UInt64
        let selection: MenuBarInventoryRefreshPolicy.Selection
        let task: Task<ScanResult, Never>
    }

    @MainActor private static var cachedInventory: [Application: [Snapshot]] = [:]
    @MainActor private static var cachedSystemOverflowApplication: Application?
    @MainActor private static var cachedSystemOverflowFrame: CGRect?
    @MainActor private static var refreshTask: PendingRefresh?
    @MainActor private static var nextRefreshID: UInt64 = 0
    @MainActor private static var refreshPolicy = MenuBarInventoryRefreshPolicy()
    @MainActor private static var cachedSnapshots: [Snapshot] {
        cachedInventory.keys.sorted {
            $0.processIdentifier < $1.processIdentifier
        }.flatMap { cachedInventory[$0] ?? [] }
    }
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

    /// Refreshes one known menu extra without walking every running
    /// application. Import verification calls this after MenuBarAgent has
    /// moved the item, where a full inventory scan would add several seconds
    /// to a user-initiated drag.
    @MainActor
    static func refreshSnapshot(
        for identity: MenuBarAccessibilityIdentity,
        id: CGWindowID,
        expectedLabel: String
    ) -> Snapshot? {
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
        guard elements.indices.contains(identity.ordinal),
              let liveFrame = frame(of: elements[identity.ordinal]),
              liveFrame.width > 0,
              liveFrame.height > 0 else { return nil }

        let liveLabel = preferredLabel(
            help: stringAttribute(elements[identity.ordinal], kAXHelpAttribute),
            description: stringAttribute(
                elements[identity.ordinal],
                kAXDescriptionAttribute
            ),
            title: stringAttribute(elements[identity.ordinal], kAXTitleAttribute),
            appName: application.localizedName ?? ""
        )
        if elements.count > 1, liveLabel != expectedLabel { return nil }

        let snapshot = Snapshot(
            identity: identity,
            id: id,
            frame: liveFrame,
            ownerName: application.localizedName ?? "",
            label: liveLabel
        )
        let generation = applicationIdentity(application)
        var snapshots = cachedInventory[generation] ?? []
        if let index = snapshots.firstIndex(where: { $0.identity == identity }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        // Do not retain an earlier process generation with the same PID.
        cachedInventory = cachedInventory.filter {
            $0.key.processIdentifier != generation.processIdentifier
                || $0.key == generation
        }
        cachedInventory[generation] = snapshots
        return snapshot
    }

    /// Refreshes only MenuBarAgent's native overflow control. Its position can
    /// shift when status items exchange visible and hidden membership.
    @MainActor
    static func refreshSystemOverflowFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.runningApplications.first(
                  where: {
                      !$0.isTerminated
                          && $0.bundleIdentifier == "com.apple.MenuBarAgent"
                  }
              ) else { return nil }
        cachedSystemOverflowApplication = applicationIdentity(application)
        cachedSystemOverflowFrame = nativeOverflowButtonFrame(
            in: AXUIElementCreateApplication(application.processIdentifier)
        )
        return cachedSystemOverflowFrame
    }

    @MainActor
    @discardableResult
    static func refresh(force: Bool = false) async -> [Snapshot] {
        while true {
            guard AXIsProcessTrusted() else {
                refreshTask?.task.cancel()
                cachedInventory = [:]
                cachedSystemOverflowApplication = nil
                cachedSystemOverflowFrame = nil
                refreshPolicy = MenuBarInventoryRefreshPolicy()
                return []
            }
            guard !Task.isCancelled else { return cachedSnapshots }
            let applications = runningApplications()
            let liveApplications = Set(applications.map(\.generation))
            pruneCache(runningApplications: liveApplications)

            if let pending = refreshTask {
                let result = await pending.task.value
                finishRefresh(pending, result: result)
                guard AXIsProcessTrusted() else { return [] }
                if result.wasCancelled { continue }
                // A user action joining an incremental scan still receives a
                // full inventory. Do not cancel work shared with other callers.
                if force,
                   (!pending.selection.isFullSweep
                    || !liveApplications.isSubset(of: pending.selection.applications)) {
                    continue
                }
                return cachedSnapshots
            }
            if !force,
               liveApplications == refreshPolicy.runningApplications,
               ContinuousClock.Instant.now - lastRefresh < minimumRefreshInterval {
                return cachedSnapshots
            }
            let selection = refreshPolicy.selection(
                runningApplications: applications.map(\.generation),
                now: ProcessInfo.processInfo.systemUptime,
                force: force
            )
            let selected = applications.filter {
                selection.applications.contains($0.generation)
            }
            let reservedIDs = Set(cachedInventory.filter {
                !selection.applications.contains($0.key)
            }.values.flatMap { $0.map(\.id) })
            nextRefreshID &+= 1
            let pending = PendingRefresh(
                id: nextRefreshID,
                selection: selection,
                task: Task.detached(priority: .utility) {
                    scan(applications: selected, reservedIDs: reservedIDs)
                }
            )
            refreshTask = pending
            // Join directly. Looping back through the shared-task branch here
            // would query every NSRunningApplication's properties a second
            // time before this very same scan has even completed.
            let result = await pending.task.value
            finishRefresh(pending, result: result)
            guard AXIsProcessTrusted() else { return [] }
            if result.wasCancelled { continue }
            return cachedSnapshots
        }
    }

    @MainActor
    private static func applicationIdentity(
        _ application: NSRunningApplication
    ) -> Application {
        Application(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier ?? "",
            launchDate: application.launchDate
        )
    }

    @MainActor
    private static func runningApplications() -> [RunningApplicationIdentity] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != ownProcessIdentifier
        }.map {
            RunningApplicationIdentity(
                generation: applicationIdentity($0),
                ownerName: $0.localizedName ?? ""
            )
        }
    }

    @MainActor
    private static func pruneCache(runningApplications: Set<Application>) {
        cachedInventory = MenuBarInventoryRefreshPolicy.merging(
            [:],
            into: cachedInventory,
            runningApplications: runningApplications
        )
        if let host = cachedSystemOverflowApplication,
           !runningApplications.contains(host) {
            cachedSystemOverflowApplication = nil
            cachedSystemOverflowFrame = nil
        }
    }

    @MainActor
    private static func finishRefresh(
        _ pending: PendingRefresh,
        result: ScanResult
    ) {
        // Only the first waiter consumes this task. A late waiter must never
        // clear a newer task or overwrite a fresher targeted snapshot.
        guard refreshTask?.id == pending.id else { return }
        refreshTask = nil
        guard AXIsProcessTrusted() else {
            cachedInventory = [:]
            cachedSystemOverflowApplication = nil
            cachedSystemOverflowFrame = nil
            refreshPolicy = MenuBarInventoryRefreshPolicy()
            return
        }
        let liveApplications = Set(runningApplications().map(\.generation))
        pruneCache(runningApplications: liveApplications)
        guard !result.wasCancelled else { return }
        lastRefreshStatistics = RefreshStatistics(
            scannedApplications: result.inventory.count,
            runningApplications: pending.selection.runningApplications.count,
            isFullSweep: pending.selection.isFullSweep
        )
        cachedInventory = MenuBarInventoryRefreshPolicy.merging(
            result.inventory,
            into: cachedInventory,
            runningApplications: liveApplications
        )
        refreshPolicy.recordCompletion(
            of: pending.selection,
            completedApplications: Set(result.inventory.keys),
            applicationsWithMenuExtras: Set(result.inventory.filter {
                !$0.value.isEmpty
            }.keys)
        )
        if let host = result.systemOverflowApplication,
           liveApplications.contains(host) {
            cachedSystemOverflowApplication = host
            cachedSystemOverflowFrame = result.systemOverflowFrame
        }
        lastRefresh = .now
    }

    private nonisolated static func scan(
        applications: [RunningApplicationIdentity],
        reservedIDs: Set<CGWindowID>
    ) -> ScanResult {
        var inventory: [Application: [Snapshot]] = [:]
        var usedIDs = reservedIDs
        var systemOverflowApplication: Application?
        var systemOverflowFrame: CGRect?

        for application in applications {
            guard !Task.isCancelled else { break }
            let generation = application.generation
            let appElement = AXUIElementCreateApplication(
                generation.processIdentifier
            )
            let overflowFrame = generation.bundleIdentifier == "com.apple.MenuBarAgent"
                ? nativeOverflowButtonFrame(in: appElement) : nil
            var snapshots: [Snapshot] = []
            for (ordinal, element) in menuExtras(in: appElement).enumerated() {
                guard !Task.isCancelled else { break }
                guard let frame = frame(of: element),
                      frame.width > 0,
                      frame.height > 0 else { continue }
                let identity = MenuBarAccessibilityIdentity(
                    processIdentifier: generation.processIdentifier,
                    bundleIdentifier: generation.bundleIdentifier,
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
            guard !Task.isCancelled else { break }
            inventory[generation] = snapshots
            if generation.bundleIdentifier == "com.apple.MenuBarAgent" {
                systemOverflowApplication = generation
                systemOverflowFrame = overflowFrame
            }
        }
        return ScanResult(
            inventory: inventory,
            systemOverflowApplication: systemOverflowApplication,
            systemOverflowFrame: systemOverflowFrame,
            wasCancelled: Task.isCancelled
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
        return pressResultIndicatesDispatch(
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        )
    }

    /// Some menu-extra implementations dispatch AXPress but fail to acknowledge
    /// the synchronous accessibility message before its timeout. Tauri status
    /// items exhibit this behavior: the real menu opens while AppKit reports
    /// `cannotComplete`. The element has already been re-resolved by process,
    /// bundle, ordinal, label, and live frame, so this result is an indeterminate
    /// acknowledgement rather than evidence that a different item was targeted.
    nonisolated static func pressResultIndicatesDispatch(_ result: AXError) -> Bool {
        result == .success || result == .cannotComplete
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
        var extras: [AXUIElement] = []
        for child in children(of: application) {
            guard !Task.isCancelled else { return [] }
            guard stringAttribute(child, kAXRoleAttribute) == "AXMenuBar" else {
                continue
            }
            for element in children(of: child) {
                guard !Task.isCancelled else { return [] }
                if stringAttribute(element, kAXSubroleAttribute) == "AXMenuExtra" {
                    extras.append(element)
                }
            }
        }
        return extras
    }

    private nonisolated static func nativeOverflowButtonFrame(
        in application: AXUIElement
    ) -> CGRect? {
        for window in children(of: application) {
            guard !Task.isCancelled else { return nil }
            guard stringAttribute(window, kAXRoleAttribute) == "AXWindow",
                  let windowFrame = frame(of: window),
                  windowFrame.minY <= 1,
                  windowFrame.height >= 30,
                  windowFrame.height <= 40 else { continue }
            for element in children(of: window) {
                guard !Task.isCancelled else { return nil }
                guard stringAttribute(element, kAXRoleAttribute) == "AXButton",
                      stringAttribute(element, kAXSubroleAttribute).isEmpty,
                      let buttonFrame = frame(of: element),
                      buttonFrame.minY <= 2,
                      buttonFrame.width >= 8,
                      buttonFrame.width <= 30,
                      buttonFrame.height >= 28,
                      buttonFrame.height <= 36 else { continue }
                return buttonFrame
            }
        }
        return nil
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
