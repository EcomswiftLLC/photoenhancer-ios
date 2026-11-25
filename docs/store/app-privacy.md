# Clarivo: App Privacy answers (App Store Connect, "App Privacy")

These answers describe the shipped build: no analytics of our own, no account, photos processed on the device with Core ML and never uploaded, ads from Google AdMob (Google Mobile Ads SDK + UMP) with the App Tracking Transparency prompt. They match `Sources/Resources/PrivacyInfo.xcprivacy` (`NSPrivacyTracking` stays false in the manifest, as required for ITMS-91064; Apple's label, not the manifest flag, carries the tracking answer) and the privacy policy at https://ecomswiftllc.github.io/clarivo/privacy/. Same answers as Aperta and Lumotion.

## Data collection

"Do you or your third-party partners collect data from this app?" Yes.

| Data type | Collected | Linked to the user | Used to track | Purposes |
|---|---|---|---|---|
| Identifiers: Device ID | Yes | Yes | **Yes** | Third-Party Advertising (and Analytics, as Google reports it) |
| Usage Data: Advertising Data | Yes | Yes | **Yes** | Third-Party Advertising |
| Usage Data: Product Interaction | Yes | Yes | No | Third-Party Advertising |
| Diagnostics: Performance Data | Yes | Yes | No | Third-Party Advertising, Analytics (ad SDK diagnostics) |
| Location: Coarse Location | Yes | **No** | No | Third-Party Advertising |
| Diagnostics: Crash Data | Yes | **No** | No | Analytics |

Everything else: **No**. In particular **Photos or Videos: No** (photos are opened through PHPicker or Files, processed in memory on the device and saved back only where the user chooses), User Content, Audio Data, Contacts, Name, Email, Purchases, Search History, Browsing History, Precise Location, Health and Fitness, Financial Info, Sensitive Info. EXIF/GPS metadata of the user's photos is never read for any purpose other than keeping or stripping it in the exported file.

## Tracking

"Does this app use data for tracking?" **Yes**: Device ID and Advertising Data (the IDFA, only if the user allows tracking in the ATT prompt) are used by Google's advertising SDK for third-party advertising. The app shows the ATT prompt after the UMP consent step. `NSUserTrackingUsageDescription` must be in Info.plist.

## Notes for the person filling the form

- Answer per Apple's definitions: data a third-party SDK (Google Mobile Ads) collects counts as collected by the app.
- Privacy Policy URL: https://ecomswiftllc.github.io/clarivo/privacy/
- If a later version adds analytics, a crash reporter, sign-in, cloud processing or any upload, update this file, `PrivacyInfo.xcprivacy`, the policy page and the ASC answers together before submitting.
