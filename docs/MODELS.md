# Clarivo Core ML models (models-v1)

Owner: MODELS agent. Pipeline: `coreml/` + `.github/workflows/models.yml` (GitHub Actions `macos-26`, workflow_dispatch).
Release: https://github.com/EcomswiftLLC/photoenhancer-ios/releases/tag/models-v1
Assets: `ESRGANGeneral.mlpackage.zip`, `DDColorTiny.mlpackage.zip`, `models-manifest.json` (NAFNetDeblur deferred, listed under `deferred` in the manifest). Re-run: Actions > "Core ML models" (inputs: publish, ddcolor_variant, ship_nafnet=false).
Weights are downloaded in CI from upstream (sha256-pinned) and never committed. Nothing model-related lives in `Models/` in git: that folder is the app bundle resource folder CI fills from the release.

> Path note: ARCHITECTURE.md assigns `models/**` to this agent, but the repo already tracks the app bundle folder `Models/` and Windows/macOS file systems are case-insensitive, so the conversion pipeline lives in **`coreml/`** to keep Python files out of the app bundle.

## Status (models-v1, published 2026-11-25)

| model | in models-v1 | zip | mlpackage | precision | licence |
|---|---|---|---|---|---|
| ESRGANGeneral (Real-ESRGAN realesr-general-x4v3) | **yes** | 2.29 MB | 2.50 MB | fp16 | BSD-3-Clause |
| DDColorTiny (DDColor paper tiny) | **yes** | 50.7 MB | 61.3 MB | 8-bit linear weights, fp16 compute | Apache-2.0 |
| NAFNetDeblur (NAFNet GoPro width32) | **no - deferred** | (31.8 MB) | (35.1 MB) | fp16 | MIT |

Total shipped: 53.0 MB zipped (63.8 MB as mlpackages). Unblur in v1 = ESRGANGeneral pass (4x, then high-quality downscale) + classical Core Image sharpen / noise reduction.

Upstream weights (sha256-pinned in `coreml/fetch_weights.py`):
- `realesr-general-x4v3.pth` 8dc7edb9ac80ccdc30c3a5dca6616509367f05fbc184ad95b731f05bece96292 - https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth
- `ddcolor_paper_tiny.pth` 81dd643904f4664c3718513e3320ae3db0c567f0d3e18398606659adee7bfc17 - https://huggingface.co/piddnad/DDColor-models (model card licence: apache-2.0); arch code piddnad/DDColor @ 2adb63f
- `NAFNet-GoPro-width32.pth` 19394e6155d12ef6371d1d57496f87f0ec88f92bdffa27c0792690722d5d1a5c - official Google Drive id 1Fr2QadtDCEXg6iwWX8OzeZLbHOx2t5Bj (megvii-research/NAFNet README); byte-identical mirrors huggingface.co/nyanko7/nafnet-models and huggingface.co/mikestealth/nafnet-models (sha256 checked against the official file on 2026-11-25)

## Fix log
- 2026-11-25 iOS Simulator check (run 45645231122, `coreml/simcheck/main.swift`, now a step in models.yml): the published DDColorTiny gives the same ab in the iPhone Simulator (cpuOnly) as on macOS through `MLFeatureValue(cgImage:constraint:)` + `MLShapedArray<Float>(converting:)`. Migrant Mother mean|a| 7.4, mean|b| 13.5; colour photo mean|b| 13.6; Wright flyer 2.0 / 3.3; Lincoln 0.9 / 1.0 (a genuinely weak result, see verdict). fp16, int8 and fp32-compute builds agree, so the model is fine in the Simulator. If an app path gets near-zero ab, check the INPUT: redraw the source into an 8-bit sRGB RGBA `CGContext` (or a 32BGRA `CVPixelBuffer`) at 512x512 before making the feature value. Gray (1-channel), 16-bit or extended-range CGImages from old-photo files are the usual suspects.
- 2026-11-25 (republished, run 45636782825): DDColorTiny came out grey in the iOS Simulator (CPU): its LayerNorms overflowed float16 (activations ~1800, (x-mu)^2 ~3e6 > 65504). The macOS CPU path used for verification hid it. All 55 LayerNorms now use an exact overflow-free formulation (`coreml/archs/ddcolor.py` safe_layer_norm; fp32 output identical to upstream, max diff 2e-4). ESRGANGeneral activations peak at 74, so it is not affected. New sha256 values are in the manifest. Verification now also runs on CPU_AND_GPU (same numbers on the CI VM). The Simulator/iPhone result is still to be confirmed by the APP agent's CI.

