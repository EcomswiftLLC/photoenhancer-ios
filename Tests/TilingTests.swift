import XCTest
@testable import Clarivo

final class TilingTests: XCTestCase {
    func testAxisCoversTheImageWithEvenOverlap() {
        for length in [1, 17, 255, 256, 257, 300, 496, 497, 1000, 1023, 4032] {
            let axis = TileAxis(length: length, tile: 256, overlap: 16)
            XCTAssertEqual(axis.starts.first, 0, "length \(length)")
            if length <= 256 {
                XCTAssertEqual(axis.count, 1)
                continue
            }
            XCTAssertEqual(axis.starts.last, length - 256, "last tile ends at the edge for \(length)")
            for i in 1..<axis.count {
                let overlap = axis.starts[i - 1] + 256 - axis.starts[i]
                XCTAssertGreaterThanOrEqual(overlap, 16, "length \(length) tile \(i)")
                XCTAssertLessThan(axis.starts[i], axis.starts[i - 1] + 256)
            }
        }
    }

    func testWeightsSumToExactlyOneEverywhere() {
        for length in [257, 300, 497, 777, 1500] {
            for scale in [1, 2, 4] {
                let axis = TileAxis(length: length, tile: 256, overlap: 16)
                for x in 0..<(length * scale) {
                    var sum = 0
                    var owners = 0
                    for t in 0..<axis.count {
                        let w = axis.weight(tile: t, at: x, scale: scale)
                        XCTAssertTrue((0...256).contains(w))
                        if w > 0 {
                            owners += 1
                            // A tile only weighs pixels it really covers.
                            XCTAssertTrue(x >= axis.starts[t] * scale && x < (axis.starts[t] + 256) * scale, "x \(x) outside tile \(t)")
                        }
                        sum += w
                    }
                    XCTAssertEqual(sum, 256, "length \(length) scale \(scale) x \(x)")
                    XCTAssertLessThanOrEqual(owners, 2)
                }
            }
        }
    }

    /// The seam test: a tile function that changes nothing reproduces the input exactly.
    func testIdentityTileFunctionReproducesTheInput() throws {
        for (w, h) in [(700, 530), (256, 256), (300, 90), (37, 41), (1000, 257)] {
            let input = TestImages.pattern(width: w, height: h)
            var calls = 0
            let output = try TiledProcessor.process(input, tile: 256, overlap: 16, scale: 1) { tile in
                calls += 1
                XCTAssertEqual(tile.width, 256)
                XCTAssertEqual(tile.height, 256)
                return tile
            }
            XCTAssertEqual(output.width, w)
            XCTAssertEqual(output.height, h)
            XCTAssertEqual(TestImages.maxDifference(output, input), 0, "\(w)x\(h) identity must be exact")
            XCTAssertEqual(calls, TileAxis(length: w, tile: 256, overlap: 16).count * TileAxis(length: h, tile: 256, overlap: 16).count)
        }
    }

    /// With a 2x nearest-neighbour "model", the tiled result equals the whole image enlarged the same way.
    func testScaledTilesLineUpWithoutSeams() throws {
        let input = TestImages.pattern(width: 530, height: 300, seed: 3)
        let output = try TiledProcessor.process(input, tile: 128, overlap: 16, scale: 2) { $0.nearestUpscaled(2) }
        XCTAssertEqual(output.width, 1060)
        XCTAssertEqual(output.height, 600)
        XCTAssertEqual(TestImages.maxDifference(output, input.nearestUpscaled(2)), 0)
    }

    func testFourTimesScaleKeepsPixelCorrespondence() throws {
        let input = TestImages.pattern(width: 300, height: 270, seed: 5)
        let output = try TiledProcessor.process(input, tile: 64, overlap: 8, scale: 4) { $0.nearestUpscaled(4) }
        XCTAssertEqual(TestImages.maxDifference(output, input.nearestUpscaled(4)), 0)
    }

    func testWrongTileSizeIsAnErrorNotACrash() {
        let input = TestImages.pattern(width: 300, height: 300)
        XCTAssertThrowsError(try TiledProcessor.process(input, tile: 256, overlap: 16, scale: 4) { $0 })
    }

    func testCancelStopsBetweenTiles() {
        let input = TestImages.pattern(width: 900, height: 900)
        let token = CancelToken()
        var calls = 0
        XCTAssertThrowsError(try TiledProcessor.process(input, tile: 256, overlap: 16, scale: 1, cancel: token) { tile in
            calls += 1
            if calls == 2 { token.cancel() }
            return tile
        }) { error in
            XCTAssertEqual(error as? EnhanceError, .cancelled)
        }
        XCTAssertEqual(calls, 2)
    }

    func testMemoryWarningStopsWithItsOwnError() {
        let input = TestImages.pattern(width: 600, height: 600)
        let token = CancelToken()
        token.cancelForMemory()
        XCTAssertThrowsError(try TiledProcessor.process(input, tile: 256, overlap: 16, scale: 1, cancel: token) { $0 }) { error in
            XCTAssertEqual(error as? EnhanceError, .memoryPressure)
        }
    }

    func testProgressReachesOne() throws {
        let input = TestImages.pattern(width: 600, height: 400)
        var values: [Double] = []
        _ = try TiledProcessor.process(input, tile: 256, overlap: 16, scale: 1, progress: { values.append($0) }) { $0 }
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(values, values.sorted())
    }

    func testCropRepeatsEdgesOutsideTheImage() {
        let input = TestImages.pattern(width: 10, height: 8)
        let crop = input.crop(x: -3, y: 5, width: 16, height: 6)
        XCTAssertEqual(crop.width, 16)
        // Top-left of the crop is outside: it repeats pixel (0, 5).
        XCTAssertEqual(Array(crop.pixels[0..<3]), Array(input.pixels[(5 * 10) * 4..<(5 * 10) * 4 + 3]))
        // Rows below the image repeat the last row.
        let lastRowStart = (5 * 16 + 3) * 4
        XCTAssertEqual(Array(crop.pixels[lastRowStart..<lastRowStart + 3]), Array(input.pixels[(7 * 10) * 4..<(7 * 10) * 4 + 3]))
    }
}
