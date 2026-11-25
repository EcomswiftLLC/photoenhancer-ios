import SwiftUI
import UIKit

// MARK: - Buttons

enum CVButtonKind { case primary, secondary, quiet }

struct CVButtonStyle: ButtonStyle {
    var kind: CVButtonKind = .primary
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CV.Font.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, CV.Space.l)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: CV.Radius.control, style: .continuous)
                    .strokeBorder(kind == .secondary ? CV.Palette.lineStrong : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CV.Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: CV.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return CV.Palette.onGlacier
        case .secondary: return CV.Palette.pearl
        case .quiet: return CV.Palette.glacier
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: pressed ? [CV.Palette.glacierDeep, CV.Palette.glacierDeep] : [CV.Palette.glacier, CV.Palette.glacierDeep],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary:
            if pressed { CV.Palette.raised } else { Color.clear }
        case .quiet:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == CVButtonStyle {
    static var cvPrimary: CVButtonStyle { CVButtonStyle(kind: .primary) }
    static var cvPrimaryWide: CVButtonStyle { CVButtonStyle(kind: .primary, fullWidth: true) }
    static var cvSecondary: CVButtonStyle { CVButtonStyle(kind: .secondary) }
    static var cvSecondaryWide: CVButtonStyle { CVButtonStyle(kind: .secondary, fullWidth: true) }
    static var cvQuiet: CVButtonStyle { CVButtonStyle(kind: .quiet) }
}

// MARK: - Structure

struct CVHairline: View {
    var body: some View {
        Rectangle().fill(CV.Palette.line).frame(height: 1 / max(UITraitCollection.current.displayScale, 1))
    }
}

/// Sentence-case section title.
struct CVSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .cvTitle(20)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small pill used for options (format, size, mode).
struct CVChip: View {
    let title: String
    var systemImage: String? = nil
    var selected: Bool
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).accessibilityHidden(true) }
                Text(title).font(CV.Font.label).lineLimit(1).fixedSize()
            }
            .foregroundStyle(selected ? CV.Palette.onGlacier : CV.Palette.pearl)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? CV.Palette.glacier : CV.Palette.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : CV.Palette.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A group of chips that wraps onto more lines instead of truncating.
struct CVChipFlow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        FlowLayout(spacing: CV.Space.s) { content() }
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full. Sizing and placement share one
/// algorithm (`rows`), so the height it asks for always matches where it puts things.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth + 0.5 {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = rows(maxWidth: maxWidth, subviews: subviews)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (i, line) in lines.enumerated() {
            let lineWidth = line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, line.count - 1))
            widest = max(widest, lineWidth)
            height += (line.map { $0.size.height }.max() ?? 0) + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = rows(maxWidth: proposal.width ?? bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            let lineHeight = line.map { $0.size.height }.max() ?? 0
            for item in line {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += lineHeight + spacing
        }
    }
}

// MARK: - Strength slider

/// A labelled slider with its value shown as a percentage. Uses the system slider, so VoiceOver can adjust it.
struct StrengthSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onCommit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(CV.Font.label).foregroundStyle(CV.Palette.mist)
                Spacer()
                Text(percent).font(CV.Font.readout).foregroundStyle(CV.Palette.pearl)
            }
            .accessibilityHidden(true)
            Slider(value: $value, in: range, onEditingChanged: { editing in if !editing { onCommit() } })
                .tint(CV.Palette.glacier)
                .frame(minHeight: 44)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(percent))
        }
    }

    private var percent: String {
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (value - range.lowerBound) / span : 0
        return "\(Int((fraction * 100).rounded())) %"
    }
}

// MARK: - The Clarivo mark

/// The mark, after the app icon: viewfinder corners around a tile split by one bright diagonal (focus snapping in).
/// Drawn in code so it stays crisp at any size.
struct ClarivoMark: View {
    var lineWidth: CGFloat = 2
    var color: Color = CV.Palette.glacier

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Canvas { context, _ in
                let inset = lineWidth
                let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
                let arm = side * 0.3
                var corners = Path()
                corners.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
                corners.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                corners.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
                corners.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
                corners.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                corners.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
                corners.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
                corners.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                corners.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
                corners.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
                corners.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                corners.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
                context.stroke(corners, with: .color(CV.Palette.pearl), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                var diagonal = Path()
                let pad = side * 0.24
                diagonal.move(to: CGPoint(x: rect.minX + pad, y: rect.maxY - pad))
                diagonal.addLine(to: CGPoint(x: rect.maxX - pad, y: rect.minY + pad))
                context.stroke(diagonal, with: .color(color), style: StrokeStyle(lineWidth: lineWidth * 1.3, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Haptics

enum CVHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
