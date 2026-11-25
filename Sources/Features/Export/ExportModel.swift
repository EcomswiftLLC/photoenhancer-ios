import SwiftUI
import UIKit

/// Runs exports for one photo or a whole batch, and the action that follows (Photos, Share or Files).
///
/// Order: Photos permission (for Save to Photos) -> one rewarded ad through `RewardedGate` (none when no ad is ready) ->
/// full-resolution render -> save or share. A batch asks for one ad in total. Finished files are reused while the
/// options stay the same, so Save and then Share renders once.
@MainActor
final class ExportModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case rendering
        case saved(String)
        case failed(String)
    }

    enum Action { case photos, share, files }

    let assets: [PhotoAsset]
    let recipe: [EnhanceOperation]
    let before: UIImage?
    let after: UIImage?
    let enhancer: Enhancer

    @Published var options: ExportOptions
    @Published var customLongSide: Int
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentIndex = 0
    @Published var shareURLs: [URL]?
    @Published var filesURLs: [URL]?
    @Published private(set) var notes: [String] = []
    /// Set when the rating prompt should be shown (the screen shows it with Apple's `requestReview`).
    @Published var reviewRequested = false
    /// Per photo, for the batch queue.
    @Published private(set) var itemStatus: [ItemStatus]
    /// Small pictures of the photos, for the batch queue.
    var thumbnails: [UIImage] = []

    enum ItemStatus: Equatable {
        case waiting, working(Double), done, failed
    }

    private var cached: (options: ExportOptions, results: [ExportRenderer.Result])?
    private var task: Task<Void, Never>?
    private var token: CancelToken?
    private var generation = 0
    private var savedToHistory = Set<URL>()

    convenience init(asset: PhotoAsset, recipe: [EnhanceOperation], size: ExportSize, before: UIImage?, after: UIImage?, enhancer: Enhancer = .shared) {
        self.init(assets: [asset], recipe: recipe, size: size, before: before, after: after, enhancer: enhancer)
    }

    init(assets: [PhotoAsset], recipe: [EnhanceOperation], size: ExportSize, before: UIImage?, after: UIImage?, enhancer: Enhancer = .shared) {
        self.assets = assets
        self.recipe = recipe
        self.before = before
        self.after = after
        self.enhancer = enhancer
        self.itemStatus = Array(repeating: .waiting, count: assets.count)
        var options = ExportOptions()
        options.size = size
        options.format = .jpg
        self.options = options
        let longest = assets.map { Self.workingSize($0).longSide }.max() ?? 2000
        self.customLongSide = min(SizeCap.maxLongSide, longest)
        if case .custom(let long) = size { customLongSide = long }
    }

    var isBatch: Bool { assets.count > 1 }
    var isBusy: Bool { phase == .rendering }

    var upscaleAvailable: Bool { enhancer.isAvailable(.upscale) }

    var availableFormats: [ImageFormat] { ImageFormat.allCases.filter(\.isSupported) }

    /// The size the full-resolution work starts from (at most 8,192 px and 48 MP).
    static func workingSize(_ asset: PhotoAsset) -> PixelSize {
        var size = asset.uprightSize.fitting(longSide: PhotoAsset.maxWorkingPixel)
        if size.megapixels > SizeCap.maxMegapixels {
            size = size.scaled(by: (SizeCap.maxMegapixels / size.megapixels).squareRoot())
        }
        return size
    }

    func selectSize(_ size: ExportSize) {
        if case .custom = size {
            options.size = .custom(customLongSide)
        } else {
            options.size = size
        }
    }

    func customChanged() {
        customLongSide = min(max(customLongSide, 64), SizeCap.maxLongSide)
        if case .custom = options.size { options.size = .custom(customLongSide) }
    }

    /// "4,032 × 3,024 → 8,064 × 6,048 (48.8 MP)" for the first photo, and whether the cap applies.
    var sizeSummary: (text: String, capped: Bool) {
        guard let first = assets.first else { return ("", false) }
        let source = Self.workingSize(first)
        let expected = ExportRenderer.expectedSize(source: source, size: options.size)
        let text = "\(CVFormat.pixels(expected.size)), \(CVFormat.megapixels(expected.size))"
        return (isBatch ? "First photo: \(text)" : text, expected.capped)
    }

    /// Why an option cannot be used right now, or nil.
    var blockedReason: String? {
        if options.size.needsUpscaleModel && !upscaleAvailable {
            return EnhanceError.modelUnavailable(.superResolution).message
        }
        for op in recipe where !enhancer.isAvailable(op) {
            if let kind = op.requiredModel { return EnhanceError.modelUnavailable(kind).message }
        }
        if case .custom(let long) = options.size, !upscaleAvailable,
           let first = assets.first, long > Self.workingSize(first).longSide {
            return "Sizes larger than the original need the upscale model, which is not in this build."
        }
        return nil
    }

    // MARK: Running

    func perform(_ action: Action) {
        guard !isBusy, blockedReason == nil else { return }
        if action == .photos {
            generation += 1
            let id = generation
            Task {
                let allowed = await LibrarySaver.ensureAccess()
                guard id == generation else { return }
                guard allowed else {
                    phase = .failed("Clarivo needs permission to add to Photos. Allow it in Settings, or use Share or Save to Files instead.")
                    return
                }
                gate(action)
            }
        } else {
            gate(action)
        }
    }

    private func gate(_ action: Action) {
        RewardedGate.shared.requestExport { [weak self] in
            self?.start(action)
        }
    }

    func cancel() {
        generation += 1
        token?.cancel()
        task?.cancel()
        if phase == .rendering { phase = .idle }
        progress = 0
        RewardedGate.shared.exportEnded()
        ReviewPromptTracker.shared.recordExport(.cancelled, adOrShareSheetOnScreen: false)
    }

    func clearStatus() {
        if phase != .rendering { phase = .idle }
    }

    private func start(_ action: Action) {
        guard !isBusy else { return }
        generation += 1
        let id = generation
        phase = .rendering
        progress = 0
        currentIndex = 0
        notes = []
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(action, generation: id)
            UIApplication.shared.isIdleTimerDisabled = previousIdle
            RewardedGate.shared.exportEnded()
        }
    }

    private func run(_ action: Action, generation id: Int) async {
        do {
            let results = try await resultsForCurrentOptions(generation: id)
            guard id == generation else { return }
            let items = results.map(\.item)
            switch action {
            case .photos:
                try await LibrarySaver.save(items)
                CVHaptics.success()
                phase = .saved(items.count == 1 ? "Saved to Photos." : "Saved \(items.count) photos to Photos.")
                finishSuccess(results, outcome: .saved)
            case .share:
                phase = .idle
                shareURLs = items.map(\.url)
            case .files:
                phase = .idle
                filesURLs = items.map(\.url)
            }
        } catch EnhanceError.cancelled {
            guard id == generation else { return }
            phase = .idle
        } catch let error as EnhanceError {
            guard id == generation else { return }
            phase = .failed(error.message)
            ReviewPromptTracker.shared.recordExport(.failed, adOrShareSheetOnScreen: false)
        } catch LibrarySaver.SaveError.denied {
            guard id == generation else { return }
            phase = .failed("Clarivo needs permission to add to Photos. Allow it in Settings, or use Share or Save to Files instead.")
            ReviewPromptTracker.shared.recordExport(.failed, adOrShareSheetOnScreen: false)
        } catch is CancellationError {
            guard id == generation else { return }
            phase = .idle
        } catch {
            guard id == generation else { return }
            phase = .failed("The photo could not be saved. Free some space and try again.")
            ReviewPromptTracker.shared.recordExport(.failed, adOrShareSheetOnScreen: false)
        }
    }

    /// The share sheet or Files picker closed.
    func externalActionFinished(completed: Bool, shared: Bool) {
        shareURLs = nil
        filesURLs = nil
        guard completed, let results = cached?.results else {
            ReviewPromptTracker.shared.recordExport(.cancelled, adOrShareSheetOnScreen: false)
            return
        }
        phase = .saved(shared ? "Shared." : (results.count == 1 ? "Saved to Files." : "Saved \(results.count) photos to Files."))
        finishSuccess(results, outcome: .shared)
    }

    private func finishSuccess(_ results: [ExportRenderer.Result], outcome: ReviewPromptPolicy.Outcome) {
        // Keep each result once in Recent.
        for (index, result) in results.enumerated() where !savedToHistory.contains(result.item.url) {
            savedToHistory.insert(result.item.url)
            let title = index < assets.count ? assets[index].title : "Photo"
            HistoryStore.shared.add(fileAt: result.item.url, title: title, summary: Self.summary(recipe: recipe, size: result.item.pixelSize), image: result.image)
        }
        let show = ReviewPromptTracker.shared.recordExport(outcome, adOrShareSheetOnScreen: RewardedGate.shared.isPresentingAd)
        if show { reviewRequested = true }
    }

    nonisolated static func summary(recipe: [EnhanceOperation], size: PixelSize) -> String {
        let tools = Recipe.normalized(recipe).map(\.kind.title)
        let list = tools.isEmpty ? "Original" : tools.joined(separator: ", ")
        return "\(list), \(CVFormat.pixels(size))"
    }

    private func resultsForCurrentOptions(generation id: Int) async throws -> [ExportRenderer.Result] {
        if let cached, cached.options == options, cached.results.allSatisfy({ FileManager.default.fileExists(atPath: $0.item.url.path) }) {
            return cached.results
        }
        let newToken = CancelToken()
        token = newToken
        let watch = MemoryWatcher.shared.register(newToken)
        defer { MemoryWatcher.shared.unregister(watch) }
        let requested = options
        let recipe = self.recipe
        let enhancer = self.enhancer
        var results: [ExportRenderer.Result] = []
        let count = Double(assets.count)
        itemStatus = Array(repeating: .waiting, count: assets.count)
        for (index, asset) in assets.enumerated() {
            guard id == generation else { throw EnhanceError.cancelled }
            currentIndex = index
            itemStatus[index] = .working(0)
            let relay = ProgressRelay { [weak self] value in
                guard let self, id == self.generation else { return }
                self.progress = max(self.progress, (Double(index) + value) / count)
                if index < self.itemStatus.count { self.itemStatus[index] = .working(value) }
            }
            let result: ExportRenderer.Result
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try await ExportRenderer.render(asset, recipe: recipe, options: requested, enhancer: enhancer, cancel: newToken) { value in
                        relay.send(value)
                    }
                }.value
            } catch {
                if index < itemStatus.count { itemStatus[index] = .failed }
                throw error
            }
            itemStatus[index] = .done
            results.append(result)
            if result.notes.capApplied && !notes.contains(Self.capNote) { notes.append(Self.capNote) }
            for message in result.notes.messages where !notes.contains(message) { notes.append(message) }
        }
        cached = (requested, results)
        return results
    }

    static let capNote = "The size limit applied: output is at most 8,192 px on the long side and 48 MP, so the photo was reduced before upscaling."
}
