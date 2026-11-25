"""Convert the three models to Core ML (mlprogram, iOS 17, fp16; plus 8-bit weight variants),
verify every Core ML output against the PyTorch fp32 output on real image tiles, and time
per-tile latency on this machine.

Usage: python coreml/convert.py --weights build/weights --samples build/samples --out build
Writes build/mlpackages/*.mlpackage and build/report/conversion.json
"""
import argparse
import glob
import json
import os
import platform
import statistics
import subprocess
import time

import numpy as np
import torch
from PIL import Image

import common
from common import MODELS, build_torch, psnr, combine_l_ab
import degrade

import coremltools as ct
import coremltools.optimize as cto

VARIANTS = {
    "ESRGANGeneral": ["fp16"],
    "NAFNetDeblur": ["fp16", "int8"],
    "DDColorTiny": ["fp16", "int8"],
}


def convert(name, wrapper, example):
    spec = MODELS[name]
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
    inputs = [ct.ImageType(name="image", shape=tuple(example.shape), scale=1.0 / 255.0,
                           color_layout=ct.colorlayout.RGB)]
    if spec["output"] == "image":
        outputs = [ct.ImageType(name="result", color_layout=ct.colorlayout.RGB)]
    else:
        outputs = [ct.TensorType(name="ab", dtype=np.float16)]
    ml = ct.convert(traced, inputs=inputs, outputs=outputs, convert_to="mlprogram",
                    compute_precision=ct.precision.FLOAT16,
                    minimum_deployment_target=ct.target.iOS17)
    ml.author = "Converted for Clarivo from " + spec["source"]
    ml.license = spec["licence"]
    ml.short_description = spec["description"]
    ml.version = "1"
    return ml


def quantize_int8(ml):
    cfg = cto.coreml.OptimizationConfig(
        global_config=cto.coreml.OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=2048))
    return cto.coreml.linear_quantize_weights(ml, config=cfg)


def dir_size(p):
    return sum(os.path.getsize(f) for f in glob.glob(os.path.join(p, "**", "*"), recursive=True) if os.path.isfile(f))


def test_inputs(name, samples):
    """Real-photo inputs at model input size (uint8 HxWx3), as the model sees them in the app."""
    rng = np.random.default_rng(1234)
    files = sorted(glob.glob(os.path.join(samples, "color", "*.jpg")))[:4]
    bw = sorted(glob.glob(os.path.join(samples, "bw", "*.jpg")))[:2]
    n = MODELS[name]["in_size"]
    out = []
    for f in files:
        img = np.asarray(Image.open(f).convert("RGB"))
        if name == "DDColorTiny":
            out.append(np.asarray(Image.fromarray(img).resize((n, n), Image.BICUBIC)))
            continue
        if name == "ESRGANGeneral":
            img = degrade.sr_degrade(img, seed=int(rng.integers(1 << 30)))
        else:
            img = degrade.motion_blur(img, seed=int(rng.integers(1 << 30)))
        for _ in range(2):
            y = int(rng.integers(0, img.shape[0] - n + 1))
            x = int(rng.integers(0, img.shape[1] - n + 1))
            out.append(img[y:y + n, x:x + n])
    if name == "DDColorTiny":
        for f in bw:
            img = np.asarray(Image.open(f).convert("RGB"))
            out.append(np.asarray(Image.fromarray(img).resize((n, n), Image.BICUBIC)))
    return out


def torch_ref(wrapper, tile):
    x = torch.from_numpy(tile.astype(np.float32) / 255.0).permute(2, 0, 1)[None]
    with torch.no_grad():
        return wrapper(x)[0].numpy()  # (3,H,W) 0..255 or (2,H,W) ab


def ml_out(ml, name, tile):
    res = ml.predict({"image": Image.fromarray(tile)})
    if MODELS[name]["output"] == "image":
        return np.asarray(res["result"].convert("RGB"))  # HxWx3 uint8
    return np.asarray(res["ab"], np.float32)[0]  # (2,H,W)


def compare(name, ref, got, tile):
    if MODELS[name]["output"] == "image":
        r = np.clip(np.rint(ref.transpose(1, 2, 0)), 0, 255)
        return {"max_abs_diff": float(np.abs(r - got).max()), "mean_abs_diff": float(np.abs(r - got).mean()),
                "psnr_db": psnr(r, got)}
    # ab: raw diff, plus PSNR of the final colourised RGB (what the user sees)
    rgb_ref = combine_l_ab(tile, ref)
    rgb_got = combine_l_ab(tile, got)
    return {"max_abs_diff_ab": float(np.abs(ref - got).max()), "mean_abs_diff_ab": float(np.abs(ref - got).mean()),
            "psnr_db_rgb": psnr(rgb_ref, rgb_got)}


