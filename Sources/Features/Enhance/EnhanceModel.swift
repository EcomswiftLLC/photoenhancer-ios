import SwiftUI
import UIKit

/// Choices for every tool. A tool that is "on" adds one step to the recipe.
struct ToolSettings: Equatable {
    enum DenoiseMode: String, CaseIterable, Identifiable {
        case light, ai
        var id: String { rawValue }
        var title: String { self == .light ? "Light" : "AI" }
    }

    var enabled: Set<ToolKind> = []
    var upscaleFactor: Int = 2
    var denoiseMode: DenoiseMode = .light
    var denoiseStrength: Double = 0.6
    var restoreStrength: Double = 0.6
    var autoFixStrength: Double = 0.8
    var sharpenStrength: Double = 0.4

    func operation(for tool: ToolKind) -> EnhanceOperation {
        switch tool {
        case .upscale: return .upscale(factor: upscaleFactor)
        case .unblur: return .unblur
        case .denoise:
            return denoiseMode == .ai ? .denoise(strength: Float(denoiseStrength)) : .denoiseLight(strength: Float(denoiseStrength))
        case .portrait: return .portrait
        case .colorize: return .colorize
        case .restore: return .restoreOld(strength: Float(restoreStrength))
        case .autoFix: return .autoFix(strength: Float(autoFixStrength))
        case .sharpen: return .sharpen(strength: Float(sharpenStrength))
        }
    }

    var recipe: [EnhanceOperation] {
        Recipe.normalized(enabled.map { operation(for: $0) })
    }

    /// Ready-made recipes for the batch screen and quick starts.
    enum Preset: String, CaseIterable, Identifiable {
        case autoEnhance, sharpenUp, oldPhoto, upscale2x, upscale4x, cleanLowLight
        var id: String { rawValue }

        var title: String {
            switch self {
            case .autoEnhance: return "Auto enhance"
            case .sharpenUp: return "Unblur and sharpen"
            case .oldPhoto: return "Old photo"
            case .upscale2x: return "Upscale 2×"
            case .upscale4x: return "Upscale 4×"
            case .cleanLowLight: return "Low light"
            }
        }

        var detail: String {
            switch self {
            case .autoEnhance: return "Auto fix and a light sharpen."
            case .sharpenUp: return "Unblur, then sharpen gently."
            case .oldPhoto: return "Restore, then colorize black-and-white prints."
            case .upscale2x: return "Twice the pixels, with auto fix."
            case .upscale4x: return "Four times the pixels."
            case .cleanLowLight: return "AI noise removal, then auto fix."
            }
        }

        var settings: ToolSettings {
            var s = ToolSettings()
            switch self {
            case .autoEnhance: s.enabled = [.autoFix, .sharpen]; s.sharpenStrength = 0.3
            case .sharpenUp: s.enabled = [.unblur, .sharpen]; s.sharpenStrength = 0.3
            case .oldPhoto: s.enabled = [.restore, .colorize]
            case .upscale2x: s.enabled = [.upscale, .autoFix]; s.upscaleFactor = 2; s.autoFixStrength = 0.6
            case .upscale4x: s.enabled = [.upscale]; s.upscaleFactor = 4
            case .cleanLowLight: s.enabled = [.denoise, .autoFix]; s.denoiseMode = .ai; s.denoiseStrength = 0.8
            }
            return s
        }

        var requiredModels: Set<ModelKind> {
            Set(settings.recipe.compactMap(\.requiredModel))
        }
    }
}

/// The Enhance workspace: a downscaled working copy is enhanced for the comparison; Export replays the same recipe on
/// the full-resolution photo.
@MainActor
final class EnhanceModel: ObservableObject {
    let asset: PhotoAsset
    let enhancer: Enhancer

    @Published var settings = ToolSettings()
    @Published var selectedTool: ToolKind = .autoFix
    @Published private(set) var beforeImage: UIImage?
    @Published private(set) var afterImage: UIImage?
    @Published private(set) var isProcessing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    @Published var divider: Double = 0.5

    /// Longest side of the working copy for the comparison.
    static let previewLongSide = 1280
    /// An upscaled preview is kept at most this long.
    static let previewOutputLimit = 4096

    private var base: CGImage?
    private var task: Task<Void, Never>?
    private var token: CancelToken?
    private var watchID: UUID?
    private var generation = 0
    /// Results of recipe prefixes for the current base, so changing a later step does not rerun the models.
    private var cache: [String: CGImage] = [:]
    private var cacheBaseKey = ""

    init(asset: PhotoAsset, enhancer: Enhancer = .shared, initial: ToolSettings? = nil) {
        self.asset = asset
        self.enhancer = enhancer
        if let initial { settings = initial }
    }

    func isAvailable(_ tool: ToolKind) -> Bool { enhancer.isAvailable(tool) }

    var unavailableNote: String? {
        let missing = ToolKind.allCases.filter { !isAvailable($0) }
        guard !missing.isEmpty else { return nil }
        return "\(missing.map(\.title).joined(separator: ", ")) need AI models that are not in this build."
    }

    /// Loads the working copy and shows the photo. Call once when the screen appears.
    func load() async {
        guard base == nil else { return }
        let asset = self.asset
        let limit = Self.previewLongSide
        let image = await Task.detached(priority: .userInitiated) { asset.decode(maxPixel: limit) }.value
        guard let image else {
            errorMessage = EnhanceError.unreadableImage.message
            return
        }
        base = image
        beforeImage = UIImage(cgImage: image)
        if !settings.enabled.isEmpty { run() }
    }

