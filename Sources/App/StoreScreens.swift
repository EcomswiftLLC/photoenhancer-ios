#if DEBUG
import SwiftUI
import UIKit

/// Store captures: the real screens opened on the bundled sample photos with real engine output.
/// `-cvScreen shot-<name> -cvNoAds YES` opens one. Nothing here draws UI of its own. DEBUG builds only.
enum StoreScreens {
    /// Names of the store captures, in slide order. CI saves each one under exactly this name.
    static let names = ["home", "enhance-result", "compare", "unblur", "colorize", "restore", "portrait", "batch", "export", "settings"]

    struct Scene {
        var sample: String
        var tools: [ToolKind]
        var fallback: [ToolKind]
        var selected: ToolKind
        var upscale: Int = 4
        var zoom: CGFloat = 1
        var divider: Double = 0.5
    }

    static func scene(for name: String) -> Scene? {
        switch name {
        case "enhance-result":
            return Scene(sample: "historic-building-lowres", tools: [.upscale], fallback: [.autoFix, .sharpen], selected: .upscale)
        case "compare":
            return Scene(sample: "historic-building-lowres", tools: [.upscale], fallback: [.autoFix, .sharpen], selected: .upscale, zoom: 2.6, divider: 0.5)
        case "unblur":
            return Scene(sample: "street-sign-motion-blur", tools: [.unblur], fallback: [.sharpen], selected: .unblur, divider: 0.45)
        case "colorize":
            return Scene(sample: "old-street-1864", tools: [.restore, .colorize], fallback: [.restore], selected: .colorize)
        case "restore":
            return Scene(sample: "old-portrait-1859", tools: [.restore], fallback: [.restore], selected: .restore)
        case "portrait":
            return Scene(sample: "portrait-woman-lowres", tools: [.portrait, .autoFix], fallback: [.portrait], selected: .portrait)
        default:
            return nil
        }
    }

    @MainActor @ViewBuilder
    static func view(for name: String) -> some View {
        switch name {
        case "home":
            SeededHome()
        case "batch":
            BatchView(assets: galleryAssets(count: 6))
        case "export":
            StoreExportScreen()
        case "settings":
            SettingsView()
        default:
            if let scene = scene(for: name), let model = enhanceModel(scene) {
                EnhanceView(model: model, initialZoom: scene.zoom)
            } else {
                EnhanceView(asset: DebugFixtures.asset(), initial: DebugFixtures.settings([.autoFix]), selected: .autoFix)
            }
        }
    }

    @MainActor
    static func enhanceModel(_ scene: Scene) -> EnhanceModel? {
        guard let asset = PhotoAsset.sample(named: scene.sample) else { return nil }
        var settings = ToolSettings()
        let available = scene.tools.filter { Enhancer.shared.isAvailable($0) }
        settings.enabled = Set(available.count == scene.tools.count ? scene.tools : scene.fallback.filter { Enhancer.shared.isAvailable($0) })
        settings.upscaleFactor = scene.upscale
        let model = EnhanceModel(asset: asset, initial: settings)
        model.selectedTool = scene.selected
        model.divider = scene.divider
        return model
    }

    static func galleryAssets(count: Int) -> [PhotoAsset] {
        let names = SampleLibrary.availableNames().prefix(count)
        let assets = names.compactMap { PhotoAsset.sample(named: $0) }
        return assets.count >= 2 ? assets : DebugFixtures.batchAssets()
    }

    /// Fills Recent with real results: each sample run through the engine and written like a real export.
    static func seedHistory() async {
        HistoryStore.shared.clearAll()
        let picks: [(String, [EnhanceOperation])] = [
            ("old-street-1864", [.restoreOld(strength: 0.7)]),
            ("tabby-cat-noisy", [.denoiseLight(strength: 0.8), .autoFix(strength: 0.6)]),
            ("lake-autumn", [.autoFix(strength: 0.8)]),
            ("kingfisher", [.sharpen(strength: 0.4), .autoFix(strength: 0.5)]),
            ("old-portrait-1859", [.restoreOld(strength: 0.6)]),
            ("portrait-man", [.autoFix(strength: 0.7)]),
        ]
        for (name, ops) in picks {
            guard let asset = PhotoAsset.sample(named: name) else { continue }
            var options = ExportOptions()
            options.size = .factor(1)
            if let result = try? await ExportRenderer.render(asset, recipe: ops, options: options, cancel: CancelToken(), progress: { _ in }) {
                HistoryStore.shared.add(fileAt: result.item.url, title: asset.title,
                                        summary: ExportModel.summary(recipe: ops, size: result.item.pixelSize), image: result.image)
            }
        }
    }
}

/// Home with Recent filled from real engine results.
private struct SeededHome: View {
    @State private var ready = false
    var body: some View {
        Group {
            if ready { HomeView() } else { CV.Palette.ink.ignoresSafeArea() }
        }
        .task {
            await Task.detached(priority: .userInitiated) { await StoreScreens.seedHistory() }.value
            ready = true
        }
    }
}

/// The real export screen, opened on a real engine result of a bundled sample.
private struct StoreExportScreen: View {
    @State private var model: ExportModel?

    var body: some View {
        Group {
            if let model { ExportView(model: model) } else { CV.Palette.ink.ignoresSafeArea() }
        }
        .task {
            let name = "tabby-cat-noisy"
            let asset = PhotoAsset.sample(named: name) ?? DebugFixtures.asset()
            let ai = Enhancer.shared.isAvailable(.upscale)
            let recipe: [EnhanceOperation] = ai ? [.denoise(strength: 0.85), .autoFix(strength: 0.5)] : [.denoiseLight(strength: 0.8), .autoFix(strength: 0.5)]
            let pair = await Task.detached(priority: .userInitiated) { () -> (UIImage, UIImage)? in
                guard let base = asset.decode(maxPixel: 1280),
                      let output = try? await Enhancer.shared.run(recipe, on: base) else { return nil }
                return (UIImage(cgImage: base), UIImage(cgImage: output.image))
            }.value
            let export = ExportModel(asset: asset, recipe: recipe, size: .factor(ai ? 2 : 1), before: pair?.0, after: pair?.1)
            export.options.format = .heic.isSupported ? .heic : .jpg
            model = export
        }
    }
}
#endif
