import Foundation
import Testing

@testable import FoldBar

@Suite("Menu-bar inventory refresh policy")
struct InventoryRefreshPolicyTests {
    private typealias Application = MenuBarInventoryRefreshPolicy.Application

    private func app(
        _ pid: pid_t,
        _ bundle: String = "com.example.app",
        launchedAt: TimeInterval = 1
    ) -> Application {
        Application(
            processIdentifier: pid,
            bundleIdentifier: bundle,
            launchDate: Date(timeIntervalSince1970: launchedAt)
        )
    }

    private func complete(
        _ selection: MenuBarInventoryRefreshPolicy.Selection,
        policy: inout MenuBarInventoryRefreshPolicy,
        withMenuExtras owners: Set<Application> = []
    ) {
        policy.recordCompletion(
            of: selection,
            completedApplications: selection.applications,
            applicationsWithMenuExtras: owners
        )
    }

    @Test("Steady refreshes keep known owners and the host, skipping ordinary apps")
    func scopesSteadyRefreshes() {
        let ordinary = app(1)
        let owner = app(2)
        let host = app(3, "com.apple.MenuBarAgent")
        let running = [ordinary, owner, host]
        var policy = MenuBarInventoryRefreshPolicy()
        let startup = policy.selection(runningApplications: running, now: 0)
        #expect(startup.isFullSweep)
        #expect(startup.applications == Set(running))
        complete(startup, policy: &policy, withMenuExtras: [owner])
        let fallback = policy.selection(runningApplications: running, now: 30)
        complete(fallback, policy: &policy, withMenuExtras: [owner])

        let steady = policy.selection(runningApplications: running, now: 35)
        #expect(!steady.isFullSweep)
        #expect(steady.applications == [owner, host])
        // An empty reply may be a transient AX failure, so keep retrying a
        // previously known owner on the next pass rather than waiting 30 s.
        complete(steady, policy: &policy)
        let afterEmptyReply = policy.selection(runningApplications: running, now: 40)
        #expect(afterEmptyReply.applications == [owner, host])
    }

    @Test("New processes get a discovery grace even after the global startup grace")
    func discoversLateMenuExtrasAfterLaunch() {
        let ordinary = app(1)
        let late = app(2)
        var policy = MenuBarInventoryRefreshPolicy()
        let startup = policy.selection(runningApplications: [ordinary], now: 0)
        complete(startup, policy: &policy)
        let fallback = policy.selection(runningApplications: [ordinary], now: 30)
        complete(fallback, policy: &policy)

        let launched = policy.selection(runningApplications: [ordinary, late], now: 35)
        #expect(launched.applications == [late])
        complete(launched, policy: &policy)
        let waitingForExtra = policy.selection(
            runningApplications: [ordinary, late],
            now: 55
        )
        #expect(waitingForExtra.applications == [late])
        complete(waitingForExtra, policy: &policy, withMenuExtras: [late])
        let nextFallback = policy.selection(
            runningApplications: [ordinary, late],
            now: 60
        )
        complete(nextFallback, policy: &policy, withMenuExtras: [late])
        let discovered = policy.selection(runningApplications: [ordinary, late], now: 70)
        #expect(discovered.applications == [late])
    }

    @Test("An existing app adding an extra later is revisited by the bounded full sweep")
    func boundedFallbackFindsExistingApplications() {
        let ordinary = app(1)
        var policy = MenuBarInventoryRefreshPolicy()
        let startup = policy.selection(runningApplications: [ordinary], now: 0)
        complete(startup, policy: &policy)
        let firstFallback = policy.selection(runningApplications: [ordinary], now: 30)
        complete(firstFallback, policy: &policy)
        let skipped = policy.selection(runningApplications: [ordinary], now: 59)
        #expect(skipped.applications.isEmpty)
        #expect(!skipped.isFullSweep)

        let safetySweep = policy.selection(runningApplications: [ordinary], now: 60)
        #expect(safetySweep.isFullSweep)
        #expect(safetySweep.applications == [ordinary])
        complete(safetySweep, policy: &policy, withMenuExtras: [ordinary])
        let known = policy.selection(runningApplications: [ordinary], now: 65)
        #expect(known.applications == [ordinary])
    }

    @Test("An explicit request always includes apps outside the background selection")
    func forceBypassesDiscoveryCadence() {
        let ordinary = app(1)
        var policy = MenuBarInventoryRefreshPolicy()
        let startup = policy.selection(runningApplications: [ordinary], now: 0)
        complete(startup, policy: &policy)
        let fallback = policy.selection(runningApplications: [ordinary], now: 30)
        complete(fallback, policy: &policy)
        let skipped = policy.selection(runningApplications: [ordinary], now: 35)
        #expect(skipped.applications.isEmpty)

        let forced = policy.selection(runningApplications: [ordinary], now: 36, force: true)
        #expect(forced.isFullSweep)
        #expect(forced.applications == [ordinary])
    }

    @Test("Reused PIDs and exited processes cannot inherit cached snapshots or owner status")
    func processGenerationInvalidatesCache() {
        let exited = app(1)
        let old = app(2, launchedAt: 1)
        let reused = app(2, launchedAt: 2)
        let changedBundle = app(1, "com.example.other")
        var policy = MenuBarInventoryRefreshPolicy()
        let startup = policy.selection(runningApplications: [exited, old], now: 0)
        complete(startup, policy: &policy, withMenuExtras: [exited, old])
        let full = policy.selection(runningApplications: [exited, old], now: 30)
        complete(full, policy: &policy, withMenuExtras: [exited, old])

        let relaunch = policy.selection(runningApplications: [reused, changedBundle], now: 35)
        #expect(relaunch.applications == [reused, changedBundle])
        let merged = MenuBarInventoryRefreshPolicy.merging(
            [old: ["stale result"], reused: ["new label"]],
            into: [exited: ["exited"], old: ["old label"]],
            runningApplications: [reused, changedBundle]
        )
        #expect(merged == [reused: ["new label"]])
        complete(relaunch, policy: &policy)
        let laterFull = policy.selection(runningApplications: [reused, changedBundle], now: 60)
        complete(laterFull, policy: &policy)
        let noInheritedOwners = policy.selection(
            runningApplications: [reused, changedBundle],
            now: 70
        )
        #expect(noInheritedOwners.applications.isEmpty)
    }

    @Test("Partial inventory replaces scanned apps including empty results and preserves others")
    func mergesOnlyCompletedApplications() {
        let updated = app(1)
        let removedExtra = app(2)
        let unscanned = app(3)
        let exited = app(4)
        let merged = MenuBarInventoryRefreshPolicy.merging(
            [updated: ["new"], removedExtra: []],
            into: [updated: ["old"], removedExtra: ["gone"], unscanned: ["keep"], exited: ["exit"]],
            runningApplications: [updated, removedExtra, unscanned]
        )
        #expect(merged == [updated: ["new"], removedExtra: [], unscanned: ["keep"]])
    }

    @Test("A cancelled or incomplete full sweep never postpones the safety fallback")
    func incompleteSweepRemainsDue() {
        let first = app(1)
        let second = app(2)
        var policy = MenuBarInventoryRefreshPolicy()
        let partial = policy.selection(runningApplications: [first, second], now: 0)
        policy.recordCompletion(
            of: partial,
            completedApplications: [first],
            applicationsWithMenuExtras: [first]
        )
        let retry = policy.selection(runningApplications: [first, second], now: 5)
        #expect(retry.isFullSweep)
        #expect(retry.applications == [first, second])
    }
}
