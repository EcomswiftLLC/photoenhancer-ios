import XCTest
import ImageIO
@testable import Clarivo

final class ExportTests: XCTestCase {
    private let image = TestImages.cgPattern(width: 64, height: 48)

    func testWritersProduceReadableFiles() throws {
        for format in ImageFormat.allCases {
            guard format.isSupported else {
                XCTAssertNotEqual(format, .jpg, "JPG must always be supported")
                XCTAssertNotEqual(format, .png, "PNG must always be supported")
                continue
            }
            let data = try XCTUnwrap(ImageWriter.data(image, format: format, quality: 0.9, sourceMetadata: nil, keepMetadata: false), format.title)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format.utType.identifier)
            let decoded = try XCTUnwrap(ImageDecoder.decode(source, maxPixel: 1000))
            XCTAssertEqual(decoded.width, 64)
            XCTAssertEqual(decoded.height, 48)
        }
    }

    func testPNGIsLossless() throws {
        let data = try XCTUnwrap(ImageWriter.data(image, format: .png, quality: 1, sourceMetadata: nil, keepMetadata: false))
        let decoded = try XCTUnwrap(ImageDecoder.decode(data: data, maxPixel: 64))
        let a = try XCTUnwrap(RGBAImage(cgImage: image)), b = try XCTUnwrap(RGBAImage(cgImage: decoded))
        XCTAssertEqual(TestImages.maxDifference(a, b), 0)
    }

    func testQualityChangesJPEGSize() throws {
        let big = TestImages.cgPattern(width: 400, height: 300)
        let low = try XCTUnwrap(ImageWriter.data(big, format: .jpg, quality: 0.3, sourceMetadata: nil, keepMetadata: false))
        let high = try XCTUnwrap(ImageWriter.data(big, format: .jpg, quality: 1, sourceMetadata: nil, keepMetadata: false))
        XCTAssertLessThan(low.count, high.count)
    }

    func testStripRemovesLocationAndCameraDetails() throws {
        let original = TestImages.jpegWithLocation()
        let metadata = try XCTUnwrap(ImageDecoder.metadata(data: original))
        XCTAssertNotNil(metadata[kCGImagePropertyGPSDictionary as String], "the test photo has a location")
        let stripped = try XCTUnwrap(ImageWriter.data(image, format: .jpg, quality: 0.9, sourceMetadata: metadata, keepMetadata: false))
        let props = TestImages.properties(of: stripped)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String], "GPS must be gone")
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertNil(exif?[kCGImagePropertyExifLensModel as String])
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
    }

    func testKeepCarriesDetailsAndResetsOrientation() throws {
        let original = TestImages.jpegWithLocation()
        var metadata = try XCTUnwrap(ImageDecoder.metadata(data: original))
        metadata[kCGImagePropertyOrientation as String] = 6
        let kept = try XCTUnwrap(ImageWriter.data(image, format: .jpg, quality: 0.9, sourceMetadata: metadata, keepMetadata: true))
        let props = TestImages.properties(of: kept)
        let gps = try XCTUnwrap(props[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitude as String] as? Double ?? 0, 48.8584, accuracy: 0.001)
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "TestMaker")
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:11:25 09:41:00")
        XCTAssertEqual(props[kCGImagePropertyOrientation as String] as? Int ?? 1, 1, "pixels are upright, so orientation is 1")
    }

    func testPNGAndHEICAlsoStripGPS() throws {
        let metadata = try XCTUnwrap(ImageDecoder.metadata(data: TestImages.jpegWithLocation()))
        for format in [ImageFormat.png, .heic] where format.isSupported {
            let data = try XCTUnwrap(ImageWriter.data(image, format: format, quality: 0.9, sourceMetadata: metadata, keepMetadata: false))
            XCTAssertNil(TestImages.properties(of: data)[kCGImagePropertyGPSDictionary as String], format.title)
        }
    }

    func testFileNamesAreSafeAndUnique() {
        let a = ExportRenderer.fileName(for: "Street scene, 1864 / test", format: .jpg)
        let b = ExportRenderer.fileName(for: "Street scene, 1864 / test", format: .jpg)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("Clarivo-Street-scene-1864-test-"))
        XCTAssertTrue(a.hasSuffix(".jpg"))
        XCTAssertFalse(a.contains("/"))
        XCTAssertTrue(ExportRenderer.fileName(for: "", format: .heic).contains("Photo"))
        XCTAssertTrue(ExportRenderer.fileName(for: "日本", format: .png).hasSuffix(".png"))
    }

    func testExportOperationsReplaceTheUpscaleStep() {
        let source = PixelSize(width: 1000, height: 800)
        let recipe: [EnhanceOperation] = [.upscale(factor: 4), .autoFix(strength: 1)]
        XCTAssertEqual(ExportRenderer.operations(recipe: recipe, size: .factor(1), source: source), [.autoFix(strength: 1)])
        XCTAssertEqual(ExportRenderer.operations(recipe: recipe, size: .factor(2), source: source), [.autoFix(strength: 1), .upscale(factor: 2)])
        XCTAssertEqual(ExportRenderer.operations(recipe: recipe, size: .custom(3000), source: source), [.autoFix(strength: 1), .upscale(factor: 4)])
        XCTAssertEqual(ExportRenderer.operations(recipe: recipe, size: .custom(600), source: source), [.autoFix(strength: 1)])
        let expected = ExportRenderer.expectedSize(source: PixelSize(width: 4032, height: 3024), size: .factor(4))
        XCTAssertTrue(expected.capped)
        XCTAssertTrue(SizeCap.fits(expected.size))
        XCTAssertEqual(ExportSize.factor(1).title, "Original")
        XCTAssertTrue(ExportSize.factor(8).needsUpscaleModel)
        XCTAssertFalse(ExportSize.custom(9000).needsUpscaleModel)
    }

    func testFullExportWritesAFileWithoutModels() async throws {
        let data = TestImages.jpegWithLocation(width: 300, height: 200)
        let asset = try XCTUnwrap(PhotoAsset.from(data: data, title: "Test"))
        var options = ExportOptions()
        options.size = .custom(150)
        options.keepMetadata = false
        let result = try await ExportRenderer.render(asset, recipe: [.autoFix(strength: 0.5)], options: options,
                                                     enhancer: Enhancer(models: NoModels()), cancel: CancelToken(), progress: { _ in })
        XCTAssertEqual(result.item.pixelSize, PixelSize(width: 150, height: 100))
        let written = try Data(contentsOf: result.item.url)
        XCTAssertNil(TestImages.properties(of: written)[kCGImagePropertyGPSDictionary as String])
        XCTAssertGreaterThan(result.item.byteCount, 0)
        result.item.deleteFile()
    }

    func testHistoryKeepsAWeek() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTest-\(UUID().uuidString)")
        let store = HistoryStore(folder: folder)
        let file = folder.appendingPathComponent("source.jpg")
        try TestImages.jpegData(image).write(to: file)
        let item = try XCTUnwrap(store.add(fileAt: file, title: "One", summary: "Auto fix", image: image))
        XCTAssertEqual(store.items().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.thumbnailURL(of: item).path))
        store.pruneOld(now: Date().addingTimeInterval(6 * 86_400))
        XCTAssertEqual(store.items().count, 1)
        store.pruneOld(now: Date().addingTimeInterval(8 * 86_400))
        XCTAssertEqual(store.items().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(of: item).path))
        try? FileManager.default.removeItem(at: folder)
    }

    func testSampleLibraryReadsTheCatalog() {
        XCTAssertEqual(SampleLibrary.titleFromName("old-portrait_02"), "Old portrait")
        XCTAssertEqual(SampleLibrary.titleFromName("sample_01"), "Sample")
        let names = SampleLibrary.availableNames()
        if !names.isEmpty {
            // Bundled samples decode and use their catalog titles.
            XCTAssertNotNil(SampleLibrary.image(named: names[0], maxPixel: 200))
            XCTAssertFalse(names.contains { $0.lowercased().hasPrefix("appicon") })
            let catalog = SampleLibrary.catalog()
            if let first = catalog.first, names.contains(first.name) {
                XCTAssertEqual(names.first, first.name, "samples.json order comes first")
                XCTAssertEqual(SampleLibrary.title(for: first.name), first.title)
            }
        }
    }

    func testLicencesAreBundled() {
        let entries = LicensesView.load()
        let names = entries.map(\.name).joined(separator: " ")
        for required in ["Real-ESRGAN", "NAFNet", "DDColor", "Google Mobile Ads", "User Messaging Platform"] {
            XCTAssertTrue(names.contains(required), "Licence for \(required) is missing")
        }
        XCTAssertTrue(entries.allSatisfy { !$0.text.isEmpty && !$0.license.isEmpty })
    }
}
