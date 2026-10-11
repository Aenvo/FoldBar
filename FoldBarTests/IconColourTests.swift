import AppKit
import Testing

@testable import FoldBar

@Suite("Menu-bar screenshot colour recovery")
@MainActor
struct IconColourTests {
    private struct RGB {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private struct Pixel {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        var chroma: Double {
            max(red, green, blue) - min(red, green, blue)
        }

        func matches(_ colour: RGB, tolerance: Double = 0.05) -> Bool {
            abs(red - Double(colour.red) / 255) <= tolerance
                && abs(green - Double(colour.green) / 255) <= tolerance
                && abs(blue - Double(colour.blue) / 255) <= tolerance
        }
    }

    /// These are already-composited, opaque screen pixels. Creating them from
    /// device-RGB bytes keeps the test independent of NSColor conversion.
    private struct Screenshot {
        let width = 48
        let height = 48
        let backdrop: RGB
        var bytes: [UInt8]

        init(backdrop: RGB) {
            self.backdrop = backdrop
            bytes = Array(repeating: 0, count: 48 * 48 * 4)
            for index in 0..<(48 * 48) {
                bytes[index * 4] = backdrop.red
                bytes[index * 4 + 1] = backdrop.green
                bytes[index * 4 + 2] = backdrop.blue
                bytes[index * 4 + 3] = 255
            }
        }

        mutating func fill(
            x: Range<Int>, y: Range<Int>, colour: RGB, coverage: Double = 1
        ) {
            let foreground = [colour.red, colour.green, colour.blue]
            let background = [backdrop.red, backdrop.green, backdrop.blue]
            for row in y {
                for column in x {
                    let offset = (row * width + column) * 4
                    for channel in 0..<3 {
                        bytes[offset + channel] = UInt8(
                            (Double(foreground[channel]) * coverage
                                + Double(background[channel]) * (1 - coverage)).rounded()
                        )
                    }
                }
            }
        }

        func image() throws -> CGImage {
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            return try #require(CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ))
        }
    }

    private func pixels(in image: NSImage) throws -> [Pixel] {
        let output = try #require(image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        let bitmap = NSBitmapImageRep(cgImage: output)
        var result: [Pixel] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                result.append(Pixel(
                    red: Double(colour.redComponent),
                    green: Double(colour.greenComponent),
                    blue: Double(colour.blueComponent),
                    alpha: Double(colour.alphaComponent)
                ))
            }
        }
        return result
    }

    @Test("Pink wallpaper cannot colour antialiased white or grey artwork", arguments: [UInt8(255), UInt8(160)])
    func neutralAntialiasingOnPinkWallpaper(intensity: UInt8) throws {
        let background = Screenshot(backdrop: RGB(red: 210, green: 30, blue: 150))
        var source = background
        let neutral = RGB(red: intensity, green: intensity, blue: intensity)
        source.fill(x: 6..<42, y: 6..<42, colour: neutral, coverage: 0.15)
        source.fill(x: 8..<40, y: 8..<40, colour: neutral, coverage: 0.4)
        source.fill(x: 10..<38, y: 10..<38, colour: neutral, coverage: 0.7)
        source.fill(x: 12..<36, y: 12..<36, colour: neutral)

        let image = try #require(IconCapturer.menuBarImage(
            from: source.image(),
            logicalSize: CGSize(width: 24, height: 24),
            background: background.image()
        ))
        #expect(image.isTemplate)
        let foreground = try pixels(in: image).filter { $0.alpha > 0.05 }
        #expect(!foreground.isEmpty)
        #expect(foreground.allSatisfy { $0.chroma < 0.02 })
        // Grey artwork must keep its tone instead of becoming a solid white
        // silhouette. Antialiased pixels must still have intermediate coverage.
        let peakAlpha = try #require(foreground.map(\.alpha).max())
        #expect(abs(peakAlpha - Double(intensity) / 255) < 0.06)
        #expect(foreground.contains { $0.alpha > 0.07 && $0.alpha < peakAlpha - 0.1 })
    }

    @Test("A same-hue coloured core keeps its actual colour and opacity")
    func sameHueColourAndOpacity() throws {
        let background = Screenshot(backdrop: RGB(red: 255, green: 51, blue: 255))
        var source = background
        let colour = RGB(red: 230, green: 26, blue: 204)
        source.fill(x: 12..<36, y: 12..<36, colour: colour)

        let image = try #require(IconCapturer.menuBarImage(
            from: source.image(),
            logicalSize: CGSize(width: 24, height: 24),
            background: background.image()
        ))
        #expect(!image.isTemplate)
        let output = try pixels(in: image)
        let opaqueCore = output.filter { $0.alpha > 0.97 }
        #expect(opaqueCore.count >= 100)
        #expect(opaqueCore.allSatisfy { $0.matches(colour) })
    }

    @Test("Mixed artwork removes pink from neutral edges and recovers coloured edges")
    func mixedArtworkAntialiasing() throws {
        let background = Screenshot(backdrop: RGB(red: 130, green: 20, blue: 80))
        var source = background
        let white = RGB(red: 255, green: 255, blue: 255)
        let pink = RGB(red: 245, green: 20, blue: 195)
        source.fill(x: 6..<22, y: 8..<40, colour: white, coverage: 0.4)
        source.fill(x: 8..<20, y: 10..<38, colour: white)
        source.fill(x: 26..<42, y: 8..<40, colour: pink, coverage: 0.4)
        source.fill(x: 28..<40, y: 10..<38, colour: pink)

        let image = try #require(IconCapturer.menuBarImage(
            from: source.image(),
            logicalSize: CGSize(width: 24, height: 24),
            background: background.image()
        ))
        #expect(!image.isTemplate)
        let output = try pixels(in: image)
        #expect(output.filter { $0.alpha > 0.97 && $0.matches(white) }.count >= 100)
        #expect(output.filter { $0.alpha > 0.97 && $0.matches(pink) }.count >= 100)

        let fringe = output.filter { abs($0.alpha - 0.4) < 0.06 }
        let neutralFringe = fringe.filter { $0.chroma < 0.03 }
        let colouredFringe = fringe.filter { $0.chroma > 0.1 }
        #expect(neutralFringe.count >= 20)
        #expect(colouredFringe.count >= 20)
        #expect(neutralFringe.allSatisfy { $0.matches(white) })
        #expect(colouredFringe.allSatisfy { $0.matches(pink, tolerance: 0.06) })
    }

    @Test("A coloured backdrop without artwork remains an empty capture")
    func colouredBackdropWithoutArtwork() throws {
        let background = Screenshot(backdrop: RGB(red: 210, green: 30, blue: 150))
        let screenshot = try background.image()
        #expect(IconCapturer.menuBarImage(
            from: screenshot,
            logicalSize: CGSize(width: 24, height: 24),
            background: screenshot
        ) == nil)
    }
}
