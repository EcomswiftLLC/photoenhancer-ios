import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @ObservedObject private var ads = AdsManager.shared
    @State private var confirmingClear = false
    @State private var recentCount = HistoryStore.shared.items().count

    private let mailURL = URL(string: "mailto:support@ecomswiftllc.com")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CV.Space.l) {
                    CVHeader(title: "Settings", subtitle: "Clarivo is free. Your photos are processed on your device and never uploaded.")

                    section("Privacy") {
                        if ads.privacyOptionsRequired {
                            row("Ad privacy choices", symbol: "hand.raised") { ads.presentPrivacyOptions() }
                            CVHairline()
                        }
                        link("Privacy policy", symbol: "lock", url: AppInfo.privacyURL)
                        CVHairline()
                        row("Clear recent results", symbol: "trash", value: recentCount == 0 ? "None" : "\(recentCount)") {
                            confirmingClear = true
                        }
                        .disabled(recentCount == 0)
                        Text("Ads are shown by Google AdMob; your photos are never shared with them. Recent results stay on this device and are removed after 7 days.")
                            .font(CV.Font.caption)
                            .foregroundStyle(CV.Palette.mist)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, CV.Space.s)
                    }

                    section("Help") {
                        link("Support", symbol: "questionmark.circle", url: AppInfo.supportURL)
                        CVHairline()
                        link("Email us", symbol: "envelope", url: mailURL)
                        CVHairline()
                        row("Rate this app", symbol: "star") { rate() }
                    }

                    section("About") {
                        NavigationLink {
                            LicensesView()
                        } label: {
                            CVRow(title: "Open-source licences", symbol: "doc.text")
                        }
                        .buttonStyle(.plain)
                        CVHairline()
                        link("Terms of use", symbol: "doc.plaintext", url: AppInfo.termsURL)
                        CVHairline()
                        CVRow(title: "Version", symbol: "info.circle", value: "\(AppInfo.version) (\(AppInfo.build))", showsChevron: false)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, CV.Space.m)
                .padding(.bottom, CV.Space.xl)
                .readableWidth()
            }
            .cvScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(CV.Palette.glacier)
                }
            }
            .confirmationDialog("Clear recent results?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear recent results", role: .destructive) {
                    HistoryStore.shared.clearAll()
                    recentCount = 0
                }
            } message: {
                Text("They are removed from this device. Copies you saved to Photos or Files stay.")
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Opens the App Store review page once the app has an App Store id, otherwise Apple's rating prompt.
    private func rate() {
        if let url = AppInfo.writeReviewURL() {
            openURL(url)
        } else {
            requestReview()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CV.Space.s) {
            CVSectionTitle(text: title)
            VStack(spacing: 0) {
                CVHairline()
                content()
                CVHairline()
            }
        }
    }

    private func row(_ title: String, symbol: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { CVRow(title: title, symbol: symbol, value: value) }
            .buttonStyle(.plain)
    }

    private func link(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) { CVRow(title: title, symbol: symbol, external: true) }
            .accessibilityHint(Text("Opens in Safari"))
    }
}

/// Every model and SDK licence and attribution, from the bundled Licenses.json, plus the sample photo credits.
struct LicensesView: View {
    struct Entry: Decodable, Identifiable {
        var name: String
        var use: String
        var license: String
        var copyright: String
        var source: String
        var text: String
        var id: String { name }
    }

    struct File: Decodable { var entries: [Entry] }

    static func load(bundle: Bundle = .main) -> [Entry] {
        guard let url = bundle.url(forResource: "Licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.entries
    }

    private let entries = LicensesView.load()
    private let credits = SampleLibrary.credits()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CV.Space.l) {
                CVHeader(title: "Open-source licences", subtitle: "Clarivo is built with these models and libraries. Thank you to their authors.", size: 28)
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: CV.Space.s) {
                        CVSectionTitle(text: entry.name)
                        Text("\(entry.use). \(entry.license).").font(CV.Font.callout).foregroundStyle(CV.Palette.pearl)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.copyright).font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: entry.source) {
                            Link(entry.source, destination: url).font(CV.Font.caption).foregroundStyle(CV.Palette.glacier)
                        }
                        Text(entry.text).font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(CV.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cvCard(radius: CV.Radius.tile)
                }
                if !credits.isEmpty {
                    VStack(alignment: .leading, spacing: CV.Space.s) {
                        CVSectionTitle(text: "Sample photos")
                        ForEach(credits, id: \.self) { line in
                            Text(line).font(CV.Font.caption).foregroundStyle(CV.Palette.mist)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, CV.Space.m)
            .padding(.bottom, CV.Space.xl)
            .readableWidth()
        }
        .cvScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
