import AppKit
import Darwin
import ObjectiveC.runtime
import OSLog

/// macOS 27 moved third-party status items into MenuBarAgent. Its private
/// assessment-mode assertion is the only observed system interface that hides
/// selected hosted items without borrowing the system `«` overflow UI.
///
/// Everything is resolved dynamically so macOS 14–26 never load or link a
/// private framework. A failure is fail-open: FoldBar keeps the real items
/// visible and does not commit a new managed bundle.
@MainActor
final class MenuBarVisibilityRestriction {
    nonisolated struct RunningApplicationIdentity: Equatable {
        let bundleIdentifier: String
        let processIdentifier: pid_t
    }

    nonisolated struct ConfigurationKey: Equatable {
        let hiddenBundleIdentifiers: Set<String>
        let allowedBundleIdentifiers: [String]
        let statusItemApplicationGenerations: [String]
    }

    nonisolated private static let logger = Logger(
        subsystem: "local.foldbar.app",
        category: "VisibilityRestriction"
    )

    /// `MBAssessmentModeConfiguration` accepts the raw NSNumber values of
    /// `MBSystemItemIdentifier`, not their display strings. macOS 27 currently
    /// defines the system-item cases in this contiguous range. Including the
    /// full range keeps Control Center, battery, Wi-Fi, clock, and the other
    /// system indicators visible while third-party bundles are restricted.
    nonisolated static let allSystemItemRawValues = Array(0...15)

    private typealias Allocate = @convention(c) (
        AnyClass,
        Selector
    ) -> Unmanaged<AnyObject>?
    private typealias Initialize = @convention(c) (
        AnyObject,
        Selector
    ) -> Unmanaged<AnyObject>?
    private typealias InitializeConfiguration = @convention(c) (
        AnyObject,
        Selector,
        NSArray,
        NSArray
    ) -> Unmanaged<AnyObject>?
    private typealias ActivationReply = @convention(block) (NSError?) -> Void
    private typealias Activate = @convention(c) (
        AnyObject,
        Selector,
        AnyObject,
        ActivationReply
    ) -> Void
    private typealias SendVoid = @convention(c) (
        AnyObject,
        Selector
    ) -> Void

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var activeAssertion: AnyObject?
    private var activeConfigurationKey: ConfigurationKey?
    private var isInvalidated = false
    private var requestGeneration: UInt64 = 0

    nonisolated static func isSupported(on majorVersion: Int) -> Bool {
        majorVersion >= 27
    }

    /// Computes the application allowlist sent to MenuBarAgent. System items
    /// have a separate allowlist and are always preserved.
    nonisolated static func allowedBundleIdentifiers(
        runningBundleIdentifiers: [String],
        hiddenBundleIdentifiers: Set<String>,
        ownBundleIdentifier: String?
    ) -> [String] {
        var allowed = Set(
            runningBundleIdentifiers.filter { !$0.isEmpty }
        ).subtracting(hiddenBundleIdentifiers)
        if let ownBundleIdentifier, !ownBundleIdentifier.isEmpty {
            allowed.insert(ownBundleIdentifier)
        }
        return allowed.sorted()
    }

    nonisolated static func configurationKey(
        runningApplications: [RunningApplicationIdentity],
        statusItemApplications: [RunningApplicationIdentity],
        hiddenBundleIdentifiers: Set<String>,
        ownBundleIdentifier: String?
    ) -> ConfigurationKey {
        let allowed = allowedBundleIdentifiers(
            runningBundleIdentifiers: runningApplications.map(
                \.bundleIdentifier
            ),
            hiddenBundleIdentifiers: hiddenBundleIdentifiers,
            ownBundleIdentifier: ownBundleIdentifier
        )
        let allowedSet = Set(allowed)
        return ConfigurationKey(
            hiddenBundleIdentifiers: hiddenBundleIdentifiers,
            allowedBundleIdentifiers: allowed,
            // MenuBarAgent can bind an allowlisted bundle to the application
            // generation publishing the status item when the assertion is
            // activated. Track only observed, un-managed menu-extra owners so
            // ordinary application and helper launches do not churn assertions.
            statusItemApplicationGenerations: Set(
                statusItemApplications.compactMap { application in
                    guard allowedSet.contains(application.bundleIdentifier) else {
                        return nil
                    }
                    return "\(application.bundleIdentifier)|\(application.processIdentifier)"
                }
            ).sorted()
        )
    }

