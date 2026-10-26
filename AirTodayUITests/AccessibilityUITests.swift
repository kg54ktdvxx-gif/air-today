import XCTest

/// Apple's accessibility audit — labels, traits, hit areas, clipped text — on the hero,
/// each card and each onboarding step, at the default text size and at the largest
/// accessibility size. Screenshots are kept in the result bundle for what the audit
/// can't judge here:
/// - contrast: every surface is translucent glass or text over a photo, and the audit
///   samples the pixels behind the blur, so it fails even white headings on dark glass;
/// - Dynamic Type: it flags the chart, hero and later-days row, which stop growing on
///   purpose (each says why), and the rest is checked in the `_largest` shots.
/// The forecast chart's own labels (bands, "Now", the peak, the hours) are drawn text
/// with no element of their own: the chart is one element with a spoken summary of
/// the same values, so those flags are skipped.
@MainActor
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        // Keep going after an issue, so one run reports every screen's.
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Fails with each issue the audit finds on what's on screen now, naming the screen.
    private func audit(_ screen: String) {
        do {
            try app.performAccessibilityAudit(for: .all.subtracting([.contrast, .dynamicType])) { issue in
                if issue.auditType == .elementDetection, issue.element == nil, self.chartIsOnScreen { return true }
                let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\"" } ?? "no element"
                XCTFail("\(screen): \(issue.compactDescription) — \(element). \(issue.detailedDescription)")
                return true
            }
        } catch {
            XCTFail("\(screen): audit didn't run — \(error)")
        }
    }

    private var chartIsOnScreen: Bool {
        let chart = app.descendants(matching: .any)["Hourly forecast, today and tomorrow"].firstMatch
        return chart.exists && app.windows.firstMatch.frame.intersects(chart.frame)
    }

    private func checkMainScreen(_ suffix: String) {
        XCTAssertTrue(app.buttons["cityPicker"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.waitForReading(), "No reading loaded")
        snap("hero\(suffix)")
        audit("Hero\(suffix)")
        for card in ["Activities", "Forecast", "Details"] {
            XCTAssertTrue(app.scroll(toCard: card), "Couldn't scroll \(card) into place")
            snap("\(card.lowercased())\(suffix)")
            audit("\(card)\(suffix)")
        }
    }

    private func checkOnboarding(_ suffix: String) {
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 30))
        snap("welcome\(suffix)")
        audit("Welcome\(suffix)")
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["Tailor your guidance"].waitForExistence(timeout: 10))
        snap("you\(suffix)")
        audit("You\(suffix)")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Location and alerts"].waitForExistence(timeout: 10))
        snap("setup\(suffix)")
        audit("Location and alerts\(suffix)")
    }

    func testMainScreen() {
        app.launchArguments += ["-uitest-seed"]
        app.launch()
        checkMainScreen("")
    }

    func testMainScreenAtLargestText() {
        app.launchArguments += ["-uitest-seed"] + Self.largestText
        app.launch()
        checkMainScreen("_largest")
    }

    func testOnboarding() {
        app.launchArguments += ["-uitest-onboarding"]
        app.launch()
        checkOnboarding("")
    }

    func testOnboardingAtLargestText() {
        app.launchArguments += ["-uitest-onboarding"] + Self.largestText
        app.launch()
        checkOnboarding("_largest")
    }
}
