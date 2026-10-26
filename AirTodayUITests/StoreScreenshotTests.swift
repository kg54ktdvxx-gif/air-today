import XCTest

/// App Store screenshots. Not part of the regular suite's purpose — run on the
/// screenshot simulators (6.9" iPhone, 13" iPad) with the status bar overridden and
/// the location set, then export the attachments from the result bundle.
@MainActor
final class StoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        // The screenshot sets are portrait; a simulator can remember landscape.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
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
        XCTAssertTrue(app.waitForReading(), "No reading loaded")
        snap("01_home")

        choose(city: "Tashkent")
        XCTAssertTrue(app.waitForReading(), "No reading loaded")
        snap("02_polluted")

        choose(city: "My Location")
        XCTAssertTrue(app.waitForReading(), "No reading loaded")
        XCTAssertTrue(app.scroll(toCard: "Activities"), "Couldn't scroll Activities into place")
        snap("03_activities")
        XCTAssertTrue(app.scroll(toCard: "Forecast"), "Couldn't scroll Forecast into place")
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
