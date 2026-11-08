import Foundation

/// Keeps an onboarding decision separate from an actual system request. Choosing
/// Later suppresses automatic reminders while leaving the manual request open.
struct PermissionOnboardingPolicy {
    static let decisionKey = "didCompletePermissionOnboardingV1"
    static let systemRequestKey = "didRequestCombinedPermissionsV1"

    enum Destination {
        case allGranted
        case requestPermissions
        case systemSettings
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func destination(
        screenGranted: Bool,
        accessibilityGranted: Bool
    ) -> Destination {
        if screenGranted, accessibilityGranted { return .allGranted }
        return defaults.bool(forKey: Self.systemRequestKey)
            ? .systemSettings
            : .requestPermissions
    }

    func shouldPresentAutomatically(
        screenGranted: Bool,
        accessibilityGranted: Bool
    ) -> Bool {
        !defaults.bool(forKey: Self.decisionKey)
            && destination(
                screenGranted: screenGranted,
                accessibilityGranted: accessibilityGranted
            ) == .requestPermissions
    }

    func recordDecision(requestPermissions: Bool) {
        defaults.set(true, forKey: Self.decisionKey)
        if requestPermissions {
            // Preserve the existing key so users who already requested access
            // keep the settings-only recovery path after upgrading.
            defaults.set(true, forKey: Self.systemRequestKey)
        }
    }
}
