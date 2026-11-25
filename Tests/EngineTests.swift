import XCTest
import CoreGraphics
import UIKit
@testable import Clarivo

final class SizeCapTests: XCTestCase {
    func testSmallPhotosAreNotReduced() {
        let plan = SizeCap.plan(source: PixelSize(width: 1000, height: 750), scale: 4)
        XCTAssertFalse(plan.capApplied)
        XCTAssertFalse(plan.inputReduced)
        XCTAssertEqual(plan.output, PixelSize(width: 4000, height: 3000))
    }

    func testLongSideCap() {
        let plan = SizeCap.plan(source: PixelSize(width: 4000, height: 1000), scale: 4)
        XCTAssertTrue(plan.capApplied)
        XCTAssertTrue(plan.inputReduced)
        XCTAssertLessThanOrEqual(plan.output.longSide, SizeCap.maxLongSide)
        XCTAssertGreaterThan(plan.output.longSide, SizeCap.maxLongSide - 8)
        XCTAssertEqual(plan.output.width, plan.input.width * 4)
    }

    func testMegapixelCap() {
        // 12 MP at 4x would be 193 MP.
        let plan = SizeCap.plan(source: PixelSize(width: 4032, height: 3024), scale: 4)
        XCTAssertTrue(plan.capApplied)
        XCTAssertLessThanOrEqual(Double(plan.output.width * plan.output.height), SizeCap.maxMegapixels * 1_000_000)
        XCTAssertGreaterThan(plan.output.megapixels, 46)
        XCTAssertLessThanOrEqual(plan.output.longSide, SizeCap.maxLongSide)
        // Aspect ratio is kept (within a pixel of rounding).
        XCTAssertEqual(Double(plan.output.width) / Double(plan.output.height), 4032.0 / 3024.0, accuracy: 0.01)
    }

    func testEightTimesNeedsATinyInput() {
        let plan = SizeCap.plan(source: PixelSize(width: 2000, height: 1500), scale: 8)
        XCTAssertTrue(plan.inputReduced)
        XCTAssertLessThanOrEqual(plan.input.longSide, 1024)
        XCTAssertTrue(SizeCap.fits(plan.output))
    }

    func testExactBoundaryFits() {
        XCTAssertTrue(SizeCap.fits(PixelSize(width: 8192, height: 5859)))
        XCTAssertFalse(SizeCap.fits(PixelSize(width: 8193, height: 10)))
        XCTAssertFalse(SizeCap.fits(PixelSize(width: 8000, height: 6001)))
        let plan = SizeCap.plan(source: PixelSize(width: 2048, height: 1464), scale: 4)
        XCTAssertFalse(plan.capApplied, "8192 x 5856 is 47.97 MP, inside the cap")
    }

    func testScaleOneOfAHugePanoramaIsCapped() {
        let plan = SizeCap.plan(source: PixelSize(width: 20000, height: 3000), scale: 1)
        XCTAssertTrue(plan.capApplied)
        XCTAssertLessThanOrEqual(plan.output.longSide, 8192)
    }

    func testCustomSizesAndFactors() {
        let source = PixelSize(width: 1000, height: 500)
        XCTAssertEqual(SizeCap.size(for: source, longSide: 3000), PixelSize(width: 3000, height: 1500))
        XCTAssertEqual(SizeCap.size(for: source, longSide: 99_999).longSide, 8192)
        XCTAssertEqual(SizeCap.factor(toReach: PixelSize(width: 800, height: 400), from: source), 1)
        XCTAssertEqual(SizeCap.factor(toReach: PixelSize(width: 1500, height: 750), from: source), 2)
        XCTAssertEqual(SizeCap.factor(toReach: PixelSize(width: 3000, height: 1500), from: source), 4)
        XCTAssertEqual(SizeCap.factor(toReach: PixelSize(width: 7000, height: 3500), from: source), 8)
    }

    func testFittingNeverEnlarges() {
        XCTAssertEqual(PixelSize(width: 100, height: 50).fitting(longSide: 400), PixelSize(width: 100, height: 50))
        XCTAssertEqual(PixelSize(width: 4000, height: 2000).fitting(longSide: 400), PixelSize(width: 400, height: 200))
    }