def compare_ml(name, a, b, tile):
    if MODELS[name]["output"] == "image":
        return {"psnr_db": psnr(a, b), "max_abs_diff": float(np.abs(a.astype(int) - b.astype(int)).max())}
    return {"psnr_db_rgb": psnr(combine_l_ab(tile, a), combine_l_ab(tile, b)),
            "max_abs_diff_ab": float(np.abs(a - b).max())}


def latency(path, name, tile, units):
    try:
        t0 = time.perf_counter()
        ml = ct.models.MLModel(path, compute_units=units)
        load_ms = (time.perf_counter() - t0) * 1000
        img = Image.fromarray(tile)
        for _ in range(2):
            ml.predict({"image": img})
        ts = []
        for _ in range(8):
            t = time.perf_counter()
            ml.predict({"image": img})
            ts.append((time.perf_counter() - t) * 1000)
        return {"load_ms": round(load_ms, 1), "median_ms": round(statistics.median(ts), 1),
                "min_ms": round(min(ts), 1)}
    except Exception as e:
        return {"error": str(e)[:300]}


def mean_stats(rows):
    keys = rows[0].keys()
    out = {}
    for k in keys:
        vals = [r[k] for r in rows]
        if k.startswith("max"):
            out[k] = max(vals)
        elif k.startswith("psnr"):
            finite = [v for v in vals if np.isfinite(v)]
            out[k + "_min"] = min(finite) if finite else float("inf")
            out[k + "_mean"] = float(np.mean(finite)) if finite else float("inf")
        else:
            out[k] = float(np.mean(vals))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", default="build/weights")
    ap.add_argument("--samples", default="build/samples")
    ap.add_argument("--out", default="build")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    mdir = os.path.join(args.out, "mlpackages")
    rdir = os.path.join(args.out, "report")
    os.makedirs(mdir, exist_ok=True)
    os.makedirs(rdir, exist_ok=True)
    report = {
        "machine": {"platform": platform.platform(), "processor": platform.processor(),
                    "chip": subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip(),
                    "torch": torch.__version__, "coremltools": ct.__version__},
        "models": {},
    }
    failures = []
    names = [n for n in VARIANTS if not args.only or n in args.only.split(",")]
    for name in names:
        print("=== converting", name, flush=True)
        wrapper, example = build_torch(name, args.weights)
        ml16 = convert(name, wrapper, example)
        tiles = test_inputs(name, args.samples)
        refs = [torch_ref(wrapper, t) for t in tiles]
        entry = {"variants": {}}
        outs16 = None
        for v in VARIANTS[name]:
            ml = ml16 if v == "fp16" else quantize_int8(ml16)
            path = os.path.join(mdir, f"{name}{'' if v == 'fp16' else '-int8'}.mlpackage")
            ml.save(path)
            ml_loaded = ct.models.MLModel(path, compute_units=ct.ComputeUnit.CPU_ONLY)
            outs = [ml_out(ml_loaded, name, t) for t in tiles]
            vs_torch = mean_stats([compare(name, r, o, t) for r, o, t in zip(refs, outs, tiles)])
            item = {"path": path, "size_bytes": dir_size(path), "n_test_inputs": len(tiles),
                    "vs_torch_fp32_cpu": vs_torch}
            if v == "fp16":
                outs16 = outs
            else:
                item["vs_fp16_coreml"] = mean_stats([compare_ml(name, a, b, t) for a, b, t in zip(outs16, outs, tiles)])
            item["latency_per_tile"] = {
                "CPU_ONLY": latency(path, name, tiles[0], ct.ComputeUnit.CPU_ONLY),
                "CPU_AND_GPU": latency(path, name, tiles[0], ct.ComputeUnit.CPU_AND_GPU),
                "ALL": latency(path, name, tiles[0], ct.ComputeUnit.ALL),
            }
            entry["variants"][v] = item
            print(json.dumps({name + ":" + v: item}, indent=1), flush=True)
            worst = min(val for k, val in vs_torch.items() if k.startswith("psnr") and k.endswith("_min"))
            if worst < 40.0:
                failures.append(f"{name}:{v} worst-tile PSNR vs torch {worst:.1f} dB < 40 dB")
        report["models"][name] = entry
        del wrapper
    with open(os.path.join(rdir, "conversion.json"), "w") as f:
        json.dump(report, f, indent=2)
    if failures:
        raise SystemExit("CONVERSION CHECK FAILED: " + "; ".join(failures))


if __name__ == "__main__":
    main()
