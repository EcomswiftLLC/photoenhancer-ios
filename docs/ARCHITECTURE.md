# Clarivo (Photo Enhancer HD) - architecture and contracts

Free iPhone + iPad app (iOS 17+, universal "1,2"), SwiftUI, XcodeGen, no Mac: every build, test, screenshot and release runs on GitHub Actions `macos-26`.
Repo EcomswiftLLC/photoenhancer-ios (public). Bundle `com.ecomswift.photoenhancer`, team N84NGN3KSH. Xcode target/scheme/module **Clarivo**, tests **ClarivoTests**, UI tests **ClarivoUITests**.
Store name (<=30 chars, keywords first): **Photo Enhancer HD: Clarivo** (26). Subtitle: **Unblur, Upscale & Sharpen**. Home-screen name: Clarivo. (Store name must be verified free in ASC at creation; fallbacks: "Photo Enhancer HD: Clarix", "Photo Enhancer HD: Crispa".)

Shell copied from Lumotion (Sources/Ads, Sources/Theme, workflows, tools/ci_signing.py). Rename the `LM` namespace to `CV` and `lm*` keys/args to `cv*` (Info.plist `CVBannerAdUnitID`, `CVRewardedAdUnitID`, launch arg `-cvScreen`, `-cvNoAds`). Keep Lumotion's proven ad logic (UMP -> ATT -> GMA start, RewardedGate with grace window, no-ad = export free).

## Features (each must really work)
1. **Enhance (AI upscale)** 2x / 4x / 8x. 2x and 4x: Real-ESRGAN `realesr-general-x4v3` (BSD-3), 4x native, 2x = 4x pass then high-quality downscale to 2x. 8x = two tiled passes (4x then 2x-downscaled-pass i.e. 4x + 2x) with a HARD cap: output long side <= 8192 px and <= 48 MP, input is first reduced if needed; the UI says when the cap applied. Tiled (256 px tiles, 16 px overlap, feathered blend), run on the Neural Engine/GPU (`MLModelConfiguration.computeUnits = .all`), process tiles sequentially, release buffers per tile (memory-safe).
2. **Unblur** (motion blur / camera shake): NAFNet (MIT) deblur model, tiled. Plus classical **Sharpen** (Core Image luminance sharpen / unsharp) with a strength slider for mild softness. Honest copy: it reduces blur, it cannot recover detail that was never captured.
3. **Denoise**: realesr-general-x4v3 (the `wdn` weight interpolation is NOT used in v1) - denoise = run the SR model at 4x then downscale back to 1x (supersample denoise), strength blends with the original. Also Core Image noise reduction as the light option.
4. **Portrait enhance** (licence-safe "face restore"): Vision face rectangles -> run SR on padded face crops, feathered-mask blend back. NOT a generative face model (GFPGAN / CodeFormer are not used: dataset/licence issues). Copy must not say "face reconstruction".
5. **Colorize** black-and-white photos: DDColor tiny (Apache-2.0), 512x512 model gives `ab`; combine with the original full-res L channel in Lab. Detect already-colour photos (saturation test) and warn.
6. **Restore old photo** (classical, honest): scratch/dust removal (thin-structure mask via morphology + median inpaint), fade fix (auto levels / contrast stretch / de-yellow), optional denoise. No model.
7. **Auto fix** light and colour: Core Image auto-adjust + gentle custom tone curve + vibrance; one tap, strength slider.
8. **Before/after**: slider compare with pinch/double-tap zoom and pan (zoom synchronised), tap-and-hold to show original.
9. **Batch queue**: pick many photos, apply the chosen preset to all, progress per item, cancel, one rewarded ad for the whole batch.
10. **Export**: JPG / PNG / HEIC, size chosen (original, 2x, 4x, 8x, custom long side), quality slider, **EXIF keep / strip** (strip also removes GPS), save to Photos, save to Files, Share.
11. **Import**: PHPicker (Photos, multiple) and Files (`fileImporter`), drag and drop on iPad, Camera not needed. (Share extension: later, not v1.)
12. **Settings**: privacy choices (UMP), Rate this app (write-review URL once an App Store id is set in `AppInfo.appStoreID`), open-source licences screen (every model + SDK licence and attribution), privacy policy / terms / support links, version.
13. **History**: recent results in the app container (cleared at launch when older than 7 days; user can clear).

## Engine contract (Sources/Engine) - pure Swift, unit tested, no UI
```
enum EnhanceOperation { case upscale(factor: Int), unblur, denoise(strength: Float), portrait, colorize, restoreOld, autoFix(strength: Float), sharpen(strength: Float) }
struct EnhanceJob { source: URL/CGImage; operations: [EnhanceOperation]; ... }
protocol ModelProviding { func model(_ kind: ModelKind) async throws -> MLModel? }   // nil => model not bundled
enum ModelKind { case superResolution, deblur, colorize }
```
When a model file is not present in the bundle (e.g. a CI build before the models release exists) every operation that needs it must fail gracefully (`EnhanceError.modelUnavailable`) and the UI hides/disables it; classical operations keep working. Memory guard: never hold more than one full-resolution RGBA buffer plus one output buffer plus the current tile; use `CGImageSource` thumbnails/downsampling for previews; respect `UIApplication.didReceiveMemoryWarningNotification` (cancel gracefully with message).
Preview = run the operation on a downscaled working copy for the compare slider; Export = full resolution. Tests must include tiling seam test (identity tile function reproduces the input), cap logic, EXIF strip/keep, format writers, review-prompt rule, rewarded policy, ad id guards.

