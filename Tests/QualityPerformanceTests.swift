import XCTest
import CoreGraphics
import ImageIO
import CoreML
@testable import Clarivo

/// Runs every model (and the classical tools) on the bundled samples, records time and peak memory per image, and writes
/// before/after PNGs plus results.json to build/quality in the repository (the `quality` CI job uploads it).
///
/// Only runs when CV_QUALITY=1 (xcodebuild passes TEST_RUNNER_CV_QUALITY). The simulator has no Neural Engine and no
/// Core ML GPU path, so every time here is a CPU time on the CI Mac, not an iPhone time.
final class QualityPerformanceTests: XCTestCase {
    struct Case {
        var name: String
        var sample: String
        var operations: [EnhanceOperation]
        var maxInput: Int
    }

    static let cases: [Case] = [
        Case(name: "upscale-4x", sample: "historic-building-lowres", operations: [.upscale(factor: 4)], maxInput: 2000),
        Case(name: "upscale-2x", sample: "portrait-woman-lowres", operations: [.upscale(factor: 2)], maxInput: 2000),
        Case(name: "upscale-8x", sample: "historic-building-lowres", operations: [.upscale(factor: 8)], maxInput: 2000),
        Case(name: "denoise-ai", sample: "tabby-cat-noisy", operations: [.denoise(strength: 1)], maxInput: 1600),
        Case(name: "denoise-light", sample: "tabby-cat-noisy", operations: [.denoiseLight(strength: 0.8)], maxInput: 1600),
        Case(name: "unblur", sample: "street-sign-motion-blur", operations: [.unblur], maxInput: 1600),
        Case(name: "colorize-street", sample: "old-street-1864", operations: [.colorize], maxInput: 2000),
        Case(name: "colorize-portrait", sample: "old-portrait-1859", operations: [.colorize], maxInput: 2000),
        Case(name: "restore", sample: "old-portrait-1859", operations: [.restoreOld(strength: 0.7)], maxInput: 2000),
        Case(name: "portrait", sample: "portrait-woman-lowres", operations: [.portrait], maxInput: 2000),
        Case(name: "autofix-sharpen", sample: "lake-autumn", operations: [.autoFix(strength: 0.8), .sharpen(strength: 0.4)], maxInput: 2400),
    ]

    private var outputFolder: URL { Repo.root.appendingPathComponent("build/quality", isDirectory: true) }

    func testRunEveryModelOnTheSamples() async throws {
        guard ProcessInfo.processInfo.environment["CV_QUALITY"] == "1" else {
            throw XCTSkip("Set CV_QUALITY=1 (TEST_RUNNER_CV_QUALITY=1) to run the quality and performance job.")
        }
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let provider = BundleModelProvider.shared
        var results: [[String: Any]] = []
        for kind in ModelKind.allCases {
            results.append(["model": kind.resourceName, "bundled": provider.isAvailable(kind)])
        }
        let enhancer = Enhancer.shared
        var rows: [[String: Any]] = []
        for item in Self.cases {
            var row: [String: Any] = ["case": item.name, "sample": item.sample, "operations": item.operations.map { "\($0)" }]
            guard let asset = PhotoAsset.sample(named: item.sample), let input = asset.decode(maxPixel: item.maxInput) else {
                row["status"] = "sample missing"
                rows.append(row)
                continue
            }
            row["input"] = "\(input.width)x\(input.height)"
            guard item.operations.allSatisfy({ enhancer.isAvailable($0) }) else {
                row["status"] = "model not bundled"
                rows.append(row)
                continue
            }
            // Warm-up: load the model outside the timed run (first load compiles for the device).
            for kind in Set(item.operations.compactMap(\.requiredModel)) { _ = try? await provider.model(kind) }
            let sampler = FootprintSampler()
            let baseline = MemoryGuard.physicalFootprint()
            sampler.start()
            let started = Date()
            do {
                let output = try await enhancer.run(item.operations, on: input, applyCap: true)
                let seconds = Date().timeIntervalSince(started)
                let peak = sampler.stop()
                row["status"] = "ok"
                row["seconds"] = (seconds * 100).rounded() / 100
                row["output"] = "\(output.image.width)x\(output.image.height)"
                row["peakFootprintMB"] = Int(peak / 1_048_576)
                row["baselineFootprintMB"] = Int(baseline / 1_048_576)
                row["capApplied"] = output.notes.capApplied
                if let faces = output.notes.facesFound { row["faces"] = faces }
                if item.operations.contains(.colorize) { row["colorizeOutput"] = Enhancer.lastColorizeDiagnostics }
                if !output.notes.messages.isEmpty { row["notes"] = output.notes.messages }
                try writePNG(input, name: "\(item.name)-before.png")
                try writePNG(output.image, name: "\(item.name)-after.png")
                try writeComparison(before: input, after: output.image, name: "\(item.name)-compare.png")
            } catch EnhanceError.noColourFound {
                // Recorded, not a test failure: the model ran, it just returned no colour (see colorizeOutput).
                _ = sampler.stop()
                row["status"] = "no colour from the model"
                row["seconds"] = (Date().timeIntervalSince(started) * 100).rounded() / 100
                row["colorizeOutput"] = Enhancer.lastColorizeDiagnostics
            } catch {
                _ = sampler.stop()
                row["status"] = "failed: \(error)"
                XCTFail("\(item.name) failed: \(error)")
            }
            rows.append(row)
            BundleModelProvider.shared.unloadAll()
        }
        rows.append(contentsOf: await colorizeComputeUnitDiagnostics())
        let report: [String: Any] = [
            "note": "iOS Simulator on a GitHub macos-26 runner: no Neural Engine, Core ML runs on the CPU. Times are CPU times, not iPhone times. Peak = highest phys_footprint sampled every 20 ms during the run.",
            "models": results,
            "runs": rows,
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: outputFolder.appendingPathComponent("results.json"))
        print(String(data: json, encoding: .utf8) ?? "")
    }

