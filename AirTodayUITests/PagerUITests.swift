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
        // What VoiceOver hears: the value, or in a vertical bar (iPhone Duo), which keeps
        // only a label, the end of the label.
        let predicate = NSPredicate(format: "value == %@ OR label ENDSWITH %@", expected, ", \(expected)")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: picker)], timeout: 8)
        XCTAssertEqual(result, .completed, "After \(action), expected \"\(expected)\" but picker shows label \"\(picker.label)\", value \"\(picker.value as? String ?? "nil")\"", file: file, line: line)
    }

    /// A horizontal drag across the middle of the screen. `press` first, so the
    /// touch is down before it moves — XCUITest's flick helpers are sometimes too
    /// short to register as a pan on this simulator.
    ///
    /// When the hero sits beside the cards, the drag crosses the top of the page (the
    /// place name, then Activities): lower down, the forecast chart scrubs on a horizontal
    /// drag, and a drag kept to the hero pane is under half a page.
    ///
    /// Placed on the window, not the app: on iPhone Duo's inner display XCUITest gives the
    /// app the display's native portrait frame while the window is landscape, so points
    /// placed on the app land in the wrong spot (checked on the simulator).
    private func drag(from startX: CGFloat, to endX: CGFloat, velocity: XCUIGestureVelocity) {
        let window = app.windows.firstMatch
        let y: CGFloat = app.cardsScrollView?.identifier == "place.panes" ? 0.15 : 0.6
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: y))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: y))
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

    /// Hero and cards share the page by the room it has, not by device: one column on a
    /// phone-width page, side by side where two card columns fit (iPad, the inner display
    /// of iPhone Duo). Side by side, the first card is in view beside the reading.
    func testPlaceLayoutFollowsTheRoomOnThePage() {
        XCTAssertTrue(app.waitForReading(), "No reading loaded")
        let window = app.windows.firstMatch.frame
        guard let cards = app.cardsScrollView else { return XCTFail("No page scroll view on screen") }
        // Two of the narrowest card columns (343 pt) and the gap between them (24 pt).
        let fitsTwoColumns = window.width >= 2 * 343 + 24
        XCTAssertEqual(cards.identifier, fitsTwoColumns ? "place.panes" : "place.column", "Layout for a \(Int(window.width)) pt wide window")
        guard fitsTwoColumns else { return }
        XCTAssertGreaterThan(cards.frame.minX, window.width * 0.3, "The cards should sit beside the hero, not under it")
        // The gap between the panes (24 pt) is centred on the window, where an iPhone Duo's
        // fold is, whether or not the system reports the fold; the cards start just past it.
        XCTAssertEqual(cards.frame.minX, window.midX + 12, accuracy: 12, "The gap between the panes should sit at the middle of the window")
        let activities = app.staticTexts.matching(NSPredicate(format: "label == 'Activities'")).allElementsBoundByIndex
            .first { $0.frame.minX >= cards.frame.minX && $0.frame.minX < window.width }
        XCTAssertNotNil(activities, "Activities should be in view without scrolling")
        if let activities { XCTAssertLessThan(activities.frame.maxY, window.height, "Activities should be in view without scrolling") }
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
}
