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
    ) -> AnyObject?
    private typealias Initialize = @convention(c) (
        AnyObject,
        Selector
    ) -> AnyObject?
    private typealias InitializeConfiguration = @convention(c) (
        AnyObject,
        Selector,
        NSArray,
        NSArray
    ) -> AnyObject?
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
    private var activeHiddenBundleIdentifiers: Set<String> = []
    private var isInvalidated = false

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

    /// Atomically replaces FoldBar's private assertion. The replacement is
    /// activated before the previous one is invalidated, avoiding an
    /// all-visible flash while membership changes.
    func apply(hiddenBundleIdentifiers: Set<String>) async -> Bool {
        guard Self.isSupported(
            on: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ) else { return hiddenBundleIdentifiers.isEmpty }
        guard !isInvalidated else { return false }

        if hiddenBundleIdentifiers == activeHiddenBundleIdentifiers,
           activeAssertion != nil {
            return true
        }
        if hiddenBundleIdentifiers.isEmpty {
            invalidateActiveAssertion()
            return true
        }

        guard loadPrivateFramework(),
              let configuration = makeConfiguration(
                  hiddenBundleIdentifiers: hiddenBundleIdentifiers
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

        let previousAssertion = activeAssertion
        activeAssertion = assertion
        activeHiddenBundleIdentifiers = hiddenBundleIdentifiers
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
        invalidateActiveAssertion()
        // Private Objective-C classes and autoreleased transport objects may
        // outlive the assertion. Keep MenuBarClientCore loaded until process
        // exit rather than invalidating its code pages.
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
        hiddenBundleIdentifiers: Set<String>
    ) -> AnyObject? {
        guard let configurationClass = NSClassFromString(
            "MBAssessmentModeConfiguration"
        ), let rawConfiguration = Self.allocate(configurationClass) else {
            return nil
        }

        let allowedBundles = Self.allowedBundleIdentifiers(
            runningBundleIdentifiers: NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier),
            hiddenBundleIdentifiers: hiddenBundleIdentifiers,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
        let systemItems = Self.allSystemItemRawValues.map(
            NSNumber.init(value:)
        )
        let selector = NSSelectorFromString(
            "initWithAllowedSystemItems:allowedBundleIdentifiers:"
        )
        guard let implementation = Self.instanceImplementation(
            configurationClass,
            selector: selector
        ) else { return nil }
        return unsafeBitCast(
            implementation,
            to: InitializeConfiguration.self
        )(
            rawConfiguration,
            selector,
            systemItems as NSArray,
            allowedBundles as NSArray
        )
    }

    private func makeAssertion() -> AnyObject? {
        guard let assertionClass = NSClassFromString(
            "MBAssessmentModeAssertion"
        ), let rawAssertion = Self.allocate(assertionClass) else {
            return nil
        }
        let selector = NSSelectorFromString("init")
        guard let implementation = Self.instanceImplementation(
            assertionClass,
            selector: selector
        ) else { return nil }
        return unsafeBitCast(implementation, to: Initialize.self)(
            rawAssertion,
            selector
        )
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
        activeHiddenBundleIdentifiers = []
    }

    private func invalidate(_ assertion: AnyObject) {
        let selector = NSSelectorFromString("invalidate")
        guard let implementation = Self.objectImplementation(
            assertion,
            selector: selector
        ) else { return }
        unsafeBitCast(implementation, to: SendVoid.self)(assertion, selector)
    }

    private static func allocate(_ type: AnyClass) -> AnyObject? {
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
