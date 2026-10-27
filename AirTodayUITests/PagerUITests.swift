import XCTest

/// Swiping between cities with real touch events. Each swipe must land on exactly
/// the next (or previous) city, and the top-bar city picker must say which.
@MainActor
final class PagerUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Seeded by `-uitest-seed`: the current location, then these three.
    private let cities = ["My Location", "Paris", "Tashkent Chilanzar", "Sydney East"]

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-seed"]
        app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "City picker never appeared")
        assertShowing(0, after: "launch")
    }

    private var picker: XCUIElement { app.buttons["cityPicker"] }

    /// e.g. "Paris, 2 of 4"
    private func pickerValue(for index: Int) -> String {
        "\(cities[index]), \(index + 1) of \(cities.count)"
    }

    private func assertShowing(_ index: Int, after action: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = pickerValue(for: index)
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: picker)], timeout: 8)
        XCTAssertEqual(result, .completed, "After \(action), expected \"\(expected)\" but picker shows \"\(picker.value as? String ?? "nil")\"", file: file, line: line)
    }

    /// A horizontal drag across the middle of the screen. `press` first, so the
    /// touch is down before it moves — XCUITest's flick helpers are sometimes too
    /// short to register as a pan on this simulator.
    private func drag(from startX: CGFloat, to endX: CGFloat, velocity: XCUIGestureVelocity) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.6))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0)
    }

    private func nextCity(_ velocity: XCUIGestureVelocity = .default) { drag(from: 0.85, to: 0.1, velocity: velocity) }
    private func previousCity(_ velocity: XCUIGestureVelocity = .default) { drag(from: 0.15, to: 0.9, velocity: velocity) }

    func testSwipingStepsOneCityAtATime() {
        for target in 1..<cities.count {
            nextCity()
            assertShowing(target, after: "swipe \(target) forward")
        }
        for target in stride(from: cities.count - 2, through: 0, by: -1) {
            previousCity()
            assertShowing(target, after: "swipe back to \(cities[target])")
        }
    }

    func testQuickBackAndForthStaysInStep() {
        // Rapid alternation — the reported case.
        for round in 0..<4 {
            nextCity(.fast)
            assertShowing(1, after: "fast swipe forward, round \(round)")
            previousCity(.fast)
            assertShowing(0, after: "fast swipe back, round \(round)")
        }
    }

    func testCityMenuListsEveryCityAndJumps() {
        // Every city is listed by name, with its reading, so dots aren't the only clue.
        for (target, name) in [(2, cities[2]), (0, cities[0]), (3, cities[3])] {
            picker.tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) isn't in the city menu")
            for other in cities {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", other)).firstMatch.exists, "\(other) missing from the menu")
            }
            item.tap()
            assertShowing(target, after: "choosing \(name) from the menu")
        }
    }

    /// Add City… opens the search sheet, and typing a city lists its stations. On a Mac
    /// the sheet has a plain text field instead of the system search bar, which quits
    /// the iPad app there — run this on My Mac (Designed for iPad) to cover that.
    func testAddCitySearchListsStations() {
        picker.tap()
        let addCity = app.buttons["Add City…"]
        XCTAssertTrue(addCity.waitForExistence(timeout: 5), "Add City… isn't in the city menu")
        addCity.tap()

        let prompt = "Search cities or stations"
        let searchBar = app.searchFields.firstMatch
        let macField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", prompt, prompt)).firstMatch
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5) || macField.waitForExistence(timeout: 5), "The search sheet has no search field")
        let field = searchBar.exists ? searchBar : macField
        field.tap()
        field.typeText("Paris")

        let station = app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'paris'")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 20), "Searching for Paris listed no stations")
    }
}
