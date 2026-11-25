import SwiftUI
import StoreKit

/// Export: the finished result and its before/after come first, then format, size, quality and metadata, then
/// Save to Photos, Share or Save to Files (each through one rewarded ad; a batch needs only one).
struct ExportView: View {
    @StateObject private var model: ExportModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var divider: Double = 0.5
    @FocusState private var customFocused: Bool

    init(model: ExportModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 700
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: CV.Space.l) {
                                preview(height: min(geo.size.height - 120, 620)).frame(maxWidth: .infinity)
                                options.frame(width: 360)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: CV.Space.l) {
                                preview(height: min(max(geo.size.height * 0.42, 220), 460))
                                options
                            }
                            .readableWidth(CV.Layout.narrow + 80)
                        }
                    }
                    .padding(.horizontal, CV.Space.m)
                    .padding(.bottom, CV.Space.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .cvScreen()
            .navigationTitle(model.isBatch ? "Export \(model.assets.count) photos" : "Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        model.cancel()
                        dismiss()
                    }
                    .foregroundStyle(CV.Palette.glacier)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Set size") {
                        customFocused = false
                        model.customChanged()
                    }
                }
            }
            .sheet(isPresented: Binding(get: { model.shareURLs != nil }, set: { if !$0 { model.shareURLs = nil } })) {
                ShareSheet(urls: model.shareURLs ?? []) { completed in
                    model.externalActionFinished(completed: completed, shared: true)
                }
            }
            .sheet(isPresented: Binding(get: { model.filesURLs != nil }, set: { if !$0 { model.filesURLs = nil } })) {
                FilesExporter(urls: model.filesURLs ?? []) { saved in
                    model.externalActionFinished(completed: saved, shared: false)
                }
            }
            .onChange(of: model.reviewRequested) { _, requested in
                guard requested else { return }
                model.reviewRequested = false
                // Shown a moment after the "Saved" confirmation appears, never over an ad or a share sheet.
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard model.shareURLs == nil, model.filesURLs == nil, !RewardedGate.shared.isPresentingAd else { return }
                    requestReview()
                    ReviewPromptTracker.shared.recordPromptShown()
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.isBusy)
    }

    // MARK: Preview

    private func preview(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CompareView(before: model.before, after: model.after, divider: $divider)
                .frame(height: max(200, height))
                .clipShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
            Text(model.isBatch
                 ? "The first photo of \(model.assets.count). Every photo gets the same enhancements."
                 : "This is your result. The saved file is made at full size.")
                .font(CV.Font.caption)
                .foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
            if model.isBatch {
                BatchQueueStrip(model: model)
            }
        }
        .padding(.top, CV.Space.s)
    }

    // MARK: Options

    private var options: some View {
        VStack(alignment: .leading, spacing: CV.Space.l) {
            group("Format") {
                CVChipFlow {
                    ForEach(model.availableFormats) { format in
                        CVChip(title: format.title, selected: model.options.format == format) { model.options.format = format }
                            .accessibilityHint(Text(format.detail))
                    }
                }
                Text(model.options.format.detail).font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
            }

            group("Size") {
                CVChipFlow {
                    ForEach([1, 2, 4, 8], id: \.self) { factor in
                        let size = ExportSize.factor(factor)
                        CVChip(title: size.title, selected: model.options.size == size,
                               enabled: factor == 1 || model.upscaleAvailable) { model.selectSize(size) }
                            .accessibilityLabel(Text(factor == 1 ? "Original size" : "Upscale \(factor) times"))
                    }
                    CVChip(title: "Custom", selected: isCustom) { model.selectSize(.custom(model.customLongSide)) }
                }
                if isCustom {
                    HStack {
                        Text("Long side").font(CV.Font.callout).foregroundStyle(CV.Palette.pearl)
                        Spacer()
                        TextField("Pixels", value: $model.customLongSide, format: .number)
                            .keyboardType(.numberPad)
                            .focused($customFocused)
                            .multilineTextAlignment(.trailing)
                            .font(CV.Font.readout)
                            .frame(maxWidth: 120, minHeight: 44)
                            .padding(.horizontal, CV.Space.s)
                            .background(CV.Palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onSubmit { model.customChanged() }
                            .onChange(of: model.customLongSide) { _, _ in model.customTyped() }
                            .accessibilityLabel(Text("Long side in pixels"))
                        Text("px").font(CV.Font.callout).foregroundStyle(CV.Palette.mist)
                    }
                }
                let summary = model.sizeSummary
                Text(summary.text).font(CV.Font.readout).foregroundStyle(CV.Palette.pearl)
                if summary.capped {
                    Text("Limited to 8,192 px on the long side and 48 MP, so the photo is reduced before upscaling.")
                        .font(CV.Font.caption).foregroundStyle(CV.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.options.format.isLossy {
                group("Quality") {
                    StrengthSlider(title: "Quality", value: $model.options.quality, range: 0.5...1)
                }
            }

            group("Photo details") {
                Toggle(isOn: $model.options.keepMetadata) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep camera details and location").font(CV.Font.body).foregroundStyle(CV.Palette.pearl)
                        Text(model.options.keepMetadata
                             ? "Date, camera and location (if the photo has one) stay in the file."
                             : "All details are removed, including location.")
                            .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(CV.Palette.glacier)
                .frame(minHeight: 44)
            }

            actions
        }
    }

    private var isCustom: Bool {
        if case .custom = model.options.size { return true }
        return false
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CVSectionTitle(text: title)
            content()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            status
            if let reason = model.blockedReason {
                Label(reason, systemImage: "lock")
                    .font(CV.Font.caption).foregroundStyle(CV.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                model.perform(.photos)
            } label: {
                Label(model.isBatch ? "Save all to Photos" : "Save to Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.cvPrimaryWide)
            .disabled(model.isBusy || model.blockedReason != nil)

            HStack(spacing: CV.Space.s) {
                Button { model.perform(.share) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.cvSecondaryWide)
                Button { model.perform(.files) } label: { Label("Save to Files", systemImage: "folder") }
                    .buttonStyle(.cvSecondaryWide)
            }
            .disabled(model.isBusy || model.blockedReason != nil)

            Text(model.isBatch
                 ? "Clarivo is free. Saving or sharing may show one short ad first, once for the whole batch."
                 : "Clarivo is free. Saving or sharing may show one short ad first.")
                .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
            Label("Your photos are processed on your device and never uploaded.", systemImage: "lock.shield")
                .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .rendering:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: model.progress).tint(CV.Palette.glacier)
                HStack {
                    Text(model.isBatch
                         ? "Enhancing photo \(model.currentIndex + 1) of \(model.assets.count) at full size"
                         : "Enhancing at full size, \(Int((model.progress * 100).rounded())) %")
                        .font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                    Spacer()
                    Button("Cancel") { model.cancel() }
                        .font(CV.Font.label).foregroundStyle(CV.Palette.glacier)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        case .saved(let text):
            VStack(alignment: .leading, spacing: 4) {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(CV.Font.headline).foregroundStyle(CV.Palette.success)
                ForEach(model.notes, id: \.self) { note in
                    Text(note).font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(CV.Font.callout).foregroundStyle(CV.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The batch queue: every photo with its own progress.
struct BatchQueueStrip: View {
    @ObservedObject var model: ExportModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CV.Space.s) {
                ForEach(Array(model.assets.enumerated()), id: \.offset) { index, asset in
                    tile(index: index, title: asset.title)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tile(index: Int, title: String) -> some View {
        let status = index < model.itemStatus.count ? model.itemStatus[index] : .waiting
        return ZStack {
            if index < model.thumbnails.count {
                Image(uiImage: model.thumbnails[index]).resizable().scaledToFill()
            } else {
                CV.Palette.raised
            }
            switch status {
            case .waiting:
                EmptyView()
            case .working(let value):
                Color.black.opacity(0.45)
                ProgressView(value: value).progressViewStyle(.circular).tint(CV.Palette.glacier)
            case .done:
                Color.black.opacity(0.25)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(CV.Palette.success)
            case .failed:
                Color.black.opacity(0.45)
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(CV.Palette.danger)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Photo \(index + 1), \(Self.describe(status))"))
    }

    static func describe(_ status: ExportModel.ItemStatus) -> String {
        switch status {
        case .waiting: return "waiting"
        case .working(let value): return "enhancing, \(Int((value * 100).rounded())) percent"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}
