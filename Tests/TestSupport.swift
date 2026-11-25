import XCTest
import CoreGraphics
import CoreML
import UIKit
@testable import Clarivo

/// Pictures and helpers shared by the tests.
enum TestImages {
    /// A smooth gradient with a pattern of fine lines: every pixel different, so seams would show.
    static func pattern(width: Int, height: Int, seed: Int = 1) -> RGBAImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o] = UInt8((x * 255 / max(1, width - 1) + seed * 7) & 0xFF)
                pixels[o + 1] = UInt8((y * 255 / max(1, height - 1)) & 0xFF)
                pixels[o + 2] = UInt8(((x * 13 + y * 7 + seed) % 256) & 0xFF)
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func cgPattern(width: Int, height: Int) -> CGImage {
        pattern(width: width, height: height).makeCGImage()!
    }

    static func solid(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = r; pixels[i * 4 + 1] = g; pixels[i * 4 + 2] = b
        }
        return RGBAImage(width: width, height: height, pixels: pixels).makeCGImage()!
    }

    /// A grey photo-like picture (for colorize and black-and-white checks).
    static func gray(width: Int, height: Int) -> RGBAImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x + y) * 255 / max(1, width + height - 2))
                let o = (y * width + x) * 4
                pixels[o] = v; pixels[o + 1] = v; pixels[o + 2] = v
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func jpegData(_ image: CGImage, metadata: [CFString: Any]? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary?)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// JPEG with camera details and a GPS position, as a phone writes them.
    static func jpegWithLocation(width: Int = 64, height: Int = 48) -> Data {
        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:11:25 09:41:00",
                kCGImagePropertyExifLensModel: "Test lens",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "TestMaker",
                kCGImagePropertyTIFFModel: "TestCam",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.8584,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.2945,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        return jpegData(cgPattern(width: width, height: height), metadata: metadata)
    }

    static func properties(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        return props
    }

    static func maxDifference(_ a: RGBAImage, _ b: RGBAImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return 255 }
        var worst = 0
        for i in 0..<a.pixels.count where i % 4 != 3 {
            worst = max(worst, abs(Int(a.pixels[i]) - Int(b.pixels[i])))
        }
        return worst
    }

    static func meanDifference(_ a: RGBAImage, _ b: RGBAImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 255 }
        var sum = 0
        var n = 0
        for i in 0..<a.pixels.count where i % 4 != 3 {
            sum += abs(Int(a.pixels[i]) - Int(b.pixels[i]))
            n += 1
        }
        return Double(sum) / Double(max(n, 1))
    }
}

/// A model provider with no models: what a build without the models-v1 release has.
final class NoModels: ModelProviding {
    func model(_ kind: ModelKind) async throws -> MLModel? { nil }
    func isAvailable(_ kind: ModelKind) -> Bool { false }
}

/// The repository root, found from this file's path (the simulator can read the Mac's files).
enum Repo {
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func text(_ relative: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
