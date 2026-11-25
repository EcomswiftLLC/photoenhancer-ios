import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Enhancements that need no model: Core Image filters and a few pixel operations written out in Swift.
enum ClassicalOps {
    /// One shared context. Rendering huge images is tiled by Core Image itself.
    static let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    static func render(_ image: CIImage, extent: CGRect) -> CGImage? {
        context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: RGBAImage.colorSpace)
    }

    /// Radii scale with the photo, so a 12 MP photo and its 1,600 px preview look alike. 1 at 2,000 px on the long side.
    static func resolutionFactor(_ image: CGImage) -> Double {
        max(0.35, Double(max(image.width, image.height)) / 2000)
    }

    // MARK: Auto fix

    /// Core Image's automatic adjustments (no red-eye, no face pass), a gentle S tone curve and a little vibrance,
    /// mixed with the original by `strength`.
    static func autoFix(_ image: CGImage, strength: Float) -> CGImage? {
        let original = CIImage(cgImage: image)
        var adjusted = original
        for filter in original.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(adjusted, forKey: kCIInputImageKey)
            if let output = filter.outputImage { adjusted = output }
        }
        let curve = CIFilter.toneCurve()
        curve.inputImage = adjusted
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: 0.25, y: 0.23)
        curve.point2 = CGPoint(x: 0.5, y: 0.5)
        curve.point3 = CGPoint(x: 0.75, y: 0.77)
        curve.point4 = CGPoint(x: 1, y: 1)
        adjusted = curve.outputImage ?? adjusted
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = adjusted
        vibrance.amount = 0.22
        adjusted = vibrance.outputImage ?? adjusted
        return render(mix(original, adjusted, strength), extent: original.extent)
    }

    // MARK: Sharpen

    /// Luminance sharpening plus a soft unsharp mask, so colour edges do not fringe.
    static func sharpen(_ image: CGImage, strength: Float) -> CGImage? {
        let s = Double(min(max(strength, 0), 1))
        let k = resolutionFactor(image)
        let original = CIImage(cgImage: image)
        let lum = CIFilter.sharpenLuminance()
        lum.inputImage = original.clampedToExtent()
        lum.sharpness = Float(0.55 * s)
        lum.radius = Float(1.4 * k)
        var out = lum.outputImage ?? original
        let usm = CIFilter.unsharpMask()
        usm.inputImage = out
        usm.radius = Float(2.2 * k)
        usm.intensity = Float(0.55 * s)
        out = (usm.outputImage ?? out).cropped(to: original.extent)
        return render(out, extent: original.extent)
    }

    // MARK: Light denoise

    static func denoiseLight(_ image: CGImage, strength: Float) -> CGImage? {
        let s = Double(min(max(strength, 0), 1))
        let original = CIImage(cgImage: image)
        let filter = CIFilter.noiseReduction()
        filter.inputImage = original.clampedToExtent()
        filter.noiseLevel = Float(0.008 + 0.045 * s)
        filter.sharpness = Float(0.45 - 0.2 * s)
        let out = (filter.outputImage ?? original).cropped(to: original.extent)
        return render(out, extent: original.extent)
    }

    // MARK: Restore old photo

    /// Classical restoration: dust and thin scratches are found as thin bright or dark structures (morphological
    /// top-hat) and replaced with the surrounding tones, then faded and yellowed tones are stretched back per channel.
    static func restoreOld(_ image: CGImage, strength: Float) -> CGImage? {
        let s = Double(min(max(strength, 0), 1))
        let cleaned = removeScratches(image, strength: s) ?? image
        guard var pixels = RGBAImage(cgImage: cleaned) else { return cleaned }
        let levels = Levels.measure(pixels, lowPercentile: 0.004, highPercentile: 0.996)
        levels.apply(to: &pixels, amount: Float(0.55 + 0.45 * s))
        guard let toned = pixels.makeCGImage() else { return cleaned }
        if s > 0.25 {
            return denoiseLight(toned, strength: Float(0.25 * s)) ?? toned
        }
        return toned
    }

    /// Replaces thin bright and dark marks (narrower than the morphology radius) with an opening/closing of the photo.
    static func removeScratches(_ image: CGImage, strength s: Double) -> CGImage? {
        let original = CIImage(cgImage: image)
        let extent = original.extent
        let radius = Double(min(4, max(1, Int((resolutionFactor(image) * 1.6).rounded()))))
        let clamped = original.clampedToExtent()

        func morph(_ input: CIImage, _ name: String) -> CIImage {
            input.applyingFilter(name, parameters: [kCIInputRadiusKey: radius])
        }
        let opened = morph(morph(clamped, "CIMorphologyMinimum"), "CIMorphologyMaximum")
        let closed = morph(morph(clamped, "CIMorphologyMaximum"), "CIMorphologyMinimum")
        // Higher strength removes fainter marks.
        let threshold = Float(0.2 - 0.12 * s)

        func mask(_ difference: CIImage) -> CIImage {
            let gray = difference.applyingFilter("CIMaximumComponent")
            let thresholdFilter = CIFilter.colorThreshold()
            thresholdFilter.inputImage = gray
            thresholdFilter.threshold = threshold
            let hard = thresholdFilter.outputImage ?? gray
            let grown = hard.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.0])
            return grown.applyingGaussianBlur(sigma: 0.8)
        }
        // Bright marks: |image - opening| (opening <= image). Dark marks: |closing - image| (closing >= image).
        let bright = opened.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: clamped])
        let dark = closed.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: clamped])
        let step1 = opened.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clamped, kCIInputMaskImageKey: mask(bright),
        ])
        let step2 = closed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: step1, kCIInputMaskImageKey: mask(dark),
        ])
        return render(step2.cropped(to: extent), extent: extent)
    }

    // MARK: Helpers

    /// `amount` 0 keeps `a`, 1 gives `b`.
    static func mix(_ a: CIImage, _ b: CIImage, _ amount: Float) -> CIImage {
        let t = min(max(amount, 0), 1)
        if t >= 0.999 { return b }
        if t <= 0.001 { return a }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = a
        dissolve.targetImage = b
        dissolve.time = t
        return dissolve.outputImage ?? b
    }
}

