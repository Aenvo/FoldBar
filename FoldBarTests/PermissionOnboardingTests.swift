import Foundation
import Testing

@testable import FoldBar

@Suite("Permission onboarding decisions")
struct PermissionOnboardingTests {
    private func withDefaults(
        _ body: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "local.foldbar.tests.permissions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }

    @Test("A fresh install offers onboarding only when a permission is missing")
    func freshInstall() throws {
        try withDefaults { defaults, _ in
            let policy = PermissionOnboardingPolicy(defaults: defaults)
            for (screen, accessibility) in [(false, false), (true, false), (false, true)] {
                #expect(policy.shouldPresentAutomatically(
                    screenGranted: screen, accessibilityGranted: accessibility
                ))
                #expect(policy.destination(
                    screenGranted: screen, accessibilityGranted: accessibility
                ) == .requestPermissions)
            }
            #expect(!policy.shouldPresentAutomatically(
                screenGranted: true, accessibilityGranted: true
            ))
        }
    }

    @Test("Later survives a restart without claiming a system request occurred")
    func laterSurvivesRestart() throws {
        try withDefaults { defaults, suiteName in
            PermissionOnboardingPolicy(defaults: defaults).recordDecision(requestPermissions: false)

            let reloaded = try #require(UserDefaults(suiteName: suiteName))
            let restarted = PermissionOnboardingPolicy(defaults: reloaded)
            #expect(!restarted.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: false
            ))
            #expect(!reloaded.bool(forKey: PermissionOnboardingPolicy.systemRequestKey))
            #expect(restarted.destination(
                screenGranted: false, accessibilityGranted: false
            ) == .requestPermissions)
        }
    }

    @Test("A manual request remains available after Later, then routes to settings")
    func manualRequestAfterLater() throws {
        try withDefaults { defaults, suiteName in
            let policy = PermissionOnboardingPolicy(defaults: defaults)
            policy.recordDecision(requestPermissions: false)
            #expect(policy.destination(
                screenGranted: false, accessibilityGranted: true
            ) == .requestPermissions)

            policy.recordDecision(requestPermissions: true)
            let reloaded = try #require(UserDefaults(suiteName: suiteName))
            let restarted = PermissionOnboardingPolicy(defaults: reloaded)
            #expect(restarted.destination(
                screenGranted: false, accessibilityGranted: true
            ) == .systemSettings)
            #expect(!restarted.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: true
            ))
        }
    }

    @Test("Denied or partially granted requests do not request again after restart")
    func requestedPermissionsSurviveRestart() throws {
        try withDefaults { defaults, suiteName in
            PermissionOnboardingPolicy(defaults: defaults).recordDecision(requestPermissions: true)
            let reloaded = try #require(UserDefaults(suiteName: suiteName))
            let restarted = PermissionOnboardingPolicy(defaults: reloaded)
            for (screen, accessibility) in [(false, false), (true, false), (false, true)] {
                #expect(!restarted.shouldPresentAutomatically(
                    screenGranted: screen, accessibilityGranted: accessibility
                ))
                #expect(restarted.destination(
                    screenGranted: screen, accessibilityGranted: accessibility
                ) == .systemSettings)
            }
        }
    }

    @Test("Existing request history suppresses onboarding without migration writes")
    func existingRequestHistory() throws {
        try withDefaults { defaults, _ in
            defaults.set(true, forKey: "didRequestCombinedPermissionsV1")
            let policy = PermissionOnboardingPolicy(defaults: defaults)
            #expect(!policy.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: false
            ))
            #expect(policy.destination(
                screenGranted: false, accessibilityGranted: false
            ) == .systemSettings)
            #expect(defaults.object(forKey: PermissionOnboardingPolicy.decisionKey) == nil)
        }
    }

    @Test("Delayed onboarding rechecks a decision made while it was pending")
    func delayedPresentationRechecksDecision() throws {
        try withDefaults { defaults, _ in
            let pending = PermissionOnboardingPolicy(defaults: defaults)
            #expect(pending.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: false
            ))
            PermissionOnboardingPolicy(defaults: defaults).recordDecision(requestPermissions: false)
            #expect(!pending.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: false
            ))
        }
    }

    @Test("External grants suppress a pending prompt without changing request history")
    func externalGrants() throws {
        try withDefaults { defaults, _ in
            let policy = PermissionOnboardingPolicy(defaults: defaults)
            #expect(policy.shouldPresentAutomatically(
                screenGranted: false, accessibilityGranted: false
            ))
            #expect(!policy.shouldPresentAutomatically(
                screenGranted: true, accessibilityGranted: true
            ))
            #expect(policy.destination(
                screenGranted: true, accessibilityGranted: true
            ) == .allGranted)
            #expect(defaults.object(forKey: PermissionOnboardingPolicy.systemRequestKey) == nil)
            #expect(defaults.object(forKey: PermissionOnboardingPolicy.decisionKey) == nil)
        }
    }

    @Test("Recording Later never clears an existing system request")
    func laterPreservesRequestHistory() throws {
        try withDefaults { defaults, _ in
            let policy = PermissionOnboardingPolicy(defaults: defaults)
            policy.recordDecision(requestPermissions: true)
            policy.recordDecision(requestPermissions: false)
            #expect(defaults.bool(forKey: PermissionOnboardingPolicy.systemRequestKey))
            #expect(policy.destination(
                screenGranted: false, accessibilityGranted: false
            ) == .systemSettings)
        }
    }
}
