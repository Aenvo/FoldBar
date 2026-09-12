import AppKit

struct ActivationWindowRecord: Equatable, Sendable {
    let id: CGWindowID
    let ownerProcessIdentifier: pid_t
    let layer: Int
    let frame: CGRect
    let alpha: CGFloat
}

enum ActivationWindowScanner {
    static func visibleAuxiliaryWindowIDs(
        ownerProcessIdentifier: pid_t,
        on displayBounds: CGRect
    ) -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo(
            .optionAll,
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let records = list.compactMap { info -> ActivationWindowRecord? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return ActivationWindowRecord(
                id: id,
                ownerProcessIdentifier: owner,
                layer: layer,
                frame: frame,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)
                    .map { CGFloat($0.doubleValue) } ?? 1
            )
        }
        return candidateIDs(
            ownerProcessIdentifier: ownerProcessIdentifier,
            on: displayBounds,
            statusWindowLayer: Int(CGWindowLevelForKey(.statusWindow)),
            among: records
        )
    }

    static func candidateIDs(
        ownerProcessIdentifier: pid_t,
        on displayBounds: CGRect,
        statusWindowLayer: Int,
        among windows: [ActivationWindowRecord]
    ) -> Set<CGWindowID> {
        Set(windows.compactMap { window in
            guard window.ownerProcessIdentifier == ownerProcessIdentifier,
                  window.layer != statusWindowLayer,
                  window.alpha > 0,
                  window.frame.width >= 20,
                  window.frame.height >= 20,
                  window.frame.intersects(displayBounds)
            else { return nil }
            return window.id
        })
    }
}
