import CoreGraphics
import Foundation
import Testing

@testable import FoldBar

@Suite("Background capture retry policy")
struct CaptureRetryPolicyTests {
    private func item(
        id: CGWindowID = 1,
        processIdentifier: pid_t = 100,
        x: CGFloat = 1_000,
        bundleIdentifier: String = "com.example.capture"
    ) -> MenuBarItemWindow {
        MenuBarItemWindow(
            id: id,
            frame: CGRect(x: x, y: 4, width: 24, height: 24),
            ownerName: "Example",
            windowName: "Example item",
            accessibilityIdentity: MenuBarAccessibilityIdentity(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                ordinal: 0
            ),
            bundleIdentifier: bundleIdentifier
        )
    }

    @Test("Failed images back off to a finite cooldown and remain retryable")
    func boundedBackoff() {
        var policy = MenuBarCaptureRetryPolicy()
        let candidate = item()
        var now: TimeInterval = 0
        let initial = policy.retryableItems(among: [candidate], now: now)
        #expect(initial.map(\.id) == [candidate.id])

        let delays: [TimeInterval] = [15, 30, 60, 120, 300, 300, 300]
        for delay in delays {
            policy.recordResults(for: [candidate], capturedIDs: [], now: now)
            let beforeDeadline = policy.retryableItems(among: [candidate], now: now + delay - 0.1)
            let atDeadline = policy.retryableItems(among: [candidate], now: now + delay)
            #expect(beforeDeadline.isEmpty)
            #expect(atDeadline.map(\.id) == [candidate.id])
            now += delay
        }
    }

    @Test("A successful image resets its next failure to the initial delay")
    func successResetsBackoff() {
        var policy = MenuBarCaptureRetryPolicy()
        let candidate = item()
        policy.recordResults(for: [candidate], capturedIDs: [], now: 0)
        policy.recordResults(for: [candidate], capturedIDs: [], now: 15)
        policy.recordResults(for: [candidate], capturedIDs: [candidate.id], now: 45)

        let afterSuccess = policy.retryableItems(among: [candidate], now: 45)
        #expect(afterSuccess.count == 1)
        policy.recordResults(for: [candidate], capturedIDs: [], now: 45)
        let beforeDeadline = policy.retryableItems(among: [candidate], now: 59.9)
        let atDeadline = policy.retryableItems(among: [candidate], now: 60)
        #expect(beforeDeadline.isEmpty)
        #expect(atDeadline.count == 1)
    }

    @Test("A moved frame retries immediately and starts a new failure sequence")
    func geometryChangeResetsBackoff() {
        var policy = MenuBarCaptureRetryPolicy()
        let original = item()
        let moved = item(x: 1_025)
        policy.recordResults(for: [original], capturedIDs: [], now: 0)
        policy.recordResults(for: [original], capturedIDs: [], now: 15)

        let afterMove = policy.retryableItems(among: [moved], now: 16)
        #expect(afterMove.count == 1)
        policy.recordResults(for: [moved], capturedIDs: [], now: 16)
        let beforeDeadline = policy.retryableItems(among: [moved], now: 30.9)
        let atDeadline = policy.retryableItems(among: [moved], now: 31)
        #expect(beforeDeadline.isEmpty)
        #expect(atDeadline.count == 1)
    }

    @Test("A new application generation is independent of an old failed item")
    func applicationGenerationRetriesImmediately() {
        var policy = MenuBarCaptureRetryPolicy()
        let old = item()
        let restarted = item(processIdentifier: 101)
        let newlyLaunched = item(id: 2, processIdentifier: 102, bundleIdentifier: "com.example.new")
        policy.recordResults(for: [old], capturedIDs: [], now: 0)

        let afterLaunch = policy.retryableItems(among: [old, newlyLaunched], now: 1)
        let afterRestart = policy.retryableItems(among: [restarted], now: 1)
        #expect(afterLaunch.map(\.id) == [newlyLaunched.id])
        #expect(afterRestart.map(\.id) == [restarted.id])
    }

    @Test("Explicit retries can reset one bundle or the whole panel session")
    func explicitRetriesResetCooldown() {
        var policy = MenuBarCaptureRetryPolicy()
        let first = item()
        let second = item(id: 2, processIdentifier: 200, bundleIdentifier: "com.example.second")
        policy.recordResults(for: [first, second], capturedIDs: [], now: 0)
        policy.reset(bundleIdentifier: first.bundleIdentifier)
        let afterBundleReset = policy.retryableItems(among: [first, second], now: 1)
        #expect(afterBundleReset.map(\.id) == [first.id])

        policy.reset()
        let afterSessionReset = policy.retryableItems(among: [first, second], now: 1)
        #expect(afterSessionReset.map(\.id) == [first.id, second.id])
    }

