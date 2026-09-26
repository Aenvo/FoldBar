import AppKit
import Darwin
import ObjectiveC.runtime
import OSLog

/// macOS 27 moved third-party status items into MenuBarAgent. Its private
/// visibility-restriction service is the only observed system interface that
/// hides those hosted items without borrowing the system `«` overflow UI.
///
/// Everything is resolved dynamically so macOS 14–26 never load or link a
/// private framework. A connection failure is fail-open: FoldBar keeps the real
/// items visible and does not commit a new managed bundle.
@MainActor
final class MenuBarVisibilityRestriction: NSObject {
    nonisolated private static let logger = Logger(
        subsystem: "local.foldbar.app",
        category: "VisibilityRestriction"
    )

    nonisolated static let allSystemItems = [
        "battery",
        "bluetooth",
        "clock",
        "displays",
        "keyboard",
        "volume",
        "wifi",
        "screenMirroring",
        "primaryBentoBox",
    ]

    private typealias MakeEndpoint = @convention(c) (
        AnyClass,
        Selector,
        NSString,
        AnyObject,
        NSString?
    ) -> AnyObject?
    private typealias MakeConnection = @convention(c) (
        AnyClass,
        Selector,
        AnyObject
    ) -> AnyObject?
    private typealias ClassSendObject = @convention(c) (
        AnyClass,
        Selector,
        AnyObject
    ) -> AnyObject?
    private typealias ClassSendTwoObjects = @convention(c) (
        AnyClass,
        Selector,
        AnyObject,
        AnyObject
    ) -> AnyObject?
    private typealias ConfigurationBlock = @convention(block) (AnyObject) -> Void
    private typealias Configure = @convention(c) (
        AnyObject,
        Selector,
        ConfigurationBlock
    ) -> Void
    private typealias SendSetter = @convention(c) (
        AnyObject,
        Selector,
        AnyObject
    ) -> Void
    private typealias SendVoid = @convention(c) (AnyObject, Selector) -> Void
    private typealias SendNoArgument = @convention(c) (
        AnyObject,
        Selector
    ) -> AnyObject?
    private typealias Reply = @convention(block) (NSError?) -> Void
    private typealias Acquire = @convention(c) (
        AnyObject,
        Selector,
        NSString,
        NSNumber,
        NSArray,
        NSArray,
        Reply
    ) -> Void
    private typealias Release = @convention(c) (
        AnyObject,
        Selector,
        NSString,
        Reply
    ) -> Void

    private var frameworkHandles: [UnsafeMutableRawPointer] = []
    private var serviceConnection: AnyObject?
    private var remoteTarget: AnyObject?
    private var activeAssertionID: String?
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

    /// Atomically replaces FoldBar's assertion. The replacement is acquired
    /// before the previous assertion is released, avoiding an all-visible flash
    /// while membership changes.
    func apply(hiddenBundleIdentifiers: Set<String>) async -> Bool {
        guard Self.isSupported(
            on: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ) else { return hiddenBundleIdentifiers.isEmpty }
        guard !isInvalidated else { return false }

        if hiddenBundleIdentifiers.isEmpty {
            return await releaseActiveAssertion()
        }
        guard ensureConnection(), let proxy = remoteTarget else {
            Self.logger.error("visibility service unavailable; leaving items visible")
            return false
        }

        let allowedBundles = Self.allowedBundleIdentifiers(
            runningBundleIdentifiers: NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier),
            hiddenBundleIdentifiers: hiddenBundleIdentifiers,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
        let newAssertionID = "local.foldbar.visibility.\(UUID().uuidString)"
        guard await acquire(
            assertionID: newAssertionID,
            allowedBundleIdentifiers: allowedBundles,
            proxy: proxy
        ) else { return false }

        let previousAssertionID = activeAssertionID
        activeAssertionID = newAssertionID
        if let previousAssertionID {
            _ = await release(assertionID: previousAssertionID, proxy: proxy)
        }
        return true
    }

