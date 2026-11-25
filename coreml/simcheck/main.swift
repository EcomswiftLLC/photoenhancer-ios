// Core ML prediction check that runs natively on macOS AND inside the iOS Simulator
// (built for the simulator SDK and launched with `xcrun simctl spawn`).
// usage: simcheck <compiled .mlmodelc> <png 512x512> <cpuOnly|cpuAndGPU|all>
import CoreML
import Foundation
import ImageIO

let a = CommandLine.arguments
let cfg = MLModelConfiguration()
cfg.computeUnits = a[3] == "cpuOnly" ? .cpuOnly : (a[3] == "cpuAndGPU" ? .cpuAndGPU : .all)
do {
    let model = try MLModel(contentsOf: URL(fileURLWithPath: a[1]), configuration: cfg)
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let c = model.modelDescription.inputDescriptionsByName["image"]!.imageConstraint!
    let fv = try MLFeatureValue(cgImage: cg, constraint: c, options: nil)
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": fv]))
    let arr = out.featureValue(for: "ab")!.multiArrayValue!
    let sh = MLShapedArray<Float>(converting: arr)
    let s = sh.scalars
    let n = s.count / 2
    var ma = 0.0, mb = 0.0
    var lo: Float = .infinity, hi: Float = -.infinity
    for i in 0..<n { ma += Double(abs(s[i])); mb += Double(abs(s[n + i])); lo = min(lo, s[i], s[n + i]); hi = max(hi, s[i], s[n + i]) }
    print("{\"model\":\"\(URL(fileURLWithPath: a[1]).lastPathComponent)\",\"units\":\"\(a[3])\",\"mean_abs_a\":\(ma / Double(n)),\"mean_abs_b\":\(mb / Double(n)),\"min\":\(lo),\"max\":\(hi),\"dtype\":\(arr.dataType.rawValue)}")
} catch {
    print("{\"model\":\"\(a[1])\",\"units\":\"\(a[3])\",\"error\":\"\(error)\"}")
}
