import Foundation
import Testing
@testable import AirTodayCore

@Suite("Best window from the hourly forecast")
struct BestWindowTests {
    /// A modelled reading whose US AQI at each UTC hour comes from `aqi`.
    private func quality(now: Date, aqi: @escaping (_ day: Int, _ hour: Int) -> Int) -> AirQuality {
        Fixture.modelled(Fixture.model(current: now) { time in
            let parts = Fixture.utc.dateComponents([.day, .hour], from: time)
            return Fixture.sample(time, us: aqi(parts.day!, parts.hour!))
        })
    }

    @Test("A Good day all through daylight needs no planning")
    func anyTime() throws {
        let now = Fixture.date(hour: 7)
        let window = try #require(BestWindow.on(now, for: quality(now: now) { _, _ in 30 }, scale: .usEPA, now: now))
        #expect(window.timing == .anyTime)
        #expect(window.headline == "Any time")
        #expect(window.dayName(now: now) == "today")
    }

    @Test("The cleanest two hours left, earliest on a tie")
    func cleanestPair() throws {
        let now = Fixture.date(hour: 7)
        // Moderate all day, cleaner 11:00–13:00 and again 16:00–18:00.
        let q = quality(now: now) { _, hour in [11, 12, 16, 17].contains(hour) ? 45 : 80 }
        let window = try #require(BestWindow.on(now, for: q, scale: .usEPA, now: now))
        #expect(window.start == Fixture.date(hour: 11))
        #expect(window.headline == "11 AM–1 PM")
        #expect(window.level == .good)
        #expect(window.dayWorstLevel == .moderate)
        #expect(window.detail == "The cleanest air left today.")
    }

    @Test("Hours already gone don't count")
    func onlyAhead() throws {
        let now = Fixture.date(hour: 14, minute: 30)
        let q = quality(now: now) { _, hour in hour < 10 ? 20 : (hour >= 19 ? 60 : 90) }
        let window = try #require(BestWindow.on(now, for: q, scale: .usEPA, now: now))
        // 14:00 is still under way, but the morning has passed.
        #expect(window.start == Fixture.date(hour: 19))
        #expect(window.headline == "7–9 PM")
    }

    @Test("After dark, the next window is tomorrow's")
    func tomorrow() throws {
        let now = Fixture.date(hour: 20, minute: 10)
        let q = quality(now: now) { day, hour in day == 26 && hour == 6 ? 30 : 70 }
        #expect(BestWindow.on(now, for: q, scale: .usEPA, now: now) == nil)
        let next = try #require(BestWindow.next(for: q, scale: .usEPA, now: now))
        #expect(next.start == Fixture.date(day: 26, hour: 6))
        #expect(next.dayName(now: now) == "tomorrow")
    }

    @Test("A bad day's best window says to keep it brief")
    func badDay() throws {
        let now = Fixture.date(hour: 6)
        let q = quality(now: now) { _, _ in 180 }
        let window = try #require(BestWindow.on(now, for: q, scale: .usEPA, now: now))
        #expect(window.detail == "Little change today — this is as clean as it gets. Even then it's unhealthy — keep it brief.")
    }

    @Test("No forecast, no window")
    func noModel() {
        let now = Fixture.date(hour: 9)
        #expect(BestWindow.next(for: Fixture.station(aqi: 80, at: now), scale: .usEPA, now: now) == nil)
    }

    @Test("Times read in the place's own clock")
    func localTime() {
        // Open-Meteo's hours fall on the place's whole hours: 05:30 UTC is 11:00 in India.
        #expect(BestWindow.format(Fixture.date(hour: 5, minute: 30), Fixture.date(hour: 7, minute: 30), utcOffsetSeconds: 19_800) == "11 AM–1 PM")
    }
}
