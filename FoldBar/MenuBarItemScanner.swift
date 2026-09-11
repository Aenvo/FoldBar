import AppKit

/// Discovers the status-item windows without private APIs.
///
/// macOS 26 hosts many third-party status items inside Control Center, so the
/// process owner is not a reliable identity. The collapsed separator is found
/// by its distinctive multi-thousand-point width, then the contiguous run to
/// its left is treated as this app's overflow section.
enum MenuBarItemScanner {
    private static let separatorMinWidth: CGFloat = 2_500
    private static let contiguityGap: CGFloat = 50

    static func hiddenItems() -> [MenuBarItemWindow] {
        hiddenItems(among: statusWindows())
    }

    /// Finds this app's managed section while the separator is at its normal
    /// width. Capturing at this point avoids the visible flash that would be
    /// caused by expanding the separator after the user opens the panel.
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

    static func frame(of id: CGWindowID) -> CGRect? {
        statusWindows().first { $0.id == id }?.frame
    }

    static func statusItemFingerprint() -> Set<String> {
        Set(statusWindows().map { "\($0.id)@\(Int($0.frame.minX.rounded()))" })
    }

    static func statusWindows() -> [MenuBarItemWindow] {
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
                windowName: info[kCGWindowName as String] as? String ?? ""
            )
        }
    }
}
