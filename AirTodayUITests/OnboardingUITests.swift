import XCTest

/// Onboarding ends on the alerts step, worded for the person's health answers, and
/// someone who has seen it isn't offered alerts again on the main screen.
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

    /// Welcome → Atmosphere → You → Location (skipped) → Alerts.
    private func goToAlerts(selecting healthAnswer: String? = nil) {
        tapButton("Get Started")
        tapButton("Continue")
        if let healthAnswer { tapButton(healthAnswer) }
        tapButton("Continue")
        tapButton("Skip for Now")
        XCTAssertTrue(app.staticTexts["Get warned when air gets worse"].waitForExistence(timeout: 10), "Alerts step never appeared")
    }

    private func alertsDescription() -> String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Air Today checks in the background")).firstMatch.label
    }

    func testAlertsStepSuggestsUnhealthyWithoutHealthAnswers() {
        goToAlerts()
        XCTAssertTrue(alertsDescription().contains("reaches Unhealthy on the US EPA AQI"), alertsDescription())

        tapButton("Not Now")
        XCTAssertTrue(app.buttons["cityPicker"].waitForExistence(timeout: 20), "Main screen never appeared")
        // The one-time offer is for people updating from 1.1, not for someone who just said no.
        XCTAssertFalse(app.staticTexts["Get warned when air gets worse"].exists)
    }

    func testAlertsStepSuggestsSensitiveLevelWithAHealthAnswer() {
        goToAlerts(selecting: "Asthma or respiratory condition")
        XCTAssertTrue(alertsDescription().contains("reaches Unhealthy for Sensitive Groups"), alertsDescription())
    }
}
