# Clarivo: AdMob ids

Created 2026-11-25 in the Ecom Swift AdMob account (publisher `pub-8621573128492952`), through the owner's logged-in Chrome. No payment or tax data was entered. (The separate Android app "Photo Enhancer HD - Clarity", `~2657759329`, is a different product and is not used here.)

| Item | Name in AdMob | Id |
|---|---|---|
| iOS app (not yet in the App Store, answered "No" to listed) | Photo Enhancer HD: Clarivo | `ca-app-pub-8621573128492952~9170509399` |
| Banner ad unit | Clarivo Home Banner | `ca-app-pub-8621573128492952/4919312734` |
| Rewarded ad unit (reward: 1 Reward) | Clarivo Export Rewarded | `ca-app-pub-8621573128492952/6826969978` |

- `Config/Release.xcconfig` holds these three ids (`ADMOB_APP_ID`, `ADMOB_BANNER_UNIT_ID`, `ADMOB_REWARDED_UNIT_ID`). `Config/Debug.xcconfig` keeps Google's public test ids. `.github/workflows/release.yml` refuses test ids in a release.
- Status in AdMob: "Requires review" (limited ad serving) until the App Store listing is linked. New units may take up to an hour to serve ads. After the app is live: AdMob > Apps > Photo Enhancer HD: Clarivo > Add store.
- `app-ads.txt` already lists this publisher id at https://ecomswiftllc.github.io/app-ads.txt (shared by every app of the account). Set the App Store "Marketing URL"/developer website to https://ecomswiftllc.github.io/clarivo/ so the match works.
- Recommended in AdMob: maximum ad content rating General or Parental Guidance and block sensitive categories, to match a 4+ age rating.
- Policy reminders (HARD): banner on Home only, never over the compare view or editing controls; the rewarded ad is opt-in and shown only after the finished result is visible; when no ad is ready the export is free; one ad per batch.