    nonisolated static func requiresRegistrationReset(
        previous: ConfigurationKey?,
        next: ConfigurationKey
    ) -> Bool {
        guard let previous,
              previous.hiddenBundleIdentifiers == next.hiddenBundleIdentifiers else {
            return false
        }
        return !Set(next.statusItemApplicationGenerations).subtracting(
            previous.statusItemApplicationGenerations
        ).isEmpty
    }

    /// Replaces FoldBar's private assertion. Managed membership changes remain
    /// atomic. A newly observed, un-managed application generation uses the
    /// bounded registration reset below because macOS 27 does not publish it
    /// while the stale assessment session remains continuously active.
    func apply(hiddenBundleIdentifiers: Set<String>) async -> Bool {
        guard Self.isSupported(
            on: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ) else { return hiddenBundleIdentifiers.isEmpty }
        guard !isInvalidated, !Task.isCancelled else { return false }
        requestGeneration &+= 1
        let generation = requestGeneration

        let runningApplications = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated }
            .compactMap { application -> RunningApplicationIdentity? in
                guard let bundleIdentifier = application.bundleIdentifier,
                      !bundleIdentifier.isEmpty else { return nil }
                return RunningApplicationIdentity(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: application.processIdentifier
                )
            }
        let statusItemApplications = MenuBarAccessibility.snapshots().map {
            snapshot in
            RunningApplicationIdentity(
                bundleIdentifier: snapshot.identity.bundleIdentifier,
                processIdentifier: snapshot.identity.processIdentifier
            )
        }
        let configurationKey = Self.configurationKey(
            runningApplications: runningApplications,
            statusItemApplications: statusItemApplications,
            hiddenBundleIdentifiers: hiddenBundleIdentifiers,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
        if configurationKey == activeConfigurationKey,
           activeAssertion != nil {
            return true
        }
        if hiddenBundleIdentifiers.isEmpty {
            invalidateActiveAssertion()
            return true
        }

        let requiresRegistrationReset = activeAssertion != nil
            && Self.requiresRegistrationReset(
                previous: activeConfigurationKey,
                next: configurationKey
            )
        if requiresRegistrationReset {
            // MenuBarAgent does not retroactively publish a menu extra from a
            // newly observed application generation while an older assessment
            // session remains continuously active. Briefly release only for
            // this reconciliation case, then reapply the unchanged managed set.
            invalidateActiveAssertion()
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil,
                  !Task.isCancelled,
                  !isInvalidated,
                  generation == requestGeneration else { return false }
        }

        guard loadPrivateFramework(),
              let configuration = makeConfiguration(
                  allowedBundleIdentifiers: configurationKey.allowedBundleIdentifiers
              ),
              let assertion = makeAssertion() else {
            Self.logger.error(
                "visibility assertion unavailable; leaving items visible"
            )
            return false
        }

        guard await activate(assertion, configuration: configuration) else {
            invalidate(assertion)
            return false
        }
        // Completion can arrive after cancellation, a newer request, or quit.
        // Never publish that retired assertion over the current managed set.
        guard !isInvalidated, !Task.isCancelled,
              generation == requestGeneration else {
            invalidate(assertion)
            return false
        }

        let previousAssertion = activeAssertion
        activeAssertion = assertion
        activeConfigurationKey = configurationKey
        if let previousAssertion {
            invalidate(previousAssertion)
        }
        return true
    }