    func testMemoryFootprintIsReadable() {
        XCTAssertGreaterThan(MemoryGuard.physicalFootprint(), 0)
        XCTAssertGreaterThan(MemoryGuard.estimatedPeakBytes(input: PixelSize(width: 2000, height: 1500), output: PixelSize(width: 8000, height: 6000), tileOut: 1024), 192_000_000)
    }
}

final class RecipeTests: XCTestCase {
    func testStepsRunInPipelineOrderOnePerTool() {
        let ops: [EnhanceOperation] = [.upscale(factor: 2), .sharpen(strength: 0.3), .restoreOld(strength: 0.5), .autoFix(strength: 1), .upscale(factor: 4)]
        let ordered = Recipe.normalized(ops)
        XCTAssertEqual(ordered, [.restoreOld(strength: 0.5), .autoFix(strength: 1), .sharpen(strength: 0.3), .upscale(factor: 4)])
        XCTAssertEqual(Recipe.totalScale(ops), 4)
    }

    func testDenoiseModesShareOneTool() {
        let ordered = Recipe.normalized([.denoise(strength: 0.5), .denoiseLight(strength: 0.2)])
        XCTAssertEqual(ordered, [.denoiseLight(strength: 0.2)])
    }

    func testToolsKnowTheirModels() {
        XCTAssertEqual(EnhanceOperation.upscale(factor: 2).requiredModel, .superResolution)
        XCTAssertEqual(EnhanceOperation.denoise(strength: 1).requiredModel, .superResolution)
        XCTAssertNil(EnhanceOperation.denoiseLight(strength: 1).requiredModel)
        XCTAssertEqual(EnhanceOperation.unblur.requiredModel, .deblur)
        XCTAssertEqual(EnhanceOperation.colorize.requiredModel, .colorize)
        XCTAssertNil(EnhanceOperation.portrait.requiredModel, "Portrait falls back to classical enhancement")
        for tool in ToolKind.allCases {
            XCTAssertFalse(tool.title.isEmpty)
            XCTAssertFalse(tool.blurb.isEmpty)
            XCTAssertNotNil(UIImage(systemName: tool.symbol), "Missing SF Symbol \(tool.symbol)")
        }
    }

    func testHonestCopy() {
        let banned = ["recover lost", "never there", "reconstruct", "perfect", "magic", "face restoration"]
        for tool in ToolKind.allCases {
            for word in banned {
                XCTAssertFalse(tool.blurb.lowercased().contains(word), "\(tool) blurb says \(word)")
            }
        }
    }

    func testPresetSettingsMakeRecipes() {
        for preset in ToolSettings.Preset.allCases {
            XCTAssertFalse(preset.settings.recipe.isEmpty, preset.title)
        }
        XCTAssertEqual(ToolSettings.Preset.upscale4x.requiredModels, [.superResolution])
        XCTAssertTrue(ToolSettings.Preset.autoEnhance.requiredModels.isEmpty)
    }
}

final class EngineTests: XCTestCase {
    private let noModels = Enhancer(models: NoModels())

    func testModelStepsFailGracefullyWithoutModels() async {
        let image = TestImages.cgPattern(width: 64, height: 64)
        for op in [EnhanceOperation.upscale(factor: 2), .unblur, .colorize, .denoise(strength: 0.5)] {
            do {
                _ = try await noModels.run([op], on: image)
                XCTFail("\(op) should need a model")
            } catch let error as EnhanceError {
                guard case .modelUnavailable = error else { return XCTFail("\(op): \(error)") }
                XCTAssertFalse(error.message.isEmpty)
            } catch {
                XCTFail("\(error)")
            }
        }
        XCTAssertFalse(noModels.isAvailable(ToolKind.upscale))
        XCTAssertTrue(noModels.isAvailable(ToolKind.autoFix))
        XCTAssertTrue(noModels.isAvailable(ToolKind.portrait))
    }

