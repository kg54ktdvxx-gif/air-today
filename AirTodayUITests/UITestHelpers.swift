import XCTest

extension XCUIApplication {
    /// Waits for the page's source line, which appears once a reading has loaded.
    func waitForReading(timeout: TimeInterval = 40) -> Bool {
        staticTexts.matching(NSPredicate(format: "label CONTAINS ' station · ' OR label BEGINSWITH 'Area estimate'"))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    /// Drags the page up in small steps until the card titled `title` sits just
    /// under the top bar — or, for the last card, until the page stops moving with it
    /// on screen. Small held drags, so there's no momentum to overshoot.
    func scroll(toCard title: String) -> Bool {
        let window = windows.firstMatch
        let height = window.frame.height
        var lastY: CGFloat?
        for _ in 0..<30 {
            // The pager keeps neighbouring cities' pages loaded; use the one on screen.
            let header = staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
                .first { $0.frame.minX >= 0 && $0.frame.minX < window.frame.width }
            if let header, header.frame.minY > height * 0.12, header.frame.minY < height * 0.3 { return true }
            if let header, header.frame.minY > height * 0.12, header.frame.minY < height * 0.85,
               header.frame.minY == lastY { return true }
            lastY = header?.frame.minY
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        return false
    }
}

extension XCTestCase {
    /// Keeps a screenshot of the whole screen in the result bundle.
    @MainActor
    func snap(_ name: String) {
        // Content rises in over about a second; let it land before the screenshot.
        RunLoop.current.run(until: Date().addingTimeInterval(1.6))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