/// Per-channel black and white points, measured from a histogram (auto levels). Stretching each channel separately
/// also neutralises an overall yellow or magenta cast of a faded print.
struct Levels: Equatable {
    var low: [Int]
    var high: [Int]

    static func measure(_ image: RGBAImage, lowPercentile: Double, highPercentile: Double) -> Levels {
        var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
        // Sample at most ~250k pixels.
        let step = max(1, image.pixelCount / 250_000)
        var counted = 0
        image.pixels.withUnsafeBufferPointer { p in
            var i = 0
            while i < image.pixelCount {
                let o = i * 4
                histograms[0][Int(p[o])] += 1
                histograms[1][Int(p[o + 1])] += 1
                histograms[2][Int(p[o + 2])] += 1
                counted += 1
                i += step
            }
        }
        var low = [0, 0, 0], high = [255, 255, 255]
        for c in 0..<3 {
            let lowTarget = Int(Double(counted) * lowPercentile)
            let highTarget = Int(Double(counted) * highPercentile)
            var sum = 0
            var foundLow = false
            for v in 0..<256 {
                sum += histograms[c][v]
                if !foundLow && sum > lowTarget { low[c] = v; foundLow = true }
                if sum >= highTarget { high[c] = v; break }
            }
        }
        return Levels(low: low, high: high)
    }

    /// Lookup tables mapping each channel's [low, high] to [0, 255], mixed with identity by `amount`.
    func tables(amount: Float) -> [[UInt8]] {
        (0..<3).map { c in
            let lo = Double(low[c]), hi = Double(max(high[c], low[c] + 16))
            return (0..<256).map { v in
                let stretched = min(255, max(0, (Double(v) - lo) / (hi - lo) * 255))
                let mixed = Double(v) + (stretched - Double(v)) * Double(amount)
                return UInt8(min(255, max(0, mixed.rounded())))
            }
        }
    }

    func apply(to image: inout RGBAImage, amount: Float) {
        let t = tables(amount: amount)
        image.pixels.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                p[i] = t[0][Int(p[i])]
                p[i + 1] = t[1][Int(p[i + 1])]
                p[i + 2] = t[2][Int(p[i + 2])]
                i += 4
            }
        }
    }
}