    func testClassicalStepsKeepSizeAndChangePixels() async throws {
        let image = TestImages.cgPattern(width: 320, height: 240)
        let original = try XCTUnwrap(RGBAImage(cgImage: image))
        let ops: [EnhanceOperation] = [.autoFix(strength: 1), .sharpen(strength: 1), .denoiseLight(strength: 1), .restoreOld(strength: 1), .portrait]
        for op in ops {
            let output = try await noModels.run([op], on: image)
            XCTAssertEqual(output.image.width, 320, "\(op)")
            XCTAssertEqual(output.image.height, 240, "\(op)")
            if op != .portrait {
                let result = try XCTUnwrap(RGBAImage(cgImage: output.image))
                XCTAssertGreaterThan(TestImages.meanDifference(result, original), 0.05, "\(op) changed nothing")
            }
        }
    }

    func testPortraitWithoutFacesChangesNothingAndSaysSo() async throws {
        let image = TestImages.cgPattern(width: 200, height: 160)
        let output = try await noModels.run([.portrait], on: image)
        XCTAssertEqual(output.notes.facesFound, 0)
        XCTAssertTrue(output.notes.messages.contains { $0.contains("No faces") })
    }

    func testZeroStrengthKeepsThePhoto() throws {
        let image = TestImages.cgPattern(width: 120, height: 90)
        let out = try XCTUnwrap(ClassicalOps.autoFix(image, strength: 0))
        let a = try XCTUnwrap(RGBAImage(cgImage: image)), b = try XCTUnwrap(RGBAImage(cgImage: out))
        XCTAssertLessThanOrEqual(TestImages.maxDifference(a, b), 2)
    }

    func testTinyImagesWork() async throws {
        for (w, h) in [(1, 1), (2, 3), (7, 1)] {
            let image = TestImages.solid(width: w, height: h, r: 120, g: 80, b: 40)
            let output = try await noModels.run([.autoFix(strength: 1), .sharpen(strength: 1), .restoreOld(strength: 1), .denoiseLight(strength: 1)], on: image)
            XCTAssertEqual(output.image.width, w)
            XCTAssertEqual(output.image.height, h)
        }
    }

    func testLargeImageClassicalRunStaysSane() async throws {
        // 6000 x 4000 = 24 MP: decode, run and render without a crash.
        let big = TestImages.solid(width: 6000, height: 4000, r: 90, g: 120, b: 150)
        let output = try await noModels.run([.autoFix(strength: 0.8), .sharpen(strength: 0.4)], on: big)
        XCTAssertEqual(output.image.width, 6000)
    }

    func testCorruptAndEmptyDataAreRefused() {
        XCTAssertNil(PhotoAsset.from(data: Data(), title: "empty"))
        XCTAssertNil(PhotoAsset.from(data: Data([0xFF, 0xD8, 0xFF, 0x00, 0x12]), title: "truncated jpeg"))
        XCTAssertNil(PhotoAsset.from(data: Data("not a photo".utf8), title: "text"))
        var random = [UInt8](repeating: 0, count: 4096)
        for i in random.indices { random[i] = UInt8((i * 31 + 7) & 0xFF) }
        XCTAssertNil(PhotoAsset.from(data: Data(random), title: "noise"))
        // A real JPEG cut in half: header fine, pixels missing. Must not crash, whatever ImageIO decides.
        let jpeg = TestImages.jpegData(TestImages.cgPattern(width: 400, height: 300))
        let half = jpeg.prefix(jpeg.count / 2)
        if let asset = PhotoAsset.from(data: Data(half), title: "half") {
            _ = asset.decode(maxPixel: 200)
        }
        XCTAssertNil(ImageDecoder.decode(data: Data(), maxPixel: 100))
    }

    func testDecodeCapsSizeAndKeepsSmallPhotos() throws {
        let data = TestImages.jpegData(TestImages.cgPattern(width: 3000, height: 1500))
        let asset = try XCTUnwrap(PhotoAsset.from(data: data, title: "Wide"))
        XCTAssertEqual(asset.uprightSize, PixelSize(width: 3000, height: 1500))
        let reduced = try XCTUnwrap(asset.decode(maxPixel: 1000))
        XCTAssertEqual(max(reduced.width, reduced.height), 1000)
        let full = try XCTUnwrap(asset.decodeFull())
        XCTAssertEqual(full.width, 3000)
    }

    func testCancelledRunThrowsCancelled() async {
        let token = CancelToken()
        token.cancel()
        do {
            _ = try await noModels.run([.autoFix(strength: 1)], on: TestImages.cgPattern(width: 50, height: 50), cancel: token)
            XCTFail("should stop")
        } catch {
            XCTAssertEqual(error as? EnhanceError, .cancelled)
        }
    }

