import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// What Home opens: one photo in the Enhance workspace, or several in the batch queue.
struct WorkSession: Identifiable {
    let id = UUID()
    let assets: [PhotoAsset]
    var initial: ToolSettings? = nil
    var selected: ToolKind? = nil
}

/// A bundled sample shown on Home, with the tool it shows off best.
struct SampleCard: Identifiable {
    let id: String
    let title: String
    let tool: ToolKind?
    let thumbnail: UIImage?
    let asset: () -> PhotoAsset?
}

@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var recent: [HistoryStore.Item] = []
    @Published private(set) var samples: [SampleCard] = []
    @Published var importing = false
    @Published var notice: String?

    func refresh() {
        recent = HistoryStore.shared.items()
    }

    func loadSamples() async {
        guard samples.isEmpty else { return }
        let cards = await Task.detached(priority: .userInitiated) { () -> [SampleCardData] in
            Self.sampleData()
        }.value
        samples = cards.map { data in
            SampleCard(id: data.name, title: data.title, tool: data.tool,
                       thumbnail: data.thumbnail.map { UIImage(cgImage: $0) },
                       asset: data.makeAsset)
        }
    }

    struct SampleCardData: @unchecked Sendable {
        var name: String
        var title: String
        var tool: ToolKind?
        var thumbnail: CGImage?
        var makeAsset: () -> PhotoAsset?
    }

    nonisolated static func sampleData() -> [SampleCardData] {
        let entries = SampleLibrary.catalog()
        // samples.json lists the gallery first; the sharp originals after it are reference copies for tests.
        let names = entries.isEmpty ? SampleLibrary.availableNames() : Array(SampleLibrary.availableNames().prefix(Self.galleryCount))
        var result: [SampleCardData] = names.map { name in
            let entry = entries.first { $0.name == name }
            return SampleCardData(
                name: name,
                title: entry?.title ?? SampleLibrary.titleFromName(name),
                tool: entry?.tool.flatMap { ToolKind(rawValue: $0) ?? Self.toolAlias($0) },
                thumbnail: SampleLibrary.image(named: name, maxPixel: 520),
                makeAsset: { PhotoAsset.sample(named: name) }
            )
        }
        #if DEBUG
        if result.isEmpty {
            // No bundled samples yet: a clearly labelled generated test image, debug builds only.
            let image = DebugFixtures.testImage()
            result = [SampleCardData(name: "debug-test", title: "Test image (debug build)", tool: .autoFix,
                                     thumbnail: Enhancer.resize(image, to: PixelSize(width: image.width, height: image.height).fitting(longSide: 520)),
                                     makeAsset: { PhotoAsset.generated(image, title: "Test image (debug build)") })]
        }
        #endif
        return result
    }

    nonisolated static let galleryCount = 7

    nonisolated static func toolAlias(_ text: String) -> ToolKind? {
        switch text.lowercased() {
        case "restore", "restoreold", "old", "restore-old": return .restore
        case "auto", "autofix", "auto-fix": return .autoFix
        case "deblur": return .unblur
        case "upscale2x", "upscale4x", "upscale8x", "super-resolution": return .upscale
        default: return nil
        }
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()
    @StateObject private var bannerSlot = BannerAdSlot()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingFiles = false
    @State private var showingSettings = false
    @State private var session: WorkSession?
    @State private var batchSession: WorkSession?
    @State private var openResult: HistoryStore.Item?
    @State private var dropTargeted = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 820
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: CV.Space.xl) {
                            VStack(alignment: .leading, spacing: CV.Space.l) {
                                header
                                hero
                                actions
                                privacyLine
                            }
                            .frame(width: CV.Layout.homeRail)
                            VStack(alignment: .leading, spacing: CV.Space.l) {
                                samplesSection(columns: max(3, Int((geo.size.width - CV.Layout.homeRail - 96) / 230)))
                                recentSection(columns: max(4, Int((geo.size.width - CV.Layout.homeRail - 96) / 170)))
                                CVInlineBanner(slot: bannerSlot)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, CV.Space.xl)
                    } else {
                        VStack(alignment: .leading, spacing: CV.Space.l) {
                            header
                            hero
                            actions
                            privacyLine
                            samplesSection(columns: geo.size.width > 560 ? 3 : 2)
                            recentSection(columns: geo.size.width > 560 ? 4 : 3)
                            CVInlineBanner(slot: bannerSlot)
                        }
                        .padding(.horizontal, CV.Space.m)
                        .readableWidth(760)
                    }
                }
                .padding(.bottom, CV.Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .cvScreen()
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: CV.Radius.panel, style: .continuous)
                    .strokeBorder(CV.Palette.glacier, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(CV.Space.s)
                    .overlay(Text("Drop photos to enhance").cvTitle(20))
                    .allowsHitTesting(false)
            }
            if model.importing {
                ProgressView("Opening photos").tint(CV.Palette.glacier).padding(CV.Space.l).cvGlass()
            }
        }
        .onDrop(of: [UTType.image], isTargeted: $dropTargeted) { providers in
            Task {
                model.importing = true
                let assets = await MediaImport.assets(fromDrop: providers)
                model.importing = false
                open(assets, failed: providers.count - assets.count)
            }
            return true
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                model.importing = true
                let loaded = await MediaImport.assets(from: items)
                model.importing = false
                pickerItems = []
                open(loaded.assets, failed: loaded.failed)
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                model.importing = true
                let loaded = await MediaImport.assets(fromFiles: urls)
                model.importing = false
                open(loaded.assets, failed: loaded.failed)
            }
        }
        .fullScreenCover(item: $session, onDismiss: { model.refresh() }) { session in
            if let asset = session.assets.first {
                EnhanceView(asset: asset, initial: session.initial, selected: session.selected)
            }
        }
        .fullScreenCover(item: $batchSession, onDismiss: { model.refresh() }) { session in
            BatchView(assets: session.assets)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $openResult, onDismiss: { model.refresh() }) { item in
            RecentResultView(item: item) { asset in
                openResult = nil
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    session = WorkSession(assets: [asset])
                }
            }
        }
        .alert("Some files could not be opened", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
        .onAppear { model.refresh() }
        .task { await model.loadSamples() }
    }

    private func open(_ assets: [PhotoAsset], failed: Int) {
        if failed > 0 {
            model.notice = failed == 1
                ? "One file is not a photo Clarivo can read (JPEG, HEIC, PNG and most camera formats work)."
                : "\(failed) files are not photos Clarivo can read (JPEG, HEIC, PNG and most camera formats work)."
        }
        if assets.count == 1 {
            session = WorkSession(assets: assets)
        } else if assets.count > 1 {
            batchSession = WorkSession(assets: assets)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: CV.Space.s) {
            ClarivoMark(lineWidth: 1.6).frame(width: 28, height: 28)
            Text("Clarivo").cvTitle(20)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CVIconButton(symbol: "gearshape", label: "Settings") { showingSettings = true }
        }
        .padding(.top, CV.Space.s)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            Text("Sharper, cleaner, bigger photos.")
                .cvDisplay(34)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Upscale, unblur, remove noise, colorize and restore with AI that runs on this device.")
                .font(CV.Font.body)
                .foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: CV.Space.s) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: MediaImport.maxBatch, matching: .images, photoLibrary: .shared()) {
                Label("Choose photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.cvPrimaryWide)
            .accessibilityHint(Text("Pick one photo to enhance, or several for a batch"))
            Button {
                showingFiles = true
            } label: {
                Label("Import from Files", systemImage: "folder")
            }
            .buttonStyle(.cvSecondaryWide)
        }
    }

    private var privacyLine: some View {
        Label("Your photos are processed on your device and never uploaded.", systemImage: "lock.shield")
            .font(CV.Font.callout)
            .foregroundStyle(CV.Palette.mist)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func samplesSection(columns: Int) -> some View {
        if !model.samples.isEmpty {
            VStack(alignment: .leading, spacing: CV.Space.s) {
                CVSectionTitle(text: "Try a sample")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CV.Space.s), count: columns), spacing: CV.Space.s) {
                    // Whole rows only, so the grid never ends on a lone tile.
                    let shown = model.samples.count > columns
                        ? Array(model.samples.prefix(model.samples.count / columns * columns)) : model.samples
                    ForEach(shown) { card in
                        Button {
                            guard let asset = card.asset() else { return }
                            var initial: ToolSettings?
                            if let tool = card.tool, Enhancer.shared.isAvailable(tool) {
                                var settings = ToolSettings()
                                settings.enabled = [tool]
                                initial = settings
                            }
                            session = WorkSession(assets: [asset], initial: initial, selected: card.tool)
                        } label: {
                            sampleTile(card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(card.tool.map { "\(card.title), sample for \($0.title)" } ?? card.title))
                    }
                }
            }
        }
    }

    private func sampleTile(_ card: SampleCard) -> some View {
        Color.clear
            .aspectRatio(0.8, contentMode: .fit)
            .overlay {
                if let image = card.thumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    CV.Palette.raised
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if let tool = card.tool {
                        Text(tool.shortTitle).font(CV.Font.caption).foregroundStyle(CV.Palette.frost)
                    }
                    Text(card.title).font(CV.Font.label).foregroundStyle(.white).lineLimit(2)
                }
                .padding(CV.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous).strokeBorder(CV.Palette.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private func recentSection(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CVSectionTitle(text: "Recent")
            if model.recent.isEmpty {
                Text("Photos you save or share appear here for 7 days. They stay on this device.")
                    .font(CV.Font.callout)
                    .foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(CV.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cvCard(radius: CV.Radius.tile)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CV.Space.s), count: columns), spacing: CV.Space.s) {
                    ForEach(model.recent) { item in
                        Button { openResult = item } label: { RecentTile(item: item) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(item.title), \(item.summary)"))
                    }
                }
            }
        }
    }
}

struct RecentTile: View {
    let item: HistoryStore.Item
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    CV.Palette.raised
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CV.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CV.Radius.chip, style: .continuous).strokeBorder(CV.Palette.line, lineWidth: 1))
            .task(id: item.id) {
                let url = HistoryStore.shared.thumbnailURL(of: item)
                image = await Task.detached(priority: .utility) { () -> UIImage? in
                    ImageDecoder.decode(url: url, maxPixel: 400).map { UIImage(cgImage: $0) }
                }.value
            }
    }
}
