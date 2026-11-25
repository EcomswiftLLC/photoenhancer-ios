import SwiftUI
import UIKit

// MARK: - Buttons

enum LMButtonKind { case primary, secondary, quiet }

struct LMButtonStyle: ButtonStyle {
    var kind: LMButtonKind = .primary
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LM.Font.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, LM.Space.l)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: LM.Radius.control, style: .continuous)
                    .strokeBorder(kind == .secondary ? LM.Palette.paper.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LM.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return LM.Palette.onGlow
        case .secondary: return LM.Palette.paper
        case .quiet: return LM.Palette.glow
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [LM.Palette.glow, LM.Palette.glowDeep.opacity(pressed ? 1 : 0.92)],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary:
            if pressed { LM.Palette.graphite } else { Color.clear }
        case .quiet:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == LMButtonStyle {
    static var apPrimary: LMButtonStyle { LMButtonStyle(kind: .primary) }
    static var apPrimaryWide: LMButtonStyle { LMButtonStyle(kind: .primary, fullWidth: true) }
    static var apSecondary: LMButtonStyle { LMButtonStyle(kind: .secondary) }
    static var apSecondaryWide: LMButtonStyle { LMButtonStyle(kind: .secondary, fullWidth: true) }
    static var apQuiet: LMButtonStyle { LMButtonStyle(kind: .quiet) }
}

// MARK: - Structure

struct LMHairline: View {
    var body: some View {
        Rectangle().fill(LM.Palette.line).frame(height: 1 / UIScreen.main.scale)
    }
}

/// Sentence-case section title in the editorial serif.
struct LMSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(LM.Font.title(22))
            .foregroundStyle(LM.Palette.paper)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small pill used for options (ratio, format, preset).
struct LMChip: View {
    let title: String
    var systemImage: String? = nil
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(LM.Font.label).lineLimit(1)
            }
            .foregroundStyle(selected ? LM.Palette.onGlow : LM.Palette.paper)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? LM.Palette.glow : LM.Palette.graphite, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : LM.Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A group of chips that scrolls sideways.
struct LMChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LM.Space.s) { content() }
                .padding(.horizontal, LM.Space.m)
        }
    }
}

// MARK: - Dial slider (the signature control)

/// A slider drawn as the focus ring of a lens: a ruled scale slides under a fixed glow index.
/// Drag sideways to change the value, double tap to reset. A light tick is felt on every graduation
/// and the value snaps to the default when it gets close.
struct DialSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    var defaultValue: Double = 0
    /// Shown after the number, for example a degree sign or a percent sign.
    var unit: String = ""
    var decimals: Int = 0
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStart: Double?
    @State private var didStartEditing = false
    @State private var lastTick: Int = -1

    private let rulerWidth: CGFloat = 700
    private let tickSpacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(LM.Font.label).foregroundStyle(LM.Palette.mist)
                Spacer()
                Text(valueText)
                    .font(LM.Font.number)
                    .foregroundStyle(abs(value - defaultValue) < 0.0001 ? LM.Palette.mist : LM.Palette.glow)
            }
            GeometryReader { geo in
                ruler(width: geo.size.width)
            }
            .frame(height: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 40
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var valueText: String {
        let number = decimals == 0 ? String(Int(value.rounded())) : String(format: "%.\(decimals)f", value)
        return number + unit
    }

    private func ruler(width: CGFloat) -> some View {
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
        let originX = width / 2 - fraction * rulerWidth
        let tickCount = Int(rulerWidth / tickSpacing)
        let spacing = tickSpacing
        return Canvas { context, size in
            for k in 0...tickCount {
                let x = originX + CGFloat(k) * spacing
                if x < -2 || x > size.width + 2 { continue }
                let major = k % 5 == 0
                let h: CGFloat = major ? 18 : 10
                let distance = abs(x - size.width / 2) / (size.width / 2)
                let alpha = max(0.08, 1 - distance) * (major ? 0.85 : 0.5)
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - 3))
                path.addLine(to: CGPoint(x: x, y: size.height - 3 - h))
                context.stroke(path, with: .color(LM.Palette.paper.opacity(alpha)), lineWidth: 1)
            }
            var index = Path()
            index.move(to: CGPoint(x: size.width / 2, y: 0))
            index.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(index, with: .color(LM.Palette.glow), lineWidth: 2)
        }
        .contentShape(Rectangle())
        .overlay(
            HorizontalPanArea(
                onBegan: {
                    dragStart = value
                    lastTick = -1
                    onEditingChanged(true)
                },
                onChanged: { translation in
                    let start = dragStart ?? value
                    let delta = -Double(translation) / Double(rulerWidth) * span
                    var next = min(range.upperBound, max(range.lowerBound, start + delta))
                    if abs(next - defaultValue) < span * 0.012 { next = defaultValue }
                    let tick = Int(((next - range.lowerBound) / max(span, 0.0001)) * Double(tickCount))
                    if tick != lastTick {
                        lastTick = tick
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    value = next
                },
                onEnded: {
                    dragStart = nil
                    onEditingChanged(false)
                },
                onDoubleTap: {
                    value = defaultValue
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            )
        )
    }
}

/// A sideways drag and a double tap, written with UIKit so a mostly vertical swipe starts no drag at all and the panel
/// around the dial still scrolls. A tap or a resting finger never counts as an edit.
struct HorizontalPanArea: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPanArea?

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let parent else { return }
            let x = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began: parent.onBegan(); parent.onChanged(x)
            case .changed: parent.onChanged(x)
            case .ended, .cancelled, .failed: parent.onEnded()
            default: break
            }
        }

        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { parent?.onDoubleTap() }
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

// MARK: - Aperture mark

/// The Lumotion mark: six blades around a small opening, drawn in code so it stays sharp at any size.
struct ApertureMark: View {
    var lineWidth: CGFloat = 2
    var color: Color = LM.Palette.glow
    var openness: CGFloat = 0.28

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - lineWidth
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let inner = radius * openness
            Canvas { context, _ in
                var ring = Path()
                ring.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                context.stroke(ring, with: .color(color), lineWidth: lineWidth)
                let beta = acos(Double(openness))
                let vertexRadius = inner / CGFloat(cos(Double.pi / 6))
                for i in 0..<6 {
                    let a = Double(i) / 6 * 2 * Double.pi
                    let start = CGPoint(x: centre.x + CGFloat(cos(a + beta)) * radius, y: centre.y + CGFloat(sin(a + beta)) * radius)
                    let end = CGPoint(
                        x: centre.x + CGFloat(cos(a - Double.pi / 6)) * vertexRadius,
                        y: centre.y + CGFloat(sin(a - Double.pi / 6)) * vertexRadius
                    )
                    var blade = Path()
                    blade.move(to: start)
                    blade.addLine(to: end)
                    context.stroke(blade, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Haptics

enum LMHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