## Models (Core ML, fp16) - conversion pipeline in `models/` + workflow `.github/workflows/models.yml`
All licences permissive; weights downloaded in CI from official upstream release URLs; never committed.
| file in app bundle (`Models/*.mlmodelc` after Xcode compiles `.mlpackage`) | source | licence | in -> out |
|---|---|---|---|
| `ESRGANGeneral.mlpackage` | xinntao Real-ESRGAN `realesr-general-x4v3.pth` (SRVGGNetCompact) | BSD-3-Clause | ImageType RGB 256x256 (`image`) -> ImageType RGB 1024x1024 (`result`) |
| `NAFNetDeblur.mlpackage` | megvii NAFNet GoPro width32 (or best available permissively hosted deblur weights) | MIT | ImageType RGB 256x256 -> ImageType RGB 256x256 |
| `DDColorTiny.mlpackage` | piddnad DDColor `ddcolor_paper_tiny` | Apache-2.0 | ImageType RGB(gray replicated) 512x512 -> MLMultiArray `ab` (1,2,512,512) |
The MODELS agent publishes the converted, zipped mlpackages as assets of GitHub release **models-v1** on this repo plus `models-manifest.json` (name, sha256, size, licence, source URL, input/output specs, measured quality notes). ios.yml / release.yml download them with `gh release download models-v1` into `Models/` before `xcodegen generate` (project.yml includes `Models` as a folder resource when present). If the exact input/output spec above changes, the MODELS agent updates this table and `models-manifest.json`; the APP agent reads the manifest. Total bundled models must stay under ~100 MB (quantise to 8 bit weights if needed and show before/after quality proof).

## Monetisation (owner order, mandatory)
Free. AdMob banner on Home only. Every Save to Photos / Save to Files / Share goes through ONE rewarded ad (a batch = one ad; the 120 s grace of Lumotion's RewardedGate applies). The finished result and before/after are shown BEFORE the ad. No ad available (offline, no fill, consent pending) -> export proceeds free. No IAP, no StoreKit purchases. Debug.xcconfig keeps Google test ids; Release.xcconfig gets real ids; release.yml refuses test ids.

## Review prompt (owner order, Apple `requestReview` only, no custom star gates / incentives)
Trigger: right after the user's 3rd successful export completed, with the saved confirmation showing, only if (a) a result was really saved/shared (not failure), (b) >= 2 days or >= 3 sessions since install, (c) not within 60 s of an ad being shown and never while an ad or share sheet is on screen, (d) once per app version and never more often than every 120 days, (e) never after an error or cancel. Counters in UserDefaults; pure `ReviewPromptPolicy` struct, unit tested. Settings row "Rate this app" opens `https://apps.apple.com/app/id<ID>?action=write-review` once `AppInfo.appStoreID` is non-empty.

## Privacy / compliance
`PrivacyInfo.xcprivacy` from the shell: NSPrivacyTracking **false**, no tracking domains (ITMS-91064). ATT prompt is shown after UMP consent, so ASC App Privacy labels say tracking Yes (Device ID, Advertising Data) - same as the other apps. Photos never leave the device: say so in the listing, privacy policy and an in-app line. Permissions: only `NSPhotoLibraryAddUsageDescription` (save). Picker needs no permission. Never claim "recover details that were never there" or "restore lost detail" - use "enhance, sharpen, upscale".

## File ownership (parallel agents; never edit another agent's area)
- MODELS agent: `models/**`, `.github/workflows/models.yml`, `docs/MODELS.md`, `docs/quality/**`.
- APP agent: `Sources/**` (except Sources/Resources/Samples), `Tests/**`, `UITests/**`, `project.yml`, `.github/workflows/ios.yml`, `Config/*.xcconfig` (Debug only), `Info.plist`.
- BRAND agent: `design/**`, `tools/make_icon.py`, `Sources/Resources/Assets.xcassets/AppIcon*`, `Sources/Resources/Samples/**`, `website/**`, `docs/store/**`, `tools/build_store_metadata.py`, `tools/store_shots*.py`, AdMob via Chrome, `Config/Release.xcconfig` ids.
- Main session: ASC record/listing/upload, release.yml, secrets.
Commit only your own files, `git pull --rebase` before each push, small commits.

## Update 2026-11-25 (models shipped in v1)
Release `models-v1` contains only **ESRGANGeneral** (fp16, 2.3 MB) and **DDColorTiny** (8-bit weights, 51 MB). NAFNet deblur failed the visual check and is deferred (listed under `deferred` in models-manifest.json); **Unblur = Real-ESRGAN pass + Core Image sharpen/denoise**. The authoritative model contract is `docs/MODELS.md` + `models-manifest.json` (conversion code lives in `coreml/`, not `models/`). Listing and in-app copy must only claim shipped features; never claim recovered detail (upscale PSNR is ~equal to bicubic; the gain is cleaner edges and less blocking/noise).
