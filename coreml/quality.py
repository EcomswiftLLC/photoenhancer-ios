"""Real before/after quality run with the converted Core ML models, using the same tiling the app uses.

Usage: python coreml/quality.py --samples build/samples --out build --weights build/weights
Writes build/quality/**.png (full-size results), build/preview/*.jpg (small side-by-side previews)
and build/report/quality.json.
"""
import argparse
import glob
import json
import os
import time

import cv2
import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont

import common
from common import MODELS, build_torch, psnr, ssim, combine_l_ab, colorfulness, rgb_to_lab, lab_to_rgb_u8
import degrade
import tiling

import coremltools as ct

OVERLAP = 16


def load_ml(path):
    for cu in (ct.ComputeUnit.ALL, ct.ComputeUnit.CPU_ONLY):
        try:
            return ct.models.MLModel(path, compute_units=cu), cu.name
        except Exception as e:
            print("load failed", path, cu, e)
    raise RuntimeError(path)


def tile_fn(ml):
    def fn(t):
        return np.asarray(ml.predict({"image": Image.fromarray(t)})["result"].convert("RGB"))
    return fn


def font(sz):
    try:
        return ImageFont.load_default(size=sz)
    except TypeError:
        return ImageFont.load_default()


def panel(images, labels, height=420):
    """Side-by-side panel, every image scaled (nearest for small inputs) to the same height."""
    tiles = []
    for im, lab in zip(images, labels):
        h, w = im.shape[:2]
        nw = int(round(w * height / h))
        interp = Image.NEAREST if h < height / 2 else Image.LANCZOS
        p = Image.fromarray(im).resize((nw, height), interp)
        canvas = Image.new("RGB", (nw, height + 34), (18, 18, 20))
        canvas.paste(p, (0, 34))
        ImageDraw.Draw(canvas).text((8, 6), lab, fill=(240, 240, 240), font=font(20))
        tiles.append(canvas)
    W = sum(t.width for t in tiles) + 6 * (len(tiles) - 1)
    out = Image.new("RGB", (W, height + 34), (0, 0, 0))
    x = 0
    for t in tiles:
        out.paste(t, (x, 0))
        x += t.width + 6
    return out