    /// Invalidating the assertion restores real items. MenuBarAgent also drops
    /// it if FoldBar exits or loses the private connection, so failure is open.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        requestGeneration &+= 1
        invalidateActiveAssertion()
        // Private Objective-C classes and autoreleased transport objects may
        // outlive the assertion. Keep MenuBarClientCore loaded until process
        // exit rather than invalidating its code pages.
    }

    /// Restore real items after a recoverable capture failure while keeping
    /// this adapter available for a later user-initiated collapse.
    func releaseActiveRestriction() {
        guard !isInvalidated else { return }
        requestGeneration &+= 1
        invalidateActiveAssertion()
    }

    private func loadPrivateFramework() -> Bool {
        if frameworkHandle != nil { return true }
        frameworkHandle = dlopen(
            "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
            RTLD_NOW | RTLD_LOCAL
        )
        return frameworkHandle != nil
    }

    private func makeConfiguration(
        allowedBundleIdentifiers: [String]
    ) -> AnyObject? {
        guard let configurationClass = NSClassFromString(
            "MBAssessmentModeConfiguration"
        ) else {
            return nil
        }
        return Self.makeConfiguration(
            of: configurationClass,
            allowedBundleIdentifiers: allowedBundleIdentifiers
        )
    }

    /// Keep alloc's +1 outside ARC until the initializer consumes it. Calling
    /// either IMP through an AnyObject return would use the +0 autoreleased
    /// convention and leave the initializer's retained result unbalanced.
    static func makeConfiguration(
        of configurationClass: AnyClass,
        allowedBundleIdentifiers: [String]
    ) -> AnyObject? {
        let systemItems = Self.allSystemItemRawValues.map(
            NSNumber.init(value:)
        )
        let selector = NSSelectorFromString(
            "initWithAllowedSystemItems:allowedBundleIdentifiers:"
        )
        guard let implementation = Self.instanceImplementation(
            configurationClass,
            selector: selector
        ), let rawConfiguration = Self.allocate(configurationClass) else {
            return nil
        }
        return unsafeBitCast(
            implementation,
            to: InitializeConfiguration.self
        )(
            rawConfiguration.takeUnretainedValue(),
            selector,
            systemItems as NSArray,
            allowedBundleIdentifiers as NSArray
        )?.takeRetainedValue()
    }

    private func makeAssertion() -> AnyObject? {
        guard let assertionClass = NSClassFromString(
            "MBAssessmentModeAssertion"
        ) else {
            return nil
        }
        return Self.makeAssertion(of: assertionClass)
    }

    static func makeAssertion(of assertionClass: AnyClass) -> AnyObject? {
        let selector = NSSelectorFromString("init")
        guard let implementation = Self.instanceImplementation(
            assertionClass,
            selector: selector
        ), let rawAssertion = Self.allocate(assertionClass) else { return nil }
        return unsafeBitCast(implementation, to: Initialize.self)(
            rawAssertion.takeUnretainedValue(),
            selector
        )?.takeRetainedValue()
    }

    private func activate(
        _ assertion: AnyObject,
        configuration: AnyObject
    ) async -> Bool {
        let selector = NSSelectorFromString(
            "activateWithConfiguration:completionHandler:"
        )
        guard let implementation = Self.objectImplementation(
            assertion,
            selector: selector
        ) else { return false }
        let activate = unsafeBitCast(implementation, to: Activate.self)
        return await withCheckedContinuation { continuation in
            let reply: ActivationReply = { error in
                if let error {
                    Self.logger.error(
                        "visibility assertion activation failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume(returning: error == nil)
            }
            activate(assertion, selector, configuration, reply)
        }
    }

    private func invalidateActiveAssertion() {
        if let activeAssertion {
            invalidate(activeAssertion)
        }
        activeAssertion = nil
        activeConfigurationKey = nil
    }

    private func invalidate(_ assertion: AnyObject) {
        let selector = NSSelectorFromString("invalidate")
        guard let implementation = Self.objectImplementation(
            assertion,
            selector: selector
        ) else { return }
        unsafeBitCast(implementation, to: SendVoid.self)(assertion, selector)
    }

    private static func allocate(_ type: AnyClass) -> Unmanaged<AnyObject>? {
        let selector = NSSelectorFromString("alloc")
        guard let metaClass = object_getClass(type),
              let method = class_getInstanceMethod(metaClass, selector) else {
            return nil
        }
        return unsafeBitCast(
            method_getImplementation(method),
            to: Allocate.self
        )(type, selector)
    }

    private static func instanceImplementation(
        _ type: AnyClass,
        selector: Selector
    ) -> IMP? {
        class_getInstanceMethod(type, selector).map(method_getImplementation)
    }

    private static func objectImplementation(
        _ object: AnyObject,
        selector: Selector
    ) -> IMP? {
        guard let type = object_getClass(object) else { return nil }
        return class_getInstanceMethod(type, selector).map(
            method_getImplementation
        )
    }
}

enum ManagedMenuBarBundles {
    static let defaultsKey = "managedMenuBarBundleIdentifiersV1"

    static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(
        _ bundleIdentifiers: Set<String>,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(bundleIdentifiers.sorted(), forKey: defaultsKey)
    }
}