    func testEmptyRecipeReturnsThePhoto() async throws {
        let image = TestImages.cgPattern(width: 40, height: 30)
        let output = try await noModels.run([], on: image)
        XCTAssertEqual(output.image.width, 40)
    }

    func testLevelsStretchAFadedPrint() {
        // A faded, yellowed print: values squeezed into 60...190 with a warm cast.
        var image = TestImages.gray(width: 128, height: 128)
        for i in 0..<(128 * 128) {
            let v = Int(image.pixels[i * 4])
            image.pixels[i * 4] = UInt8(70 + v * 120 / 255)
            image.pixels[i * 4 + 1] = UInt8(62 + v * 115 / 255)
            image.pixels[i * 4 + 2] = UInt8(40 + v * 100 / 255)
        }
        let levels = Levels.measure(image, lowPercentile: 0.004, highPercentile: 0.996)
        var stretched = image
        levels.apply(to: &stretched, amount: 1)
        let darkest = stretched.pixels.enumerated().filter { $0.offset % 4 == 0 }.map(\.element).min() ?? 255
        let brightest = stretched.pixels.enumerated().filter { $0.offset % 4 == 0 }.map(\.element).max() ?? 0
        XCTAssertLessThan(darkest, 10)
        XCTAssertGreaterThan(brightest, 245)
        // The yellow cast is gone: the middle pixel is close to neutral.
        let mid = (64 * 128 + 64) * 4
        XCTAssertLessThan(abs(Int(stretched.pixels[mid]) - Int(stretched.pixels[mid + 2])), 20)
    }

    func testScratchRemovalErasesAThinLine() throws {
        // Mid-grey photo with a one-pixel white scratch.
        var image = RGBAImage(width: 200, height: 200, pixels: [UInt8](repeating: 120, count: 200 * 200 * 4))
        image.makeOpaque()
        for y in 0..<200 {
            let o = (y * 200 + 100) * 4
            image.pixels[o] = 250; image.pixels[o + 1] = 250; image.pixels[o + 2] = 250
        }
        let cg = try XCTUnwrap(image.makeCGImage())
        let cleaned = try XCTUnwrap(ClassicalOps.removeScratches(cg, strength: 0.8))
        let out = try XCTUnwrap(RGBAImage(cgImage: cleaned))
        let o = (100 * 200 + 100) * 4
        XCTAssertLessThan(Int(out.pixels[o]), 170, "the scratch should be mostly gone")
        // Far from the scratch nothing changes.
        let far = (100 * 200 + 20) * 4
        XCTAssertLessThan(abs(Int(out.pixels[far]) - 120), 6)
    }

    func testTransferCorrectionAddsTheSmallChange() {
        let before = RGBAImage(width: 10, height: 10, pixels: [UInt8](repeating: 100, count: 400))
        let after = RGBAImage(width: 10, height: 10, pixels: [UInt8](repeating: 110, count: 400))
        let full = RGBAImage(width: 40, height: 40, pixels: [UInt8](repeating: 50, count: 6400))
        let out = Enhancer.transferCorrection(from: before, to: after, onto: full)
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(Int(out.pixels[(20 * 40 + 20) * 4]), 60)
    }

    func testBlendAndResize() {
        let a = RGBAImage(width: 4, height: 4, pixels: [UInt8](repeating: 0, count: 64))
        let b = RGBAImage(width: 4, height: 4, pixels: [UInt8](repeating: 200, count: 64))
        XCTAssertEqual(a.blended(with: b, amount: 0.5).pixels[0], 100)
        XCTAssertEqual(a.blended(with: b, amount: 0).pixels[0], 0)
        XCTAssertEqual(a.blended(with: b, amount: 1).pixels[0], 200)
        let big = TestImages.pattern(width: 300, height: 200).resized(width: 150, height: 100)
        XCTAssertEqual(big.width, 150)
        XCTAssertEqual(big.height, 100)
    }

