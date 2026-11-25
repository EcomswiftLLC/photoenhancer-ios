import Foundation
import CoreGraphics
import CoreML

/// One enhancement step. The engine always runs the steps of a recipe in a fixed order (see `stage`), whatever order
/// they were chosen in, so the result is predictable: repair first, then colour and detail, upscale last.
enum EnhanceOperation: Equatable, Hashable, Codable {
    case upscale(factor: Int)
    case unblur
    /// AI noise reduction (supersampled through the super-resolution model), blended with the original by `strength`.
    case denoise(strength: Float)
    /// Core Image noise reduction, the light option. Needs no model.
    case denoiseLight(strength: Float)
    case portrait
    case colorize
    case restoreOld(strength: Float)
    case autoFix(strength: Float)
    case sharpen(strength: Float)

    var kind: ToolKind {
        switch self {
        case .upscale: return .upscale
        case .unblur: return .unblur
        case .denoise, .denoiseLight: return .denoise
        case .portrait: return .portrait
        case .colorize: return .colorize
        case .restoreOld: return .restore
        case .autoFix: return .autoFix
        case .sharpen: return .sharpen
        }
    }

    /// Position in the pipeline (lower runs first).
    var stage: Int {
        switch self {
        case .restoreOld: return 0
        case .colorize: return 1
        case .denoise, .denoiseLight: return 2
        case .unblur: return 3
        case .portrait: return 4
        case .autoFix: return 5
        case .sharpen: return 6
        case .upscale: return 7
        }
    }

    /// The model this step needs, or nil for classical steps.
    var requiredModel: ModelKind? {
        switch self {
        case .upscale, .denoise: return .superResolution
        case .unblur: return .deblur
        case .colorize: return .colorize
        case .portrait, .denoiseLight, .restoreOld, .autoFix, .sharpen: return nil
        }
    }

    /// Output size over input size.
    var scale: Int {
        if case .upscale(let factor) = self { return max(1, factor) }
        return 1
    }
}

/// The tools shown in the workspace. One tool can hold one step of the recipe.
enum ToolKind: String, CaseIterable, Identifiable, Codable {
    case upscale, unblur, denoise, portrait, colorize, restore, autoFix, sharpen
    var id: String { rawValue }

    var title: String {
        switch self {
        case .upscale: return "Upscale"
        case .unblur: return "Unblur"
        case .denoise: return "Remove noise"
        case .portrait: return "Portrait"
        case .colorize: return "Colorize"
        case .restore: return "Restore old photo"
        case .autoFix: return "Auto fix"
        case .sharpen: return "Sharpen"
        }
    }

    /// Short title for the tool strip.
    var shortTitle: String {
        switch self {
        case .restore: return "Restore"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .upscale: return "arrow.up.left.and.arrow.down.right"
        case .unblur: return "camera.metering.spot"
        case .denoise: return "circle.dotted"
        case .portrait: return "person.crop.square"
        case .colorize: return "paintpalette"
        case .restore: return "photo.badge.checkmark"
        case .autoFix: return "wand.and.stars"
        case .sharpen: return "triangle.lefthalf.filled"
        }
    }

    /// One honest line about what the tool does.
    var blurb: String {
        switch self {
        case .upscale: return "Adds pixels with an on-device AI model, for crisp prints and crops."
        case .unblur: return "Reduces motion blur and camera shake. It cannot bring back detail the camera never caught."
        case .denoise: return "Smooths grain from low light. Light keeps the most texture, AI cleans the most."
        case .portrait: return "Finds faces and enhances them with the upscale model, blended softly into the photo."
        case .colorize: return "Adds natural colour to black-and-white photos. Colours are a model's best guess."
        case .restore: return "Removes dust and thin scratches, and lifts faded, yellowed tones."
        case .autoFix: return "Balances light and colour in one tap."
        case .sharpen: return "Crisps up mild softness. Keep it low to avoid halos."
        }
    }

