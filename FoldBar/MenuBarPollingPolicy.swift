enum MenuBarPollingPolicy {
    static func shouldMonitorCollapsedItems(
        usesAccessibilityBackend: Bool,
        hasManagedApplications: Bool
    ) -> Bool {
        // An empty private set has no assertion that can park new apps. Failed
        // images must still be retried when the persisted managed set is nonempty.
        !usesAccessibilityBackend || hasManagedApplications
    }

    static func collapsedIntervalMilliseconds(usesAccessibilityBackend: Bool) -> Int {
        usesAccessibilityBackend ? 5_000 : 1_500
    }

    // The AX inventory already has a 500 ms minimum refresh interval. Match it
    // instead of rebuilding candidates twice between fresh inventories.
    static let panelIntervalMilliseconds = 500
}