    func toggle(_ tool: ToolKind) {
        guard isAvailable(tool) else {
            if let model = tool.requiredModel { errorMessage = EnhanceError.modelUnavailable(model).message }
            return
        }
        if settings.enabled.contains(tool) { settings.enabled.remove(tool) } else { settings.enabled.insert(tool) }
        run()
    }

    func setEnabled(_ tool: ToolKind, _ on: Bool) {
        guard isAvailable(tool) || !on else { return }
        if on { settings.enabled.insert(tool) } else { settings.enabled.remove(tool) }
        run()
    }

    /// Re-runs after a control changed (sliders call this when the finger lifts).
    func settingsChanged() {
        run()
    }

    func reset() {
        settings.enabled = []
        run()
    }

    var hasChanges: Bool { !settings.enabled.isEmpty }

    func cancel() {
        token?.cancel()
        task?.cancel()
        isProcessing = false
        progress = 0
        message = "Stopped. The comparison shows the last finished result."
    }

    // MARK: Running

    private func previewInput(for recipe: [EnhanceOperation]) -> CGImage? {
        guard let base else { return nil }
        let scale = Recipe.totalScale(recipe)
        let size = PixelSize(width: base.width, height: base.height)
        let limit = max(256, Self.previewOutputLimit / max(1, scale))
        if size.longSide <= limit { return base }
        return Enhancer.resize(base, to: size.fitting(longSide: limit))
    }

    func run() {
        token?.cancel()
        task?.cancel()
        errorMessage = nil
        message = nil
        generation += 1
        let id = generation
        let recipe = settings.recipe
        guard let input = previewInput(for: recipe) else { return }
        let baseKey = "\(input.width)x\(input.height)"
        if baseKey != cacheBaseKey {
            cache = [:]
            cacheBaseKey = baseKey
        }
        beforeImage = UIImage(cgImage: input)
        if recipe.isEmpty {
            afterImage = nil
            isProcessing = false
            return
        }
        let newToken = CancelToken()
        token = newToken
        if let watchID { MemoryWatcher.shared.unregister(watchID) }
        watchID = MemoryWatcher.shared.register(newToken)
        isProcessing = true
        progress = 0
        let enhancer = self.enhancer
        let cached = cache
        let relay = ProgressRelay { [weak self] value in self?.report(value, id: id) }
        task = Task { [weak self] in
            var stepNotes = EnhanceNotes()
            do {
                // Step by step, reusing finished prefixes.
                var current = input
                var newEntries: [String: CGImage] = [:]
                var key = ""
                for (index, step) in recipe.enumerated() {
                    key += "|\(step)"
                    if let hit = cached[key] {
                        current = hit
                        continue
                    }
                    let source = current
                    let count = Double(recipe.count)
                    let output = try await Task.detached(priority: .userInitiated) {
                        try await enhancer.run([step], on: source, applyCap: true, cancel: newToken) { value in
                            relay.send((Double(index) + value) / count)
                        }
                    }.value
                    current = output.image
                    newEntries[key] = output.image
                    stepNotes.capApplied = stepNotes.capApplied || output.notes.capApplied
                    stepNotes.messages += output.notes.messages
                    if let faces = output.notes.facesFound { stepNotes.facesFound = faces }
                }
                guard let self, id == self.generation else { return }
                for (k, v) in newEntries { self.cache[k] = v }
                if self.cache.count > 8 { self.cache = newEntries }
                self.afterImage = UIImage(cgImage: current)
                self.isProcessing = false
                self.progress = 1
                self.message = Self.describe(stepNotes)
            } catch let error as EnhanceError {
                guard let self, id == self.generation else { return }
                self.isProcessing = false
                if error != .cancelled { self.errorMessage = error.message }
            } catch {
                guard let self, id == self.generation else { return }
                self.isProcessing = false
                self.errorMessage = EnhanceError.modelFailed("\(error)").message
            }
            if let self, let watch = self.watchID, id == self.generation {
                MemoryWatcher.shared.unregister(watch)
                self.watchID = nil
            }
        }
    }

    private func report(_ value: Double, id: Int) {
        guard id == generation, isProcessing else { return }
        progress = max(progress, min(max(value, 0), 1))
    }

    static func describe(_ notes: EnhanceNotes) -> String? {
        var lines = notes.messages
        if let faces = notes.facesFound, faces > 0 {
            lines.append(faces == 1 ? "Enhanced 1 face." : "Enhanced \(faces) faces.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    /// The export size that matches the workspace's upscale choice.
    var defaultExportSize: ExportSize {
        settings.enabled.contains(.upscale) ? .factor(settings.upscaleFactor) : .factor(1)
    }

    /// The recipe for export (its upscale is replaced by the export size).
    var recipe: [EnhanceOperation] { settings.recipe }
}

/// Hands progress from background work to the main actor.
final class ProgressRelay: @unchecked Sendable {
    private let handler: @MainActor (Double) -> Void
    private let lock = NSLock()
    private var lastSent: Double = -1

    init(_ handler: @escaping @MainActor (Double) -> Void) {
        self.handler = handler
    }

    /// Sends at most one update per 1 % of progress.
    func send(_ value: Double) {
        lock.lock()
        let changed = value - lastSent >= 0.01 || value >= 1
        if changed { lastSent = value }
        lock.unlock()
        guard changed else { return }
        let handler = self.handler
        Task { @MainActor in handler(value) }
    }
}
