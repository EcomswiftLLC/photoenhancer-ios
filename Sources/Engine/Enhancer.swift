import Foundation
import CoreGraphics
import CoreML
import Vision
import CoreImage

/// Runs a recipe of enhancement steps on a photo. Pure engine: no UI. Call it off the main thread.
final class Enhancer: @unchecked Sendable {
    static let shared = Enhancer()

    let models: ModelProviding
    /// Overlap between neighbouring tiles, in model input pixels.
    static let overlap = 16
    /// Unblur looks further around each pixel, so its tiles overlap more.
    static let deblurOverlap = 32
    /// The colorize model's `ab` output in Lab units per output unit (DDColor gives Lab units directly).
    static var colorizeABScale: Float = 1
    /// What the last colorize run read from the model (type, shape, value ranges), for the quality report.
    static var lastColorizeDiagnostics = ""
    /// The exact model input of the last colorize run (quality report only).
    static var lastColorizeInput: CGImage?
    /// mean((|a| + |b|) / 2) below this means the colorize model produced no usable colour.
    static let minimumColorizeStrength: Float = 1.5
    /// Gaussian blur sigmas (model-input pixels) tried in turn on a colourless result.
    static let colorizeRetryBlurs: [Double] = [0, 1.5, 2.5]

    static func meanColour(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in 0..<a.count { sum += abs(a[i]) + abs(b[i]) }
        return sum / Float(a.count) / 2
    }

