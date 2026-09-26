import AppKit

/// Discovers the status-item windows without private APIs.
///
/// macOS 26 hosts many third-party status items inside Control Center, so the
/// process owner is not a reliable identity. macOS 27 stops publishing those
/// hosted items as individual WindowServer windows, so discovery switches to
/// public AXMenuExtra elements while preserving the same geometry pipeline.
/// The collapsed separator is found by its distinctive multi-thousand-point
/// width, then the contiguous run to its left is treated as the overflow.
enum MenuBarItemScanner {
    private static let separatorMinWidth: CGFloat = 2_500
    private static let contiguityGap: CGFloat = 50

    static var usesAccessibilityBackend: Bool {
        usesAccessibilityBackend(
            for: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }

    static func usesAccessibilityBackend(for majorVersion: Int) -> Bool {
        majorVersion >= 27
    }

    @MainActor
    static func refreshStatusWindows(force: Bool = false) async {
        guard usesAccessibilityBackend else { return }
        await MenuBarAccessibility.refresh(force: force)
    }

    @MainActor
    static func hiddenItems() -> [MenuBarItemWindow] {
        if usesAccessibilityBackend {
            return systemOverflowHiddenItems(
                among: statusWindows(),
                overflowFrame: MenuBarAccessibility.systemOverflowFrame()
            )
        }
        return hiddenItems(among: statusWindows())
    }

    @MainActor
    static func systemOverflowFrame() -> CGRect? {
        guard usesAccessibilityBackend else { return nil }
        return MenuBarAccessibility.systemOverflowFrame()
    }

    @MainActor
    static func systemOverflowHiddenItems() -> [MenuBarItemWindow] {
        systemOverflowHiddenItems(
            among: statusWindows(),
            overflowFrame: MenuBarAccessibility.systemOverflowFrame()
        )
    }

    @MainActor
    static func systemOverflowVisibleItems() -> [MenuBarItemWindow] {
        systemOverflowVisibleItems(
            among: statusWindows(),
            overflowFrame: MenuBarAccessibility.systemOverflowFrame()
        )
    }

    /// Finds this app's managed section while the separator is at its normal
    /// width. Capturing at this point avoids the visible flash that would be
    /// caused by expanding the separator after the user opens the panel.
    @MainActor
    static func itemsLeft(of separatorMinX: CGFloat) -> [MenuBarItemWindow] {
        itemsLeft(of: separatorMinX, among: statusWindows())
    }

    static func itemsLeft(
        of separatorMinX: CGFloat,
        among windows: [MenuBarItemWindow]
    ) -> [MenuBarItemWindow] {
        var edge = separatorMinX
        var result: [MenuBarItemWindow] = []
        let candidates = windows
            .filter {
                $0.frame.maxX <= separatorMinX + 1
                    && $0.frame.width < separatorMinWidth
                    && $0.frame.height <= 40
            }
            .sorted { $0.frame.maxX > $1.frame.maxX }

        for window in candidates {
            guard edge - window.frame.maxX <= contiguityGap else { break }
            result.append(window)
            edge = window.frame.minX
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func hiddenItems(among windows: [MenuBarItemWindow]) -> [MenuBarItemWindow] {
        guard let separator = windows
            .filter({ $0.frame.width >= separatorMinWidth })
            .max(by: { $0.frame.minX < $1.frame.minX })
        else { return [] }

        var edge = separator.frame.minX
        var result: [MenuBarItemWindow] = []
        let candidates = windows
            .filter { $0.frame.maxX <= separator.frame.minX + 1 && $0.frame.width < separatorMinWidth }
            .sorted { $0.frame.maxX > $1.frame.maxX }

        for window in candidates {
            guard edge - window.frame.maxX <= contiguityGap else { break }
            result.append(window)
            edge = window.frame.minX
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// macOS 27 retains virtual Accessibility frames for native-overflow items.
    /// The hidden frames end at, or overlap, MenuBarAgent's `«` button; the
    /// first truly visible app item begins to its right. Using this system-owned
    /// boundary prevents a visible item from also appearing in FoldBar.
    static func systemOverflowHiddenItems(
        among windows: [MenuBarItemWindow],
        overflowFrame: CGRect?
    ) -> [MenuBarItemWindow] {
        guard let overflowFrame else { return [] }
        return panelDisplayOrder(windows.filter {
            isHiddenBySystemOverflow($0.frame, overflowFrame: overflowFrame)
        })
    }

    static func systemOverflowVisibleItems(
        among windows: [MenuBarItemWindow],
        overflowFrame: CGRect?
    ) -> [MenuBarItemWindow] {
        guard let overflowFrame else { return [] }
        return panelDisplayOrder(windows.filter {
            isVisibleBySystemOverflow($0.frame, overflowFrame: overflowFrame)
        })
    }

    static func isHiddenBySystemOverflow(
        _ frame: CGRect,
        overflowFrame: CGRect
    ) -> Bool {
        frame.minX < overflowFrame.maxX + 1
    }

    static func isVisibleBySystemOverflow(
        _ frame: CGRect,
        overflowFrame: CGRect
    ) -> Bool {
        !isHiddenBySystemOverflow(frame, overflowFrame: overflowFrame)
    }

    /// The native overflow control keeps collapsed items' virtual AX frames
    /// overlapping its own slot. When the user expands `«`, those same item
    /// identities move into distinct, fully visible slots to its left. This
    /// geometry check avoids depending on the control's localized label.
    static func systemOverflowItemsAreExpanded(
        _ items: [MenuBarItemWindow],
        overflowFrame: CGRect?
    ) -> Bool {
        guard let overflowFrame, !items.isEmpty else { return false }
        return items.allSatisfy {
            $0.frame.maxX <= overflowFrame.minX - 1
        }
    }

    /// Keeps the panel in the same left-to-right order as the real menu bar.
    /// This makes each proxy's position predictable when the user compares the
    /// collapsed panel with the system-owned items after expanding it.
    static func panelDisplayOrder(
        _ windows: [MenuBarItemWindow]
    ) -> [MenuBarItemWindow] {
        windows.sorted {
            if $0.frame.minX == $1.frame.minX { return $0.id < $1.id }
            return $0.frame.minX < $1.frame.minX
        }
    }

    static func newlyManagedItems(
        among windows: [MenuBarItemWindow],
        excluding knownIDs: Set<CGWindowID>
    ) -> [MenuBarItemWindow] {
        panelDisplayOrder(windows.filter { !knownIDs.contains($0.id) })
    }

    @MainActor
    static func frame(of id: CGWindowID) -> CGRect? {
        statusWindows().first { $0.id == id }?.frame
    }

    /// Performs the narrow live lookup used by macOS 27 import verification.
    /// The ordinary refresh remains appropriate for background inventory
    /// updates, but it scans every running application and is too expensive on
    /// the direct manipulation path.
    @MainActor
    static func refreshStatusWindow(
        _ item: MenuBarItemWindow
    ) -> MenuBarItemWindow? {
        guard usesAccessibilityBackend,
              let identity = item.accessibilityIdentity,
              let snapshot = MenuBarAccessibility.refreshSnapshot(
                  for: identity,
                  id: item.id,
                  expectedLabel: item.windowName
              ) else { return nil }
        return MenuBarItemWindow(
            id: snapshot.id,
            frame: snapshot.frame,
            ownerName: snapshot.ownerName,
            windowName: snapshot.label,
            accessibilityIdentity: snapshot.identity,
            ownerProcessIdentifier: snapshot.identity.processIdentifier,
            bundleIdentifier: snapshot.identity.bundleIdentifier
        )
    }

    @MainActor
    static func refreshSystemOverflowFrame() -> CGRect? {
        guard usesAccessibilityBackend else { return nil }
        return MenuBarAccessibility.refreshSystemOverflowFrame()
    }

    @MainActor
    static func statusItemFingerprint() -> Set<String> {
        Set(statusWindows().map { "\($0.id)@\(Int($0.frame.minX.rounded()))" })
    }

    @MainActor
    static func statusWindows() -> [MenuBarItemWindow] {
        if usesAccessibilityBackend {
            return MenuBarAccessibility.snapshots().map { snapshot in
                MenuBarItemWindow(
                    id: snapshot.id,
                    frame: snapshot.frame,
                    ownerName: snapshot.ownerName,
                    windowName: snapshot.label,
                    accessibilityIdentity: snapshot.identity,
                    ownerProcessIdentifier: snapshot.identity.processIdentifier,
                    bundleIdentifier: snapshot.identity.bundleIdentifier
                )
            }
        }

        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLayer,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 0, frame.height > 0
            else { return nil }
            return MenuBarItemWindow(
                id: id,
                frame: frame,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                windowName: info[kCGWindowName as String] as? String ?? "",
                nativeWindowID: id,
                ownerProcessIdentifier: info[kCGWindowOwnerPID as String] as? pid_t
            )
        }
    }
}