    /// DDColor on each compute-unit setting, to see whether a colour collapse depends on the compute path.
    private func colorizeComputeUnitDiagnostics() async -> [[String: Any]] {
        guard let asset = PhotoAsset.sample(named: "old-street-1864"), let image = asset.decode(maxPixel: 1200),
              let rgba = RGBAImage(cgImage: image) else { return [] }
        var rows: [[String: Any]] = []
        for (name, units) in [("cpuOnly", MLComputeUnits.cpuOnly), ("cpuAndGPU", .cpuAndGPU), ("all", .all)] {
            let provider = BundleModelProvider(bundle: .main)
            provider.computeUnits = units
            guard provider.isAvailable(.colorize) else { continue }
            let enhancer = Enhancer(models: provider)
            var row: [String: Any] = ["case": "colorize-diagnostic-\(name)"]
            do {
                let out = try await enhancer.colorize(rgba, cancel: CancelToken())
                row["status"] = "ok"
                row["meanChannelSpread"] = Self.channelSpread(out)
            } catch {
                row["status"] = "\(error)"
            }
            row["colorizeOutput"] = Enhancer.lastColorizeDiagnostics
            rows.append(row)
        }
        return rows
    }

    static func channelSpread(_ image: RGBAImage) -> Double {
        var sum = 0
        for i in stride(from: 0, to: image.pixels.count, by: 4) { sum += abs(Int(image.pixels[i]) - Int(image.pixels[i + 2])) }
        return Double(sum) / Double(max(1, image.pixelCount))
    }

    private func writePNG(_ image: CGImage, name: String) throws {
        guard let data = ImageWriter.data(image, format: .png, quality: 1, sourceMetadata: nil, keepMetadata: false) else {
            throw EnhanceError.writeFailed
        }
        try data.write(to: outputFolder.appendingPathComponent(name))
    }

    /// The same centre crop of before (enlarged, smooth) and after, side by side at the output's pixel scale.
    private func writeComparison(before: CGImage, after: CGImage, name: String) throws {
        let side = min(512, min(after.width, after.height))
        let scaleX = Double(after.width) / Double(before.width)
        let cropAfter = CGRect(x: (after.width - side) / 2, y: (after.height - side) / 2, width: side, height: side)
        let cropBefore = CGRect(x: cropAfter.minX / scaleX, y: cropAfter.minY / scaleX, width: Double(side) / scaleX, height: Double(side) / scaleX)
        guard let a = after.cropping(to: cropAfter), let b = before.cropping(to: cropBefore.integral),
              let context = CGContext(data: nil, width: side * 2 + 8, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: RGBAImage.colorSpace, bitmapInfo: RGBAImage.bitmapInfo) else { return }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side * 2 + 8, height: side))
        context.interpolationQuality = .medium
        context.draw(b, in: CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(a, in: CGRect(x: side + 8, y: 0, width: side, height: side))
        if let image = context.makeImage() { try writePNG(image, name: name) }
    }
}

/// Samples this process's physical footprint on a background thread and keeps the highest value.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var running = false

    func start() {
        lock.lock(); running = true; peak = MemoryGuard.physicalFootprint(); lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let go = running
                let value = MemoryGuard.physicalFootprint()
                if value > peak { peak = value }
                lock.unlock()
                if !go { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> UInt64 {
        lock.lock()
        running = false
        let value = max(peak, MemoryGuard.physicalFootprint())
        lock.unlock()
        return value
    }
}
