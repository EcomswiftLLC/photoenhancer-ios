import SwiftUI
import UIKit

@main
struct ClarivoApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CVAppearance.configure()
        // Exports from an earlier session are no longer being shared, and results older than a week go.
        ExportRenderer.clearExports()
        HistoryStore.shared.pruneOld()
        ReviewPromptTracker.shared.recordSession()
        MemoryWatcher.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(ads)
                .preferredColorScheme(.dark)
                .tint(CV.Palette.glacier)
        }
        .onChange(of: scenePhase) { old, new in
            if old == .background && new != .background { appState.returnedFromBackground() }
            if new == .background { appState.wentToBackground() }
        }
    }
}

final class AppState: ObservableObject {
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "cv.hasOnboarded") }
    }
    private var backgroundedAt: Date?

    init() {
        hasOnboarded = UserDefaults.standard.bool(forKey: "cv.hasOnboarded")
    }

    func wentToBackground() { backgroundedAt = Date() }

    /// A return after 30 minutes away counts as a new session for the rating rules.
    func returnedFromBackground() {
        if let at = backgroundedAt, Date().timeIntervalSince(at) > 30 * 60 {
            ReviewPromptTracker.shared.recordSession()
        }
        backgroundedAt = nil
    }
}

/// Cancels running work when iOS warns about memory, so the app explains instead of being closed.
final class MemoryWatcher {
    static let shared = MemoryWatcher()
    private var observer: NSObjectProtocol?
    private let lock = NSLock()
    private var tokens: [UUID: CancelToken] = [:]

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWarning()
        }
    }

    /// Registers running work; returns an id for `unregister`.
    func register(_ token: CancelToken) -> UUID {
        let id = UUID()
        lock.lock(); tokens[id] = token; lock.unlock()
        return id
    }

    func unregister(_ id: UUID) {
        lock.lock(); tokens[id] = nil; lock.unlock()
    }

    func handleWarning() {
        lock.lock()
        let running = Array(tokens.values)
        lock.unlock()
        running.forEach { $0.cancelForMemory() }
        if !running.isEmpty { BundleModelProvider.shared.unloadAll() }
    }
}

/// Chooses between the welcome screen and Home, and starts ads only after the first frame and only once the person is
/// past the welcome screen. Launch is never blocked by ads.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ads: AdsManager
    @State private var adsStarted = false

    var body: some View {
        ZStack {
            #if DEBUG
            if let screen = DebugScreens.requested {
                DebugScreens.view(for: screen)
            } else {
                content
            }
            #else
            content
            #endif
        }
        .cvScreen()
        .task(id: appState.hasOnboarded) { await startAdsWhenReady() }
        .onChange(of: ads.adsReady) { _, ready in
            if ready { RewardedGate.shared.preloadIfPossible() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.hasOnboarded {
            HomeView().transition(.opacity)
        } else {
            OnboardingView().transition(.opacity)
        }
    }

    private func startAdsWhenReady() async {
        if AppFlags.noAds { return }
        #if DEBUG
        if DebugScreens.requested != nil { return }
        #endif
        guard appState.hasOnboarded, !adsStarted else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled, !adsStarted else { return }
        adsStarted = true
        await ads.start()
    }
}

enum AppFlags {
    /// Debug builds only: `-cvNoAds YES` (UI tests and store captures) keeps Google's consent form and ads away.
    static var noAds: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "cvNoAds")
        #else
        return false
        #endif
    }
}
