import SwiftUI

/// Batch queue: many photos, one preset for all of them, a preview on the first photo, then one export (one ad).
@MainActor
final class BatchModel: ObservableObject {
    @Published private(set) var assets: [PhotoAsset]
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    @Published var preset: ToolSettings.Preset = .autoEnhance
    @Published private(set) var before: UIImage?
    @Published private(set) var after: UIImage?
    @Published private(set) var previewing = false
    @Published private(set) var previewError: String?
    private var previewTask: Task<Void, Never>?
    private var token: CancelToken?
    let enhancer: Enhancer

    init(assets: [PhotoAsset], enhancer: Enhancer = .shared) {
        self.assets = assets
        self.enhancer = enhancer
        if !isAvailable(preset) {
            preset = ToolSettings.Preset.allCases.first(where: { isAvailable($0) }) ?? .autoEnhance
        }
    }

    func isAvailable(_ preset: ToolSettings.Preset) -> Bool {
        preset.requiredModels.allSatisfy { enhancer.models.isAvailable($0) }
    }

    func loadThumbnails() async {
        for asset in assets where thumbnails[asset.id] == nil {
            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                asset.decode(maxPixel: 300).map { UIImage(cgImage: $0) }
            }.value
            if let image { thumbnails[asset.id] = image }
        }
    }

    func remove(_ asset: PhotoAsset) {
        assets.removeAll { $0.id == asset.id }
        thumbnails[asset.id] = nil
        if assets.first?.id != nil { runPreview() }
    }

    func choose(_ preset: ToolSettings.Preset) {
        guard isAvailable(preset) else { return }
        self.preset = preset
        runPreview()
    }

    /// The preset on the first photo at preview size, so the result is seen before anything is saved.
    func runPreview() {
        token?.cancel()
        previewTask?.cancel()
        guard let first = assets.first else { return }
        let recipe = preset.settings.recipe
        let newToken = CancelToken()
        token = newToken
        previewing = true
        previewError = nil
        let enhancer = self.enhancer
        previewTask = Task { [weak self] in
            do {
                let output = try await Task.detached(priority: .userInitiated) { () -> (CGImage, CGImage)? in
                    let scale = Recipe.totalScale(recipe)
                    guard let base = first.decode(maxPixel: max(256, 2048 / scale)) else { return nil }
                    let result = try await enhancer.run(recipe, on: base, applyCap: true, cancel: newToken)
                    return (base, result.image)
                }.value
                guard let self, !Task.isCancelled else { return }
                if let output {
                    self.before = UIImage(cgImage: output.0)
                    self.after = UIImage(cgImage: output.1)
                }
                self.previewing = false
            } catch let error as EnhanceError {
                guard let self else { return }
                self.previewing = false
                if error != .cancelled { self.previewError = error.message }
            } catch {
                self?.previewing = false
            }
        }
    }

    func makeExportModel() -> ExportModel {
        let settings = preset.settings
        let size: ExportSize = settings.enabled.contains(.upscale) ? .factor(settings.upscaleFactor) : .factor(1)
        let model = ExportModel(assets: assets, recipe: settings.recipe, size: size, before: before, after: after ?? before, enhancer: enhancer)
        model.thumbnails = assets.compactMap { thumbnails[$0.id] }
        if model.thumbnails.count != assets.count { model.thumbnails = [] }
        return model
    }
}

struct BatchView: View {
    @StateObject private var model: BatchModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportModel: ExportModel?
    @State private var divider: Double = 0.5

    init(assets: [PhotoAsset]) {
        _model = StateObject(wrappedValue: BatchModel(assets: assets))
    }

    init(model: BatchModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 760
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: CV.Space.l) {
                                VStack(alignment: .leading, spacing: CV.Space.l) {
                                    preview(height: min(geo.size.height - 160, 560))
                                    queue(columns: 6)
                                }
                                .frame(maxWidth: .infinity)
                                presets.frame(width: CV.Layout.inspector)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: CV.Space.l) {
                                preview(height: min(max(geo.size.height * 0.36, 220), 420))
                                queue(columns: geo.size.width > 500 ? 6 : 4)
                                presets
                            }
                            .readableWidth(CV.Layout.narrow + 120)
                        }
                    }
                    .padding(.horizontal, CV.Space.m)
                    .padding(.bottom, CV.Space.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .cvScreen()
            .navigationTitle("Batch, \(model.assets.count) photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(CV.Palette.glacier)
                }
            }
            .sheet(item: $exportModel) { model in
                ExportView(model: model)
            }
            .task {
                model.runPreview()
                await model.loadThumbnails()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func preview(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            ZStack {
                CompareView(before: model.before, after: model.previewing ? nil : model.after, divider: $divider)
                if model.previewing {
                    ProgressView("Previewing on the first photo").tint(CV.Palette.glacier)
                        .padding(CV.Space.m).cvGlass(radius: CV.Radius.chip)
                }
            }
            .frame(height: max(200, height))
            .clipShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
            if let error = model.previewError {
                Label(error, systemImage: "exclamationmark.triangle").font(CV.Font.caption).foregroundStyle(CV.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Preview of the first photo. Every photo in the batch gets the same enhancements.")
                    .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, CV.Space.s)
    }

    private func queue(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CVSectionTitle(text: "Queue")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CV.Space.s), count: columns), spacing: CV.Space.s) {
                ForEach(model.assets) { asset in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let image = model.thumbnails[asset.id] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                CV.Palette.raised
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if model.assets.count > 2 {
                                Button { model.remove(asset) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove \(asset.title) from the batch"))
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text(asset.title))
                }
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CVSectionTitle(text: "Enhance every photo with")
            ForEach(ToolSettings.Preset.allCases) { preset in
                let available = model.isAvailable(preset)
                let selected = model.preset == preset
                Button { model.choose(preset) } label: {
                    HStack(spacing: CV.Space.m) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? CV.Palette.glacier : CV.Palette.mist)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title).font(CV.Font.headline).foregroundStyle(CV.Palette.pearl)
                            Text(available ? preset.detail : "Needs an AI model that is not in this build.")
                                .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(CV.Space.m)
                    .frame(minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: CV.Radius.control, style: .continuous)
                            .fill(selected ? CV.Palette.raised : CV.Palette.deep)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CV.Radius.control, style: .continuous)
                            .strokeBorder(selected ? CV.Palette.glacier.opacity(0.6) : CV.Palette.line, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .opacity(available ? 1 : 0.45)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button {
                exportModel = model.makeExportModel()
            } label: {
                Label("Continue to export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.cvPrimaryWide)
            .disabled(model.assets.isEmpty || model.previewing)
            .padding(.top, CV.Space.s)
            Text("Saving the whole batch shows at most one short ad.")
                .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension ExportModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
