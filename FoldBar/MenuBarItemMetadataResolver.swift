import AppKit
import ApplicationServices

struct MenuBarItemAccessibilityMetadata: Equatable, Sendable {
    let frame: CGRect
    let label: String
    let processIdentifier: pid_t?

    init(frame: CGRect, label: String, processIdentifier: pid_t? = nil) {
        self.frame = frame
        self.label = label
        self.processIdentifier = processIdentifier
    }
}

enum MenuBarItemMetadataResolver {
    private struct RunningApplicationIdentity: Sendable {
        let processIdentifier: pid_t
        let name: String
    }

    private static let horizontalCenterTolerance: CGFloat = 3
    private static let verticalCenterTolerance: CGFloat = 6
    private static let genericLabels = Set([
        "Control Center",
        "控制中心",
        "Item-0",
        "Menu bar item",
        "菜单栏图标",
        "Status menu",
        "状态菜单"
    ])

    @MainActor
    static func labels(for windows: [MenuBarItemWindow]) async -> [CGWindowID: String] {
        let resolved = await metadata(for: windows)
        return resolved.mapValues(\.label)
    }

    @MainActor
    static func metadata(
        for windows: [MenuBarItemWindow]
    ) async -> [CGWindowID: MenuBarItemAccessibilityMetadata] {
        guard !windows.isEmpty, AXIsProcessTrusted() else { return [:] }

        let applications: [RunningApplicationIdentity] = NSWorkspace.shared.runningApplications.compactMap { application in
            guard !application.isTerminated else { return nil }
            return RunningApplicationIdentity(
                processIdentifier: application.processIdentifier,
                name: application.localizedName ?? ""
            )
        }
        let task = Task.detached(priority: .utility) {
            scanMetadata(for: windows, applications: applications)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func scanMetadata(
        for windows: [MenuBarItemWindow],
        applications: [RunningApplicationIdentity]
    ) -> [CGWindowID: MenuBarItemAccessibilityMetadata] {
        var metadata: [MenuBarItemAccessibilityMetadata] = []
        for application in applications {
            guard !Task.isCancelled else { break }
            let appElement = AXUIElementCreateApplication(application.processIdentifier)

            // A status item is exposed as an AXMenuExtra inside a small
            // AXMenuBar child of its owning application. Looking only at these
            // containers avoids walking every application's complete UI tree.
            for container in children(of: appElement)
            where stringAttribute(container, kAXRoleAttribute) == "AXMenuBar" {
                for item in children(of: container)
                where stringAttribute(item, kAXSubroleAttribute) == "AXMenuExtra" {
                    guard let frame = frame(of: item),
                          frame.width > 0,
                          frame.height > 0,
                          let label = preferredLabel(
                            help: stringAttribute(item, kAXHelpAttribute),
                            description: stringAttribute(item, kAXDescriptionAttribute),
                            title: stringAttribute(item, kAXTitleAttribute),
                            appName: application.name
                          ) else { continue }
                    metadata.append(.init(
                        frame: frame,
                        label: label,
                        processIdentifier: application.processIdentifier
                    ))
                }
            }
        }
        return matchMetadata(windows: windows, metadata: metadata)
    }

    static func match(
        windows: [MenuBarItemWindow],
        metadata: [MenuBarItemAccessibilityMetadata]
    ) -> [CGWindowID: String] {
        matchMetadata(windows: windows, metadata: metadata).mapValues(\.label)
    }

    static func matchMetadata(
        windows: [MenuBarItemWindow],
        metadata: [MenuBarItemAccessibilityMetadata]
    ) -> [CGWindowID: MenuBarItemAccessibilityMetadata] {
        var remaining = metadata
        var result: [CGWindowID: MenuBarItemAccessibilityMetadata] = [:]

        for window in windows {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            guard let index = remaining.indices
                .filter({ candidate in
                    framesReferToSameStatusItem(
                        remaining[candidate].frame,
                        window.frame
                    )
                })
                .min(by: { lhs, rhs in
                    centerDistanceSquared(remaining[lhs].frame, center: center)
                        < centerDistanceSquared(remaining[rhs].frame, center: center)
                }) else { continue }

            result[window.id] = remaining[index]
            remaining.remove(at: index)
        }
        return result
    }

    /// Control Center moves the Quartz status window before the owning app's
    /// AXMenuExtra updates its anchor. A forwarded click in that interval can
    /// open the target popover at the old off-screen position even though the
    /// real icon is already visible. Require both representations to agree.
    static func hasSynchronizedMenuExtra(
        ownerProcessIdentifier: pid_t,
        matching windowFrame: CGRect
    ) -> Bool {
        let application = AXUIElementCreateApplication(ownerProcessIdentifier)
        for container in children(of: application)
        where stringAttribute(container, kAXRoleAttribute) == "AXMenuBar" {
            for item in children(of: container)
            where stringAttribute(item, kAXSubroleAttribute) == "AXMenuExtra" {
                guard let accessibilityFrame = frame(of: item) else { continue }
                if framesReferToSameStatusItem(accessibilityFrame, windowFrame) {
                    return true
                }
            }
        }
        return false
    }

    static func framesReferToSameStatusItem(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.midX - rhs.midX) <= horizontalCenterTolerance
            && abs(lhs.midY - rhs.midY) <= verticalCenterTolerance
    }

    static func preferredLabel(
        help: String,
        description: String,
        title: String,
        appName: String
    ) -> String? {
        [help, description, title, appName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !genericLabels.contains($0) }
    }

    private static func centerDistanceSquared(_ frame: CGRect, center: CGPoint) -> CGFloat {
        let dx = frame.midX - center.x
        let dy = frame.midY - center.y
        return dx * dx + dy * dy
    }

    private static func attribute(
        _ element: AXUIElement,
        _ name: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
