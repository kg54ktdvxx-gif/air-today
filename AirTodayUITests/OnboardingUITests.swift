import XCTest

/// Onboarding ends on the location and alerts step, with the alert level worded for
/// the person's health answers, and someone who has seen it isn't offered alerts again
/// on the main screen.
@MainActor
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-onboarding"]
        app.launch()
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \"\(label)\" button")
        button.tap()
    }

    /// Welcome → You → Location and alerts.
    private func goToSetup(selecting healthAnswer: String? = nil) {
        tapButton("Get Started")
        if let healthAnswer { tapButton(healthAnswer) }
        tapButton("Continue")
        XCTAssertTrue(app.staticTexts["Location and alerts"].waitForExistence(timeout: 10), "Location and alerts step never appeared")
    }

    private var alertsTile: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alert me at")).firstMatch
    }

    func testAlertsSuggestUnhealthyWithoutHealthAnswers() {
        goToSetup()
        XCTAssertEqual(alertsTile.label, "Alert me at Unhealthy")

        tapButton("Done")
        XCTAssertTrue(app.buttons["cityPicker"].waitForExistence(timeout: 20), "Main screen never appeared")
        // The one-time offer is for people updating from 1.1, not for someone who just left alerts off.
        XCTAssertFalse(app.staticTexts["Get warned when air gets worse"].exists)
    }

    func testAlertsSuggestSensitiveLevelWithAHealthAnswer() {
        goToSetup(selecting: "Asthma or respiratory condition")
        XCTAssertEqual(alertsTile.label, "Alert me at Unhealthy for Sensitive Groups")
    }
}
