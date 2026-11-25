import Foundation
import CoreML
import CoreVideo
import CoreImage
import CoreGraphics

/// Loads the compiled Core ML models that ship in the app bundle. A model that is not bundled (for example a CI build
/// made before the models release existed) is reported as unavailable; nothing crashes.
final class BundleModelProvider: ModelProviding, @unchecked Sendable {
    static let shared = BundleModelProvider()

    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [ModelKind: MLModel] = [:]
    /// Neural Engine and GPU when present (`.all`). The simulator has neither, so it runs on the CPU there.
    var computeUnits: MLComputeUnits = .all

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func url(for kind: ModelKind) -> URL? {
        let name = kind.resourceName
        return bundle.url(forResource: name, withExtension: "mlmodelc")
            ?? bundle.url(forResource: name, withExtension: "mlmodelc", subdirectory: "Models")
    }

    func isAvailable(_ kind: ModelKind) -> Bool {
        url(for: kind) != nil
    }

    func model(_ kind: ModelKind) async throws -> MLModel? {
        lock.lock()
        if let cached = cache[kind] { lock.unlock(); return cached }
        lock.unlock()
        guard let url = url(for: kind) else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        lock.lock()
        cache[kind] = loaded
        lock.unlock()
        return loaded
    }

    /// Frees the loaded models (memory warning).
    func unloadAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

/// What a model takes and gives, read from the model itself so a changed spec in models-manifest.json needs no code change.
struct ModelSpec: Equatable {
    var inputName: String
    var inputWidth: Int
    var inputHeight: Int
    var outputName: String
    /// Output side over input side for image outputs (4 for the super-resolution model, 1 for deblur).
    var outputIsImage: Bool

    init(inputName: String, inputWidth: Int, inputHeight: Int, outputName: String, outputIsImage: Bool) {
        self.inputName = inputName
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputName = outputName
        self.outputIsImage = outputIsImage
    }

    init?(model: MLModel) {
        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.values.first(where: { $0.type == .image || $0.type == .multiArray }),
              let output = description.outputDescriptionsByName.values.sorted(by: { $0.name < $1.name })
                .first(where: { $0.type == .image || $0.type == .multiArray }) else { return nil }
        inputName = input.name
        if let constraint = input.imageConstraint {
            inputWidth = constraint.pixelsWide
            inputHeight = constraint.pixelsHigh
        } else if let shape = input.multiArrayConstraint?.shape.map({ $0.intValue }), shape.count >= 2 {
            inputWidth = shape[shape.count - 1]
            inputHeight = shape[shape.count - 2]
        } else {
            return nil
        }
        outputName = output.name
        outputIsImage = output.type == .image
    }
}

/// Runs one model on one tile and converts between the engine's RGBA pixels and Core ML values.
enum ModelRunner {
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// Runs an image-to-image model on a tile that is exactly the model's input size.
    static func runImageModel(_ model: MLModel, spec: ModelSpec, tile: RGBAImage) throws -> RGBAImage {
        let input = try inputValue(for: model, spec: spec, tile: tile)
        let provider = try MLDictionaryFeatureProvider(dictionary: [spec.inputName: input])
        let result = try model.prediction(from: provider)
        guard let value = result.featureValue(for: spec.outputName) else {
            throw EnhanceError.modelFailed("No output named \(spec.outputName)")
        }
        if let buffer = value.imageBufferValue {
            return try rgba(from: buffer)
        }
        if let array = value.multiArrayValue {
            return try rgba(fromCHW: array)
        }
        throw EnhanceError.modelFailed("Unexpected output type")
    }

