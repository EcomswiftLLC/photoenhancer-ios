import SwiftUI

/// The Enhance workspace: the comparison, the tools and their controls, and Export.
/// Side by side on wide windows (iPad, iPhone in landscape); stacked on narrow ones.
struct EnhanceView: View {
    @StateObject private var model: EnhanceModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false
    @State private var confirmingClose = false
    var initialZoom: CGFloat = 1
    var startsInExport = false

    init(asset: PhotoAsset, initial: ToolSettings? = nil, selected: ToolKind? = nil) {
        let model = EnhanceModel(asset: asset, initial: initial)
        if let selected { model.selectedTool = selected }
        _model = StateObject(wrappedValue: model)
    }

    init(model: EnhanceModel, initialZoom: CGFloat = 1, startsInExport: Bool = false) {
        _model = StateObject(wrappedValue: model)
        self.initialZoom = initialZoom
        self.startsInExport = startsInExport
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700 || (geo.size.width >= 560 && geo.size.width > geo.size.height)
            VStack(spacing: 0) {
                topBar
                if wide {
                    HStack(spacing: 0) {
                        compareArea.padding(CV.Space.m)
                        inspector(width: min(CV.Layout.inspector, geo.size.width * 0.4))
                    }
                } else {
                    compareArea
                        .padding(.horizontal, CV.Space.s)
                        .frame(maxHeight: .infinity)
                    statusLine.padding(.horizontal, CV.Space.m).padding(.top, CV.Space.s)
                    toolStrip.padding(.top, CV.Space.s)
                    ScrollView {
                        controls
                            .padding(.horizontal, CV.Space.m)
                            .padding(.vertical, CV.Space.m)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: min(260, geo.size.height * 0.34))
                }
            }
        }
        .cvScreen()
        .task {
            await model.load()
            if startsInExport { showingExport = true }
        }
        .sheet(isPresented: $showingExport) {
            ExportView(model: ExportModel(asset: model.asset, recipe: model.recipe, size: model.defaultExportSize,
                                          before: model.beforeImage, after: model.afterImage ?? model.beforeImage))
        }
        .confirmationDialog("Close this photo?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close without saving", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your enhancements are not saved until you export.")
        }
    }

    private func close() {
        model.cancel()
        dismiss()
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: CV.Space.s) {
            CVIconButton(symbol: "xmark", label: "Close") {
                if model.hasChanges { confirmingClose = true } else { close() }
            }
            Text(model.asset.title)
                .font(CV.Font.headline)
                .foregroundStyle(CV.Palette.pearl)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button {
                showingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(CVButtonStyle(kind: .primary))
            .disabled(model.beforeImage == nil)
            .accessibilityHint(Text("Choose a format and size, then save or share"))
        }
        .padding(.horizontal, CV.Space.m)
        .padding(.vertical, CV.Space.s)
    }

    private var compareArea: some View {
        ZStack {
            if model.beforeImage == nil && model.errorMessage == nil {
                ProgressView().tint(CV.Palette.glacier)
            }
            CompareView(before: model.beforeImage, after: model.afterImage, divider: $model.divider, initialZoom: initialZoom)
                .clipShape(RoundedRectangle(cornerRadius: CV.Radius.tile, style: .continuous))
            if model.isProcessing {
                VStack {
                    Spacer()
                    ProgressView(value: model.progress)
                        .tint(CV.Palette.glacier)
                        .padding(.horizontal, CV.Space.l)
                        .padding(.bottom, CV.Space.m)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: CV.Space.s) {
            if model.isProcessing {
                Text("Enhancing on this device, \(Int((model.progress * 100).rounded())) %")
                    .font(CV.Font.caption)
                    .foregroundStyle(CV.Palette.mist)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                Button("Cancel") { model.cancel() }
                    .font(CV.Font.label)
                    .foregroundStyle(CV.Palette.glacier)
                    .frame(minWidth: 44, minHeight: 44)
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(CV.Font.caption)
                    .foregroundStyle(CV.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else if let message = model.message {
                Text(message)
                    .font(CV.Font.caption)
                    .foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Text(model.afterImage == nil ? "Turn on a tool to see the result." : "Drag the divider. Pinch to zoom. Touch and hold to see the original.")
                    .font(CV.Font.caption)
                    .foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: Tools

    private var toolStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CV.Space.s) {
                    ForEach(ToolKind.allCases) { tool in
                        toolButton(tool, compact: true).id(tool)
                    }
                }
                .padding(.horizontal, CV.Space.m)
            }
            .onAppear { proxy.scrollTo(model.selectedTool, anchor: .center) }
            .onChange(of: model.selectedTool) { _, tool in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(tool, anchor: .center) }
            }
        }
    }

    private func toolButton(_ tool: ToolKind, compact: Bool) -> some View {
        let selected = model.selectedTool == tool
        let on = model.settings.enabled.contains(tool)
        let available = model.isAvailable(tool)
        return Button {
            model.selectedTool = tool
        } label: {
            Group {
                if compact {
                    VStack(spacing: 6) {
                        toolIcon(tool, on: on, available: available)
                        Text(tool.shortTitle).font(CV.Font.caption).lineLimit(1).fixedSize()
                    }
                    .frame(minWidth: 72, minHeight: 64)
                    .padding(.horizontal, 6)
                } else {
                    HStack(spacing: CV.Space.m) {
                        toolIcon(tool, on: on, available: available)
                        Text(tool.title).font(CV.Font.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if on {
                            Text("On").font(CV.Font.label).foregroundStyle(CV.Palette.glacier)
                        } else if !available {
                            Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(CV.Palette.mist)
                        }
                    }
                    .padding(.horizontal, CV.Space.m)
                    .frame(minHeight: 48)
                }
            }
            .foregroundStyle(selected ? CV.Palette.pearl : CV.Palette.mist)
            .background(
                RoundedRectangle(cornerRadius: CV.Radius.chip, style: .continuous)
                    .fill(selected ? CV.Palette.raised : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CV.Radius.chip, style: .continuous)
                    .strokeBorder(selected ? CV.Palette.glacier.opacity(0.7) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(available ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tool.title))
        .accessibilityValue(Text(available ? (on ? "On" : "Off") : "Not available in this build"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toolIcon(_ tool: ToolKind, on: Bool, available: Bool) -> some View {
        Image(systemName: tool.symbol)
            .font(.system(size: 18, weight: .regular))
            .frame(width: 26, height: 26)
            .overlay(alignment: .topTrailing) {
                if on {
                    Circle().fill(CV.Palette.glacier).frame(width: 7, height: 7).offset(x: 4, y: -2)
                } else if !available {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CV.Palette.mist).offset(x: 6, y: -4)
                }
            }
            .accessibilityHidden(true)
    }

    private func inspector(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: CV.Space.m) {
                    VStack(spacing: 2) {
                        ForEach(ToolKind.allCases) { tool in toolButton(tool, compact: false) }
                    }
                    CVHairline()
                    controls
                    statusLine
                }
                .padding(CV.Space.m)
            }
        }
        .frame(width: width)
        .background(CV.Palette.deep.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .leading) { Rectangle().fill(CV.Palette.line).frame(width: 1) }
    }

    // MARK: Controls for the selected tool

    private var controls: some View {
        let tool = model.selectedTool
        let available = model.isAvailable(tool)
        return VStack(alignment: .leading, spacing: CV.Space.m) {
                Toggle(isOn: Binding(
                    get: { model.settings.enabled.contains(tool) },
                    set: { model.setEnabled(tool, $0) }
                )) {
                    Text(tool.title).font(CV.Font.title(18)).foregroundStyle(CV.Palette.pearl)
                }
                .tint(CV.Palette.glacier)
                .disabled(!available)
                .frame(minHeight: 44)

                Text(available ? tool.blurb : (tool.requiredModel.map { EnhanceError.modelUnavailable($0).message } ?? tool.blurb))
                    .font(CV.Font.callout)
                    .foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)

                if available {
                    parameters(for: tool)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func parameters(for tool: ToolKind) -> some View {
        switch tool {
        case .upscale:
            CVChipFlow {
                ForEach([2, 4, 8], id: \.self) { factor in
                    CVChip(title: "\(factor)×", selected: model.settings.upscaleFactor == factor) {
                        model.settings.upscaleFactor = factor
                        model.setEnabled(.upscale, true)
                    }
                    .accessibilityLabel(Text("Upscale \(factor) times"))
                }
            }
            Text("Output is limited to 8,192 px on the long side and 48 MP. Larger photos are reduced first, and the export screen says so.")
                .font(CV.Font.caption)
                .foregroundStyle(CV.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        case .denoise:
            CVChipFlow {
                ForEach(ToolSettings.DenoiseMode.allCases) { mode in
                    CVChip(title: mode.title, selected: model.settings.denoiseMode == mode,
                           enabled: mode == .light || model.isAvailable(.upscale)) {
                        model.settings.denoiseMode = mode
                        model.setEnabled(.denoise, true)
                    }
                }
            }
            slider("Strength", \.denoiseStrength, tool: .denoise)
        case .restore:
            slider("Strength", \.restoreStrength, tool: .restore)
        case .autoFix:
            slider("Strength", \.autoFixStrength, tool: .autoFix)
        case .sharpen:
            slider("Strength", \.sharpenStrength, tool: .sharpen)
        case .unblur, .portrait, .colorize:
            EmptyView()
        }
    }

    private func slider(_ title: String, _ key: WritableKeyPath<ToolSettings, Double>, tool: ToolKind) -> some View {
        StrengthSlider(
            title: title,
            value: Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 }),
            onCommit: {
                if model.settings.enabled.contains(tool) { model.settingsChanged() } else { model.setEnabled(tool, true) }
            }
        )
    }
}
