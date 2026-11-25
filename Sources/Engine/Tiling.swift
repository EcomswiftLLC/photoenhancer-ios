import Foundation

/// Where the tiles go along one axis, and how much each tile owns of every output pixel.
///
/// Tiles are spread evenly so every pair of neighbours overlaps by at least `overlap` pixels. Inside each overlap a
/// narrow feather band (centred, `feather` input pixels wide) mixes the two tiles with linear weights that add up to
/// exactly 256, and every other pixel belongs to one tile only. Because the weights always sum to the same integer,
/// a tile function that changes nothing reproduces the input exactly: no seams, no rounding drift.
struct TileAxis: Equatable {
    let length: Int
    let tile: Int
    let overlap: Int
    let starts: [Int]
    /// Feather band per neighbour pair, in input coordinates: [start, end).
    let bands: [ClosedOpenRange]

    struct ClosedOpenRange: Equatable { let lower: Int; let upper: Int }

    init(length: Int, tile: Int, overlap: Int, feather: Int? = nil) {
        precondition(length > 0 && tile > 0 && overlap >= 0 && overlap < tile)
        self.length = length
        self.tile = tile
        self.overlap = overlap
        if length <= tile {
            starts = [0]
            bands = []
            return
        }
        let stride = tile - overlap
        let count = Int((Double(length - overlap) / Double(stride)).rounded(.up))
        let n = max(2, count)
        let span = length - tile
        var s: [Int] = []
        for i in 0..<n {
            s.append(Int((Double(i) * Double(span) / Double(n - 1)).rounded()))
        }
        starts = s
        let width = max(2, min(feather ?? overlap, overlap))
        var b: [ClosedOpenRange] = []
        for i in 0..<(n - 1) {
            let sharedStart = s[i + 1], sharedEnd = s[i] + tile
            let shared = sharedEnd - sharedStart
            let w = min(width, shared)
            let centre = (sharedStart + sharedEnd) / 2
            let lower = max(sharedStart, centre - w / 2)
            b.append(ClosedOpenRange(lower: lower, upper: min(sharedEnd, lower + w)))
        }
        bands = b
    }

    var count: Int { starts.count }

    /// Weight (0...256) of tile `index` at output coordinate `x` when the output is `scale` times the input.
    func weight(tile index: Int, at x: Int, scale: Int) -> Int {
        if index > 0 {
            let band = bands[index - 1]
            let lo = band.lower * scale, hi = band.upper * scale
            if x < lo { return 0 }
            if x < hi { return Self.ramp(x - lo, hi - lo) }
        }
        if index < count - 1 {
            let band = bands[index]
            let lo = band.lower * scale, hi = band.upper * scale
            if x >= hi { return 0 }
            if x >= lo { return 256 - Self.ramp(x - lo, hi - lo) }
        }
        return 256
    }

    /// Output range [from, to) where tile `index` has a non-zero weight.
    func ownedRange(tile index: Int, scale: Int) -> Range<Int> {
        let from = index > 0 ? bands[index - 1].lower * scale : 0
        let to = index < count - 1 ? bands[index].upper * scale : length * scale
        return from..<to
    }

    /// Linear ramp from 0 to 256 across `span` pixels, sampled at pixel centres.
    static func ramp(_ offset: Int, _ span: Int) -> Int {
        guard span > 0 else { return 256 }
        let t = (Double(offset) + 0.5) / Double(span)
        return min(256, max(0, Int((t * 256).rounded())))
    }
}

/// Runs a tile function over a whole image with feathered, seam-free blending.
///
/// Memory: besides the input and the output, it holds one row of tiles worth of 32-bit accumulators (only the rows that
/// the current tile row touches) and the current tile. Tiles run one after another.
enum TiledProcessor {
    typealias TileFunction = (RGBAImage) throws -> RGBAImage

