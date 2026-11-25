import Foundation
import CoreGraphics
import Accelerate

/// 8-bit RGBA pixels in sRGB, premultiplied, row by row with no padding. The engine's working format.
struct RGBAImage: Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    var bytesPerRow: Int { width * 4 }
    var pixelCount: Int { width * height }

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A blank (transparent black) image.
    init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: 0, count: max(1, width) * max(1, height) * 4))
    }

    static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// Draws any CGImage into RGBA. Returns nil for a zero-sized image or when memory for the pixels cannot be had.
    init?(cgImage: CGImage) {
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0, width <= 32_768, height <= 32_768 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: RGBAImage.colorSpace, bitmapInfo: RGBAImage.bitmapInfo
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    func makeCGImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: RGBAImage.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: RGBAImage.bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Copies a rectangle out of the image. Parts of the rectangle outside the image repeat the nearest edge pixel,
    /// so a tile at the border can always be the size the model needs.
    func crop(x: Int, y: Int, width w: Int, height h: Int) -> RGBAImage {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let srcW = width, srcH = height
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for row in 0..<h {
                    let sy = min(max(y + row, 0), srcH - 1)
                    let srcRow = sy * srcW * 4
                    let dstRow = row * w * 4
                    let x0 = max(x, 0), x1 = min(x + w, srcW)
                    if x1 > x0 {
                        // The part inside the image in one copy.
                        let count = (x1 - x0) * 4
                        let dstStart = dstRow + (x0 - x) * 4
                        UnsafeMutableRawPointer(dst.baseAddress! + dstStart)
                            .copyMemory(from: src.baseAddress! + srcRow + x0 * 4, byteCount: count)
                    }
                    // Edge repeat on the left and right.
                    if x < 0 || x + w > srcW {
                        for col in 0..<w {
                            let sx = x + col
                            guard sx < 0 || sx >= srcW else { continue }
                            let cx = min(max(sx, 0), srcW - 1)
                            for c in 0..<4 { dst[dstRow + col * 4 + c] = src[srcRow + cx * 4 + c] }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// High-quality (Lanczos) resize with vImage. Returns self when the size is unchanged.
    func resized(width newW: Int, height newH: Int) -> RGBAImage {
        guard newW > 0, newH > 0 else { return self }
        if newW == width && newH == height { return self }
        var src = self.pixels
        var out = [UInt8](repeating: 0, count: newW * newH * 4)
        src.withUnsafeMutableBytes { s in
            out.withUnsafeMutableBytes { d in
                var source = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                var dest = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(newH), width: vImagePixelCount(newW), rowBytes: newW * 4)
                _ = vImageScale_ARGB8888(&source, &dest, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return RGBAImage(width: newW, height: newH, pixels: out)
    }

    /// Nearest-neighbour enlargement by an integer factor (tests and debug only).
    func nearestUpscaled(_ factor: Int) -> RGBAImage {
        guard factor > 1 else { return self }
        let w = width * factor, h = height * factor
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let sy = y / factor
            for x in 0..<w {
                let sx = x / factor
                let s = (sy * width + sx) * 4, d = (y * w + x) * 4
                out[d] = pixels[s]; out[d + 1] = pixels[s + 1]; out[d + 2] = pixels[s + 2]; out[d + 3] = pixels[s + 3]
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// Mixes `other` (same size) over self: 0 keeps self, 1 gives `other`.
    func blended(with other: RGBAImage, amount: Float) -> RGBAImage {
        guard other.width == width, other.height == height else { return other }
        let a = min(max(amount, 0), 1)
        if a >= 0.999 { return other }
        if a <= 0.001 { return self }
        var out = pixels
        let ai = Int((a * 256).rounded()), bi = 256 - ai
        other.pixels.withUnsafeBufferPointer { o in
            out.withUnsafeMutableBufferPointer { d in
                for i in 0..<d.count {
                    d[i] = UInt8((Int(d[i]) * bi + Int(o[i]) * ai + 128) >> 8)
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    /// Sets alpha to fully opaque (models ignore alpha; photos are opaque).
    mutating func makeOpaque() {
        pixels.withUnsafeMutableBufferPointer { p in
            var i = 3
            while i < p.count { p[i] = 255; i += 4 }
        }
    }
}

/// Sizes in pixels, kept separate so cap logic can be tested without images.
struct PixelSize: Equatable, CustomStringConvertible {
    var width: Int
    var height: Int
    var longSide: Int { max(width, height) }
    var megapixels: Double { Double(width) * Double(height) / 1_000_000 }
    var description: String { "\(width) × \(height)" }

    func scaled(by factor: Double) -> PixelSize {
        PixelSize(width: max(1, Int((Double(width) * factor).rounded())), height: max(1, Int((Double(height) * factor).rounded())))
    }

    /// Fits inside a long side, keeping the aspect ratio. Never enlarges.
    func fitting(longSide limit: Int) -> PixelSize {
        guard longSide > limit, limit > 0 else { return self }
        return scaled(by: Double(limit) / Double(longSide))
    }
}
