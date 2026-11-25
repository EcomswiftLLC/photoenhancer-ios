import Foundation

/// When Clarivo may ask for an App Store rating (Apple's `requestReview` only, no custom star screens, no rewards).
///
/// Asked right after a successful export, once the person has made at least 3, and only if all of these hold:
/// (a) the export really saved or shared a result, (b) at least 2 days or 3 sessions since install, (c) no ad shown in the
/// last 60 seconds and no ad or share sheet on screen, (d) not yet asked in this app version and not in the last 120 days,
/// (e) never after an error or a cancel.
struct ReviewPromptPolicy: Equatable {
    static let minimumExports = 3
    static let minimumDaysSinceInstall: Double = 2
    static let minimumSessions = 3
    static let adQuietSeconds: TimeInterval = 60
    static let minimumDaysBetweenPrompts: Double = 120

    enum Outcome: Equatable { case saved, shared, failed, cancelled }

    struct State: Equatable {
        var successfulExports: Int = 0
        var sessions: Int = 0
        var installDate: Date
        var lastPromptDate: Date?
        var lastPromptVersion: String?
        var lastAdShownAt: Date?
    }

    static func shouldPrompt(state: State, outcome: Outcome, now: Date, currentVersion: String, adOrShareSheetOnScreen: Bool) -> Bool {
        // (a) and (e): only right after a real save or share.
        guard outcome == .saved || outcome == .shared else { return false }
        guard state.successfulExports >= minimumExports else { return false }
        // (b)
        let days = now.timeIntervalSince(state.installDate) / 86_400
        guard days >= minimumDaysSinceInstall || state.sessions >= minimumSessions else { return false }
        // (c)
        if adOrShareSheetOnScreen { return false }
        if let ad = state.lastAdShownAt, now.timeIntervalSince(ad) < adQuietSeconds { return false }
        // (d)
        if state.lastPromptVersion == currentVersion { return false }
        if let last = state.lastPromptDate, now.timeIntervalSince(last) / 86_400 < minimumDaysBetweenPrompts { return false }
        return true
    }
}

/// Keeps the counters for `ReviewPromptPolicy` in UserDefaults.
final class ReviewPromptTracker {
    static let shared = ReviewPromptTracker()

    private let defaults: UserDefaults
    private let clock: () -> Date

    enum Key {
        static let exports = "cv.review.exports"
        static let sessions = "cv.review.sessions"
        static let install = "cv.review.installDate"
        static let lastPrompt = "cv.review.lastPromptDate"
        static let lastVersion = "cv.review.lastPromptVersion"
        static let lastAd = "cv.review.lastAdShownAt"
    }

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        if defaults.object(forKey: Key.install) == nil {
            defaults.set(clock().timeIntervalSince1970, forKey: Key.install)
        }
    }

    var state: ReviewPromptPolicy.State {
        func date(_ key: String) -> Date? {
            guard defaults.object(forKey: key) != nil else { return nil }
            return Date(timeIntervalSince1970: defaults.double(forKey: key))
        }
        return ReviewPromptPolicy.State(
            successfulExports: defaults.integer(forKey: Key.exports),
            sessions: defaults.integer(forKey: Key.sessions),
            installDate: date(Key.install) ?? clock(),
            lastPromptDate: date(Key.lastPrompt),
            lastPromptVersion: defaults.string(forKey: Key.lastVersion),
            lastAdShownAt: date(Key.lastAd)
        )
    }

    func recordSession() {
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
    }

    func recordAdShown() {
        defaults.set(clock().timeIntervalSince1970, forKey: Key.lastAd)
    }

    /// Records the outcome of an export and returns true when the rating prompt should be shown now.
    /// The caller shows it with `requestReview` and then calls `recordPromptShown`.
    @discardableResult
    func recordExport(_ outcome: ReviewPromptPolicy.Outcome, adOrShareSheetOnScreen: Bool, version: String = AppInfo.version) -> Bool {
        if outcome == .saved || outcome == .shared {
            defaults.set(defaults.integer(forKey: Key.exports) + 1, forKey: Key.exports)
        }
        return ReviewPromptPolicy.shouldPrompt(state: state, outcome: outcome, now: clock(), currentVersion: version, adOrShareSheetOnScreen: adOrShareSheetOnScreen)
    }

    func recordPromptShown(version: String = AppInfo.version) {
        defaults.set(clock().timeIntervalSince1970, forKey: Key.lastPrompt)
        defaults.set(version, forKey: Key.lastVersion)
    }
}

/// App identity and links.
enum AppInfo {
    /// The App Store id, set once the App Store record exists. While empty, "Rate this app" uses the system prompt.
    static let appStoreID = ""

    static let privacyURL = URL(string: "https://ecomswiftllc.github.io/clarivo/privacy/")!
    static let termsURL = URL(string: "https://ecomswiftllc.github.io/clarivo/terms/")!
    static let supportURL = URL(string: "https://ecomswiftllc.github.io/clarivo/support/")!

    static func writeReviewURL(appStoreID: String = appStoreID) -> URL? {
        let id = appStoreID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
