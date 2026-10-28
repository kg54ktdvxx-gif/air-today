import XCTest

extension XCUIApplication {
    /// Waits for the page's source line, which appears once a reading has loaded.
    func waitForReading(timeout: TimeInterval = 40) -> Bool {
        staticTexts.matching(NSPredicate(format: "label CONTAINS ' station · ' OR label BEGINSWITH 'Area estimate'"))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    /// Drags the page up in small steps until the card titled `title` sits just
    /// under the top bar — or, for the last card, until the page stops moving with it
    /// on screen through three drags. Small held drags, so there's no momentum to overshoot.
    func scroll(toCard title: String) -> Bool {
        let window = windows.firstMatch
        let height = window.frame.height
        // Under the top bar, a header is hidden by it. Where there's no bar across the top
        // (iPhone Duo puts the controls in a side bar), only the status bar is up there.
        let picker = buttons["cityPicker"]
        let barBottom = picker.exists && picker.frame.midX < window.frame.midX ? picker.frame.maxY : height * 0.05
        // Positions after recent drags: the page has stopped only when the last three agree.
        var recent: [CGFloat] = []
        for _ in 0..<30 {
            // The pager keeps neighbouring cities' pages loaded; use the one on screen.
            let header = staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
                .first { $0.frame.minX >= 0 && $0.frame.minX < window.frame.width }
            if let header, header.frame.minY > barBottom, header.frame.minY < height * 0.3 { return true }
            if let header {
                recent = Array((recent + [header.frame.minY]).suffix(3))
                // On screen and still through three drags: the page can't take it any higher
                // (the last card, or cards that all fit beside the hero).
                if header.frame.minY > barBottom, header.frame.minY < height * 0.85,
                   recent.count == 3, Set(recent).count == 1 { return true }
            }
            // Drag where the cards scroll: beside the hero, when the two share the page.
            let x = cardsScrollView.map { $0.frame.midX / window.frame.width } ?? 0.5
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.7))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        return false
    }

    /// The scroll view holding the cards of the page on screen. Its identifier names the
    /// layout: "place.column" (hero above the cards) or "place.panes" (side by side).
    var cardsScrollView: XCUIElement? {
        let window = windows.firstMatch
        return scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH 'place.'")).allElementsBoundByIndex
            .first { $0.frame.maxX > 0 && $0.frame.minX < window.frame.width }
    }
}

extension XCTestCase {
    /// Keeps a screenshot of the whole screen in the result bundle: the screen the app is
    /// on. iPhone Duo has two, and `XCUIScreen.main` is the outer one, black while the
    /// device is open; the app's window is the size of the screen showing it.
    @MainActor
    func snap(_ name: String) {
        // Content rises in over about a second; let it land before the screenshot.
        RunLoop.current.run(until: Date().addingTimeInterval(1.6))
        let window = XCUIApplication().windows.firstMatch.frame.size
        let screenshots = XCUIScreen.screens.map { $0.screenshot() }
        let showing = screenshots.first { abs($0.image.size.width - window.width) < 1 && abs($0.image.size.height - window.height) < 1 }
        let shot = XCTAttachment(screenshot: showing ?? XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
