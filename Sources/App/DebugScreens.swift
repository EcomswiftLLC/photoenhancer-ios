#if DEBUG
import SwiftUI
import UIKit

/// Debug builds can open a screen directly, so CI can screenshot every screen without tapping through the app:
/// `xcrun simctl launch <device> com.ecomswift.photoenhancer -cvScreen home`. None of this exists in Release builds.
enum DebugScreens {
    static var requested: String? {
        guard let value = UserDefaults.standard.string(forKey: "cvScreen"), !value.isEmpty else { return nil }
        return value
    }

    /// Every screen CI screenshots (see SCREENS in .github/workflows/ios.yml).
    static let names = ["onboarding", "home", "enhance", "enhance-tools", "export", "batch", "settings", "licenses"]

    @MainActor @ViewBuilder
    static func view(for screen: String) -> some View {
        switch screen {
        case "onboarding":
            OnboardingView().environmentObject(AppState())
        case "home":
            HomeView()
        case "settings":
            SettingsView()
        case "licenses":
            NavigationStack { LicensesView() }.preferredColorScheme(.dark)
        case "enhance":
            EnhanceView(asset: DebugFixtures.asset(), initial: DebugFixtures.settings([.autoFix]), selected: .autoFix)
        case "enhance-tools":
            EnhanceView(asset: DebugFixtures.asset(), initial: DebugFixtures.settings([.restore, .sharpen]), selected: .restore)
        case "export":
            ExportView(model: ExportModel(asset: DebugFixtures.asset(), recipe: [.autoFix(strength: 0.8)], size: .factor(1),
                                          before: DebugFixtures.preview(), after: DebugFixtures.preview()))
        case "batch":
            BatchView(assets: DebugFixtures.batchAssets())
        case let name where name.hasPrefix("shot-"):
            StoreScreens.view(for: String(name.dropFirst("shot-".count)))
        default:
            HomeView()
        }
    }
}

/// Generated pictures for development only. Every one is labelled as a test image on screen.
enum DebugFixtures {
    static func settings(_ tools: Set<ToolKind>) -> ToolSettings {
        var settings = ToolSettings()
        settings.enabled = tools.filter { Enhancer.shared.isAvailable($0) }
        return settings
    }

    /// The first bundled sample, or a generated test image when the app has none.
    static func asset() -> PhotoAsset {
        if let name = SampleLibrary.availableNames().first, let asset = PhotoAsset.sample(named: name) { return asset }
        return PhotoAsset.generated(testImage(), title: "Test image (debug build)")
    }

    static func preview() -> UIImage? {
        asset().decode(maxPixel: 1200).map { UIImage(cgImage: $0) }
    }

    static func batchAssets() -> [PhotoAsset] {
        let samples = SampleLibrary.availableNames().prefix(6).compactMap { PhotoAsset.sample(named: $0) }
        if samples.count >= 2 { return Array(samples) }
        return (0..<4).map { PhotoAsset.generated(testImage(seed: $0), title: "Test image \($0 + 1) (debug build)") }
    }

    /// A clearly labelled synthetic test picture: gradients, fine lines and text, so enhancement is visible.
    static func testImage(seed: Int = 0, size: CGSize = CGSize(width: 1200, height: 1500)) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let palettes: [[UInt32]] = [[0x16324F, 0x2E8C9A, 0xCFE9E4], [0x2A1E3F, 0x7A5C9E, 0xE8D9F2], [0x1E3324, 0x5C9A6E, 0xE6F2D9], [0x3A2416, 0xA0683E, 0xF2E2CF]]
        let colors = palettes[abs(seed) % palettes.count]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors.map { UIColor(hex: $0).cgColor } as CFArray, locations: [0, 0.6, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.7).setStroke()
            for i in 0..<40 {
                let y = CGFloat(i) * size.height / 40
                cg.setLineWidth(CGFloat(1 + i % 3))
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y + size.height * 0.1))
                cg.strokePath()
            }
            let text = "Test image (debug build)" as NSString
            text.draw(at: CGPoint(x: 48, y: size.height - 140), withAttributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: UIColor.white,
            ])
        }
        return image.cgImage ?? UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.cgImage!
    }
}
#endif
