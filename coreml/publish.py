"""Zip the shipping mlpackages and write models-manifest.json (the APP agent's contract).

Usage: python coreml/publish.py --out build --nafnet fp16|int8 --ddcolor fp16|int8
Writes build/release/{ESRGANGeneral,NAFNetDeblur,DDColorTiny}.mlpackage.zip + models-manifest.json
"""
import argparse
import hashlib
import json
import os
import shutil
import zipfile

from common import MODELS
from fetch_weights import WEIGHTS

COMMON_IMAGE_IN = {
    "name": "image", "type": "image", "pixel_format": "kCVPixelFormatType_32BGRA (any RGB CVPixelBuffer; Core ML converts)",
    "color_space": "sRGB", "value_range": "0...255 per channel (model scales by 1/255 internally)",
}

CONTRACT = {
    "ESRGANGeneral": {
        "task": "4x super-resolution (upscale, also used for denoise/supersample and portrait crops)",
        "input": dict(COMMON_IMAGE_IN, shape=[1, 3, 256, 256], width=256, height=256),
        "output": {"name": "result", "type": "image", "shape": [1, 3, 1024, 1024], "width": 1024, "height": 1024,
                   "color_space": "sRGB", "value_range": "0...255, clamped inside the graph"},
        "tile": 256, "overlap": 16, "scale": 4,
        "preprocessing": "none beyond tiling (feed sRGB tiles; pad images smaller than 256 by edge replication)",
        "postprocessing": "feathered tile blend (see tiling); 2x = run 4x then high-quality downscale by 0.5",
    },
    "NAFNetDeblur": {
        "task": "motion/camera-shake deblur (two passes: global context, then tiles)",
        "inputs": [
            dict(COMMON_IMAGE_IN, shape=[1, 3, 256, 256], width=256, height=256),
            {"name": "context", "type": "MLMultiArray", "dtype": "Float16", "shape": [1, 8384],
             "meaning": "global channel-attention statistics = the `stats` output of pass 1; zeros in pass 1"},
            {"name": "mix", "type": "MLMultiArray", "dtype": "Float16", "shape": [1, 1],
             "meaning": "0 in pass 1 (use the input's own statistics), 1 in pass 2 (use `context`)"},
        ],
        "input": dict(COMMON_IMAGE_IN, shape=[1, 3, 256, 256], width=256, height=256),
        "outputs": [
            {"name": "result", "type": "image", "shape": [1, 3, 256, 256], "width": 256, "height": 256,
             "color_space": "sRGB", "value_range": "0...255, clamped inside the graph"},
            {"name": "stats", "type": "MLMultiArray", "dtype": "Float16", "shape": [1, 8384],
             "meaning": "global statistics; read it after pass 1 and pass it as `context` to every tile in pass 2 (ignore it in pass 2)"},
        ],
        "output": {"name": "result", "type": "image", "shape": [1, 3, 256, 256], "width": 256, "height": 256,
                   "color_space": "sRGB", "value_range": "0...255, clamped inside the graph"},
        "tile": 256, "overlap": 16, "scale": 1,
        "preprocessing": "PASS 1 (once per photo): resize the whole working image to 256x256 (stretch), predict with context = zeros, mix = 0, keep output `stats`. PASS 2: every 256x256 tile with context = stats, mix = 1, take `result`. Skipping pass 1 (plain per-tile NAFNet) produces garbage tiles on dark flat areas - this is a property of the upstream model, reproduced in fp32 PyTorch. Blur of ~5-25 px at the working size is the model's comfort zone: for photos with a long side > 2048 px run on a copy at long side 2048.",
        "postprocessing": "feathered tile blend (see tiling)",
    },
    "DDColorTiny": {
        "task": "automatic colorization of black-and-white photos",
        "input": dict(COMMON_IMAGE_IN, shape=[1, 3, 512, 512], width=512, height=512,
                      note="feed the photo (colour or B&W) resized to exactly 512x512 (stretch, no aspect preservation, as upstream). The graph converts it to gray (CIE L*) itself."),
        "output": {"name": "ab", "type": "MLMultiArray", "dtype": "Float16", "shape": [1, 2, 512, 512],
                   "meaning": "CIE Lab a* (channel 0) and b* (channel 1), OpenCV float Lab units (about -128...127), D65"},
        "tile": None, "overlap": None, "scale": 1,
        "preprocessing": "resize full image to 512x512 (bilinear/Lanczos)",
        "postprocessing": "resize ab bilinearly to the original size, take L* of the ORIGINAL full-resolution image, Lab(L, a, b) -> sRGB (D65, see docs/MODELS.md formulas), clamp 0...1",
    },
}

