import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A photo to enhance: an imported file (its original bytes and metadata), a bundled sample, or a generated debug image.
struct PhotoAsset: Identifiable {
    let id = UUID()
    var title: String
    var data: Data?
    var url: URL?
    var generated: CGImage?
    var metadata: [String: Any]?
    var uprightSize: PixelSize

    /// Longest side decoded for full-resolution work. Larger photos are reduced to this first.
    static let maxWorkingPixel = 8192
    /// Files larger than this are refused before decoding.
    static let maxFileBytes = 250 * 1_024 * 1_024

    /// Reads photo bytes. Nil when they are not a readable image (corrupt, empty, not a photo, too big).
    static func from(data: Data, title: String) -> PhotoAsset? {
        guard !data.isEmpty, data.count <= maxFileBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = ImageDecoder.info(source),
              // Make sure it really decodes (a damaged file can have a valid header).
              ImageDecoder.decode(source, maxPixel: 64) != nil else { return nil }
        return PhotoAsset(title: title, data: data, url: nil, generated: nil,
                          metadata: ImageDecoder.metadata(data: data), uprightSize: info.uprightSize)
    }

    static func sample(named name: String) -> PhotoAsset? {
        guard let url = SampleLibrary.url(named: name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let info = ImageDecoder.info(source) else { return nil }
        return PhotoAsset(title: SampleLibrary.title(for: name), data: nil, url: url, generated: nil, metadata: nil, uprightSize: info.uprightSize)
    }

    static func generated(_ image: CGImage, title: String) -> PhotoAsset {
        PhotoAsset(title: title, data: nil, url: nil, generated: image, metadata: nil,
                   uprightSize: PixelSize(width: image.width, height: image.height))
    }

    /// Decodes upright at most `maxPixel` on the long side.
    func decode(maxPixel: Int) -> CGImage? {
        if let data { return ImageDecoder.decode(data: data, maxPixel: maxPixel) }
        if let url { return ImageDecoder.decode(url: url, maxPixel: maxPixel) }
        if let generated {
            let size = PixelSize(width: generated.width, height: generated.height)
            return size.longSide <= maxPixel ? generated : Enhancer.resize(generated, to: size.fitting(longSide: maxPixel))
        }
        return nil
    }

    /// The full-resolution working image: at most 8,192 px long and 48 MP.
    func decodeFull() -> CGImage? {
        var limit = min(Self.maxWorkingPixel, uprightSize.longSide)
        let mp = uprightSize.megapixels
        if mp > SizeCap.maxMegapixels {
            limit = min(limit, Int(Double(uprightSize.longSide) * (SizeCap.maxMegapixels / mp).squareRoot()))
        }
        return decode(maxPixel: limit)
    }
}

/// The size the person picks on the export screen.
enum ExportSize: Hashable {
    /// 1 = original size; 2, 4, 8 = AI upscale.
    case factor(Int)
    /// A long side in pixels.
    case custom(Int)

    var title: String {
        switch self {
        case .factor(1): return "Original"
        case .factor(let f): return "\(f)×"
        case .custom: return "Custom"
        }
    }

    var needsUpscaleModel: Bool {
        switch self {
        case .factor(let f): return f > 1
        case .custom: return false
        }
    }
}

struct ExportOptions: Equatable {
    var format: ImageFormat = .jpg
    var size: ExportSize = .factor(1)
    /// 0...1, for JPG and HEIC.
    var quality: Double = 0.92
    /// Keep camera details and location. Off strips all metadata, including GPS.
    var keepMetadata: Bool = false
}

/// One finished file, ready to be saved to Photos, shared or put in Files.
struct ExportItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let format: ImageFormat
    let pixelSize: PixelSize

    var utType: UTType { format.utType }
    var byteCount: Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    func deleteFile() { try? FileManager.default.removeItem(at: url) }
}

/// Makes the full-resolution export: replays the recipe on the original photo at the chosen size and writes the file.
enum ExportRenderer {
    static var exportsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClarivoExports", isDirectory: true)
    }

    /// Steps for the export: the recipe without its upscale step, plus the upscale the chosen size needs.
    static func operations(recipe: [EnhanceOperation], size: ExportSize, source: PixelSize) -> [EnhanceOperation] {
        var ops = recipe.filter { if case .upscale = $0 { return false }; return true }
        let factor: Int
        switch size {
        case .factor(let f): factor = f
        case .custom(let long): factor = SizeCap.factor(toReach: SizeCap.size(for: source, longSide: long), from: source)
        }
        if factor > 1 { ops.append(.upscale(factor: factor)) }
        return Recipe.normalized(ops)
    }

    /// Final pixel size for the options (before the cap is checked by the engine).
    static func expectedSize(source: PixelSize, size: ExportSize) -> (size: PixelSize, capped: Bool) {
        switch size {
        case .factor(let f):
            let plan = SizeCap.plan(source: source, scale: f)
            return (plan.output, plan.capApplied)
        case .custom(let long):
            let target = SizeCap.size(for: source, longSide: long)
            return (target, target.longSide < long)
        }
    }

    struct Result {
        var item: ExportItem
        var image: CGImage
        var notes: EnhanceNotes
    }

    static func render(
        _ asset: PhotoAsset,
        recipe: [EnhanceOperation],
        options: ExportOptions,
        enhancer: Enhancer = .shared,
        cancel: CancelToken,
        progress: @escaping (Double) -> Void
    ) async throws -> Result {
        guard let full = asset.decodeFull() else { throw EnhanceError.unreadableImage }
        let source = PixelSize(width: full.width, height: full.height)
        let ops = operations(recipe: recipe, size: options.size, source: source)
        var output = try await enhancer.run(ops, on: full, applyCap: true, cancel: cancel, progress: { progress($0 * 0.95) })
        if case .custom(let long) = options.size {
            let target = SizeCap.size(for: source, longSide: long)
            if output.image.width != target.width || output.image.height != target.height,
               let resized = Enhancer.resize(output.image, to: target) {
                output.image = resized
            }
        }
        try cancel.check()
        try FileManager.default.createDirectory(at: exportsFolder, withIntermediateDirectories: true)
        let url = exportsFolder.appendingPathComponent(fileName(for: asset.title, format: options.format))
        try ImageWriter.write(output.image, to: url, format: options.format, quality: options.quality,
                              sourceMetadata: asset.metadata, keepMetadata: options.keepMetadata)
        progress(1)
        let item = ExportItem(url: url, format: options.format, pixelSize: PixelSize(width: output.image.width, height: output.image.height))
        return Result(item: item, image: output.image, notes: output.notes)
    }

    /// "Clarivo-Old-portrait-20261125-0941-3F2A.jpg": readable, unique, safe characters only.
    static func fileName(for title: String, format: ImageFormat, date: Date = Date()) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = title.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let collapsed = cleaned.split(separator: "-").joined(separator: "-")
        let stem = collapsed.isEmpty ? "Photo" : String(collapsed.prefix(40))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = String(UUID().uuidString.prefix(4))
        return "Clarivo-\(stem)-\(formatter.string(from: date))-\(suffix).\(format.fileExtension)"
    }

    static func clearExports() {
        try? FileManager.default.removeItem(at: exportsFolder)
    }
}

// Photo assets and results are immutable values handed from background work to the screen.
extension PhotoAsset: @unchecked Sendable {}
extension ExportRenderer.Result: @unchecked Sendable {}
extension Enhancer.Output: @unchecked Sendable {}
