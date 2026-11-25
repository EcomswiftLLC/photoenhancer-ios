import SwiftUI

/// A recent result: look at it again, share or save it (through the same single rewarded ad), enhance it further, or delete it.
struct RecentResultView: View {
    let item: HistoryStore.Item
    let onEnhanceAgain: (PhotoAsset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var shareURLs: [URL]?
    @State private var status: String?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CV.Space.m) {
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
                                .accessibilityLabel(Text(item.title))
                        } else {
                            ProgressView().tint(CV.Palette.glacier).frame(height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Text(item.summary).font(CV.Font.callout).foregroundStyle(CV.Palette.mist)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status {
                        Label(status, systemImage: "checkmark.circle.fill").font(CV.Font.headline).foregroundStyle(CV.Palette.success)
                    }
                    Button { save() } label: { Label("Save to Photos", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.cvPrimaryWide)
                    HStack(spacing: CV.Space.s) {
                        Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.cvSecondaryWide)
                        Button { enhanceAgain() } label: { Label("Enhance again", systemImage: "wand.and.stars") }
                            .buttonStyle(.cvSecondaryWide)
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete from Recent", systemImage: "trash").foregroundStyle(CV.Palette.danger)
                    }
                    .buttonStyle(.cvQuiet)
                }
                .padding(CV.Space.m)
                .readableWidth(CV.Layout.narrow + 120)
            }
            .cvScreen()
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(CV.Palette.glacier)
                }
            }
            .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
                ShareSheet(urls: shareURLs ?? []) { completed in
                    shareURLs = nil
                    if completed { status = "Shared." }
                }
            }
            .confirmationDialog("Delete this result?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    HistoryStore.shared.remove(item)
                    dismiss()
                }
            } message: {
                Text("It is removed from Recent. Copies you saved to Photos or Files stay.")
            }
            .task {
                let url = HistoryStore.shared.url(of: item)
                image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    ImageDecoder.decode(url: url, maxPixel: 2400).map { UIImage(cgImage: $0) }
                }.value
            }
        }
        .preferredColorScheme(.dark)
    }

    private var fileURL: URL { HistoryStore.shared.url(of: item) }

    private var format: ImageFormat {
        ImageFormat(rawValue: fileURL.pathExtension.lowercased()) ?? .jpg
    }

    private func save() {
        Task {
            guard await LibrarySaver.ensureAccess() else {
                status = nil
                return
            }
            RewardedGate.shared.requestExport {
                Task {
                    let item = ExportItem(url: fileURL, format: format, pixelSize: PixelSize(width: self.item.pixelWidth, height: self.item.pixelHeight))
                    do {
                        try await LibrarySaver.save([item])
                        status = "Saved to Photos."
                        CVHaptics.success()
                    } catch {
                        status = nil
                    }
                    RewardedGate.shared.exportEnded()
                }
            }
        }
    }

    private func share() {
        RewardedGate.shared.requestExport {
            shareURLs = [fileURL]
            RewardedGate.shared.exportEnded()
        }
    }

    private func enhanceAgain() {
        guard let data = try? Data(contentsOf: fileURL), let asset = PhotoAsset.from(data: data, title: item.title) else { return }
        onEnhanceAgain(asset)
    }
}