    /// Gaussian blur of a small image (edges clamped, so the border does not darken).
    static func blurred(_ image: RGBAImage, sigma: Double) -> RGBAImage? {
        guard let cg = image.makeCGImage() else { return nil }
        let ci = CIImage(cgImage: cg)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: ci.extent)
        guard let rendered = ClassicalOps.render(out, extent: ci.extent) else { return nil }
        return RGBAImage(cgImage: rendered)
    }

    init(models: ModelProviding = BundleModelProvider.shared) {
        self.models = models
    }

    struct Output {
        var image: CGImage
        var notes: EnhanceNotes
    }

    func isAvailable(_ tool: ToolKind) -> Bool {
        guard let kind = tool.requiredModel else { return true }
        return models.isAvailable(kind)
    }

    func isAvailable(_ operation: EnhanceOperation) -> Bool {
        guard let kind = operation.requiredModel else { return true }
        return models.isAvailable(kind)
    }

    /// Runs every step in pipeline order.
    /// - Parameter applyCap: reduce the input first when the upscaled output would pass `SizeCap`.
    func run(
        _ operations: [EnhanceOperation],
        on source: CGImage,
        applyCap: Bool = true,
        cancel: CancelToken = CancelToken(),
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> Output {
        let steps = Recipe.normalized(operations)
        var notes = EnhanceNotes()
        for step in steps {
            if let kind = step.requiredModel, !models.isAvailable(kind) { throw EnhanceError.modelUnavailable(kind) }
        }
        guard source.width > 0, source.height > 0 else { throw EnhanceError.unreadableImage }

        var current = source
        let scale = Recipe.totalScale(steps)
        if applyCap {
            let plan = SizeCap.plan(source: PixelSize(width: source.width, height: source.height), scale: scale)
            if plan.inputReduced {
                notes.capApplied = true
                notes.inputReduced = true
                guard let reduced = Self.resize(source, to: plan.input) else { throw EnhanceError.unreadableImage }
                current = reduced
            }
            let needed = MemoryGuard.estimatedPeakBytes(input: plan.input, output: plan.output, tileOut: 1024)
            if !MemoryGuard.canAfford(needed) { throw EnhanceError.memoryPressure }
        }
        if steps.isEmpty { return Output(image: current, notes: notes) }

        let share = 1.0 / Double(steps.count)
        for (index, step) in steps.enumerated() {
            try cancel.check()
            let base = Double(index) * share
            let report: (Double) -> Void = { value in progress(base + min(max(value, 0), 1) * share) }
            current = try await apply(step, to: current, notes: &notes, cancel: cancel, progress: report)
            report(1)
        }
        return Output(image: current, notes: notes)
    }

    // MARK: Steps

    private func apply(
        _ step: EnhanceOperation,
        to image: CGImage,
        notes: inout EnhanceNotes,
        cancel: CancelToken,
        progress: @escaping (Double) -> Void
    ) async throws -> CGImage {
        switch step {
        case .autoFix(let strength):
            return try unwrap(ClassicalOps.autoFix(image, strength: strength))
        case .sharpen(let strength):
            return try unwrap(ClassicalOps.sharpen(image, strength: strength))
        case .denoiseLight(let strength):
            return try unwrap(ClassicalOps.denoiseLight(image, strength: strength))
        case .restoreOld(let strength):
            return try unwrap(ClassicalOps.restoreOld(image, strength: strength))
        case .upscale(let factor):
            let rgba = try pixels(image)
            let out = try await superResolve(rgba, factor: factor, cancel: cancel, progress: progress)
            return try unwrap(out.makeCGImage())
        case .denoise(let strength):
            let rgba = try pixels(image)
            let cleaned = try await superResolve(rgba, factor: 1, cancel: cancel, progress: progress)
            return try unwrap(rgba.blended(with: cleaned, amount: strength).makeCGImage())
        case .unblur:
            if models.isAvailable(.deblur) {
                let rgba = try pixels(image)
                let out = try await deblur(rgba, cancel: cancel, progress: progress)
                return try unwrap(out.makeCGImage())
            }
            return try await unblurWithoutDeblurModel(image, cancel: cancel, progress: progress)
        case .colorize:
            let rgba = try pixels(image)
            if LabColor.isAlreadyColour(rgba.resized(width: min(rgba.width, 256), height: max(1, rgba.height * min(rgba.width, 256) / rgba.width))) {
                notes.alreadyColour = true
                notes.messages.append("This photo already has colour, so the result may look different from the original colours.")
            }
            let out = try await colorize(rgba, cancel: cancel)
            return try unwrap(out.makeCGImage())
        case .portrait:
            let (out, faces) = try await portrait(image, cancel: cancel, progress: progress)
            notes.facesFound = faces
            if faces == 0 { notes.messages.append("No faces were found in this photo, so Portrait changed nothing.") }
            return out
        }
    }

    // MARK: Super-resolution

    /// Upscales by 1 (supersampled denoise), 2, 4 or 8. 2x runs the 4x model and reduces each tile to 2x; 8x runs two
    /// passes (4x, then 2x). Tiles are processed one at a time.
    func superResolve(_ image: RGBAImage, factor: Int, cancel: CancelToken, progress: @escaping (Double) -> Void) async throws -> RGBAImage {
        guard let model = try await models.model(.superResolution) else { throw EnhanceError.modelUnavailable(.superResolution) }
        guard let spec = ModelSpec(model: model), spec.inputWidth == spec.inputHeight, spec.inputWidth >= 32 else {
            throw EnhanceError.modelFailed("Unexpected super-resolution model")
        }
        let passes: [Int]
        switch factor {
        case ...1: passes = [1]
        case 2: passes = [2]
        case 3...4: passes = [4]
        default: passes = [4, 2]
        }
        var current = image
        current.makeOpaque()
        for (index, passScale) in passes.enumerated() {
            let tile = spec.inputWidth
            let base = Double(index) / Double(passes.count)
            current = try TiledProcessor.process(current, tile: tile, overlap: Self.overlap, scale: passScale, cancel: cancel, progress: { value in
                progress(base + value / Double(passes.count))
            }) { tileIn in
                let out = try ModelRunner.runImageModel(model, spec: spec, tile: tileIn)
                let side = tile * passScale
                return (out.width == side && out.height == side) ? out : out.resized(width: side, height: side)
            }
        }
        return current
    }

    // MARK: Unblur

    func deblur(_ image: RGBAImage, cancel: CancelToken, progress: @escaping (Double) -> Void) async throws -> RGBAImage {
        guard let model = try await models.model(.deblur) else { throw EnhanceError.modelUnavailable(.deblur) }
        guard let spec = ModelSpec(model: model), spec.inputWidth == spec.inputHeight, spec.inputWidth > Self.deblurOverlap * 2 else {
            throw EnhanceError.modelFailed("Unexpected deblur model")
        }
        var input = image
        input.makeOpaque()
        let tile = spec.inputWidth
        let run: (RGBAImage) throws -> RGBAImage = { source in
            try TiledProcessor.process(source, tile: tile, overlap: Self.deblurOverlap, scale: 1, cancel: cancel, progress: progress) { tileIn in
                let out = try ModelRunner.runImageModel(model, spec: spec, tile: tileIn)
                return (out.width == tile && out.height == tile) ? out : out.resized(width: tile, height: tile)
            }
        }
        let longSide = max(input.width, input.height)
        guard longSide > Self.deblurWorkingLongSide else { return try run(input) }
        // The model learned camera shake at about 1280 x 720. On a big photo the same shake spans many more pixels, so
        // it runs on a copy at 2,048 px and only its correction is carried back to full size.
        let small = PixelSize(width: input.width, height: input.height).fitting(longSide: Self.deblurWorkingLongSide)
        let reduced = input.resized(width: small.width, height: small.height)
        let corrected = try run(reduced)
        return Self.transferCorrection(from: reduced, to: corrected, onto: input)
    }

    /// Unblur when the deblur model is not bundled: a little noise reduction (so sharpening does not lift grain), the
    /// super-resolution model at 1x when it is bundled (cleaner, crisper edges), then luminance sharpening.
    func unblurWithoutDeblurModel(_ image: CGImage, cancel: CancelToken, progress: @escaping (Double) -> Void) async throws -> CGImage {
        var current = try unwrap(ClassicalOps.denoiseLight(image, strength: 0.2))
        progress(0.1)
        try cancel.check()
        if models.isAvailable(.superResolution) {
            let rgba = try pixels(current)
            let cleaned = try await superResolve(rgba, factor: 1, cancel: cancel, progress: { progress(0.1 + $0 * 0.8) })
            current = try unwrap(cleaned.makeCGImage())
        }
        try cancel.check()
        return try unwrap(ClassicalOps.sharpen(current, strength: 0.75))
    }

    /// Longest side unblur works at; larger photos get the correction of a reduced copy.
    static let deblurWorkingLongSide = 2048

    /// `full + upscale(after - before)`: adds the change a step made on a reduced copy to the full-size photo.
    static func transferCorrection(from before: RGBAImage, to after: RGBAImage, onto full: RGBAImage) -> RGBAImage {
        guard before.width == after.width, before.height == after.height else { return full }
        // Signed difference, offset by 128 so it fits in bytes, then enlarged smoothly.
        var diff = [UInt8](repeating: 128, count: before.pixels.count)
        for i in 0..<diff.count where i % 4 != 3 {
            diff[i] = UInt8(min(255, max(0, Int(after.pixels[i]) - Int(before.pixels[i]) + 128)))
        }
        let enlarged = RGBAImage(width: before.width, height: before.height, pixels: diff).resized(width: full.width, height: full.height)
        var out = full.pixels
        for i in 0..<out.count where i % 4 != 3 {
            out[i] = UInt8(min(255, max(0, Int(out[i]) + Int(enlarged.pixels[i]) - 128)))
        }
        return RGBAImage(width: full.width, height: full.height, pixels: out)
    }

    // MARK: Colorize

    /// The model sees the photo's lightness at its own input size and predicts `ab` colour; the colour is laid under the
    /// original full-resolution lightness, so no detail is lost.
    func colorize(_ image: RGBAImage, cancel: CancelToken) async throws -> RGBAImage {
        guard let model = try await models.model(.colorize) else { throw EnhanceError.modelUnavailable(.colorize) }
        guard let spec = ModelSpec(model: model) else { throw EnhanceError.modelFailed("Unexpected colorize model") }
        try cancel.check()
        // The whole photo stretched to the model's input size; the model converts it to grey (L*) itself.
        var small = image.resized(width: spec.inputWidth, height: spec.inputHeight)
        small.makeOpaque()
        // DDColor tiny collapses to grey on some sharp, detailed old prints. Then the model input (only the small copy;
        // the colour is laid under the full-resolution lightness afterwards) is blurred a little and predicted again
        // (docs/MODELS.md, DDColorTiny step 5). Never blurred by default: that tints photos that colorize well.
        var value: MLFeatureValue?
        for sigma in Self.colorizeRetryBlurs {
            try cancel.check()
            let fed = sigma > 0 ? (Self.blurred(small, sigma: sigma) ?? small) : small
            Self.lastColorizeInput = ModelRunner.standardImage(fed)
            let input = try ModelRunner.inputValue(for: model, spec: spec, tile: fed)
            let provider = try MLDictionaryFeatureProvider(dictionary: [spec.inputName: input])
            let result = try await model.prediction(from: provider)
            guard let out = result.featureValue(for: spec.outputName) else { throw EnhanceError.modelFailed("No colorize output") }
            value = out
            guard let array = out.multiArrayValue else { break }
            let a = try ModelRunner.plane(array, channel: 0)
            let b = try ModelRunner.plane(array, channel: 1)
            let strength = Self.meanColour(a.values, b.values)
            Self.lastColorizeDiagnostics = "blur \(sigma) strength \(strength) "
                + "a[\(a.values.min() ?? 0), \(a.values.max() ?? 0)] b[\(b.values.min() ?? 0), \(b.values.max() ?? 0)]"
            if strength >= Self.minimumColorizeStrength {
                let scale = Self.colorizeABScale
                return LabColor.merge(
                    lightnessOf: image,
                    a: scale == 1 ? a.values : a.values.map { $0 * scale },
                    b: scale == 1 ? b.values : b.values.map { $0 * scale },
                    planeWidth: a.width, planeHeight: a.height
                )
            }
        }
        try cancel.check()
        guard let value else { throw EnhanceError.modelFailed("No colorize output") }
        // An `ab` array that stayed (almost) colourless on every try: say so instead of returning a grey photo.
        if value.multiArrayValue != nil { throw EnhanceError.noColourFound }
        if let buffer = value.imageBufferValue {
            // A model that returns a colour image: take its colour, keep the original lightness.
            let colour = try ModelRunner.rgba(from: buffer)
            var a = [Float](repeating: 0, count: colour.pixelCount), b = a
            for i in 0..<colour.pixelCount {
                let lab = LabColor.lab(r: colour.pixels[i * 4], g: colour.pixels[i * 4 + 1], b: colour.pixels[i * 4 + 2])
                a[i] = lab.a; b[i] = lab.b
            }
            return LabColor.merge(lightnessOf: image, a: a, b: b, planeWidth: colour.width, planeHeight: colour.height)
        }
        throw EnhanceError.modelFailed("Unexpected colorize output")
    }

    // MARK: Portrait

    /// Finds faces with Vision, enhances a padded crop around each one and blends it back with a soft oval mask.
    /// Uses the upscale model (supersampled at 1x) when it is bundled, otherwise light denoise and sharpening.
    func portrait(_ image: CGImage, cancel: CancelToken, progress: @escaping (Double) -> Void) async throws -> (CGImage, Int) {
        let faces = try Portrait.faceRects(in: image)
        guard !faces.isEmpty else { return (image, 0) }
        var canvas = try pixels(image)
        canvas.makeOpaque()
        let useModel = models.isAvailable(.superResolution)
        for (index, face) in faces.enumerated() {
            try cancel.check()
            let crop = Portrait.paddedCrop(face, in: PixelSize(width: canvas.width, height: canvas.height))
            guard crop.width >= 16, crop.height >= 16 else { continue }
            let region = canvas.crop(x: crop.minXInt, y: crop.minYInt, width: crop.widthInt, height: crop.heightInt)
            var enhanced: RGBAImage
            if useModel && max(region.width, region.height) <= 1400 {
                enhanced = try await superResolve(region, factor: 1, cancel: cancel, progress: { _ in })
            } else {
                enhanced = region
            }
            if let cg = enhanced.makeCGImage() {
                let cleaned = useModel ? cg : (ClassicalOps.denoiseLight(cg, strength: 0.4) ?? cg)
                if let sharp = ClassicalOps.sharpen(cleaned, strength: 0.35), let px = RGBAImage(cgImage: sharp) {
                    enhanced = px
                }
            }
            Portrait.blend(enhanced, into: &canvas, at: crop)
            progress(Double(index + 1) / Double(faces.count))
        }
        return (try unwrap(canvas.makeCGImage()), faces.count)
    }

    // MARK: Helpers

    private func pixels(_ image: CGImage) throws -> RGBAImage {
        guard let rgba = RGBAImage(cgImage: image) else { throw EnhanceError.memoryPressure }
        return rgba
    }

    private func unwrap(_ image: CGImage?) throws -> CGImage {
        guard let image else { throw EnhanceError.modelFailed("Rendering failed") }
        return image
    }

    /// High-quality resize of a CGImage.
    static func resize(_ image: CGImage, to size: PixelSize) -> CGImage? {
        if image.width == size.width && image.height == size.height { return image }
        guard let rgba = RGBAImage(cgImage: image) else { return nil }
        return rgba.resized(width: size.width, height: size.height).makeCGImage()
    }
}

