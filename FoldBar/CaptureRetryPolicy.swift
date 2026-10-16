import CoreGraphics
import Foundation

/// Limits only failed background image capture. Inventory and visibility
/// reconciliation continue on their own cadence, including during cooldown.
struct MenuBarCaptureRetryPolicy {
    private struct Failure {
        let frame: CGRect
        let attemptCount: Int
        let nextRetryUptime: TimeInterval
    }

    private let retryDelays: [TimeInterval]
    private var failures: [MenuBarAccessibilityIdentity: Failure] = [:]

    init(retryDelays: [TimeInterval] = [15, 30, 60, 120, 300]) {
        precondition(!retryDelays.isEmpty && retryDelays.allSatisfy { $0.isFinite && $0 > 0 })
        self.retryDelays = retryDelays
    }

    mutating func retryableItems(
        among items: [MenuBarItemWindow],
        now: TimeInterval
    ) -> [MenuBarItemWindow] {
        let liveIdentities = Set(items.compactMap(\.accessibilityIdentity))
        failures = failures.filter { liveIdentities.contains($0.key) }
        return items.filter { item in
            guard let identity = item.accessibilityIdentity,
                  let failure = failures[identity] else { return true }
            guard failure.frame == item.frame else {
                failures.removeValue(forKey: identity)
                return true
            }
            return now >= failure.nextRetryUptime
        }
    }

    mutating func recordResults(
        for attemptedItems: [MenuBarItemWindow],
        capturedIDs: Set<CGWindowID>,
        now: TimeInterval
    ) {
        for item in attemptedItems {
            guard let identity = item.accessibilityIdentity else { continue }
            guard !capturedIDs.contains(item.id) else {
                failures.removeValue(forKey: identity)
                continue
            }
            let previous = failures[identity]
            let priorAttempts = previous?.frame == item.frame ? previous?.attemptCount ?? 0 : 0
            let delayIndex = min(priorAttempts, retryDelays.count - 1)
            failures[identity] = Failure(
                frame: item.frame,
                attemptCount: min(priorAttempts + 1, retryDelays.count),
                nextRetryUptime: now + retryDelays[delayIndex]
            )
        }
    }

    mutating func reset() {
        failures.removeAll()
    }

    mutating func reset(bundleIdentifier: String) {
        failures = failures.filter { $0.key.bundleIdentifier != bundleIdentifier }
    }
}

/// Preview values may be shared image references. Retaining a candidate keeps
/// its preview available; a request from a closed panel can never refill it.
struct MenuBarImportPreviewCache<Value> {
    struct Request: Equatable, Sendable {
        let generation: UInt64
        let itemIDs: Set<CGWindowID>
    }

    private(set) var generation: UInt64 = 0
    private var images: [CGWindowID: Value] = [:]
    private var requestedIDs: Set<CGWindowID> = []

    subscript(_ id: CGWindowID) -> Value? { images[id] }

    mutating func retain(
        candidateIDs: Set<CGWindowID>,
        activeDragItemID: CGWindowID?
    ) {
        let retainedIDs = Self.retainedIDs(
            candidateIDs: candidateIDs,
            activeDragItemID: activeDragItemID
        )
        images = images.filter { retainedIDs.contains($0.key) }
        requestedIDs.formIntersection(retainedIDs)
    }

    mutating func request(for candidateIDs: Set<CGWindowID>) -> Request? {
        let missing = candidateIDs.subtracting(requestedIDs)
        guard !missing.isEmpty else { return nil }
        requestedIDs.formUnion(missing)
        return Request(generation: generation, itemIDs: missing)
    }

    @discardableResult
    mutating func merge(
        _ results: [CGWindowID: Value],
        for request: Request,
        candidateIDs: Set<CGWindowID>,
        activeDragItemID: CGWindowID?
    ) -> Bool {
        guard request.generation == generation else { return false }
        retain(candidateIDs: candidateIDs, activeDragItemID: activeDragItemID)
        let acceptedIDs = request.itemIDs.intersection(Self.retainedIDs(
            candidateIDs: candidateIDs,
            activeDragItemID: activeDragItemID
        ))
        for (id, value) in results where acceptedIDs.contains(id) && images[id] == nil {
            // A drag may have supplied a fresher image while prefetch waited.
            images[id] = value
        }
        return true
    }

    mutating func store(_ image: Value, for id: CGWindowID) {
        images[id] = image
        requestedIDs.insert(id)
    }

    mutating func reset() {
        generation &+= 1
        images.removeAll()
        requestedIDs.removeAll()
    }

    private static func retainedIDs(
        candidateIDs: Set<CGWindowID>,
        activeDragItemID: CGWindowID?
    ) -> Set<CGWindowID> {
        guard let activeDragItemID else { return candidateIDs }
        return candidateIDs.union([activeDragItemID])
    }
}
