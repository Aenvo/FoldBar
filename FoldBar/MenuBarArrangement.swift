import Foundation

/// Backs up valid status-item positions before the oversized separator moves
/// the real windows off-screen. The snapshot is merged, never replaced, so a
/// value already damaged by macOS cannot overwrite the last known-good value.
enum MenuBarArrangement {
    typealias Snapshot = [String: [String: Double]]

    static let ownDomain = Bundle.main.bundleIdentifier ?? "local.foldbar.app"
    private static let keyPrefix = "NSStatusItem Preferred Position"
    private static let snapshotKey = "savedArrangement"
    private static let validRange: ClosedRange<Double> = 0...10_000

    static func isValid(_ value: Double) -> Bool { validRange.contains(value) }

    @discardableResult
    static func captureAndSave() -> Int {
        let (fresh, domains) = capture()
        guard !domains.isEmpty else { return savedCount() }
        let merged = merge(saved: saved() ?? [:], fresh: fresh, liveDomains: domains)
        UserDefaults.standard.set(merged, forKey: snapshotKey)
        return merged.values.reduce(0) { $0 + $1.count }
    }

    static func capture() -> (positions: Snapshot, domains: Set<String>) {
        var positions: Snapshot = [:]
        var domains: Set<String> = []
        for domain in preferenceDomains() {
            domains.insert(domain)
            guard let keys = CFPreferencesCopyKeyList(
                domain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String] else { continue }

            var found: [String: Double] = [:]
            for key in keys where key.hasPrefix(keyPrefix) {
                guard let value = CFPreferencesCopyValue(
                    key as CFString,
                    domain as CFString,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                ) as? Double, isValid(value) else { continue }
                found[key] = value
            }
            if !found.isEmpty { positions[domain] = found }
        }
        return (positions, domains)
    }

    static func merge(saved: Snapshot, fresh: Snapshot, liveDomains: Set<String>) -> Snapshot {
        guard !liveDomains.isEmpty else { return saved }
        var merged = saved.filter { liveDomains.contains($0.key) }
        for (domain, values) in fresh {
            merged[domain, default: [:]].merge(values) { _, new in new }
        }
        return merged
    }

    @discardableResult
    static func restore(_ snapshot: Snapshot) -> Int {
        var rewritten = 0
        for (domain, positions) in snapshot {
            var changed = false
            for (key, value) in positions where isValid(value) && isRestorable(domain: domain, key: key) {
                let current = CFPreferencesCopyValue(
                    key as CFString,
                    domain as CFString,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                ) as? Double
                guard current != value else { continue }
                CFPreferencesSetValue(
                    key as CFString,
                    NSNumber(value: value),
                    domain as CFString,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                )
                changed = true
                rewritten += 1
            }
            if changed { CFPreferencesAppSynchronize(domain as CFString) }
        }
        return rewritten
    }

    static func isRestorable(domain: String, key: String, home: String = NSHomeDirectory()) -> Bool {
        guard key.hasPrefix(keyPrefix), domain != ownDomain, !domain.hasPrefix(".") else { return false }
        if domain.hasPrefix("/") {
            return domain.hasPrefix(home + "/Library/Containers/") && !domain.contains("/../")
        }
        return !domain.contains("/")
    }

    static func saved() -> Snapshot? {
        guard let raw = UserDefaults.standard.dictionary(forKey: snapshotKey) else { return nil }
        let decoded = decode(raw)
        return decoded.isEmpty ? nil : decoded
    }

    static func decode(_ raw: [String: Any]) -> Snapshot {
        var result: Snapshot = [:]
        for (domain, entry) in raw {
            guard let values = entry as? [String: Any] else { continue }
            var decoded: [String: Double] = [:]
            for (key, value) in values {
                guard let number = value as? NSNumber else { continue }
                decoded[key] = number.doubleValue
            }
            if !decoded.isEmpty { result[domain] = decoded }
        }
        return result
    }

    static func savedCount() -> Int {
        (saved() ?? [:]).values.reduce(0) { $0 + $1.count }
    }

    static func savedOwnPosition(_ key: String) -> Double? {
        saved()?[ownDomain]?[key]
    }

    static func containerPlistPath(home: String, containerID: String) -> String {
        "\(home)/Library/Containers/\(containerID)/Data/Library/Preferences/\(containerID).plist"
    }

    private static func preferenceDomains() -> [String] {
        let home = NSHomeDirectory()
        let manager = FileManager.default
        let plain = ((try? manager.contentsOfDirectory(atPath: home + "/Library/Preferences")) ?? [])
            .filter { $0.hasSuffix(".plist") }
            .map { String($0.dropLast(6)) }
        let containers = ((try? manager.contentsOfDirectory(atPath: home + "/Library/Containers")) ?? [])
            .map { containerPlistPath(home: home, containerID: $0) }
            .filter(manager.fileExists)
        return plain + containers
    }
}
