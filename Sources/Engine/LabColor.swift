import Foundation

/// sRGB <-> CIE L*a*b* (D65), used to put a colorize model's `ab` colours under the photo's own full-resolution lightness.
/// Constants are identical to OpenCV's float `COLOR_RGB2Lab` / `COLOR_Lab2RGB`, which DDColor was trained with
/// (docs/MODELS.md).
enum LabColor {
    // D65 reference white.
    private static let xn: Float = 0.950_456, yn: Float = 1.0, zn: Float = 1.088_754

    /// sRGB byte -> linear 0...1.
    static let toLinear: [Float] = (0..<256).map { v in
        let c = Float(v) / 255
        return c <= 0.040_45 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// Linear 0...1 (4,096 steps) -> sRGB byte.
    private static let linearSteps = 4096
    private static let toSRGB: [UInt8] = (0...linearSteps).map { i in
        let c = Float(i) / Float(linearSteps)
        let s = c <= 0.003_130_8 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, (s * 255).rounded())))
    }

    @inline(__always) private static func f(_ t: Float) -> Float {
        t > 0.008_856 ? cbrtf(t) : (7.787 * t + 16 / 116)
    }

    @inline(__always) private static func finv(_ t: Float) -> Float {
        t > 0.206_893 ? t * t * t : (t - 16 / 116) / 7.787
    }

    @inline(__always) static func lab(r: UInt8, g: UInt8, b: UInt8) -> (L: Float, a: Float, b: Float) {
        let rl = toLinear[Int(r)], gl = toLinear[Int(g)], bl = toLinear[Int(b)]
        let x = (0.412_453 * rl + 0.357_580 * gl + 0.180_423 * bl) / xn
        let y = (0.212_671 * rl + 0.715_160 * gl + 0.072_169 * bl) / yn
        let z = (0.019_334 * rl + 0.119_193 * gl + 0.950_227 * bl) / zn
        let fx = f(x), fy = f(y), fz = f(z)
        let L = y > 0.008_856 ? 116 * cbrtf(y) - 16 : 903.3 * y
        return (L, 500 * (fx - fy), 200 * (fy - fz))
    }

    @inline(__always) static func rgb(L: Float, a: Float, b: Float) -> (UInt8, UInt8, UInt8) {
        let fy = (L + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        let y = L > 7.9996 ? fy * fy * fy : L / 903.3
        let x = finv(fx) * xn, z = finv(fz) * zn
        let rl = 3.240_479 * x - 1.537_150 * y - 0.498_535 * z
        let gl = -0.969_256 * x + 1.875_992 * y + 0.041_556 * z
        let bl = 0.055_648 * x - 0.204_043 * y + 1.057_311 * z
        return (encode(rl), encode(gl), encode(bl))
    }

    @inline(__always) private static func encode(_ linear: Float) -> UInt8 {
        let clamped = min(1, max(0, linear))
        return toSRGB[Int((clamped * Float(linearSteps)).rounded())]
    }

    /// The photo's lightness only, as grey RGB (what DDColor expects as input: L with a = b = 0).
    static func grayscaleLightness(_ image: RGBAImage) -> RGBAImage {
        var out = image.pixels
        out.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                let L = lab(r: p[i], g: p[i + 1], b: p[i + 2]).L
                let (r, g, b) = rgb(L: L, a: 0, b: 0)
                p[i] = r; p[i + 1] = g; p[i + 2] = b; p[i + 3] = 255
                i += 4
            }
        }
        return RGBAImage(width: image.width, height: image.height, pixels: out)
    }

    /// Combines the full-resolution lightness of `image` with `a`/`b` planes of any size (bilinear sampled).
    static func merge(lightnessOf image: RGBAImage, a: [Float], b: [Float], planeWidth: Int, planeHeight: Int, amount: Float = 1) -> RGBAImage {
        guard planeWidth > 0, planeHeight > 0, a.count == planeWidth * planeHeight, b.count == a.count else { return image }
        var out = image.pixels
        let w = image.width, h = image.height
        let sx = Float(planeWidth) / Float(w), sy = Float(planeHeight) / Float(h)
        let t = min(max(amount, 0), 1)
        out.withUnsafeMutableBufferPointer { p in
            for y in 0..<h {
                let fyp = max(0, (Float(y) + 0.5) * sy - 0.5)
                let y0 = min(Int(fyp), planeHeight - 1), y1 = min(y0 + 1, planeHeight - 1)
                let wy = fyp - Float(y0)
                for x in 0..<w {
                    let fxp = max(0, (Float(x) + 0.5) * sx - 0.5)
                    let x0 = min(Int(fxp), planeWidth - 1), x1 = min(x0 + 1, planeWidth - 1)
                    let wx = fxp - Float(x0)
                    func sample(_ plane: [Float]) -> Float {
                        let top = plane[y0 * planeWidth + x0] * (1 - wx) + plane[y0 * planeWidth + x1] * wx
                        let bottom = plane[y1 * planeWidth + x0] * (1 - wx) + plane[y1 * planeWidth + x1] * wx
                        return top * (1 - wy) + bottom * wy
                    }
                    let o = (y * w + x) * 4
                    let source = lab(r: p[o], g: p[o + 1], b: p[o + 2])
                    let na = source.a + (sample(a) - source.a) * t
                    let nb = source.b + (sample(b) - source.b) * t
                    let (r, g, bb) = rgb(L: source.L, a: na, b: nb)
                    p[o] = r; p[o + 1] = g; p[o + 2] = bb; p[o + 3] = 255
                }
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// Mean chroma and the share of clearly coloured pixels, measured on at most ~65k pixels.
    static func colourfulness(_ image: RGBAImage) -> (meanChroma: Float, colouredShare: Float) {
        let step = max(1, image.pixelCount / 65_536)
        var sum: Float = 0, coloured = 0, n = 0
        image.pixels.withUnsafeBufferPointer { p in
            var i = 0
            while i < image.pixelCount {
                let o = i * 4
                let c = lab(r: p[o], g: p[o + 1], b: p[o + 2])
                let chroma = (c.a * c.a + c.b * c.b).squareRoot()
                sum += chroma
                if chroma > 15 { coloured += 1 }
                n += 1
                i += step
            }
        }
        guard n > 0 else { return (0, 0) }
        return (sum / Float(n), Float(coloured) / Float(n))
    }

    /// True for a photo that already has real colour (not black and white, and not a single sepia or blue tone).
    static func isAlreadyColour(_ image: RGBAImage) -> Bool {
        let measure = colourfulness(image)
        if measure.colouredShare < 0.06 { return false }
        // A toned print (sepia, cyanotype) has chroma, but all of it points the same way. Check hue spread.
        return hueSpread(image) > 0.35 && measure.meanChroma > 6
    }

    /// 0 when every coloured pixel has the same hue, towards 1 when hues are spread around the circle.
    static func hueSpread(_ image: RGBAImage) -> Float {
        let step = max(1, image.pixelCount / 65_536)
        var sx: Float = 0, sy: Float = 0, n: Float = 0
        image.pixels.withUnsafeBufferPointer { p in
            var i = 0
            while i < image.pixelCount {
                let o = i * 4
                let c = lab(r: p[o], g: p[o + 1], b: p[o + 2])
                let chroma = (c.a * c.a + c.b * c.b).squareRoot()
                if chroma > 10 {
                    sx += c.a / chroma
                    sy += c.b / chroma
                    n += 1
                }
                i += step
            }
        }
        guard n > 0 else { return 0 }
        let resultant = (sx * sx + sy * sy).squareRoot() / n
        return 1 - resultant
    }
}
