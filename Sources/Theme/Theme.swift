import SwiftUI
import UIKit

/// Clarivo design tokens, from docs/DESIGN.md (BRAND). Every colour, size and font of the app lives in this one file.
///
/// Glacier aqua on deep blue ink: cool, clean and precise. One accent per screen; photos sit on `ink` untinted.
enum CV {
    enum Palette {
        /// App background and launch background.
        static let ink = Color(hex: 0x081219)
        /// First surface: cards, sheets, tool bars.
        static let deep = Color(hex: 0x0F1C26)
        /// Raised surface: pressed rows, chips, slider tracks.
        static let raised = Color(hex: 0x172836)
        static let line = Color.white.opacity(0.09)
        static let lineStrong = Color.white.opacity(0.16)
        /// Primary text, 17.1:1 on ink.
        static let pearl = Color(hex: 0xEEF5F7)
        /// Secondary text, 8.7:1 on ink, 6.9:1 on raised.
        static let mist = Color(hex: 0x9DB3BF)
        /// Tertiary text: large text or icons only.
        static let faint = Color(hex: 0x6B8494)
        /// The accent: primary button, selected state, progress, links (12.8:1 on ink).
        static let glacier = Color(hex: 0x7FE6D7)
        static let glacierDeep = Color(hex: 0x47C9BA)
        /// Highlight only: the compare divider ring and the focus snap.
        static let frost = Color(hex: 0xCFF7F1)
        /// Text and icons on glacier (11.6:1).
        static let onGlacier = Color(hex: 0x04201D)
        static let success = Color(hex: 0x6FD39A)
        static let warning = Color(hex: 0xF4C56A)
        static let danger = Color(hex: 0xFF8A80)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let control: CGFloat = 14
        static let tile: CGFloat = 18
        static let panel: CGFloat = 24
    }

    /// Widths that keep content comfortable on iPad.
    enum Layout {
        /// Forms and settings on iPad.
        static let readable: CGFloat = 760
        static let narrow: CGFloat = 560
        static let inspector: CGFloat = 360
        static let homeRail: CGFloat = 400
    }

    enum Font {
        /// Sizes follow the person's text size setting, capped so a headline never outgrows the screen.
        private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle, cap: CGFloat) -> CGFloat {
            min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * cap)
        }
        /// SF Pro Display semibold (tracking -0.8 via `cvDisplay`).
        static func display(_ size: CGFloat = 34) -> SwiftUI.Font {
            .system(size: scaled(size, .largeTitle, cap: 1.5), weight: .semibold)
        }
        /// SF Pro semibold (tracking -0.4 via `cvTitle`).
        static func title(_ size: CGFloat = 22) -> SwiftUI.Font {
            .system(size: scaled(size, .title2, cap: 1.6), weight: .semibold)
        }
        static let headline = SwiftUI.Font.system(.headline).weight(.semibold)
        static let body = SwiftUI.Font.system(.body)
        static let callout = SwiftUI.Font.system(.callout)
        static let label = SwiftUI.Font.system(.footnote).weight(.medium)
        static let caption = SwiftUI.Font.system(.caption)
        /// Real readouts only: 4×, 3024 × 4032, 12.2 MP, 84 %.
        static let readout = SwiftUI.Font.system(.callout, design: .monospaced).monospacedDigit().weight(.medium)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// Full-screen background in the app's base colour.
    func cvScreen() -> some View {
        background(CV.Palette.ink.ignoresSafeArea())
    }

    func cvDisplay(_ size: CGFloat = 34) -> some View {
        font(CV.Font.display(size)).tracking(-0.8).foregroundStyle(CV.Palette.pearl)
    }

    func cvTitle(_ size: CGFloat = 22) -> some View {
        font(CV.Font.title(size)).tracking(-0.4).foregroundStyle(CV.Palette.pearl)
    }
}

/// Appearance for system bars, set once at launch.
enum CVAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xEEF5F7)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(hex: 0xEEF5F7)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(hex: 0x7FE6D7)
    }
}
