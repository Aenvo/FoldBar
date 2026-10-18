import Foundation

/// Bounds background AX discovery without retaining AX objects or forgetting
/// a process that previously published a menu extra. Explicit user actions can
/// still request a full inventory immediately.
struct MenuBarInventoryRefreshPolicy {
    struct Application: Hashable, Sendable {
        let processIdentifier: pid_t
        let bundleIdentifier: String
        let launchDate: Date?
    }

    struct Selection: Sendable {
        let applications: Set<Application>
        let runningApplications: Set<Application>
        let isFullSweep: Bool
        let startedAt: TimeInterval
    }

    private let discoveryGrace: TimeInterval
    private let fullSweepInterval: TimeInterval
    private var firstObservedAt: [Application: TimeInterval] = [:]
    private var knownMenuExtraApplications: Set<Application> = []
    private var lastFullSweep: TimeInterval?
    private(set) var runningApplications: Set<Application> = []

    init(
        discoveryGrace: TimeInterval = 30,
        fullSweepInterval: TimeInterval = 30
    ) {
        precondition(discoveryGrace.isFinite && discoveryGrace > 0)
        precondition(fullSweepInterval.isFinite && fullSweepInterval > 0)
        self.discoveryGrace = discoveryGrace
        self.fullSweepInterval = fullSweepInterval
    }

    mutating func selection(
        runningApplications applications: [Application],
        now: TimeInterval,
        force: Bool = false
    ) -> Selection {
        runningApplications = Set(applications)
        firstObservedAt = firstObservedAt.filter {
            runningApplications.contains($0.key)
        }
        knownMenuExtraApplications.formIntersection(runningApplications)
        for application in applications where firstObservedAt[application] == nil {
            firstObservedAt[application] = now
        }
        let isFullSweep = force || lastFullSweep.map {
            now - $0 >= fullSweepInterval
        } ?? true
        let selected = runningApplications.filter { application in
            isFullSweep
                || application.bundleIdentifier == "com.apple.MenuBarAgent"
                || knownMenuExtraApplications.contains(application)
                || now - (firstObservedAt[application] ?? now) < discoveryGrace
        }
        return Selection(
            applications: selected,
            runningApplications: runningApplications,
            isFullSweep: isFullSweep,
            startedAt: now
        )
    }

    mutating func recordCompletion(
        of selection: Selection,
        completedApplications: Set<Application>,
        applicationsWithMenuExtras: Set<Application>
    ) {
        // A transient AX failure must not stop the next background refresh of
        // a known menu-extra owner. Forget it only when its process exits.
        knownMenuExtraApplications.formUnion(
            applicationsWithMenuExtras
                .intersection(completedApplications)
                .intersection(runningApplications)
        )
        if selection.isFullSweep,
           completedApplications.isSuperset(of: selection.applications) {
            lastFullSweep = selection.startedAt
        }
    }

    /// A completed empty scan replaces that process's old snapshots, while a
    /// cancelled/incomplete process scan supplies no entry and preserves them.
    /// Generation keys discard terminated or reused PIDs before any merge.
    static func merging<Value>(
        _ scanned: [Application: [Value]],
        into cached: [Application: [Value]],
        runningApplications: Set<Application>
    ) -> [Application: [Value]] {
        var merged = cached.filter { runningApplications.contains($0.key) }
        for (application, snapshots) in scanned
            where runningApplications.contains(application) {
            merged[application] = snapshots
        }
        return merged
    }
}
