import XCTest
import UIKit

/// Opens each screen on a device rotated to landscape and saves a screenshot of it. Each test fails when the window does
/// not end up wider than it is tall, so a rotation that silently did not happen never passes as a landscape check.
/// Run by the `ipad-landscape` and `iphone-landscape` CI jobs.
final class LandscapeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// The simulator hands back its portrait frame buffer with a landscape picture lying on its side, so turn it upright.
    private func uprightScreenshot() -> UIImage {
        let source: UIImage = XCUIScreen.main.screenshot().image
        let sourceFormat = UIGraphicsImageRendererFormat()
        sourceFormat.scale = source.scale
        let image: UIImage = UIGraphicsImageRenderer(size: source.size, format: sourceFormat).image { _ in source.draw(at: .zero) }
        guard image.size.height > image.size.width else { return image }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            image.draw(at: .zero)
        }
    }

    private func check(_ screen: String, settle: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchArguments = ["-cvScreen", screen, "-cvNoAds", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "No app window for \(screen)", file: file, line: line)
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, window.frame.width <= window.frame.height {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))

        let frame = window.frame
        let shot = XCTAttachment(image: uprightScreenshot())
        shot.name = "landscape-\(screen)"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertGreaterThan(frame.width, frame.height, "\(screen): window is \(Int(frame.width))x\(Int(frame.height)), not landscape", file: file, line: line)
        XCTAssertTrue(app.state == .runningForeground, "\(screen): app left the foreground", file: file, line: line)
        app.terminate()
    }

    func testOnboarding() { check("onboarding") }
    func testHome() { check("home") }
    func testEnhance() { check("enhance", settle: 12) }
    func testEnhanceTools() { check("enhance-tools", settle: 12) }
    func testExport() { check("export") }
    func testBatch() { check("batch", settle: 12) }
    func testSettings() { check("settings") }
    func testLicences() { check("licenses") }
}

/// Walks the real first-run path in portrait: welcome screen, Get started, Home, Settings and back, then a sample
/// opens in the Enhance workspace and closes again.
final class FirstRunUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testWelcomeThenHomeThenSample() {
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Ask App Not to Track", "Don’t Allow", "Don't Allow", "Not Now", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = XCUIApplication()
        // The launch argument overrides the stored value, so every run starts on the welcome screen.
        app.launchArguments = ["-cv.hasOnboarded", "NO", "-cvNoAds", "YES"]
        app.launch()

        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 30), "Welcome screen has no Get started button")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'never leave your device'")).firstMatch.exists, "the privacy card is missing")
        getStarted.tap()

        XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout: 20), "Home has no Choose photos button")
        XCTAssertTrue(app.buttons["Import from Files"].exists, "Home has no Files button")
        XCTAssertTrue(app.buttons["Settings"].exists, "Home has no Settings button")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "Settings has no Done button")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Rate this app'")).firstMatch.exists, "Settings has no Rate this app row")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout: 10))

        // A bundled sample opens the workspace (when the build has samples).
        let sample = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sample for'")).firstMatch
        if sample.waitForExistence(timeout: 10) {
            sample.tap()
            XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 20), "the workspace has no Export button")
            XCTAssertTrue(app.buttons["Close"].exists)
            app.buttons["Close"].tap()
            let discard = app.buttons["Close without saving"]
            if discard.waitForExistence(timeout: 5) { discard.tap() }
            XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout: 10))
        }
    }
}
