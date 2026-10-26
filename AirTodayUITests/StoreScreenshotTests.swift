import XCTest

/// App Store screenshots. Not part of the regular suite's purpose — run on the
/// screenshot simulators (6.9" iPhone, 13" iPad) with the status bar overridden and
/// the location set, then export the attachments from the result bundle.
@MainActor
final class StoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for the page's source line, which appears once a reading has loaded.
    private func waitForReading(timeout: TimeInterval = 40) {
        let source = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' station · ' OR label BEGINSWITH 'Area estimate'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: timeout), "No reading loaded")
    }

    /// Drags the page up in small steps until the card titled `title` sits just
    /// under the top bar. Small held drags, so there's no momentum to overshoot.
    private func scroll(toCard title: String) {
        let window = app.windows.firstMatch
        let height = window.frame.height
        for _ in 0..<20 {
            // The pager keeps neighbouring cities' pages loaded; use the one on screen.
            let header = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
                .first { $0.frame.minX >= 0 && $0.frame.minX < window.frame.width }
            if let header, header.frame.minY > height * 0.12, header.frame.minY < height * 0.3 { return }
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("Couldn't scroll \(title) into place")
    }

    private func choose(city: String) {
        app.buttons["cityPicker"].tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", city)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "\(city) not in the menu")
        item.tap()
    }

    func testMainScreens() {
        app.launchArguments += ["-uitest-seed", "-uitest-effects"]
        app.launch()
        XCTAssertTrue(app.buttons["cityPicker"].waitForExistence(timeout: 30))
        waitForReading()
        snap("01_home")

        choose(city: "Tashkent")
        waitForReading()
        snap("02_polluted")

        choose(city: "My Location")
        waitForReading()
        scroll(toCard: "Activities")
        snap("03_activities")
        scroll(toCard: "Forecast")
        snap("04_forecast")

        // Back to the top: the number is in the hero.
        for _ in 0..<4 { app.swipeDown() }
        let number = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Air Quality Index'")).firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 10))
        number.tap()
        XCTAssertTrue(app.staticTexts["Bands"].waitForExistence(timeout: 10))
        snap("05_scale")
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Places"].waitForExistence(timeout: 10))
        snap("06_settings")
    }

    func testAlertsStep() {
        app.launchArguments += ["-uitest-onboarding", "-uitest-effects"]
        app.launch()
        for label in ["Get Started", "Continue"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 20), "No \(label)")
            button.tap()
        }
        XCTAssertTrue(app.staticTexts["Location and alerts"].waitForExistence(timeout: 20))
        snap("07_alerts")
    }
}