def detail_crop_box(img, size):
    """Most detailed size x size window (Laplacian energy) on a coarse grid."""
    g = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY).astype(np.float32)
    lap = np.abs(cv2.Laplacian(g, cv2.CV_32F))
    h, w = g.shape
    best, box = -1, (0, 0)
    for y in range(0, max(1, h - size + 1), max(1, size // 4)):
        for x in range(0, max(1, w - size + 1), max(1, size // 4)):
            e = lap[y:y + size, x:x + size].mean()
            if e > best:
                best, box = e, (y, x)
    return box


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(img).save(path)


def save_preview(pil, path, maxw=1500):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if pil.width > maxw:
        pil = pil.resize((maxw, int(pil.height * maxw / pil.width)), Image.LANCZOS)
    pil.save(path, "JPEG", quality=84, optimize=True)


def run_sr(args, rep):
    ml, cu = load_ml(os.path.join(args.out, "mlpackages", "ESRGANGeneral.mlpackage"))
    torch_w, _ = build_torch("ESRGANGeneral", args.weights)
    rows = []
    for i, f in enumerate(sorted(glob.glob(os.path.join(args.samples, "color", "*.jpg")))):
        name = os.path.splitext(os.path.basename(f))[0]
        hr = np.asarray(Image.open(f).convert("RGB"))
        lr = degrade.sr_degrade(hr, seed=100 + i)
        gt = hr[: lr.shape[0] * 4, : lr.shape[1] * 4]
        t = time.perf_counter()
        sr = tiling.run_tiled(lr, tile_fn(ml), t=256, o=OVERLAP, s=4)
        secs = time.perf_counter() - t
        bic = np.asarray(Image.fromarray(lr).resize((gt.shape[1], gt.shape[0]), Image.BICUBIC))
        with torch.no_grad():
            full = torch_w(torch.from_numpy(lr.astype(np.float32) / 255).permute(2, 0, 1)[None])[0]
        full = np.clip(np.rint(full.permute(1, 2, 0).numpy()), 0, 255).astype(np.uint8)
        row = {"image": name, "lr_size": list(lr.shape[:2]), "out_size": list(sr.shape[:2]),
               "seconds_tiled_coreml": round(secs, 2), "compute_units": cu,
               "psnr_bicubic_vs_gt": psnr(bic, gt), "psnr_esrgan_vs_gt": psnr(sr, gt),
               "ssim_bicubic_vs_gt": ssim(bic, gt), "ssim_esrgan_vs_gt": ssim(sr, gt),
               "psnr_tiled_coreml_vs_whole_image_torch": psnr(sr, full)}
        rows.append(row)
        save(lr, os.path.join(args.out, "quality", "sr", f"{name}_input_lr.png"))
        save(sr, os.path.join(args.out, "quality", "sr", f"{name}_esrgan_x4.png"))
        y, x = detail_crop_box(gt, 384)
        crop = (slice(y, y + 384), slice(x, x + 384))
        lrc = lr[y // 4:(y + 384) // 4, x // 4:(x + 384) // 4]
        p = panel([lrc, bic[crop], sr[crop], gt[crop]],
                  ["input (1/4 + blur/noise/JPEG)", "bicubic x4", "ESRGANGeneral x4 (Core ML)", "original"])
        save_preview(p, os.path.join(args.out, "preview", f"sr_{name}.jpg"))
        print(json.dumps(row), flush=True)
    rep["super_resolution"] = rows


def run_deblur(args, rep):
    variants = {}
    for v, fn in (("fp16", "NAFNetDeblur.mlpackage"), ("int8", "NAFNetDeblur-int8.mlpackage")):
        p = os.path.join(args.out, "mlpackages", fn)
        if os.path.exists(p):
            variants[v] = load_ml(p)
    torch_w, _ = build_torch("NAFNetDeblur", args.weights)
    rows = []
    for i, f in enumerate(sorted(glob.glob(os.path.join(args.samples, "color", "*.jpg")))):
        name = os.path.splitext(os.path.basename(f))[0]
        sharp = np.asarray(Image.open(f).convert("RGB"))
        if sharp.shape[1] > 1280:
            sharp = np.asarray(Image.fromarray(sharp).resize((1280, int(sharp.shape[0] * 1280 / sharp.shape[1])), Image.LANCZOS))
        blurred = degrade.motion_blur(sharp, seed=200 + i)
        row = {"image": name, "size": list(sharp.shape[:2]),
               "psnr_blurred_vs_sharp": psnr(blurred, sharp), "ssim_blurred_vs_sharp": ssim(blurred, sharp)}
        outs = {}
        for v, (ml, cu) in variants.items():
            t = time.perf_counter()
            outs[v] = tiling.run_tiled(blurred, tile_fn(ml), t=256, o=OVERLAP, s=1)
            row[f"seconds_tiled_{v}"] = round(time.perf_counter() - t, 2)
            row[f"psnr_{v}_vs_sharp"] = psnr(outs[v], sharp)
            row[f"ssim_{v}_vs_sharp"] = ssim(outs[v], sharp)
            save(outs[v], os.path.join(args.out, "quality", "deblur", f"{name}_nafnet_{v}.png"))
        if "int8" in outs:
            row["psnr_int8_vs_fp16"] = psnr(outs["int8"], outs["fp16"])
            row["ssim_int8_vs_fp16"] = ssim(outs["int8"], outs["fp16"])
        # seam/tiling check against whole-image torch (differs a little by design: SCA pools per tile)
        with torch.no_grad():
            h, w = blurred.shape[:2]
            ph, pw = (16 - h % 16) % 16, (16 - w % 16) % 16
            x = torch.from_numpy(np.pad(blurred, ((0, ph), (0, pw), (0, 0)), mode="edge").astype(np.float32) / 255).permute(2, 0, 1)[None]
            full = torch_w(x)[0].permute(1, 2, 0).numpy()[:h, :w]
        full = np.clip(np.rint(full), 0, 255).astype(np.uint8)
        row["psnr_torch_whole_image_vs_sharp"] = psnr(full, sharp)
        row["psnr_tiled_fp16_vs_whole_image_torch"] = psnr(outs["fp16"], full)
        save(blurred, os.path.join(args.out, "quality", "deblur", f"{name}_input_blurred.png"))
        y, x = detail_crop_box(sharp, 448)
        c = (slice(y, y + 448), slice(x, x + 448))
        ims = [blurred[c], outs["fp16"][c]] + ([outs["int8"][c]] if "int8" in outs else []) + [sharp[c]]
        labs = ["input (synthetic motion blur)", "NAFNetDeblur fp16 (Core ML)"] + (["8-bit weights"] if "int8" in outs else []) + ["original"]
        save_preview(panel(ims, labs, height=448), os.path.join(args.out, "preview", f"deblur_{name}.jpg"))
        rows.append(row)
        print(json.dumps(row), flush=True)
    rep["deblur"] = rows


def ddcolor_upstream_reference(model, rgb, n=512):
    """Exact upstream preprocessing (cv2 Lab gray) with the torch model, for an end-to-end check."""
    img = rgb.astype(np.float32) / 255.0
    r = cv2.resize(img, (n, n))
    L = cv2.cvtColor(r, cv2.COLOR_RGB2Lab)[:, :, :1]
    gray = cv2.cvtColor(np.concatenate([L, 0 * L, 0 * L], -1), cv2.COLOR_LAB2RGB)
    with torch.no_grad():
        ab = model(torch.from_numpy(gray.transpose(2, 0, 1))[None].float())[0].numpy()
    return ab


def run_colorize(args, rep):
    variants = {}
    for v, fn in (("fp16", "DDColorTiny.mlpackage"), ("int8", "DDColorTiny-int8.mlpackage")):
        p = os.path.join(args.out, "mlpackages", fn)
        if os.path.exists(p):
            variants[v] = load_ml(p)
    torch_w, _ = build_torch("DDColorTiny", args.weights)
    rows = []
    for group in ("color", "bw"):
        for f in sorted(glob.glob(os.path.join(args.samples, group, "*.jpg"))):
            name = os.path.splitext(os.path.basename(f))[0]
            orig = np.asarray(Image.open(f).convert("RGB"))
            if orig.shape[1] > 1600:
                orig = np.asarray(Image.fromarray(orig).resize((1600, int(orig.shape[0] * 1600 / orig.shape[1])), Image.LANCZOS))
            lab = rgb_to_lab(orig)
            gray = lab_to_rgb_u8(np.stack([lab[..., 0], 0 * lab[..., 0], 0 * lab[..., 0]], -1))
            small = np.asarray(Image.fromarray(gray).resize((512, 512), Image.BICUBIC))
            row = {"image": name, "group": group, "size": list(orig.shape[:2])}
            outs = {}
            for v, (ml, cu) in variants.items():
                t = time.perf_counter()
                ab = np.asarray(ml.predict({"image": Image.fromarray(small)})["ab"], np.float32)[0]
                row[f"seconds_{v}"] = round(time.perf_counter() - t, 2)
                outs[v] = combine_l_ab(gray, ab)
                row[f"colorfulness_{v}"] = colorfulness(outs[v])
                if group == "color":
                    row[f"psnr_{v}_vs_original_colour"] = psnr(outs[v], orig)
                save(outs[v], os.path.join(args.out, "quality", "colorize", f"{name}_ddcolor_{v}.png"))
            if "int8" in outs:
                row["psnr_int8_vs_fp16"] = psnr(outs["int8"], outs["fp16"])
                row["ssim_int8_vs_fp16"] = ssim(outs["int8"], outs["fp16"])
            ab_up = ddcolor_upstream_reference(torch_w.model, orig)
            up = combine_l_ab(gray, ab_up)
            row["psnr_fp16_vs_upstream_torch_pipeline"] = psnr(outs["fp16"], up)
            if group == "color":
                row["colorfulness_original"] = colorfulness(orig)
            save(gray, os.path.join(args.out, "quality", "colorize", f"{name}_input_gray.png"))
            ims = [gray if group == "color" else orig, outs["fp16"]] + ([outs["int8"]] if "int8" in outs else [])
            labs = ["input (gray)" if group == "color" else "input (historical B&W)", "DDColorTiny fp16 (Core ML)"] + (["8-bit weights"] if "int8" in outs else [])
            if group == "color":
                ims.append(orig)
                labs.append("original colour")
            save_preview(panel(ims, labs, height=480), os.path.join(args.out, "preview", f"colorize_{name}.jpg"), maxw=1800)
            rows.append(row)
            print(json.dumps(row), flush=True)
    rep["colorize"] = rows


def seam_identity_test(rep):
    rng = np.random.default_rng(0)
    img = rng.integers(0, 256, (700, 1000, 3), dtype=np.uint8)
    same = tiling.run_tiled(img, lambda t: t, t=256, o=16, s=1)
    up = tiling.run_tiled(img[:300, :500], lambda t: np.repeat(np.repeat(t, 4, 0), 4, 1), t=256, o=16, s=4)
    ref = np.repeat(np.repeat(img[:300, :500], 4, 0), 4, 1)
    small = tiling.run_tiled(img[:100, :180], lambda t: t, t=256, o=16, s=1)
    rep["tiling_identity_test"] = {"identity_exact": bool((same == img).all()),
                                   "nearest_x4_exact": bool((up == ref).all()),
                                   "small_image_padded_exact": bool((small == img[:100, :180]).all())}
    print(rep["tiling_identity_test"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", default="build/samples")
    ap.add_argument("--weights", default="build/weights")
    ap.add_argument("--out", default="build")
    ap.add_argument("--only", default="sr,deblur,colorize")
    args = ap.parse_args()
    rep = {}
    seam_identity_test(rep)
    if "sr" in args.only:
        run_sr(args, rep)
    if "deblur" in args.only:
        run_deblur(args, rep)
    if "colorize" in args.only:
        run_colorize(args, rep)
    os.makedirs(os.path.join(args.out, "report"), exist_ok=True)
    with open(os.path.join(args.out, "report", "quality.json"), "w") as f:
        json.dump(rep, f, indent=2)


if __name__ == "__main__":
    main()
