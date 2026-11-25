import SwiftUI

/// The glass panel: a blurred, lightly tinted surface with a hairline edge. Used for panels that sit over a photo.
struct CVGlass: ViewModifier {
    var radius: CGFloat = CV.Radius.panel
    var tint: Double = 0.78

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(CV.Palette.deep.opacity(tint)))
                .overlay(shape.strokeBorder(CV.Palette.line, lineWidth: 1))
        }
    }
}

/// A plain surface card (no blur), for content on the app background.
struct CVCard: ViewModifier {
    var radius: CGFloat = CV.Radius.panel
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(CV.Palette.deep).overlay(shape.strokeBorder(CV.Palette.line, lineWidth: 1))
        }
    }
}

extension View {
    func cvGlass(radius: CGFloat = CV.Radius.panel, tint: Double = 0.78) -> some View {
        modifier(CVGlass(radius: radius, tint: tint))
    }

    func cvCard(radius: CGFloat = CV.Radius.panel) -> some View {
        modifier(CVCard(radius: radius))
    }

    /// On iPad, keeps reading content a comfortable width and centred. On iPhone it changes nothing.
    func readableWidth(_ width: CGFloat = CV.Layout.readable) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

/// Large headline and one supporting line, used at the top of full screens and sheets.
struct CVHeader: View {
    let title: String
    var subtitle: String? = nil
    var size: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).cvDisplay(size)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(CV.Font.callout).foregroundStyle(CV.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tappable row in a settings-style list: symbol, title, optional value and a chevron.
struct CVRow: View {
    let title: String
    let symbol: String
    var value: String? = nil
    var showsChevron: Bool = true
    var external: Bool = false

    var body: some View {
        HStack(spacing: CV.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(CV.Palette.glacier)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title).font(CV.Font.body).foregroundStyle(CV.Palette.pearl)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(CV.Font.callout).foregroundStyle(CV.Palette.mist)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.Palette.mist)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// Round icon button with a 44 pt target, used in bars.
struct CVIconButton: View {
    let symbol: String
    let label: String
    var disabled: Bool = false
    var tint: Color = CV.Palette.pearl
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(CV.Palette.deep.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(CV.Palette.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(Text(label))
    }
}
