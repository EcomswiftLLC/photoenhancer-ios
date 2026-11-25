import SwiftUI

/// Three short, honest cards, then Home. Scrolls on short screens so the button is always reachable.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0
    @State private var heroImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Card: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
    }

    static let cards = [
        Card(id: 0, symbol: "arrow.up.left.and.arrow.down.right", title: "Sharper, larger photos",
             text: "Upscale up to 8×, reduce blur and noise, and sharpen in a few taps."),
        Card(id: 1, symbol: "photo.badge.checkmark", title: "Bring old photos back",
             text: "Remove dust and scratches, lift faded tones and add natural-looking colour. Colours are an estimate."),
        Card(id: 2, symbol: "lock.shield", title: "Photos never leave your device",
             text: "Your photos are processed on your device and never uploaded. Clarivo is free, with ads."),
    ]

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700 && geo.size.width > geo.size.height
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .center, spacing: CV.Space.xl) {
                            hero.frame(maxWidth: .infinity).frame(height: min(max(geo.size.height - 96, 240), 560))
                            copy.frame(maxWidth: 440)
                        }
                        .padding(.horizontal, CV.Space.xl)
                        .frame(minHeight: geo.size.height)
                    } else {
                        VStack(alignment: .leading, spacing: CV.Space.l) {
                            hero.frame(height: min(geo.size.height * 0.32, 320)).padding(.top, CV.Space.m)
                            copy
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: geo.size.height)
                        .readableWidth(CV.Layout.narrow)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .cvScreen()
        .task {
            heroImage = await Task.detached(priority: .utility) { () -> UIImage? in
                let names = SampleLibrary.availableNames()
                let name = names.first(where: { $0.hasPrefix("portrait-woman") && !$0.contains("lowres") }) ?? names.first
                return name.flatMap { SampleLibrary.image(named: $0, maxPixel: 1200) }.map { UIImage(cgImage: $0) }
            }.value
        }
    }

    private var hero: some View {
        // The photo fills the frame it is given and never widens the layout.
        CV.Palette.deep
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let heroImage {
                    Image(uiImage: heroImage).resizable().scaledToFill()
                        .accessibilityHidden(true)
                } else {
                    ClarivoMark(lineWidth: 3).frame(width: 96, height: 96)
                }
            }
            .clipped()
        .clipShape(RoundedRectangle(cornerRadius: CV.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CV.Radius.panel, style: .continuous).strokeBorder(CV.Palette.line, lineWidth: 1))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CV.Space.s) {
                ClarivoMark(lineWidth: 1.6).frame(width: 24, height: 24)
                Text("Clarivo").cvTitle(18)
            }
            Text("Welcome to Clarivo.")
                .cvDisplay(36)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CV.Space.m)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                CVHairline()
                ForEach(Self.cards) { card in
                    line(card)
                    CVHairline()
                }
            }
            .padding(.top, CV.Space.l)
            Button {
                let change = { appState.hasOnboarded = true }
                if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.25), change) }
            } label: {
                Text("Get started")
            }
            .buttonStyle(.cvPrimaryWide)
            .padding(.vertical, CV.Space.l)
        }
    }

    private func line(_ card: Card) -> some View {
        HStack(alignment: .top, spacing: CV.Space.m) {
            Image(systemName: card.symbol)
                .font(.system(size: 19))
                .foregroundStyle(CV.Palette.glacier)
                .frame(width: 32)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(CV.Font.headline).foregroundStyle(CV.Palette.pearl)
                Text(card.text).font(CV.Font.callout).foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