    var requiredModel: ModelKind? {
        switch self {
        case .upscale: return .superResolution
        case .unblur: return .deblur
        case .colorize: return .colorize
        default: return nil
        }
    }
}

enum ModelKind: String, CaseIterable, Codable {
    case superResolution, deblur, colorize

    /// Base name of the compiled model in the app bundle (`<name>.mlmodelc`).
    var resourceName: String {
        switch self {
        case .superResolution: return "ESRGANGeneral"
        case .deblur: return "NAFNetDeblur"
        case .colorize: return "DDColorTiny"
        }
    }
}

enum EnhanceError: Error, Equatable {
    /// The model this step needs is not in this build.
    case modelUnavailable(ModelKind)
    /// The photo could not be read.
    case unreadableImage
    case cancelled
    /// iOS reported low memory, so the work stopped before the app could be closed.
    case memoryPressure
    /// The model ran but returned something unexpected.
    case modelFailed(String)
    case writeFailed

    var message: String {
        switch self {
        case .modelUnavailable(let kind):
            switch kind {
            case .superResolution: return "The upscale model is not included in this build, so Upscale and AI Denoise are off."
            case .deblur: return "The unblur model is not included in this build. Try Sharpen for mild softness."
            case .colorize: return "The colorize model is not included in this build."
            }
        case .unreadableImage: return "This file could not be opened as a photo. Try a JPEG, HEIC or PNG."
        case .cancelled: return "Stopped. Nothing was changed."
        case .memoryPressure: return "Your device ran low on memory, so Clarivo stopped. Try a smaller size or close other apps."
        case .modelFailed: return "The enhancement did not finish. Try again, or choose a smaller size."
        case .writeFailed: return "The file could not be written. Free some space and try again."
        }
    }
}

/// What the engine reports about a finished run, in plain words for the screen.
struct EnhanceNotes: Equatable {
    /// The output was limited by the size cap (long side and megapixels).
    var capApplied = false
    /// The input was reduced first so the output stays inside the cap.
    var inputReduced = false
    var facesFound: Int?
    /// Colorize was asked for on a photo that already has colour.
    var alreadyColour = false
    var messages: [String] = []
}

/// A photo plus the steps to run on it.
struct EnhanceJob {
    var source: CGImage
    var operations: [EnhanceOperation]

    /// Steps in pipeline order, one per tool (the last one chosen for a tool wins).
    var orderedOperations: [EnhanceOperation] { Recipe.normalized(operations) }
}

enum Recipe {
    /// One step per tool, sorted by pipeline stage.
    static func normalized(_ operations: [EnhanceOperation]) -> [EnhanceOperation] {
        var byKind: [ToolKind: EnhanceOperation] = [:]
        for op in operations { byKind[op.kind] = op }
        return byKind.values.sorted { $0.stage < $1.stage }
    }

    static func totalScale(_ operations: [EnhanceOperation]) -> Int {
        normalized(operations).reduce(1) { $0 * $1.scale }
    }
}

/// Loads Core ML models. Returns nil when a model is not bundled.
protocol ModelProviding: AnyObject {
    func model(_ kind: ModelKind) async throws -> MLModel?
    func isAvailable(_ kind: ModelKind) -> Bool
}

/// Lets long work stop between tiles: cancelled by the person or by a memory warning.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _memory = false

    init() {}

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    var isMemoryPressure: Bool { lock.lock(); defer { lock.unlock() }; return _memory }

    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
    func cancelForMemory() { lock.lock(); _cancelled = true; _memory = true; lock.unlock() }

    /// Throws `.memoryPressure` or `.cancelled` when the work should stop, also when the Swift task was cancelled.
    func check() throws {
        if isMemoryPressure { throw EnhanceError.memoryPressure }
        if isCancelled || Task.isCancelled { throw EnhanceError.cancelled }
    }
}
