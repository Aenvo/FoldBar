import AppKit
import ScreenCaptureKit

@MainActor
enum IconCapturer {
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
        allowAccessibilityRegionCapture: Bool = !MenuBarItemScanner.usesAccessibilityBackend
    ) async -> [CapturedItem] {
        // Collapsed macOS 27 items retain virtual AX frames even though their
        // pixels are not on screen. Callers may opt in only after the native
        // overflow control has exposed those identities in real visible slots.
        async let images = captureImages(
            windows,
            allowAccessibilityRegionCapture: allowAccessibilityRegionCapture
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
        allowAccessibilityRegionCapture: Bool = true
    ) async -> [CGWindowID: NSImage] {
        let needsWindowCapture = windows.contains { $0.nativeWindowID != nil }
        let content: SCShareableContent?
        if needsWindowCapture {
            content = try? await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: false)
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

                if let image = try? await SCScreenshotManager.captureImage(
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
                    for attempt in 0..<3 where result[window.id] == nil {
                        if attempt > 0 {
                            try? await Task.sleep(for: .milliseconds(70))
                        }
                        if let image = try? await SCScreenshotManager.captureImage(
                            in: window.frame
                        ), let template = menuBarTemplateImage(
                            from: image,
                            logicalSize: window.frame.size
                        ) {
                            result[window.id] = template
                        }
                    }
                }
            }

            // macOS 27 hosts menu extras in a managed scene and no longer makes
            // each item available as an SCWindow. Region capture normally
            // supplies the real pixels; retain a monochrome fallback if an item
            // changes identity during capture.
            if result[window.id] == nil {
                result[window.id] = fallbackImage(for: window)
            }
        }
        return result
    }

    private static func menuBarTemplateImage(
        from source: CGImage,
        logicalSize: CGSize
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
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var alphaValues = Array(repeating: UInt8.zero, count: width * height)

        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0
        var sampleCount = 0
        for y in 0..<height {
            for x in 0..<width where x < 2 || x >= width - 2 || y < 2 || y >= height - 2 {
                let offset = y * bytesPerRow + x * 4
                redTotal += Int(pixels[offset])
                greenTotal += Int(pixels[offset + 1])
                blueTotal += Int(pixels[offset + 2])
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return nil }
        let background = (
            redTotal / sampleCount,
            greenTotal / sampleCount,
            blueTotal / sampleCount
        )

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let distance = max(
                    abs(Int(pixels[offset]) - background.0),
                    abs(Int(pixels[offset + 1]) - background.1),
                    abs(Int(pixels[offset + 2]) - background.2)
                )
                let alpha = templateAlpha(forColorDistance: distance)
                pixels[offset] = alpha
                pixels[offset + 1] = alpha
                pixels[offset + 2] = alpha
                pixels[offset + 3] = alpha
                alphaValues[y * width + x] = alpha
            }
        }

        guard context.makeImage() != nil else { return nil }
        guard let contentBounds = templateContentBounds(
            alphaValues: alphaValues,
            pixelWidth: width,
            pixelHeight: height,
            opticallyCentered: logicalSize.width <= logicalSize.height * 1.5
        ) else { return nil }
        return templateImage(
            pixels: pixels,
            pixelWidth: width,
            pixelHeight: height,
            contentBounds: contentBounds,
            logicalSize: logicalSize,
            colorSpace: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    /// Keep intensity differences inside multicolour status artwork instead of
    /// clipping every non-background pixel to fully opaque white. This retains
    /// details such as a light letter inside a coloured circle after AppKit
    /// applies the monochrome menu-bar tint.
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

    private static func templateImage(
        pixels: UnsafePointer<UInt8>,
        pixelWidth: Int,
        pixelHeight: Int,
        contentBounds: CGRect,
        logicalSize: CGSize,
        colorSpace: CGColorSpace,
        bitmapInfo: UInt32
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
        image.isTemplate = true
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