    /// Releases the active assertion and tears down the XPC transport. A dead
    /// connection also invalidates its server-side assertion, so quit/crash is
    /// fail-open even when the asynchronous release cannot complete.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if let assertionID = activeAssertionID, let proxy = remoteTarget {
            releaseWithoutWaiting(assertionID: assertionID, proxy: proxy)
        }
        activeAssertionID = nil
        if let serviceConnection {
            Self.sendVoid(serviceConnection, selectorName: "invalidate")
        }
        serviceConnection = nil
        remoteTarget = nil
        // Private Objective-C classes and autoreleased transport objects may
        // outlive the explicit connection. Keep the two system frameworks
        // loaded until process exit rather than invalidating their code pages.
    }

    @objc nonisolated dynamic func visibilityRestrictionsDidChange(
        _ value: NSNumber
    ) {
        Self.logger.debug(
            "MenuBarAgent visibility restriction state=\(value.boolValue, privacy: .public)"
        )
    }

    private func ensureConnection() -> Bool {
        if remoteTarget != nil { return true }
        guard loadPrivateFrameworks(),
              let endpointClass = NSClassFromString("BSServiceConnectionEndpoint"),
              let connectionClass = NSClassFromString("BSServiceConnection"),
              let protocolClass = NSClassFromString("BSObjCProtocol"),
              let interfaceClass = NSClassFromString("BSServiceInterface"),
              let serverProtocol = NSProtocolFromString(
                  "MBVisibilityRestrictionXPCServer"
              ),
              let clientProtocol = NSProtocolFromString(
                  "MBVisibilityRestrictionXPCClient"
              ) else { return false }

        let endpointSelector = NSSelectorFromString(
            "endpointForMachName:service:instance:"
        )
        guard let endpointImplementation = Self.classImplementation(
            endpointClass,
            selector: endpointSelector
        ) else { return false }
        let makeEndpoint = unsafeBitCast(
            endpointImplementation,
            to: MakeEndpoint.self
        )
        guard let endpoint = makeEndpoint(
            endpointClass,
            endpointSelector,
            "com.apple.MenuBarAgent.systemservices",
            "com.apple.MenuBarAgent.visibility-restriction" as NSString,
            nil
        ) else { return false }

        let connectionSelector = NSSelectorFromString("connectionWithEndpoint:")
        guard let connectionImplementation = Self.classImplementation(
            connectionClass,
            selector: connectionSelector
        ) else { return false }
        let makeConnection = unsafeBitCast(
            connectionImplementation,
            to: MakeConnection.self
        )
        guard let connection = makeConnection(
            connectionClass,
            connectionSelector,
            endpoint
        ) else { return false }

        let wrapSelector = NSSelectorFromString("protocolForProtocol:")
        guard let wrapImplementation = Self.classImplementation(
            protocolClass,
            selector: wrapSelector
        ) else { return false }
        let wrapProtocol = unsafeBitCast(
            wrapImplementation,
            to: ClassSendObject.self
        )
        guard let wrappedServer = wrapProtocol(
            protocolClass,
            wrapSelector,
            serverProtocol
        ), let wrappedClient = wrapProtocol(
            protocolClass,
            wrapSelector,
            clientProtocol
        ) else { return false }

        let interfaceSelector = NSSelectorFromString("interfaceWithServer:client:")
        guard let interfaceImplementation = Self.classImplementation(
            interfaceClass,
            selector: interfaceSelector
        ) else { return false }
        let makeInterface = unsafeBitCast(
            interfaceImplementation,
            to: ClassSendTwoObjects.self
        )
        guard let interface = makeInterface(
            interfaceClass,
            interfaceSelector,
            wrappedServer,
            wrappedClient
        ) else { return false }

        let invalidationHandler: @convention(block) () -> Void = {
            Self.logger.error("MenuBarAgent visibility connection invalidated")
        }
        let configurationBlock: ConfigurationBlock = { configuration in
            Self.set(configuration, selectorName: "setInterface:", value: interface)
            Self.set(configuration, selectorName: "setLocalTarget:", value: self)
            Self.set(
                configuration,
                selectorName: "setInvalidationHandler:",
                value: invalidationHandler as AnyObject
            )
        }
        guard Self.configure(connection, block: configurationBlock) else {
            return false
        }
        Self.sendVoid(connection, selectorName: "activate")
        guard let proxy = Self.sendObject(
            connection,
            selectorName: "remoteTarget"
        ) else {
            Self.sendVoid(connection, selectorName: "invalidate")
            return false
        }
        serviceConnection = connection
        remoteTarget = proxy
        return true
    }

    private func loadPrivateFrameworks() -> Bool {
        if frameworkHandles.count == 2 { return true }
        let paths = [
            "/System/Library/PrivateFrameworks/BaseBoard.framework/BaseBoard",
            "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
        ]
        var handles: [UnsafeMutableRawPointer] = []
        for path in paths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                handles.forEach { dlclose($0) }
                return false
            }
            handles.append(handle)
        }
        frameworkHandles = handles
        return true
    }

    private func acquire(
        assertionID: String,
        allowedBundleIdentifiers: [String],
        proxy: AnyObject
    ) async -> Bool {
        guard let objcMessageSend = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "objc_msgSend"
        ) else { return false }
        let send = unsafeBitCast(objcMessageSend, to: Acquire.self)
        let selector = NSSelectorFromString(
            "acquireAssertionWithID:origin:allowedSystemItems:allowedBundleIdentifiers:completionHandler:"
        )
        return await withCheckedContinuation { continuation in
            let reply: Reply = { error in
                if let error {
                    Self.logger.error(
                        "visibility assertion acquire failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume(returning: error == nil)
            }
            send(
                proxy,
                selector,
                assertionID as NSString,
                0 as NSNumber,
                Self.allSystemItems as NSArray,
                allowedBundleIdentifiers as NSArray,
                reply
            )
        }
    }

    private func releaseActiveAssertion() async -> Bool {
        guard let assertionID = activeAssertionID else { return true }
        guard let proxy = remoteTarget else {
            activeAssertionID = nil
            return true
        }
        let released = await release(assertionID: assertionID, proxy: proxy)
        if released { activeAssertionID = nil }
        return released
    }

    private func release(assertionID: String, proxy: AnyObject) async -> Bool {
        guard let objcMessageSend = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "objc_msgSend"
        ) else { return false }
        let send = unsafeBitCast(objcMessageSend, to: Release.self)
        let selector = NSSelectorFromString(
            "releaseAssertionWithID:completionHandler:"
        )
        return await withCheckedContinuation { continuation in
            let reply: Reply = { error in
                if let error {
                    Self.logger.error(
                        "visibility assertion release failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume(returning: error == nil)
            }
            send(proxy, selector, assertionID as NSString, reply)
        }
    }

    private func releaseWithoutWaiting(
        assertionID: String,
        proxy: AnyObject
    ) {
        guard let objcMessageSend = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "objc_msgSend"
        ) else { return }
        let send = unsafeBitCast(objcMessageSend, to: Release.self)
        let reply: Reply = { _ in }
        send(
            proxy,
            NSSelectorFromString("releaseAssertionWithID:completionHandler:"),
            assertionID as NSString,
            reply
        )
    }

    private static func classImplementation(
        _ type: AnyClass,
        selector: Selector
    ) -> IMP? {
        class_getMethodImplementation(object_getClass(type), selector)
    }

    private static func configure(
        _ object: AnyObject,
        block: ConfigurationBlock
    ) -> Bool {
        let selector = NSSelectorFromString("configure:")
        guard let implementation = class_getMethodImplementation(
            object_getClass(object),
            selector
        ) else { return false }
        unsafeBitCast(implementation, to: Configure.self)(object, selector, block)
        return true
    }

    private static func set(
        _ object: AnyObject,
        selectorName: String,
        value: AnyObject
    ) {
        let selector = NSSelectorFromString(selectorName)
        guard let implementation = class_getMethodImplementation(
            object_getClass(object),
            selector
        ) else { return }
        unsafeBitCast(implementation, to: SendSetter.self)(
            object,
            selector,
            value
        )
    }

    private static func sendVoid(
        _ object: AnyObject,
        selectorName: String
    ) {
        let selector = NSSelectorFromString(selectorName)
        guard let implementation = class_getMethodImplementation(
            object_getClass(object),
            selector
        ) else { return }
        unsafeBitCast(implementation, to: SendVoid.self)(object, selector)
    }

    private static func sendObject(
        _ object: AnyObject,
        selectorName: String
    ) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard let implementation = class_getMethodImplementation(
            object_getClass(object),
            selector
        ) else { return nil }
        return unsafeBitCast(implementation, to: SendNoArgument.self)(
            object,
            selector
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