## Verification (GitHub Actions macos-26, Apple M1 (Virtual), coremltools 9.0, torch 2.7.1)

Conversion correctness - Core ML (CPU) vs PyTorch fp32 on real-photo inputs at model size (`docs/quality/conversion.json`):
| model | inputs | PSNR worst / mean | max abs diff |
|---|---|---|---|
| ESRGANGeneral fp16 | 8 degraded real-photo tiles | 54.0 / 54.9 dB | 9/255 (mean 0.20) |
| DDColorTiny fp16 | 6 photos (4 colour, 2 historical B&W) | 50.4 / 53.5 dB (final RGB) | ab 11.8 (mean 0.18) |
| DDColorTiny 8-bit (shipped) | same | 43.9 / 51.0 dB vs torch; 45.0 / 51.5 dB vs fp16 | ab 27.9 (mean 0.31) |
| NAFNetDeblur fp16 (not shipped) | 8 blurred tiles + 4 context passes | 56.6 / 59.9 dB | 3/255 |

Full-photo checks (`docs/quality/quality.json`): tiled Core ML ESRGAN vs whole-image PyTorch = 52.1-55.2 dB on 6 photos (no visible seams); tiling identity/nearest tests bit-exact; DDColor Core ML (in-graph gray) vs upstream OpenCV-gray PyTorch pipeline = 50.7-58.1 dB final RGB; DDColor 8-bit vs fp16 on full photos = 44.9-55.6 dB PSNR, SSIM >= 0.991 (no visible difference in the side-by-sides).

Latency per prediction on the CI VM (median ms, CPU_ONLY / CPU_AND_GPU / ALL). **These are NOT iPhone numbers**: the VM has no Neural Engine, so `.all` falls back to CPU/GPU; ANE placement on a real device is unverified.
| model | CPU_ONLY | CPU_AND_GPU | ALL |
|---|---|---|---|
| ESRGANGeneral (256 tile -> 1024) | 138 | 162 | 130 |
| DDColorTiny 8-bit (512 image) | 469 | 338 | 350 |
| NAFNetDeblur fp16 (256 tile, not shipped) | 66 | 65 | 68 |
A 12 MP photo upscaled 4x needs about 300 ESRGAN tiles; the app will also be capped by the 8192 px / 48 MP output limit.

## Visual verdict (I looked at every preview; files in `docs/quality/`)

ESRGANGeneral (input = real photo downscaled 1/4 with blur, noise and JPEG 55-75):
- Good: removes JPEG blocking and noise completely, gives clean, crisp edges (tie pattern, lapel, flag pin, suit seams), noticeably better looking than bicubic. No tile seams.
- Weak: it is a GAN-style restorer, so fine natural texture (rock faces, skin pores, fabric weave, lunar surface) comes out smooth or "painted"; detail that was destroyed is not recovered (PSNR equal to or below bicubic: 19.5-32.4 dB vs 19.9-32.6 dB, SSIM similar). Good for upscaling soft/compressed photos; marketing must not promise recovered detail.

DDColorTiny:
- Good: landscapes (blue sky, green forest, warm granite), skin tones, white space suit, US flag stripes red/blue, Migrant Mother (natural skin, blue/grey clothes, warm hair) and the Wright flyer (sand, red jacket) look convincing; 8-bit = fp16 visually.
- Weak: some objects get guessed colours (helmet visor blue instead of orange, moon tinted olive/brown), and low-contrast 19th-century portraits (Lincoln collodion print) come out almost monochrome with only a faint skin tone. Colour is a plausible guess, not a reconstruction.

NAFNetDeblur (deferred):
- Plain per-tile NAFNet (what upstream does on whole images) produces garbage tiles on dark flat areas (dark suit) when run on 256 tiles - this happens in fp32 PyTorch too (deep 256-channel blocks explode when the channel-attention statistics come from a small dark tile). Fixed by a two-pass global-context variant (`coreml/archs/nafnet.py` NAFNetContext): 0 broken blocks afterwards, conversion exact (56.6 dB worst).
- But the visual check failed: faint checkerboard/tile texture on smooth skin (forehead), streaking on fur, and versus the sharp originals the gain is small or negative (cat -0.6 dB, cat on snow -1.6 dB, astronaut +0.9, portrait +1.6). Not good enough to ship; previews `deblur_*.jpg` show it. To revisit: whole-image inference at a fixed working size, or a different permissively licensed deblur model.



