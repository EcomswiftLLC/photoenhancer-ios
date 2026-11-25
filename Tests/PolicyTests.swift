import XCTest
@testable import Clarivo

final class ReviewPromptPolicyTests: XCTestCase {
    private let install = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// A state that passes every rule, to be broken one rule at a time.
    private func eligible() -> ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(successfulExports: 3, sessions: 1, installDate: install, lastPromptDate: nil, lastPromptVersion: nil, lastAdShownAt: nil)
    }

    private var now: Date { install.addingTimeInterval(3 * day) }

    private func ask(_ state: ReviewPromptPolicy.State, _ outcome: ReviewPromptPolicy.Outcome = .saved, at time: Date? = nil,
                     version: String = "1.0.0", onScreen: Bool = false) -> Bool {
        ReviewPromptPolicy.shouldPrompt(state: state, outcome: outcome, now: time ?? now, currentVersion: version, adOrShareSheetOnScreen: onScreen)
    }

    func testEligibleAfterTheThirdExport() {
        XCTAssertTrue(ask(eligible()))
        XCTAssertTrue(ask(eligible(), .shared))
        var two = eligible()
        two.successfulExports = 2
        XCTAssertFalse(ask(two), "not before the 3rd export")
    }

    /// (a) only after a real save or share, (e) never after an error or a cancel.
    func testRuleAAndENeedASuccess() {
        XCTAssertFalse(ask(eligible(), .failed))
        XCTAssertFalse(ask(eligible(), .cancelled))
    }

    /// (b) 2 days or 3 sessions since install, boundaries included.
    func testRuleBDaysOrSessions() {
        var state = eligible()
        state.sessions = 2
        XCTAssertFalse(ask(state, at: install.addingTimeInterval(2 * day - 1)))
        XCTAssertTrue(ask(state, at: install.addingTimeInterval(2 * day)))
        state.sessions = 3
        XCTAssertTrue(ask(state, at: install.addingTimeInterval(60)), "3 sessions are enough on day one")
    }

    /// (c) not within 60 s of an ad, never while an ad or a share sheet is on screen.
    func testRuleCAdQuietTime() {
        var state = eligible()
        state.lastAdShownAt = now.addingTimeInterval(-59)
        XCTAssertFalse(ask(state))
        state.lastAdShownAt = now.addingTimeInterval(-60)
        XCTAssertTrue(ask(state))
        XCTAssertFalse(ask(eligible(), onScreen: true))
    }

    /// (d) once per version and at most every 120 days.
    func testRuleDOncePerVersionAnd120Days() {
        var state = eligible()
        state.lastPromptVersion = "1.0.0"
        state.lastPromptDate = now.addingTimeInterval(-200 * day)
        XCTAssertFalse(ask(state, version: "1.0.0"), "same version")
        XCTAssertTrue(ask(state, version: "1.1.0"))
        state.lastPromptDate = now.addingTimeInterval(-119 * day)
        XCTAssertFalse(ask(state, version: "1.1.0"), "119 days is too soon")
        state.lastPromptDate = now.addingTimeInterval(-120 * day)
        XCTAssertTrue(ask(state, version: "1.1.0"))
    }

    func testTrackerCountsAndRecords() {
        let suite = "ReviewTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var clock = install
        let tracker = ReviewPromptTracker(defaults: defaults, clock: { clock })
        tracker.recordSession()
        XCTAssertFalse(tracker.recordExport(.saved, adOrShareSheetOnScreen: false, version: "1.0.0"))
        XCTAssertFalse(tracker.recordExport(.failed, adOrShareSheetOnScreen: false, version: "1.0.0"))
        XCTAssertFalse(tracker.recordExport(.shared, adOrShareSheetOnScreen: false, version: "1.0.0"))
        XCTAssertEqual(tracker.state.successfulExports, 2, "failures are not counted")
        clock = install.addingTimeInterval(3 * day)
        XCTAssertFalse(tracker.recordExport(.cancelled, adOrShareSheetOnScreen: false, version: "1.0.0"))
        tracker.recordAdShown()
        XCTAssertFalse(tracker.recordExport(.saved, adOrShareSheetOnScreen: false, version: "1.0.0"), "an ad was just shown")
        clock = clock.addingTimeInterval(61)
        XCTAssertTrue(tracker.recordExport(.saved, adOrShareSheetOnScreen: false, version: "1.0.0"))
        tracker.recordPromptShown(version: "1.0.0")
        XCTAssertFalse(tracker.recordExport(.saved, adOrShareSheetOnScreen: false, version: "1.0.0"))
        XCTAssertEqual(tracker.state.lastPromptVersion, "1.0.0")
        defaults.removePersistentDomain(forName: suite)
    }

    func testWriteReviewURL() {
        XCTAssertNil(AppInfo.writeReviewURL(appStoreID: ""))
        XCTAssertNil(AppInfo.writeReviewURL(appStoreID: "abc"))
        XCTAssertEqual(AppInfo.writeReviewURL(appStoreID: "6836546948")?.absoluteString, "https://apps.apple.com/app/id6836546948?action=write-review")
        XCTAssertEqual(AppInfo.appStoreID, "", "set once the App Store record exists")
        XCTAssertEqual(AppInfo.privacyURL.absoluteString, "https://ecomswiftllc.github.io/clarivo/privacy/")
    }
}