TILING = {
    "tile_input": 256, "overlap_input_px": 16,
    "origins": "along each axis of length N (after edge-padding to >= 256): 0, 240, 480, ... and the last origin clamped to N-256",
    "blend": "each output tile is weighted by a separable linear ramp w(j) = clamp((j+0.5)/(16*scale), 0, 1) on edges that have a neighbour tile (and the mirrored ramp on the far edge); image borders keep weight 1; output = sum(w*tile)/sum(w)",
    "reference_implementation": "coreml/tiling.py",
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def zip_dir(src, dst, arcroot):
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(src):
            for fn in sorted(files):
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, src)
                z.write(full, os.path.join(arcroot, rel).replace(os.sep, "/"))


def dir_size(p):
    return sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build")
    ap.add_argument("--nafnet", default="fp16")
    ap.add_argument("--ddcolor", default="int8")
    args = ap.parse_args()
    choice = {"ESRGANGeneral": "fp16", "NAFNetDeblur": args.nafnet, "DDColorTiny": args.ddcolor}
    rel = os.path.join(args.out, "release")
    shutil.rmtree(rel, ignore_errors=True)
    os.makedirs(rel)
    conv = json.load(open(os.path.join(args.out, "report", "conversion.json")))
    qpath = os.path.join(args.out, "report", "quality.json")
    qual = json.load(open(qpath)) if os.path.exists(qpath) else {}
    manifest = {"release": "models-v1", "minimum_deployment_target": "iOS 17", "format": "mlprogram (.mlpackage, zipped)",
                "compute_units": "MLModelConfiguration.computeUnits = .all", "tiling": TILING,
                "conversion_machine": conv.get("machine"), "models": []}
    total = 0
    deferred = []
    deb = qual.get("deblur") or []
    naf_fail = [g for g in conv.get("gate_failures", []) if g.startswith("NAFNetDeblur")]
    v = args.nafnet
    broken = sum(r.get(f"broken_blocks_{v}", 1) for r in deb) if deb else None
    if naf_fail or not deb or broken:
        reason = "; ".join(naf_fail) or ("no deblur quality run" if not deb else f"{broken} broken 256px blocks in the real-photo quality run")
        deferred.append({"name": "NAFNetDeblur", "status": "deferred", "reason": reason,
                         "app_fallback": "Unblur ships as Real-ESRGAN pass (4x then downscale) + classical Core Image sharpen/denoise"})
        choice.pop("NAFNetDeblur")
    manifest["deferred"] = deferred
    for name, variant in choice.items():
        src = os.path.join(args.out, "mlpackages", f"{name}{'' if variant == 'fp16' else '-int8'}.mlpackage")
        dst = os.path.join(rel, f"{name}.mlpackage.zip")
        zip_dir(src, dst, f"{name}.mlpackage")
        spec = MODELS[name]
        v = conv["models"][name]["variants"][variant]
        entry = {
            "name": name, "file": os.path.basename(dst), "unzips_to": f"{name}.mlpackage",
            "sha256": sha256(dst), "zip_size_bytes": os.path.getsize(dst), "mlpackage_size_bytes": dir_size(src),
            "precision": "float16 activations, " + ("float16 weights" if variant == "fp16" else "8-bit linear symmetric weights (per-channel), float16 compute"),
            "licence": spec["licence"], "source": spec["source"], "description": spec["description"],
            "upstream_weights": {"file": spec["weights"], "sha256": WEIGHTS[spec["weights"]]["sha256"]},
            **CONTRACT[name],
            "verification": {"coreml_vs_torch_fp32": v["vs_torch_fp32_cpu"],
                             "int8_vs_fp16": v.get("vs_fp16_coreml"),
                             "latency_per_tile_ci_runner_ms": v["latency_per_tile"],
                             "note": "latency measured on a GitHub Actions macos-26 VM, NOT an iPhone Neural Engine number"},
        }
        key = {"ESRGANGeneral": "super_resolution", "NAFNetDeblur": "deblur", "DDColorTiny": "colorize"}[name]
        if qual.get(key):
            entry["quality_rows"] = qual[key]
        total += entry["zip_size_bytes"]
        manifest["models"].append(entry)
    manifest["total_zip_size_bytes"] = total
    with open(os.path.join(rel, "models-manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(json.dumps({m["name"]: [m["zip_size_bytes"], m["mlpackage_size_bytes"]] for m in manifest["models"]}), total)


if __name__ == "__main__":
    main()