    func testHalfFloatConversion() {
        XCTAssertEqual(halfToFloat(0x3C00), 1)
        XCTAssertEqual(halfToFloat(0xC000), -2)
        XCTAssertEqual(halfToFloat(0x0000), 0)
        XCTAssertEqual(halfToFloat(0x5640), 100)
        XCTAssertEqual(halfToFloat(0x3800), 0.5)
        XCTAssertTrue(halfToFloat(0x7C00).isInfinite)
    }
}

final class LabColorTests: XCTestCase {
    func testKnownValues() {
        let white = LabColor.lab(r: 255, g: 255, b: 255)
        XCTAssertEqual(white.L, 100, accuracy: 0.05)
        XCTAssertEqual(white.a, 0, accuracy: 0.05)
        XCTAssertEqual(white.b, 0, accuracy: 0.05)
        let black = LabColor.lab(r: 0, g: 0, b: 0)
        XCTAssertEqual(black.L, 0, accuracy: 0.01)
        // sRGB red, OpenCV float Lab: about (53.24, 80.09, 67.20).
        let red = LabColor.lab(r: 255, g: 0, b: 0)
        XCTAssertEqual(red.L, 53.24, accuracy: 0.2)
        XCTAssertEqual(red.a, 80.09, accuracy: 0.5)
        XCTAssertEqual(red.b, 67.20, accuracy: 0.5)
    }

    func testRoundTrip() {
        var worst = 0
        for r in stride(from: 0, through: 255, by: 15) {
            for g in stride(from: 0, through: 255, by: 15) {
                for b in stride(from: 0, through: 255, by: 15) {
                    let lab = LabColor.lab(r: UInt8(r), g: UInt8(g), b: UInt8(b))
                    let back = LabColor.rgb(L: lab.L, a: lab.a, b: lab.b)
                    worst = max(worst, abs(Int(back.0) - r), abs(Int(back.1) - g), abs(Int(back.2) - b))
                }
            }
        }
        XCTAssertLessThanOrEqual(worst, 1)
    }

    func testMergeWithZeroColourGivesGrey() {
        let photo = TestImages.pattern(width: 64, height: 48)
        let zeros = [Float](repeating: 0, count: 16 * 16)
        let merged = LabColor.merge(lightnessOf: photo, a: zeros, b: zeros, planeWidth: 16, planeHeight: 16)
        for i in stride(from: 0, to: merged.pixels.count, by: 4) {
            XCTAssertLessThanOrEqual(abs(Int(merged.pixels[i]) - Int(merged.pixels[i + 1])), 2)
            XCTAssertLessThanOrEqual(abs(Int(merged.pixels[i + 1]) - Int(merged.pixels[i + 2])), 2)
        }
    }

    func testMergeKeepsLightnessAndAddsColour() {
        let photo = TestImages.gray(width: 40, height: 40)
        let a = [Float](repeating: 30, count: 4), b = [Float](repeating: 20, count: 4)
        let merged = LabColor.merge(lightnessOf: photo, a: a, b: b, planeWidth: 2, planeHeight: 2)
        let mid = (20 * 40 + 20) * 4
        let original = LabColor.lab(r: photo.pixels[mid], g: photo.pixels[mid + 1], b: photo.pixels[mid + 2])
        let result = LabColor.lab(r: merged.pixels[mid], g: merged.pixels[mid + 1], b: merged.pixels[mid + 2])
        XCTAssertEqual(result.L, original.L, accuracy: 1.5)
        XCTAssertEqual(result.a, 30, accuracy: 3)
        XCTAssertEqual(result.b, 20, accuracy: 3)
    }

    func testColourDetection() {
        XCTAssertFalse(LabColor.isAlreadyColour(TestImages.gray(width: 64, height: 64)))
        // Sepia toned print: chroma, but one hue only.
        var sepia = TestImages.gray(width: 64, height: 64)
        for i in 0..<(64 * 64) {
            let v = Int(sepia.pixels[i * 4])
            sepia.pixels[i * 4] = UInt8(min(255, v + 30))
            sepia.pixels[i * 4 + 1] = UInt8(min(255, v + 10))
            sepia.pixels[i * 4 + 2] = UInt8(max(0, v - 20))
        }
        XCTAssertFalse(LabColor.isAlreadyColour(sepia), "sepia counts as black and white")
        XCTAssertTrue(LabColor.isAlreadyColour(TestImages.pattern(width: 64, height: 64)))
    }
}