## Swift contract (APP agent)

General
- Load compiled models by name, never via Xcode-generated classes (a CI build without models must still compile):
  `Bundle.main.url(forResource: "ESRGANGeneral", withExtension: "mlmodelc")` -> `MLModel(contentsOf:configuration:)` with `config.computeUnits = .all`. Missing file -> `EnhanceError.modelUnavailable`.
- Inputs are Core ML **image** features named `image`. Build them with
  `MLFeatureValue(cgImage: tile, constraint: model.modelDescription.inputDescriptionsByName["image"]!.imageConstraint!, options: nil)`
  or pass a 32BGRA `CVPixelBuffer` of the exact size. Values: sRGB, 0...255 per channel; the model applies the 1/255 scaling itself. No mean/std normalisation on the app side.
- Image outputs are named `result`: `prediction.featureValue(for: "result")!.imageBufferValue` (32BGRA `CVPixelBuffer`, sRGB, 0...255, alpha 255). Values are already clamped in the graph.
- Run tiles sequentially inside an `autoreleasepool`, one prediction at a time.

| model | input `image` | output | tile / overlap / scale |
|---|---|---|---|
| ESRGANGeneral | RGB 256x256 | `result` RGB 1024x1024 | 256 / 16 / 4 |
| NAFNetDeblur | deferred, not in models-v1 | | |
| DDColorTiny | RGB 512x512 (whole photo, stretched) | `ab` MLMultiArray Float16 [1,2,512,512] | no tiling |

Tiling (ESRGANGeneral) - reference implementation `coreml/tiling.py`, verified bit-exact with identity/nearest functions:
1. If the image is smaller than 256 in a dimension, edge-replicate pad it to 256 (crop the output back afterwards).
2. Tile origins along an axis of length N: `0, 240, 480, ...` (step = 256 - 16) while `< N - 256`, then a final origin at exactly `N - 256`.
3. Each output tile (size 256*s) gets weight `wy[i] * wx[j]`, where for an axis `w(j) = 1`, multiplied by `clamp((j + 0.5) / (16*s), 0, 1)` if there is a neighbour tile before it on that axis and by `clamp((256*s - j - 0.5) / (16*s), 0, 1)` if there is a neighbour after it. Image borders keep weight 1.
4. Accumulate `sum(w * pixel)` and `sum(w)` in Float32; final pixel = `round(sum / sum_w)`, clamp 0...255.
Accumulators may be per-row-band to respect the memory guard (only tiles of the current band row plus the overlap band are needed).

ESRGANGeneral
- 4x native. 2x = 4x then high-quality downscale by 0.5 (Lanczos / `CILanczosScaleTransform`). Denoise = 4x then downscale to 1x.
- Output pixel `(x*4 + i, y*4 + j)` corresponds to input pixel `(x, y)`.

NAFNetDeblur - not in models-v1 (deferred, see above). If a later release adds it, its contract is two-pass (context `stats` from the whole photo at 256x256, then tiles with `context`/`mix`), described in `coreml/publish.py`.

DDColorTiny
1. Resize the whole photo (colour or B&W) to exactly 512x512 (stretch, no aspect preservation - this is what upstream does) by drawing it into an 8-bit sRGB RGBA bitmap (`CGContext`, premultipliedLast/noneSkipLast) - also for gray or 16-bit source files. Feed as `image`. The graph converts it to gray itself (CIE L* of sRGB, D65), so no gray conversion is needed in the app.
2. Read `ab`: `prediction.featureValue(for: "ab")!.multiArrayValue!`, dataType `.float16`, shape `[1, 2, 512, 512]`; read it with `multiArray.withUnsafeBytes { ... }` (or `withUnsafeBufferPointer(ofType: Float16.self)`) honouring `strides`. Do NOT use `dataPointer`: the Float16 output is pixel-buffer backed and `dataPointer` reads zeros (gray result) - found by the APP agent in CI. Channel 0 = a*, channel 1 = b*, OpenCV float Lab units (about -128...127).
3. Upscale a* and b* bilinearly to the original image size.
4. Compute L* of the ORIGINAL full-resolution image and combine Lab(L*, a*, b*) -> sRGB (formulas below). Clamp to 0...1.
5. Optional strength slider: blend a*, b* by `s` (0 = gray, 1 = full colour).

