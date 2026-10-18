import Testing

@testable import FoldBar

@Suite("Menu bar monitoring lifetime")
struct PollingPolicyTests {
    @Test("An empty private collection does not require idle system scanning")
    func emptyPrivateCollection() {
        #expect(!MenuBarPollingPolicy.shouldMonitorCollapsedItems(
            usesAccessibilityBackend: true,
            hasManagedApplications: false
        ))
    }

    @Test("Persisted private membership keeps recovery active even without usable images")
    func unavailablePrivateImages() {
        #expect(MenuBarPollingPolicy.shouldMonitorCollapsedItems(
            usesAccessibilityBackend: true,
            hasManagedApplications: true
        ))
    }

    @Test("Legacy discovery continues without a private managed application list")
    func legacyDiscovery() {
        #expect(MenuBarPollingPolicy.shouldMonitorCollapsedItems(
            usesAccessibilityBackend: false,
            hasManagedApplications: false
        ))
    }
}