    /// - Parameters:
    ///   - tile: tile side in input pixels (the model's input size).
    ///   - scale: output size over input size. The tile function must return `tile * scale` square tiles.
    ///   - progress: 0...1 after each tile.
    static func process(
        _ input: RGBAImage,
        tile: Int,
        overlap: Int,
        scale: Int,
        cancel: CancelToken? = nil,
        progress: ((Double) -> Void)? = nil,
        function: TileFunction
    ) throws -> RGBAImage {
        let xs = TileAxis(length: input.width, tile: tile, overlap: overlap)
        let ys = TileAxis(length: input.height, tile: tile, overlap: overlap)
        let outW = input.width * scale, outH = input.height * scale
        var output = [UInt8](repeating: 255, count: outW * outH * 4)
        let total = Double(xs.count * ys.count)
        var done = 0.0

        // Accumulator rows for the current tile row: [rowStart, rowStart + rows).
        var accStart = 0
        var acc = [UInt32]()
        var accRows = 0

        for (ty, y0) in ys.starts.enumerated() {
            let rowRange = ys.ownedRange(tile: ty, scale: scale)
            // Rows below `rowRange.lowerBound` are final: flush them.
            if accRows > 0 {
                let finalUpTo = rowRange.lowerBound
                flush(&acc, accStart: accStart, rows: accRows, upTo: finalUpTo, width: outW, into: &output)
                // Keep only rows still being written.
                let keepFrom = max(finalUpTo, accStart)
                let dropped = keepFrom - accStart
                if dropped > 0 {
                    acc.removeFirst(min(acc.count, dropped * outW * 3))
                    accRows -= dropped
                    accStart = keepFrom
                }
            } else {
                accStart = rowRange.lowerBound
            }
            // Grow to cover this tile row.
            let neededRows = rowRange.upperBound - accStart
            if neededRows > accRows {
                acc.append(contentsOf: [UInt32](repeating: 0, count: (neededRows - accRows) * outW * 3))
                accRows = neededRows
            }

            for (tx, x0) in xs.starts.enumerated() {
                try cancel?.check()
                try autoreleasepool {
                    let tileIn = input.crop(x: x0, y: y0, width: tile, height: tile)
                    let tileOut = try function(tileIn)
                    guard tileOut.width == tile * scale, tileOut.height == tile * scale else {
                        throw EnhanceError.modelFailed("Tile is \(tileOut.width)x\(tileOut.height), expected \(tile * scale)")
                    }
                    let colRange = xs.ownedRange(tile: tx, scale: scale)
                    let ox = x0 * scale, oy = y0 * scale
                    let tileW = tile * scale
                    // Weights along x for this tile, computed once.
                    let cols = Array(colRange.clamped(to: 0..<outW))
                    let wx = cols.map { xs.weight(tile: tx, at: $0, scale: scale) }
                    tileOut.pixels.withUnsafeBufferPointer { t in
                        acc.withUnsafeMutableBufferPointer { a in
                            for y in rowRange where y < outH {
                                let wy = ys.weight(tile: ty, at: y, scale: scale)
                                if wy == 0 { continue }
                                let ty2 = y - oy
                                guard ty2 >= 0 && ty2 < tileW else { continue }
                                let aRow = (y - accStart) * outW * 3
                                let tRow = ty2 * tileW * 4
                                for (i, x) in cols.enumerated() {
                                    let w = UInt32(wx[i] * wy)
                                    if w == 0 { continue }
                                    let tx2 = x - ox
                                    guard tx2 >= 0 && tx2 < tileW else { continue }
                                    let tp = tRow + tx2 * 4
                                    let ap = aRow + x * 3
                                    a[ap] &+= UInt32(t[tp]) &* w
                                    a[ap + 1] &+= UInt32(t[tp + 1]) &* w
                                    a[ap + 2] &+= UInt32(t[tp + 2]) &* w
                                }
                            }
                        }
                    }
                }
                done += 1
                progress?(done / total)
            }
        }
        flush(&acc, accStart: accStart, rows: accRows, upTo: accStart + accRows, width: outW, into: &output)
        return RGBAImage(width: outW, height: outH, pixels: output)
    }

    /// Writes accumulated rows [accStart, upTo) to the output (weights sum to 65536, so the shift is exact).
    private static func flush(_ acc: inout [UInt32], accStart: Int, rows: Int, upTo: Int, width: Int, into output: inout [UInt8]) {
        let end = min(upTo, accStart + rows)
        guard end > accStart else { return }
        acc.withUnsafeBufferPointer { a in
            output.withUnsafeMutableBufferPointer { o in
                for y in accStart..<end {
                    let aRow = (y - accStart) * width * 3
                    let oRow = y * width * 4
                    guard oRow + width * 4 <= o.count else { continue }
                    for x in 0..<width {
                        let ap = aRow + x * 3, op = oRow + x * 4
                        o[op] = UInt8(min(255, (a[ap] + 32_768) >> 16))
                        o[op + 1] = UInt8(min(255, (a[ap + 1] + 32_768) >> 16))
                        o[op + 2] = UInt8(min(255, (a[ap + 2] + 32_768) >> 16))
                        o[op + 3] = 255
                    }
                }
            }
        }
    }
}
