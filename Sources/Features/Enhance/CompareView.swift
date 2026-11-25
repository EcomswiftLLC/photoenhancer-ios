import SwiftUI
import UIKit

/// Before and after, one over the other, split by a draggable divider. Pinch, double tap and drag zoom and pan both
/// images together; touch and hold anywhere to see the whole original.
struct CompareView: View {
    let before: UIImage?
    let after: UIImage?
    /// 0...1 from the left edge.
    @Binding var divider: Double
    var showsLabels: Bool = true
    var initialZoom: CGFloat = 1

    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var didApplyInitialZoom = false
    @GestureState private var holding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxZoom: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let aspect = imageAspect
            let fit = fitSize(aspect: aspect, in: bounds)
            ZStack {
                CV.Palette.ink
                Group {
                    if let before {
                        Image(uiImage: before).resizable().interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                    }
                    if let after, !holding {
                        Image(uiImage: after).resizable().interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                            .mask(alignment: .leading) {
                                // The mask is in screen space, so the divider stays under the finger at any zoom.
                                afterMask(bounds: bounds, fit: fit)
                            }
                    }
                }
                .scaleEffect(zoom)
                .offset(offset)
                .clipShape(Rectangle())

                if after != nil && !holding {
                    dividerHandle(bounds: bounds)
                        .position(x: CGFloat(divider) * bounds.width, y: bounds.height / 2)
                }
                if showsLabels && after != nil {
                    labels
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            .coordinateSpace(name: "compare")
            .contentShape(Rectangle())
            .gesture(panGesture(bounds: bounds, fit: fit))
            .simultaneousGesture(pinchGesture(bounds: bounds, fit: fit))
            .simultaneousGesture(holdGesture)
            .onTapGesture(count: 2) { toggleZoom(bounds: bounds, fit: fit) }
            .onAppear {
                if !didApplyInitialZoom && initialZoom > 1 {
                    didApplyInitialZoom = true
                    zoom = initialZoom
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(after == nil ? "Photo" : "Before and after comparison"))
        .accessibilityValue(Text(after == nil ? "" : "Divider at \(Int((divider * 100).rounded())) percent. Left shows before, right shows after."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: divider = min(1, divider + 0.1)
            case .decrement: divider = max(0, divider - 0.1)
            @unknown default: break
            }
        }
        .accessibilityAddTraits(.isImage)
    }

    private var imageAspect: CGFloat {
        let image = after ?? before
        guard let size = image?.size, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func fitSize(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        if bounds.width / bounds.height > aspect {
            return CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGSize(width: bounds.width, height: bounds.width / aspect)
    }

    /// A rectangle covering the part right of the divider, expressed in the image's own (unscaled) coordinates.
    private func afterMask(bounds: CGSize, fit: CGSize) -> some View {
        // Screen x of the divider -> x inside the scaled, offset image frame.
        let imageLeftOnScreen = bounds.width / 2 + offset.width - fit.width * zoom / 2
        let localX = (CGFloat(divider) * bounds.width - imageLeftOnScreen) / max(zoom, 0.01)
        let clamped = min(max(localX, 0), fit.width)
        return Rectangle()
            .frame(width: max(0, fit.width - clamped), height: fit.height)
            .offset(x: clamped)
    }

    private func dividerHandle(bounds: CGSize) -> some View {
        let height = bounds.height
        return ZStack {
            Rectangle()
                .fill(CV.Palette.pearl)
                .frame(width: 2, height: height)
            HStack(spacing: 1) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(CV.Palette.pearl)
            .frame(width: 28, height: 28)
            .background(Circle().fill(CV.Palette.ink.opacity(0.7)))
            .overlay(Circle().strokeBorder(CV.Palette.frost, lineWidth: 1.5))
        }
        .frame(width: 48, height: height)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("compare"))
                .onChanged { value in
                    divider = Double(min(max(value.location.x / max(bounds.width, 1), 0), 1))
                }
        )
        .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack {
            HStack {
                pill("Before")
                Spacer()
                pill("After")
            }
            Spacer()
        }
        .padding(CV.Space.m)
        .allowsHitTesting(false)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(CV.Font.label)
            .foregroundStyle(CV.Palette.pearl)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(CV.Palette.ink.opacity(0.55))))
            .overlay(Capsule().strokeBorder(CV.Palette.line, lineWidth: 1))
    }

    // MARK: Gestures

    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
    }

    private func panGesture(bounds: CGSize, fit: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if zoom <= 1.001 {
                    // Not zoomed: a sideways drag moves the divider.
                    divider = Double(min(max(value.location.x / max(bounds.width, 1), 0), 1))
                    return
                }
                let start = panStart ?? offset
                if panStart == nil { panStart = offset }
                offset = clampedOffset(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height), bounds: bounds, fit: fit, zoom: zoom)
            }
            .onEnded { _ in panStart = nil }
    }

    private func pinchGesture(bounds: CGSize, fit: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = pinchStart ?? zoom
                if pinchStart == nil { pinchStart = zoom }
                zoom = min(max(start * value, 1), maxZoom)
                offset = clampedOffset(offset, bounds: bounds, fit: fit, zoom: zoom)
            }
            .onEnded { _ in
                pinchStart = nil
                if zoom < 1.02 { withAnimation(.easeOut(duration: 0.2)) { zoom = 1; offset = .zero } }
            }
    }

    private func toggleZoom(bounds: CGSize, fit: CGSize) {
        let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.25)
        withAnimation(animation) {
            if zoom > 1.01 {
                zoom = 1
                offset = .zero
            } else {
                zoom = 3
                offset = clampedOffset(offset, bounds: bounds, fit: fit, zoom: 3)
            }
        }
    }

    private func clampedOffset(_ proposed: CGSize, bounds: CGSize, fit: CGSize, zoom: CGFloat) -> CGSize {
        let maxX = max(0, (fit.width * zoom - bounds.width) / 2)
        let maxY = max(0, (fit.height * zoom - bounds.height) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }
}