Lab <-> sRGB (D65, identical to OpenCV `COLOR_RGB2Lab` / `COLOR_Lab2RGB` on float images; use these exact constants):
```
lin(c) = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
enc(c) = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1/2.4) - 0.055
X = (0.412453 R + 0.357580 G + 0.180423 B) / 0.950456      (R,G,B linear)
Y =  0.212671 R + 0.715160 G + 0.072169 B
Z = (0.019334 R + 0.119193 G + 0.950227 B) / 1.088754
f(t) = t > 0.008856 ? cbrt(t) : 7.787 t + 16/116
L = Y > 0.008856 ? 116 cbrt(Y) - 16 : 903.3 Y
a = 500 (f(X) - f(Y));  b = 200 (f(Y) - f(Z))
inverse:
fy = (L + 16) / 116;  fx = fy + a / 500;  fz = fy - b / 200
Y = L > 7.9996 ? fy^3 : L / 903.3
finv(t) = t > 0.206893 ? t^3 : (t - 16/116) / 7.787
X = 0.950456 finv(fx);  Z = 1.088754 finv(fz)
R =  3.240479 X - 1.537150 Y - 0.498535 Z
G = -0.969256 X + 1.875992 Y + 0.041556 Z
B =  0.055648 X - 0.204043 Y + 1.057311 Z
sRGB = enc(clamp(R,G,B, 0, 1))
```
- Colour-photo detection (warn before colorizing): mean chroma `sqrt(a^2+b^2)` of the original > ~6 on a 256 px thumbnail means "already colour".

## LICENSES (for the in-app Open-source licences screen)

### Real-ESRGAN (realesr-general-x4v3) - BSD 3-Clause
Model: Real-ESRGAN `realesr-general-x4v3`, https://github.com/xinntao/Real-ESRGAN. Converted to Core ML; architecture re-implemented in `coreml/archs/srvgg.py`.

```
BSD 3-Clause License

Copyright (c) 2021, Xintao Wang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### NAFNet (NAFNet-GoPro-width32) - MIT  (NOT bundled in v1; keep for when deblur ships)
Model: NAFNet, "Simple Baselines for Image Restoration" (Chen, Chu, Zhang, Sun, ECCV 2022), https://github.com/megvii-research/NAFNet. Converted to Core ML; architecture adapted in `coreml/archs/nafnet.py`.

```
MIT License

Copyright (c) 2022 megvii-model

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
NAFNet's repository also contains BasicSR code (Copyright 2018-2020 BasicSR Authors, Apache License 2.0; full text below).

### DDColor (ddcolor_paper_tiny) - Apache License 2.0
Model: DDColor, "DDColor: Towards Photo-Realistic Image Colorization via Dual Decoders" (Kang, Yang, Ouyang, Ren, Li, Xie, ICCV 2023), https://github.com/piddnad/DDColor, weights https://huggingface.co/piddnad/DDColor-models (licence: apache-2.0). Converted to Core ML (modified: spectral norm folded, einsum rewritten as matmul, gray conversion added in the graph - see `coreml/archs/ddcolor.py`).
DDColor includes code derived from ConvNeXt (Copyright (c) Meta Platforms, Inc. and affiliates, MIT License) and DETR / Mask2Former transformer code (Copyright (c) Facebook, Inc. and its affiliates, Apache License 2.0).

Short attribution lines for the in-app screen (v1 bundles Real-ESRGAN and DDColor only; add the NAFNet/BasicSR lines only if NAFNetDeblur ships later):
- "Real-ESRGAN (realesr-general-x4v3) - Copyright (c) 2021 Xintao Wang - BSD 3-Clause License"
- "NAFNet - Copyright (c) 2022 megvii-model - MIT License"
- "DDColor - Copyright (c) 2022-2023 Xiaoyang Kang et al. (piddnad/DDColor) - Apache License 2.0; includes ConvNeXt (Meta Platforms, MIT) and DETR-derived code (Facebook, Apache 2.0)"
- "BasicSR - Copyright 2018-2020 BasicSR Authors - Apache License 2.0"

ConvNeXt (MIT):
```
MIT License

Copyright (c) Meta Platforms, Inc. and affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Apache License 2.0 (applies to DDColor, BasicSR, DETR-derived code) - full text:
```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