final class AdsPolicyTests: XCTestCase {
    func testRewardedGraceCountsFromTheEndOfTheExport() {
        var policy = RewardedPolicy()
        let start = Date()
        policy.didEarnReward(now: start)
        // A long batch: ten minutes later it is still the export the ad paid for.
        XCTAssertFalse(policy.shouldOffer(adReady: true, now: start.addingTimeInterval(600)))
        let end = start.addingTimeInterval(660)
        policy.exportDidEnd(now: end)
        XCTAssertFalse(policy.shouldOffer(adReady: true, now: end.addingTimeInterval(119)))
        XCTAssertTrue(policy.shouldOffer(adReady: true, now: end.addingTimeInterval(121)))
    }

    func testNoAdMeansExportNow() {
        let policy = RewardedPolicy()
        XCTAssertEqual(policy.decision(adsReady: false, adReady: true, reloadInFlightAfterEarlyClose: false), .exportNow)
        XCTAssertEqual(policy.decision(adsReady: true, adReady: false, reloadInFlightAfterEarlyClose: false), .exportNow)
        XCTAssertEqual(policy.decision(adsReady: true, adReady: true, reloadInFlightAfterEarlyClose: false), .offerAd)
        XCTAssertEqual(policy.decision(adsReady: true, adReady: false, reloadInFlightAfterEarlyClose: true), .waitForAd)
    }

    func testUnitIDNormalisation() {
        XCTAssertNil(AdsConfiguration.normalizedUnitID(nil))
        XCTAssertNil(AdsConfiguration.normalizedUnitID(""))
        XCTAssertNil(AdsConfiguration.normalizedUnitID("  "))
        XCTAssertNil(AdsConfiguration.normalizedUnitID("$(ADMOB_BANNER_UNIT_ID)"))
        XCTAssertNil(AdsConfiguration.normalizedUnitID(42))
        XCTAssertEqual(AdsConfiguration.normalizedUnitID(" ca-app-pub-1/2 "), "ca-app-pub-1/2")
    }

    func testDebugBuildUsesGoogleTestIDs() {
        XCTAssertEqual(AdsConfiguration.bannerKey, "CVBannerAdUnitID")
        XCTAssertEqual(AdsConfiguration.rewardedKey, "CVRewardedAdUnitID")
        XCTAssertEqual(AdsConfiguration.bannerUnitID, "ca-app-pub-3940256099942544/2435281174")
        XCTAssertEqual(AdsConfiguration.rewardedUnitID, "ca-app-pub-3940256099942544/1712485313")
        XCTAssertTrue(AdsConfiguration.testDeviceIdentifiers.isEmpty, "never commit a test device id")
        XCTAssertEqual(AdsRequestPolicy.maxContentRating, .general)
    }

    /// Release must carry real ids, never Google's test publisher (release.yml also refuses them).
    func testReleaseConfigHasRealAdMobIDs() throws {
        let text = try XCTUnwrap(Repo.text("Config/Release.xcconfig"), "Config/Release.xcconfig not readable from \(Repo.root.path)")
        func value(_ key: String) -> String? {
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == key { return parts[1] }
            }
            return nil
        }
        let app = try XCTUnwrap(value("ADMOB_APP_ID"))
        let banner = try XCTUnwrap(value("ADMOB_BANNER_UNIT_ID"))
        let rewarded = try XCTUnwrap(value("ADMOB_REWARDED_UNIT_ID"))
        for id in [app, banner, rewarded] {
            XCTAssertFalse(id.contains("3940256099942544"), "Google test id in Release: \(id)")
        }
        XCTAssertNotNil(app.range(of: #"^ca-app-pub-\d{16}~\d{10}$"#, options: .regularExpression), app)
        XCTAssertNotNil(banner.range(of: #"^ca-app-pub-\d{16}/\d{10}$"#, options: .regularExpression), banner)
        XCTAssertNotNil(rewarded.range(of: #"^ca-app-pub-\d{16}/\d{10}$"#, options: .regularExpression), rewarded)
        XCTAssertNotEqual(banner, rewarded)
        // Not Lumotion's ids (the shell was copied from it).
        XCTAssertFalse(app.contains("9505075957"), "Release still has Lumotion's AdMob app id")
    }

    func testDebugConfigKeepsTestIDs() throws {
        let text = try XCTUnwrap(Repo.text("Config/Debug.xcconfig"))
        XCTAssertTrue(text.contains("ca-app-pub-3940256099942544~1458002511"))
    }

    func testInfoPlistAndPrivacyManifest() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNotNil(info["NSPhotoLibraryAddUsageDescription"])
        XCTAssertNotNil(info["NSUserTrackingUsageDescription"])
        XCTAssertNil(info["NSCameraUsageDescription"])
        XCTAssertNil(info["NSPhotoLibraryUsageDescription"], "the picker needs no read permission")
        XCTAssertNil(info["NSLocationWhenInUseUsageDescription"])
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Clarivo")
        XCTAssertGreaterThan((info["SKAdNetworkItems"] as? [Any])?.count ?? 0, 10)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((manifest["NSPrivacyTrackingDomains"] as? [Any] ?? []).isEmpty)
    }
}