    /// The model's input built from the tile: an image when the model takes an image, otherwise a (1,3,H,W) array in 0...1.
    static func inputValue(for model: MLModel, spec: ModelSpec, tile: RGBAImage) throws -> MLFeatureValue {
        let description = model.modelDescription.inputDescriptionsByName[spec.inputName]
        if let constraint = description?.imageConstraint {
            guard let cg = tile.makeCGImage() else { throw EnhanceError.modelFailed("Tile image") }
            return try MLFeatureValue(cgImage: cg, constraint: constraint, options: nil)
        }
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: tile.height), NSNumber(value: tile.width)], dataType: .float32)
        let plane = tile.width * tile.height
        let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
        tile.pixels.withUnsafeBufferPointer { p in
            for i in 0..<plane {
                pointer[i] = Float32(p[i * 4]) / 255
                pointer[plane + i] = Float32(p[i * 4 + 1]) / 255
                pointer[2 * plane + i] = Float32(p[i * 4 + 2]) / 255
            }
        }
        return MLFeatureValue(multiArray: array)
    }

    /// Reads a model's output pixel buffer (BGRA, RGBA, ARGB or one-channel grey) as RGBA.
    static func rgba(from buffer: CVPixelBuffer) throws -> RGBAImage {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { throw EnhanceError.modelFailed("Empty output") }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw EnhanceError.modelFailed("No pixels") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        let src = base.assumingMemoryBound(to: UInt8.self)
        switch format {
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32RGBA, kCVPixelFormatType_32ARGB:
            let order: (Int, Int, Int)
            switch format {
            case kCVPixelFormatType_32BGRA: order = (2, 1, 0)
            case kCVPixelFormatType_32ARGB: order = (1, 2, 3)
            default: order = (0, 1, 2)
            }
            for y in 0..<height {
                let row = src + y * rowBytes
                for x in 0..<width {
                    let s = x * 4, d = (y * width + x) * 4
                    out[d] = row[s + order.0]
                    out[d + 1] = row[s + order.1]
                    out[d + 2] = row[s + order.2]
                }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<height {
                let row = src + y * rowBytes
                for x in 0..<width {
                    let v = row[x], d = (y * width + x) * 4
                    out[d] = v; out[d + 1] = v; out[d + 2] = v
                }
            }
        default:
            // Anything else: let Core Image convert it.
            let image = CIImage(cvPixelBuffer: buffer)
            var rendered = [UInt8](repeating: 0, count: width * height * 4)
            rendered.withUnsafeMutableBytes { raw in
                if let address = raw.baseAddress {
                    ciContext.render(image, toBitmap: address, rowBytes: width * 4,
                                     bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                     format: .RGBA8, colorSpace: nil)
                }
            }
            out = rendered
            for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 }
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    /// Reads a (1,3,H,W) or (3,H,W) float array in 0...1 as RGBA.
    static func rgba(fromCHW array: MLMultiArray) throws -> RGBAImage {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 3 else { throw EnhanceError.modelFailed("Shape \(shape)") }
        let height = shape[shape.count - 2], width = shape[shape.count - 1], channels = shape[shape.count - 3]
        guard channels >= 3, width > 0, height > 0 else { throw EnhanceError.modelFailed("Shape \(shape)") }
        let strides = array.strides.map { $0.intValue }
        let cs = strides[strides.count - 3], hs = strides[strides.count - 2], ws = strides[strides.count - 1]
        var out = [UInt8](repeating: 255, count: width * height * 4)
        func store(_ read: (Int) -> Float) {
            for y in 0..<height {
                for x in 0..<width {
                    let d = (y * width + x) * 4
                    for c in 0..<3 {
                        let v = read(c * cs + y * hs + x * ws)
                        out[d + c] = UInt8(min(255, max(0, (v * 255).rounded())))
                    }
                }
            }
        }
        try withElements(array) { read in store(read) }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    /// Calls `body` with a reader for element `i` (in strides units) as Float. Uses `withUnsafeBytes`, which is also
    /// correct for arrays Core ML backs with a pixel buffer (Float16 outputs often are), where `dataPointer` is not.
    static func withElements(_ array: MLMultiArray, _ body: ((Int) -> Float) -> Void) throws {
        let type = array.dataType
        var handled = true
        array.withUnsafeBytes { raw in
            switch type {
            case .float32:
                let p = raw.bindMemory(to: Float32.self)
                body { $0 < p.count ? p[$0] : 0 }
            case .float16:
                let p = raw.bindMemory(to: UInt16.self)
                body { $0 < p.count ? halfToFloat(p[$0]) : 0 }
            case .double:
                let p = raw.bindMemory(to: Double.self)
                body { $0 < p.count ? Float(p[$0]) : 0 }
            case .int32:
                let p = raw.bindMemory(to: Int32.self)
                body { $0 < p.count ? Float(p[$0]) : 0 }
            default:
                handled = false
            }
        }
        if !handled {
            body { array[$0].floatValue }
        }
    }

    /// Reads one 2-D plane `channel` of a (1,C,H,W) or (C,H,W) array as floats (used for the colorize `ab` output).
    static func plane(_ array: MLMultiArray, channel: Int) throws -> (width: Int, height: Int, values: [Float]) {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 3 else { throw EnhanceError.modelFailed("Shape \(shape)") }
        let height = shape[shape.count - 2], width = shape[shape.count - 1], channels = shape[shape.count - 3]
        guard channel < channels, width > 0, height > 0 else { throw EnhanceError.modelFailed("Shape \(shape)") }
        // Core ML converts from whatever storage it used (Float16, pixel-buffer backed, padded strides) to plain
        // row-major Float32 scalars, so the index below is simply c * H * W + y * W + x.
        let shaped = MLShapedArray<Float>(converting: array)
        let scalars = shaped.scalars
        let planeSize = width * height
        let start = channel * planeSize
        guard scalars.count >= start + planeSize else { throw EnhanceError.modelFailed("Short array") }
        let values = Array(scalars[start..<(start + planeSize)])
        return (width, height, values)
    }
}

/// IEEE 754 half precision bits to Float (written out, so it builds for every simulator architecture).
@inline(__always)
func halfToFloat(_ bits: UInt16) -> Float {
    let sign = UInt32(bits & 0x8000) << 16
    let exponent = UInt32(bits & 0x7C00) >> 10
    let mantissa = UInt32(bits & 0x03FF)
    if exponent == 0 {
        if mantissa == 0 { return Float(bitPattern: sign) }
        // Subnormal.
        let value = Float(mantissa) / 1024 * pow(2, -14)
        return sign != 0 ? -value : value
    }
    if exponent == 0x1F {
        return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
    }
    return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
}
