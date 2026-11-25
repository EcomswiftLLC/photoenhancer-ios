import Foundation
import Darwin
import os

/// The hard output limits: long side at most 8,192 px and at most 48 MP. When an upscale would go past them, the input
/// is reduced first so the output fits, and the screen says so.
enum SizeCap {
    static let maxLongSide = 8192
    static let maxMegapixels = 48.0

    struct Plan: Equatable {
        /// The size the input is reduced to before processing (equal to the source when nothing is reduced).
        var input: PixelSize
        var output: PixelSize
        var inputReduced: Bool
        /// True when the output is smaller than source × scale because of the cap.
        var capApplied: Bool
    }

    static func fits(_ size: PixelSize) -> Bool {
        size.longSide <= maxLongSide && Double(size.width) * Double(size.height) <= maxMegapixels * 1_000_000
    }

    /// Plans an enlargement of `source` by `scale`.
    static func plan(source: PixelSize, scale: Int) -> Plan {
        let s = max(1, scale)
        let full = PixelSize(width: source.width * s, height: source.height * s)
        if fits(full) {
            return Plan(input: source, output: full, inputReduced: false, capApplied: false)
        }
        let byLong = Double(maxLongSide) / Double(full.longSide)
        let byArea = (maxMegapixels * 1_000_000 / (Double(full.width) * Double(full.height))).squareRoot()
        var factor = min(byLong, byArea)
        var input = PixelSize(width: max(1, Int(Double(source.width) * factor)), height: max(1, Int(Double(source.height) * factor)))
        // Rounding can still land one pixel over: step down until it fits.
        while !fits(PixelSize(width: input.width * s, height: input.height * s)) && factor > 0 {
            factor *= 0.995
            input = PixelSize(width: max(1, Int(Double(source.width) * factor)), height: max(1, Int(Double(source.height) * factor)))
        }
        return Plan(input: input, output: PixelSize(width: input.width * s, height: input.height * s), inputReduced: true, capApplied: true)
    }

    /// The exact size for a requested long side (export "custom size"), clamped to the cap.
    static func size(for source: PixelSize, longSide requested: Int) -> PixelSize {
        let target = min(max(64, requested), maxLongSide)
        var size = source.scaled(by: Double(target) / Double(source.longSide))
        while !fits(size) { size = size.scaled(by: 0.98) }
        return size
    }

    /// Smallest model factor (1, 2, 4 or 8) that reaches `target` from `source`.
    static func factor(toReach target: PixelSize, from source: PixelSize) -> Int {
        for f in [1, 2, 4, 8] where source.longSide * f >= target.longSide { return f }
        return 8
    }
}

/// Memory checks so large photos fail with a message instead of the app being closed by iOS.
enum MemoryGuard {
    /// Bytes this app may still allocate (iOS reports it; 0 on the simulator's host process means "unknown").
    static var availableBytes: Int {
        let value = os_proc_available_memory()
        return value > 0 ? Int(value) : Int.max
    }

    /// Rough peak for an upscale: input + output RGBA, the accumulator band and model working memory.
    static func estimatedPeakBytes(input: PixelSize, output: PixelSize, tileOut: Int) -> Int {
        let rgbaIn = input.width * input.height * 4
        let rgbaOut = output.width * output.height * 4
        let band = output.width * min(output.height, tileOut + 64) * 12
        return rgbaIn + rgbaOut * 2 + band + 200_000_000
    }

    static func canAfford(_ bytes: Int) -> Bool {
        bytes < Int(Double(availableBytes) * 0.85)
    }

    /// Physical footprint of this process (what iOS uses to decide when to close an app), in bytes.
    static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
