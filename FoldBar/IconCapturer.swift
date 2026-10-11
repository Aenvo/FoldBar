import AppKit
import OSLog
import ScreenCaptureKit

@MainActor
enum IconCapturer {
    private static let logger = Logger(subsystem: "local.foldbar.app", category: "IconCapture")
    private struct ShareableContentResult: @unchecked Sendable {
        let content: SCShareableContent?
    }

    static var requiresScreenCapturePermission: Bool {
        true
    }

    static func hasPermission() -> Bool {
        !requiresScreenCapturePermission || CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        guard requiresScreenCapturePermission else { return }
        CGRequestScreenCaptureAccess()
    }

    private static func scale(for frame: CGRect) -> CGFloat {
        let midX = frame.midX
        let screen = NSScreen.screens.first { $0.frame.minX <= midX && midX < $0.frame.maxX }
        return (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
    }

    static func capture(
        _ windows: [MenuBarItemWindow],
        allowAccessibilityRegionCapture: Bool = true
    ) async -> [CapturedItem] {
        // macOS 27 callers validate the visible frame before reaching here and
        // capture before the private assertion hides its owning bundle.
        async let images = captureImages(
            windows,
            allowAccessibilityRegionCapture: allowAccessibilityRegionCapture,
            includeFallback: !MenuBarItemScanner.usesAccessibilityBackend,
            diagnostics: true
        )
        let resolvedMetadata: [CGWindowID: MenuBarItemAccessibilityMetadata]
        if windows.allSatisfy({ $0.accessibilityIdentity != nil }) {
            resolvedMetadata = Dictionary(uniqueKeysWithValues: windows.map {
                (
                    $0.id,
                    MenuBarItemAccessibilityMetadata(
                        frame: $0.frame,
                        label: $0.displayName,
                        processIdentifier: $0.ownerProcessIdentifier
                    )
                )
            })
        } else {
            resolvedMetadata = await MenuBarItemMetadataResolver.metadata(
                for: windows
            )
        }
        let resolvedImages = await images

        return windows.compactMap { window in
            guard let image = resolvedImages[window.id] else { return nil }
            return CapturedItem(
                window: window,
                image: image,
                hoverText: resolvedMetadata[window.id]?.label,
                ownerProcessIdentifier: resolvedMetadata[window.id]?.processIdentifier
                    ?? window.ownerProcessIdentifier
            )
        }
    }

    /// Captures only window images, without waiting for Accessibility metadata.
    /// The menu-bar drag monitor uses this for a warm preview cache so the first
    /// drag frame can show the real icon instead of a generic placeholder.
    static func captureImages(
        _ windows: [MenuBarItemWindow],
        allowAccessibilityRegionCapture: Bool = true,
        includeFallback: Bool = false,
        diagnostics: Bool = false
    ) async -> [CGWindowID: NSImage] {
        let needsWindowCapture = windows.contains {
            $0.nativeWindowID != nil
                || ($0.accessibilityIdentity != nil && allowAccessibilityRegionCapture)
        }
        let content: SCShareableContent?
        if needsWindowCapture {
            content = await shareableContent()
        } else {
            content = nil
        }
        var result: [CGWindowID: NSImage] = [:]

        for window in windows {
            if let nativeWindowID = window.nativeWindowID,
               let scWindow = content?.windows.first(where: {
                   $0.windowID == nativeWindowID
               }) {
                let configuration = SCStreamConfiguration()
                let scale = scale(for: window.frame)
                configuration.width = max(1, Int(window.frame.width * scale))
                configuration.height = max(1, Int(window.frame.height * scale))
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)

                if let image = await captureWindowImage(
                    contentFilter: filter,
                    configuration: configuration
                ) {
                    // Preserve the real logical size. Replacing it with a fixed
                    // width changes the image aspect ratio and visibly squeezes
                    // text meters such as temperatures and battery.
                    result[window.id] = NSImage(
                        cgImage: image,
                        size: window.frame.size
                    )
                }
            } else if window.accessibilityIdentity != nil,
                      allowAccessibilityRegionCapture {
                if #available(macOS 15.2, *) {
                    let captureFrame = paddedItemCaptureFrame(
                        window.frame,
                        displays: content?.displays.map { CGDisplayBounds($0.displayID) } ?? [],
                        neighbours: windows.filter { $0.id != window.id }.map(\.frame)
                    )
                    for attempt in 0..<3 where result[window.id] == nil {
                        if attempt > 0 {
                            try? await Task.sleep(for: .milliseconds(70))
                        }
                        let displayImage = await captureDisplayRegionImage(
                            in: captureFrame,
                            content: content
                        )
                        let backgroundImage = displayImage == nil ? nil : await captureDisplayRegionImage(
                            in: captureFrame,
                            content: content,
                            includeMenuBar: false,
                            excludingBundleIdentifier: window.bundleIdentifier
                        )
                        var captured = displayImage.flatMap {
                            menuBarImage(from: $0, logicalSize: captureFrame.size, background: backgroundImage, diagnostics: diagnostics)
                        }
                        var regionImage: CGImage?
                        if captured == nil {
                            regionImage = await captureRegionImage(in: captureFrame)
                            captured = regionImage.flatMap {
                                menuBarImage(from: $0, logicalSize: captureFrame.size, background: backgroundImage, diagnostics: diagnostics)
                            }
                        }
                        if let captured {
                            result[window.id] = captured
                        }
                        if diagnostics {
                            logger.notice("item=\(window.id, privacy: .public) displayImage=\(displayImage != nil, privacy: .public) backgroundImage=\(backgroundImage != nil, privacy: .public) regionImage=\(regionImage != nil, privacy: .public) usable=\(captured != nil, privacy: .public)")
                        }
                    }
                }
            }

            // A preview may use an app icon as a last resort. The macOS 27
            // managed-item cache must contain real menu-bar pixels, however:
            // an app icon can have completely different artwork.
            if includeFallback, result[window.id] == nil {
                result[window.id] = fallbackImage(for: window)
            }
        }
        return result
    }

    /// Some AX buttons are narrower than their rendered glyph. Add a small
    /// transparent margin only within the menu strip and clear of other items.
    nonisolated static func paddedItemCaptureFrame(
        _ frame: CGRect,
        displays: [CGRect],
        neighbours: [CGRect]
    ) -> CGRect {
        let padded = frame.insetBy(dx: -3, dy: -3)
        guard displays.contains(where: { displaySourceRect(for: padded, displayBounds: $0) != nil }),
              !neighbours.contains(where: { padded.intersects($0) }) else { return frame }
        return padded
    }

    /// Use an explicit display filter so menu-bar scenes are part of the
    /// screenshot. The output contains only the validated item rectangle.
    private static func captureDisplayRegionImage(
        in frame: CGRect,
        content: SCShareableContent?,
        includeMenuBar: Bool = true,
        excludingBundleIdentifier: String? = nil
    ) async -> CGImage? {
        guard let display = content?.displays.first(where: {
            displaySourceRect(for: frame, displayBounds: CGDisplayBounds($0.displayID)) != nil
        }), let sourceRect = displaySourceRect(
            for: frame,
            displayBounds: CGDisplayBounds(display.displayID)
        ) else { return nil }

        let excludedApplications = content?.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
                || $0.bundleIdentifier == excludingBundleIdentifier
                || (!includeMenuBar && $0.bundleIdentifier == "com.apple.MenuBarAgent")
        } ?? []
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        if #available(macOS 14.2, *) { filter.includeMenuBar = includeMenuBar }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int((frame.width * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.height = max(1, Int((frame.height * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.showsCursor = false
        return await captureWindowImage(contentFilter: filter, configuration: configuration)
    }

    nonisolated static func displaySourceRect(
        for frame: CGRect,
        displayBounds: CGRect
    ) -> CGRect? {
        guard frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, frame.height <= 40,
              displayBounds.contains(frame),
              frame.minY >= displayBounds.minY,
              frame.maxY <= displayBounds.minY + 40 else { return nil }
        return frame.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
    }

    /// The SDK's async overlay assumes ScreenCaptureKit always supplies a
    /// result or an error. The Objective-C callbacks explicitly allow both to
    /// be nil; macOS 27 has returned that combination during display changes.
    /// Keep the nullable result intact instead of letting the overlay trap.
    private static func shareableContent() async -> SCShareableContent? {
        let result: ShareableContentResult = await withCheckedContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            ) { content, _ in
                continuation.resume(returning: ShareableContentResult(content: content))
            }
        }
        return result.content
    }

    private static func captureWindowImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    @available(macOS 15.2, *)
    private static func captureRegionImage(in frame: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(in: frame) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func menuBarImage(
        from source: CGImage,
        logicalSize: CGSize,
        background: CGImage? = nil,
        diagnostics: Bool = false
    ) -> NSImage? {
        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let data = context.data else { return nil }
        defer { withExtendedLifetime(context) {} }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var alphaValues = Array(repeating: UInt8.zero, count: width * height)

        let backgroundContext: CGContext?
        if let background, background.width == width, background.height == height {
            backgroundContext = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo
            )
            backgroundContext?.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            backgroundContext = nil
        }
        let backgroundPixels = backgroundContext?.data?.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        defer { withExtendedLifetime(backgroundContext) {} }

        // Wallpaper remains visible through the menu-bar material. One average
        // border colour turns its gradient into foreground reaching every edge.
        // Estimate the local background from the four padded corners instead.
        func cornerColor(x startX: Int, y startY: Int) -> (Double, Double, Double) {
            var totals = [0.0, 0.0, 0.0]
            var count = 0.0
            for y in startY..<min(height, startY + 2) {
                for x in startX..<min(width, startX + 2) {
                    let offset = y * bytesPerRow + x * 4
                    for channel in 0..<3 {
                        totals[channel] += Double(pixels[offset + channel])
                            - Double(backgroundPixels?[offset + channel] ?? 0)
                    }
                    count += 1
                }
            }
            return (totals[0] / count, totals[1] / count, totals[2] / count)
        }
        let topLeft = cornerColor(x: 0, y: 0)
        let topRight = cornerColor(x: max(0, width - 2), y: 0)
        let bottomLeft = cornerColor(x: 0, y: max(0, height - 2))
        let bottomRight = cornerColor(x: max(0, width - 2), y: max(0, height - 2))
        func backgroundColor(x: Int, y: Int) -> (Int, Int, Int) {
            let horizontal = (Double(x) - 0.5) / Double(max(1, width - 2))
            let vertical = (Double(y) - 0.5) / Double(max(1, height - 2))
            let offset = y * bytesPerRow + x * 4
            func interpolate(_ a: Double, _ b: Double, _ c: Double, _ d: Double, channel: Int) -> Int {
                let top = a + (b - a) * horizontal
                let bottom = c + (d - c) * horizontal
                let value = Double(backgroundPixels?[offset + channel] ?? 0)
                    + top + (bottom - top) * vertical
                return Int(min(255, max(0, value)).rounded())
            }
            return (
                interpolate(topLeft.0, topRight.0, bottomLeft.0, bottomRight.0, channel: 0),
                interpolate(topLeft.1, topRight.1, bottomLeft.1, bottomRight.1, channel: 1),
                interpolate(topLeft.2, topRight.2, bottomLeft.2, bottomRight.2, channel: 2)
            )
        }

        let pixelCount = width * height
        var backgrounds = Array(repeating: SIMD3<Double>.zero, count: pixelCount)
        var colours = Array(repeating: SIMD3<Double>.zero, count: pixelCount)
        var neutralFits = Array(repeating: MatteFit.empty, count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let offset = index * 4
                let sample = SIMD3(Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
                let ground = backgroundColor(x: x, y: y)
                let background = SIMD3(Double(ground.0), Double(ground.1), Double(ground.2))
                colours[index] = sample
                backgrounds[index] = background
                neutralFits[index] = neutralMatteFit(sample: sample, background: background)
                let difference = sample - background
                let distance = max(abs(difference.x), abs(difference.y), abs(difference.z))
                alphaValues[index] = templateAlpha(forColorDistance: Int(distance))
            }
        }

        if logicalSize.width <= logicalSize.height * 1.5 {
            alphaValues = removingPeripheralEdgeComponents(
                alphaValues, pixelWidth: width, pixelHeight: height
            )
        }
        // A white antialiased pixel over pink wallpaper is itself pink. Test
        // whether neutral artwork can explain that blend before calling it colour.
        let foregroundCount = alphaValues.filter { $0 >= 64 }.count
        let colourfulCount = alphaValues.indices.filter { index in
            alphaValues[index] >= 64 && isChromaticArtwork(
                colours[index], neutralFit: neutralFits[index]
            )
        }.count
        let strongForegroundCount = alphaValues.filter { $0 >= 128 }.count
        let preserveColour = shouldPreserveColour(
            foregroundCount: foregroundCount,
            colourfulCount: colourfulCount
        )
        guard strongForegroundCount >= 8 || (foregroundCount >= 8 && preserveColour) else {
            if diagnostics { logger.notice("image rejected: no substantial artwork size=\(width, privacy: .public)x\(height, privacy: .public) foreground=\(foregroundCount, privacy: .public) strong=\(strongForegroundCount, privacy: .public)") }
            return nil
        }
        let palette = preserveColour ? artworkPalette(
            colours: colours, neutralFits: neutralFits, alpha: alphaValues,
            pixelWidth: width, pixelHeight: height
        ) : []
        for index in alphaValues.indices {
            let offset = index * 4
            guard alphaValues[index] >= 24 else {
                alphaValues[index] = 0
                for channel in 0..<4 { pixels[offset + channel] = 0 }
                continue
            }
            let neutral = neutralFits[index]
            if preserveColour {
                let coloured = paletteMatteFit(
                    sample: colours[index], background: backgrounds[index], palette: palette
                )
                let fit: MatteFit
                if let coloured, coloured.residual <= 10,
                   coloured.residual + 1 < neutral.residual {
                    fit = coloured
                } else if neutral.residual <= 10 {
                    fit = neutral
                } else {
                    // Unsupported gradients have no flat core to infer from.
                    // Remove the matte using the conservative support estimate.
                    let coverage = Double(alphaValues[index]) / 255
                    let foreground = (colours[index] - backgrounds[index] * (1 - coverage)) / coverage
                    fit = MatteFit(foreground: clampedColour(foreground), coverage: coverage, residual: 0)
                }
                let alpha = UInt8(clamping: Int((fit.coverage * 255).rounded()))
                let premultiplied = fit.foreground * fit.coverage
                pixels[offset] = UInt8(clamping: Int(premultiplied.x.rounded()))
                pixels[offset + 1] = UInt8(clamping: Int(premultiplied.y.rounded()))
                pixels[offset + 2] = UInt8(clamping: Int(premultiplied.z.rounded()))
                pixels[offset + 3] = alpha
                alphaValues[index] = alpha
            } else {
                let intensity = neutral.foreground.x / 255
                let backgroundIntensity = colourMean(backgrounds[index]) / 255
                // Preserve grey detail in template artwork instead of turning
                // each neutral pixel into the same opaque white silhouette.
                let tone = intensity >= backgroundIntensity ? intensity : 1 - intensity
                let alpha = UInt8(clamping: Int((neutral.coverage * tone * 255).rounded()))
                for channel in 0..<4 { pixels[offset + channel] = alpha }
                alphaValues[index] = alpha
            }
        }

        guard context.makeImage() != nil else { return nil }
        guard let unpaddedContentBounds = templateContentBounds(
                  alphaValues: alphaValues,
                  pixelWidth: width,
                  pixelHeight: height,
                  padding: 0
              ) else {
            if diagnostics { logger.notice("image rejected: blank size=\(width, privacy: .public)x\(height, privacy: .public)") }
            return nil
        }
        guard templateContentIsSafelyInsideCapture(
                  unpaddedContentBounds,
                  pixelWidth: width,
                  pixelHeight: height
              ) else {
            if diagnostics {
                logger.notice("image rejected: edge size=\(width, privacy: .public)x\(height, privacy: .public) bounds=\(String(describing: unpaddedContentBounds), privacy: .public) foreground=\(foregroundCount, privacy: .public)")
            }
            return nil
        }
        if logicalSize.width <= logicalSize.height * 1.5,
           (abs(unpaddedContentBounds.midX - CGFloat(width) / 2) > CGFloat(width) / 8
            || abs(unpaddedContentBounds.midY - CGFloat(height) / 2) > CGFloat(height) / 8) {
            // A displaced neighbouring glyph is not evidence that the AX
            // item itself rendered at this coordinate.
            if diagnostics { logger.notice("image rejected: artwork displaced from item centre size=\(width, privacy: .public)x\(height, privacy: .public)") }
            return nil
        }
        guard let contentBounds = templateContentBounds(
            alphaValues: alphaValues,
            pixelWidth: width,
            pixelHeight: height,
            opticallyCentered: logicalSize.width <= logicalSize.height * 1.5
        ) else { return nil }
        if diagnostics {
            logger.notice("image usable size=\(width, privacy: .public)x\(height, privacy: .public) foreground=\(foregroundCount, privacy: .public) strong=\(strongForegroundCount, privacy: .public) bounds=\(String(describing: unpaddedContentBounds), privacy: .public) template=\(!preserveColour, privacy: .public)")
        }
        return templateImage(
            pixels: pixels,
            pixelWidth: width,
            pixelHeight: height,
            contentBounds: contentBounds,
            logicalSize: logicalSize,
            colorSpace: colorSpace,
            bitmapInfo: bitmapInfo,
            isTemplate: !preserveColour
        )
    }

    private struct MatteFit {
        let foreground: SIMD3<Double>
        let coverage: Double
        let residual: Double
        static let empty = MatteFit(foreground: .zero, coverage: 0, residual: 0)
    }

    nonisolated private static func colourMean(_ colour: SIMD3<Double>) -> Double {
        (colour.x + colour.y + colour.z) / 3
    }

    nonisolated private static func colourDot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    nonisolated private static func clampedColour(_ colour: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(min(255, max(0, colour.x)), min(255, max(0, colour.y)), min(255, max(0, colour.z)))
    }

    /// Fit C = k B + q grey with 0 <= k <= 1 and 0 <= q <= 255(1-k).
    /// Check every boundary too: unconstrained regression can mistake a colour
    /// near the wallpaper hue for an impossible negative grey foreground.
    nonisolated private static func neutralMatteFit(
        sample: SIMD3<Double>, background: SIMD3<Double>
    ) -> MatteFit {
        let sampleMean = colourMean(sample)
        let backgroundMean = colourMean(background)
        let centeredBackground = background - SIMD3(repeating: backgroundMean)
        let variance = colourDot(centeredBackground, centeredBackground)
        var candidates: [(Double, Double)] = [(0, sampleMean)]
        if variance > 1 {
            let k = colourDot(centeredBackground, sample - SIMD3(repeating: sampleMean)) / variance
            let q = sampleMean - k * backgroundMean
            if k >= 0, k <= 1, q >= 0, q <= 255 * (1 - k) {
                candidates.append((k, q))
            }
        }
        for grey in [0.0, 255.0] {
            let direction = background - SIMD3(repeating: grey)
            let denominator = colourDot(direction, direction)
            let k = denominator > 1
                ? min(1, max(0, colourDot(sample - SIMD3(repeating: grey), direction) / denominator))
                : 1
            candidates.append((k, grey * (1 - k)))
        }
        var best = MatteFit.empty
        var bestError = Double.infinity
        for (k, q) in candidates {
            let difference = sample - (background * k + SIMD3(repeating: q))
            let error = colourDot(difference, difference)
            // Equal fits on neutral wallpaper prefer the white/black blend,
            // which retains antialias coverage rather than opaque grey pixels.
            if error <= bestError + 0.01 {
                let coverage = 1 - k
                best = MatteFit(
                    foreground: SIMD3(repeating: coverage > 0.001 ? q / coverage : 0),
                    coverage: coverage,
                    residual: max(abs(difference.x), abs(difference.y), abs(difference.z))
                )
                bestError = error
            }
        }
        return best
    }

    nonisolated private static func isChromaticArtwork(
        _ sample: SIMD3<Double>, neutralFit: MatteFit
    ) -> Bool {
        max(sample.x, sample.y, sample.z) - min(sample.x, sample.y, sample.z) >= 32
            && neutralFit.residual > 10
    }

    /// Only flat 3x3 chromatic interiors can supply an opaque foreground colour.
    /// Bright antialiasing alone cannot prove opacity and must not enter here.
    nonisolated private static func artworkPalette(
        colours: [SIMD3<Double>], neutralFits: [MatteFit], alpha: [UInt8],
        pixelWidth width: Int, pixelHeight height: Int
    ) -> [SIMD3<Double>] {
        guard width >= 3, height >= 3 else { return [] }
        var buckets: [Int: (total: SIMD3<Double>, count: Int)] = [:]
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let colour = colours[index]
                guard alpha[index] >= 24,
                      isChromaticArtwork(colour, neutralFit: neutralFits[index]) else { continue }
                var isFlatInterior = true
                for ny in (y - 1)...(y + 1) {
                    for nx in (x - 1)...(x + 1) {
                        let neighbour = ny * width + nx
                        let difference = colours[neighbour] - colour
                        if alpha[neighbour] < 24
                            || max(abs(difference.x), abs(difference.y), abs(difference.z)) > 8 {
                            isFlatInterior = false
                        }
                    }
                }
                guard isFlatInterior else { continue }
                let key = (Int(colour.x) / 8) << 10 | (Int(colour.y) / 8) << 5 | Int(colour.z) / 8
                let bucket = buckets[key] ?? (.zero, 0)
                buckets[key] = (bucket.total + colour, bucket.count + 1)
            }
        }
        return buckets.sorted { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count > rhs.value.count
        }.prefix(16).map { $0.value.total / Double($0.value.count) }
    }

    nonisolated private static func paletteMatteFit(
        sample: SIMD3<Double>, background: SIMD3<Double>, palette: [SIMD3<Double>]
    ) -> MatteFit? {
        var best: MatteFit?
        for colour in palette {
            let direction = colour - background
            let denominator = colourDot(direction, direction)
            guard denominator > 1 else { continue }
            let coverage = min(1, max(0, colourDot(sample - background, direction) / denominator))
            guard coverage >= 0.05 else { continue }
            let difference = sample - (colour * coverage + background * (1 - coverage))
            let residual = max(abs(difference.x), abs(difference.y), abs(difference.z))
            if best == nil || residual < best!.residual - 0.5
                || (abs(residual - best!.residual) <= 0.5 && coverage > best!.coverage) {
                best = MatteFit(foreground: colour, coverage: coverage, residual: residual)
            }
        }
        return best
    }

    nonisolated static func shouldPreserveColour(
        foregroundCount: Int,
        colourfulCount: Int
    ) -> Bool {
        foregroundCount > 0
            && colourfulCount >= max(3, (foregroundCount + 49) / 50)
    }

    /// AX rectangles can contain the edge of the next hosted icon. Discard
    /// only disconnected edge fragments outside the central half of a square
    /// item; a clipped component reaching the centre still fails the edge gate.
    /// Wide text and meter items keep every component.
    nonisolated static func removingPeripheralEdgeComponents(
        _ alpha: [UInt8], pixelWidth width: Int, pixelHeight height: Int
    ) -> [UInt8] {
        guard width > 0, height > 0, alpha.count == width * height else { return alpha }
        var result = alpha
        var visited = Array(repeating: false, count: alpha.count)
        let central = CGRect(x: CGFloat(width) / 4, y: CGFloat(height) / 4,
                             width: CGFloat(width) / 2, height: CGFloat(height) / 2)
        for start in alpha.indices where alpha[start] >= 24 && !visited[start] {
            var component = [start]
            visited[start] = true
            var next = 0
            var minimumX = width, maximumX = 0, minimumY = height, maximumY = 0
            while next < component.count {
                let index = component[next]
                next += 1
                let x = index % width, y = index / width
                minimumX = min(minimumX, x); maximumX = max(maximumX, x)
                minimumY = min(minimumY, y); maximumY = max(maximumY, y)
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbour = ny * width + nx
                        if !visited[neighbour], alpha[neighbour] >= 24 {
                            visited[neighbour] = true
                            component.append(neighbour)
                        }
                    }
                }
            }
            let bounds = CGRect(x: minimumX, y: minimumY,
                                width: maximumX - minimumX + 1, height: maximumY - minimumY + 1)
            if !templateContentIsSafelyInsideCapture(bounds, pixelWidth: width, pixelHeight: height),
               !bounds.intersects(central) {
                for index in component { result[index] = 0 }
            }
        }
        return result
    }

    /// Keep intensity differences in neutral artwork instead of clipping every
    /// non-background pixel to fully opaque white. AppKit tints these templates
    /// to match the panel appearance.
    nonisolated static func templateAlpha(
        forColorDistance distance: Int
    ) -> UInt8 {
        UInt8(clamping: max(0, (distance - 6) * 2))
    }

    nonisolated static func templateContentBounds(
        alphaValues: [UInt8],
        pixelWidth: Int,
        pixelHeight: Int,
        threshold: UInt8 = 24,
        padding: Int = 2,
        opticallyCentered: Bool = false
    ) -> CGRect? {
        guard pixelWidth > 0,
              pixelHeight > 0,
              alphaValues.count == pixelWidth * pixelHeight else { return nil }

        var minimumX = pixelWidth
        var minimumY = pixelHeight
        var maximumX = -1
        var maximumY = -1
        var alphaTotal = 0.0
        var horizontalMoment = 0.0
        var verticalMoment = 0.0
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth
                where alphaValues[y * pixelWidth + x] >= threshold {
                let weight = Double(alphaValues[y * pixelWidth + x])
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
                alphaTotal += weight
                horizontalMoment += (Double(x) + 0.5) * weight
                verticalMoment += (Double(y) + 0.5) * weight
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }

        if opticallyCentered, alphaTotal > 0 {
            func centeredRange(
                minimum: Int,
                maximum: Int,
                centroid: Double
            ) -> (origin: Int, length: Int) {
                // Pixel-aligned output can have an integer or half-integer
                // centre. Choose the closest one to the alpha-weighted visual
                // centre, then grow the transparent side as needed so no
                // significant source pixel is clipped.
                let centerTwice = Int((centroid * 2).rounded())
                let center = Double(centerTwice) / 2
                let paddedMinimum = minimum - padding
                let paddedMaximum = maximum + 1 + padding
                let requiredHalfLength = max(
                    center - Double(paddedMinimum),
                    Double(paddedMaximum) - center
                )
                var length = Int(ceil(requiredHalfLength * 2))
                let requiredParity = abs(centerTwice) % 2
                if length % 2 != requiredParity {
                    length += 1
                }
                return ((centerTwice - length) / 2, length)
            }

            let horizontal = centeredRange(
                minimum: minimumX,
                maximum: maximumX,
                centroid: horizontalMoment / alphaTotal
            )
            let vertical = centeredRange(
                minimum: minimumY,
                maximum: maximumY,
                centroid: verticalMoment / alphaTotal
            )
            return CGRect(
                x: horizontal.origin,
                y: vertical.origin,
                width: horizontal.length,
                height: vertical.length
            )
        }

        let paddedMinimumX = max(0, minimumX - padding)
        let paddedMinimumY = max(0, minimumY - padding)
        let paddedMaximumX = min(pixelWidth - 1, maximumX + padding)
        let paddedMaximumY = min(pixelHeight - 1, maximumY + padding)
        return CGRect(
            x: paddedMinimumX,
            y: paddedMinimumY,
            width: paddedMaximumX - paddedMinimumX + 1,
            height: paddedMaximumY - paddedMinimumY + 1
        )
    }

    /// A native-overflow animation can move real artwork through an AX frame
    /// after Accessibility has already published its final coordinates. Treat
    /// foreground touching the capture edge as a transitional, clipped frame.
    nonisolated static func templateContentIsSafelyInsideCapture(
        _ contentBounds: CGRect,
        pixelWidth: Int,
        pixelHeight: Int,
        minimumMargin: Int = 1
    ) -> Bool {
        guard pixelWidth > 0,
              pixelHeight > 0,
              minimumMargin >= 0 else { return false }
        return contentBounds.minX >= CGFloat(minimumMargin)
            && contentBounds.minY >= CGFloat(minimumMargin)
            && contentBounds.maxX <= CGFloat(pixelWidth - minimumMargin)
            && contentBounds.maxY <= CGFloat(pixelHeight - minimumMargin)
    }

    private static func templateImage(
        pixels: UnsafePointer<UInt8>,
        pixelWidth: Int,
        pixelHeight: Int,
        contentBounds: CGRect,
        logicalSize: CGSize,
        colorSpace: CGColorSpace,
        bitmapInfo: UInt32,
        isTemplate: Bool = true
    ) -> NSImage? {
        let cropX = Int(contentBounds.minX)
        let cropY = Int(contentBounds.minY)
        let cropWidth = Int(contentBounds.width)
        let cropHeight = Int(contentBounds.height)
        guard cropWidth > 0, cropHeight > 0 else { return nil }

        let sourceBytesPerRow = pixelWidth * 4
        let cropBytesPerRow = cropWidth * 4
        guard let cropContext = CGContext(
            data: nil,
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bytesPerRow: cropBytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let cropData = cropContext.data else { return nil }
        cropContext.clear(CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))
        let cropPixels = cropData.bindMemory(
            to: UInt8.self,
            capacity: cropBytesPerRow * cropHeight
        )
        for y in 0..<cropHeight {
            let sourceY = cropY + y
            guard sourceY >= 0, sourceY < pixelHeight else { continue }
            for x in 0..<cropWidth {
                let sourceX = cropX + x
                guard sourceX >= 0, sourceX < pixelWidth else { continue }
                let sourceOffset = sourceY * sourceBytesPerRow + sourceX * 4
                let destinationOffset = y * cropBytesPerRow + x * 4
                for channel in 0..<4 {
                    cropPixels[destinationOffset + channel] = pixels[sourceOffset + channel]
                }
            }
        }
        guard let croppedOutput = cropContext.makeImage() else { return nil }
        let croppedLogicalSize = CGSize(
            width: logicalSize.width * CGFloat(cropWidth) / CGFloat(pixelWidth),
            height: logicalSize.height * CGFloat(cropHeight) / CGFloat(pixelHeight)
        )
        let image = NSImage(cgImage: croppedOutput, size: croppedLogicalSize)
        image.isTemplate = isTemplate
        return image
    }

    /// Builds a readable template from a full-colour application icon. Most
    /// app icons have an opaque rounded-square surface, so using their original
    /// alpha verbatim would render as one solid white block. Keep that surface
    /// faint while promoting colour differences to stronger template alpha.
    nonisolated static func fallbackTemplateAlpha(
        colorDistance: Int,
        sourceAlpha: UInt8,
        hasOpaqueSurface: Bool
    ) -> UInt8 {
        guard sourceAlpha > 0 else { return 0 }
        guard hasOpaqueSurface else { return sourceAlpha }
        let surface = Int(sourceAlpha) * 40 / 255
        let detail = Int(templateAlpha(forColorDistance: colorDistance))
            * Int(sourceAlpha) / 255
        return UInt8(clamping: max(surface, detail))
    }

    private static func fallbackTemplateImage(from source: NSImage) -> NSImage? {
        var proposedRect = CGRect(origin: .zero, size: CGSize(width: 128, height: 128))
        guard let input = source.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high]
        ) else { return nil }

        // Always rasterize into a small working surface. Avoiding
        // `tiffRepresentation` is important here: app icons commonly contain
        // several large representations, and expanding all of them caused a
        // short-lived hundreds-of-megabytes allocation during startup.
        let width = 128
        let height = 128
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let data = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        // A five-bit RGB histogram finds the icon's main surface colour without
        // assuming a light or dark app-icon background.
        let bucketCount = 32 * 32 * 32
        var counts = Array(repeating: 0, count: bucketCount)
        var redTotals = Array(repeating: 0, count: bucketCount)
        var greenTotals = Array(repeating: 0, count: bucketCount)
        var blueTotals = Array(repeating: 0, count: bucketCount)
        var opaquePixelCount = 0
        var alphaValues = Array(repeating: UInt8.zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                guard pixels[offset + 3] >= 128 else { continue }
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let bucket = (red >> 3) << 10 | (green >> 3) << 5 | (blue >> 3)
                counts[bucket] += 1
                redTotals[bucket] += red
                greenTotals[bucket] += green
                blueTotals[bucket] += blue
                opaquePixelCount += 1
            }
        }
        guard opaquePixelCount > 0,
              let dominantBucket = counts.indices.max(by: {
                  counts[$0] < counts[$1]
              }), counts[dominantBucket] > 0 else { return nil }
        let dominantCount = counts[dominantBucket]
        let dominant = (
            redTotals[dominantBucket] / dominantCount,
            greenTotals[dominantBucket] / dominantCount,
            blueTotals[dominantBucket] / dominantCount
        )
        let hasOpaqueSurface = opaquePixelCount * 5 >= width * height * 2

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let sourceAlpha = pixels[offset + 3]
                let distance = max(
                    abs(Int(pixels[offset]) - dominant.0),
                    abs(Int(pixels[offset + 1]) - dominant.1),
                    abs(Int(pixels[offset + 2]) - dominant.2)
                )
                let alpha = fallbackTemplateAlpha(
                    colorDistance: distance,
                    sourceAlpha: sourceAlpha,
                    hasOpaqueSurface: hasOpaqueSurface
                )
                pixels[offset] = alpha
                pixels[offset + 1] = alpha
                pixels[offset + 2] = alpha
                pixels[offset + 3] = alpha
                alphaValues[y * width + x] = alpha
            }
        }

        guard context.makeImage() != nil,
              let contentBounds = templateContentBounds(
                  alphaValues: alphaValues,
                  pixelWidth: width,
                  pixelHeight: height,
                  padding: 0,
                  opticallyCentered: true
              ) else { return nil }
        return templateImage(
            pixels: pixels,
            pixelWidth: width,
            pixelHeight: height,
            contentBounds: contentBounds,
            logicalSize: CGSize(width: 24, height: 24),
            colorSpace: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    private static func fallbackImage(for window: MenuBarItemWindow) -> NSImage {
        if let processIdentifier = window.ownerProcessIdentifier,
           let source = NSRunningApplication(
               processIdentifier: processIdentifier
           )?.icon,
           let image = fallbackTemplateImage(from: source) {
            return image
        }
        let image = NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: window.displayName
        ) ?? NSImage(size: NSSize(width: 24, height: 24))
        image.isTemplate = true
        return image
    }
}