/// Face finding and blending for Portrait.
enum Portrait {
    /// Face rectangles in pixel coordinates with the origin at the top left. At most 12, largest first.
    static func faceRects(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rects = (request.results ?? []).map { face -> CGRect in
            let box = face.boundingBox
            return CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
        }
        return Array(rects.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(12))
    }

    /// The face rectangle grown by half its size on each side (hair, chin and ears), kept inside the image.
    static func paddedCrop(_ face: CGRect, in size: PixelSize) -> CGRect {
        let grown = face.insetBy(dx: -face.width * 0.5, dy: -face.height * 0.5)
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let clipped = grown.intersection(bounds)
        guard !clipped.isNull else { return .zero }
        return CGRect(x: floor(clipped.minX), y: floor(clipped.minY), width: floor(clipped.width), height: floor(clipped.height))
    }

    /// Blends `patch` over `canvas` at `rect` with an oval mask: full inside 70 % of the radius, fading to nothing at the edge.
    static func blend(_ patch: RGBAImage, into canvas: inout RGBAImage, at rect: CGRect) {
        let x0 = rect.minXInt, y0 = rect.minYInt
        let w = min(patch.width, canvas.width - x0), h = min(patch.height, canvas.height - y0)
        guard w > 0, h > 0, x0 >= 0, y0 >= 0 else { return }
        let cx = Double(w) / 2, cy = Double(h) / 2
        let canvasWidth = canvas.width
        patch.pixels.withUnsafeBufferPointer { src in
            canvas.pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let dy = (Double(y) + 0.5 - cy) / cy
                    for x in 0..<w {
                        let dx = (Double(x) + 0.5 - cx) / cx
                        let d = (dx * dx + dy * dy).squareRoot()
                        let alpha: Double
                        if d <= 0.7 { alpha = 1 } else if d >= 1 { alpha = 0 } else {
                            let t = (1 - d) / 0.3
                            alpha = t * t * (3 - 2 * t)
                        }
                        if alpha <= 0 { continue }
                        let a = Int((alpha * 256).rounded()), b = 256 - a
                        let s = (y * patch.width + x) * 4
                        let o = ((y0 + y) * canvasWidth + x0 + x) * 4
                        for c in 0..<3 {
                            dst[o + c] = UInt8((Int(dst[o + c]) * b + Int(src[s + c]) * a + 128) >> 8)
                        }
                    }
                }
            }
        }
    }
}

extension CGRect {
    var minXInt: Int { Int(minX.rounded(.down)) }
    var minYInt: Int { Int(minY.rounded(.down)) }
    var widthInt: Int { Int(width.rounded(.down)) }
    var heightInt: Int { Int(height.rounded(.down)) }
}