    @Test("Disappeared items do not leave retry records behind")
    func removedItemsArePruned() {
        var policy = MenuBarCaptureRetryPolicy()
        let candidate = item()
        policy.recordResults(for: [candidate], capturedIDs: [], now: 0)
        let whileRemoved = policy.retryableItems(among: [], now: 1)
        let afterReturn = policy.retryableItems(among: [candidate], now: 2)
        #expect(whileRemoved.isEmpty)
        #expect(afterReturn.count == 1)
    }
}

@Suite("Import preview cache lifetime")
struct ImportPreviewCacheTests {
    @Test("Pruning keeps current candidates and the active drag only")
    func keepsCandidatesAndActiveDrag() {
        var cache = MenuBarImportPreviewCache<String>()
        cache.store("current", for: 1)
        cache.store("drag", for: 2)
        cache.store("removed", for: 3)
        cache.retain(candidateIDs: [1], activeDragItemID: 2)

        #expect(cache[1] == "current")
        #expect(cache[2] == "drag")
        #expect(cache[3] == nil)
        let retainedRequest = cache.request(for: [1, 2])
        let removedRequest = cache.request(for: [3])
        #expect(retainedRequest == nil)
        #expect(removedRequest?.itemIDs == [3])
    }

    @Test("A late prefetch cannot restore an item that left the candidate list")
    func rejectsRemovedResults() throws {
        var cache = MenuBarImportPreviewCache<String>()
        let pendingRequest = cache.request(for: [1, 2, 3])
        let request = try #require(pendingRequest)
        let accepted = cache.merge(
            [1: "current", 2: "removed", 3: "active"],
            for: request,
            candidateIDs: [1],
            activeDragItemID: 3
        )
        #expect(accepted)

        #expect(cache[1] == "current")
        #expect(cache[2] == nil)
        #expect(cache[3] == "active")
        let returningRequest = cache.request(for: [2])
        #expect(returningRequest?.itemIDs == [2])
    }

    @Test("A prefetch from a closed panel cannot overwrite its new generation")
    func rejectsPreviousGeneration() throws {
        var cache = MenuBarImportPreviewCache<String>()
        let pendingOldRequest = cache.request(for: [1])
        let oldRequest = try #require(pendingOldRequest)
        cache.reset()
        let pendingNewRequest = cache.request(for: [1])
        let newRequest = try #require(pendingNewRequest)
        let acceptedNew = cache.merge(
            [1: "new"], for: newRequest, candidateIDs: [1], activeDragItemID: nil
        )
        let acceptedOld = cache.merge(
            [1: "old"], for: oldRequest, candidateIDs: [], activeDragItemID: nil
        )
        #expect(acceptedNew)
        #expect(!acceptedOld)
        #expect(cache[1] == "new")
    }

    @Test("A drag image stays newer than its earlier prefetch request")
    func preservesNewerDragImage() throws {
        var cache = MenuBarImportPreviewCache<String>()
        let pendingRequest = cache.request(for: [1])
        let request = try #require(pendingRequest)
        cache.store("fresh drag", for: 1)
        let accepted = cache.merge(
            [1: "earlier prefetch"], for: request, candidateIDs: [1], activeDragItemID: 1
        )
        #expect(accepted)
        #expect(cache[1] == "fresh drag")
    }

    @Test("A long session releases removed previews and can request returning items")
    func returningItemsCanPrefetchAgain() throws {
        var cache = MenuBarImportPreviewCache<String>()
        for id in CGWindowID(1)...CGWindowID(100) {
            cache.retain(candidateIDs: [id], activeDragItemID: nil)
            let pendingRequest = cache.request(for: [id])
            let request = try #require(pendingRequest)
            cache.merge([id: "preview"], for: request, candidateIDs: [id], activeDragItemID: nil)
            if id > 1 { #expect(cache[id - 1] == nil) }
            #expect(cache[id] == "preview")
        }
        cache.retain(candidateIDs: [1], activeDragItemID: nil)
        #expect(cache[100] == nil)
        let returningRequest = cache.request(for: [1])
        #expect(returningRequest?.itemIDs == [1])
    }
}
