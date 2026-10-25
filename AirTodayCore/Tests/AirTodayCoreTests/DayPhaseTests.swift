import Foundation
import Testing
@testable import AirTodayCore

@Suite("Day phase")
struct DayPhaseTests {
    // London on midsummer's day, BST (+01:00).
    private let latitude = 51.5074
    private let longitude = -0.1278
    private let offset = 3600

    private func utc(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: hour, minute: minute))!
    }

    @Test("Midday is day and the small hours are night")
    func dayAndNight() {
        #expect(DayPhase.at(utc(11), latitude: latitude, longitude: longitude, timeZoneOffset: offset) == .day)
        #expect(DayPhase.at(utc(0, 30), latitude: latitude, longitude: longitude, timeZoneOffset: offset) == .night)
    }

    @Test("Sunset is golden, strongest at the moment itself")
    func goldenAtSunset() throws {
        let sunset = try #require(SunCalculator.sunset(latitude: latitude, longitude: longitude, date: utc(12), timeZoneOffset: offset))
        guard case .golden(let atSunset) = DayPhase.at(sunset, latitude: latitude, longitude: longitude, timeZoneOffset: offset) else {
            Issue.record("Expected golden at sunset"); return
        }
        guard case .golden(let later) = DayPhase.at(sunset.addingTimeInterval(30 * 60), latitude: latitude, longitude: longitude, timeZoneOffset: offset) else {
            Issue.record("Expected golden 30 min after sunset"); return
        }
        #expect(atSunset > 0.99)
        #expect(later < atSunset)
        #expect(DayPhase.at(sunset.addingTimeInterval(2 * 3600), latitude: latitude, longitude: longitude, timeZoneOffset: offset) == .night)
    }

    @Test("Polar day has no sunset to tint around")
    func polarDay() {
        // Svalbard at midsummer.
        #expect(DayPhase.at(utc(23), latitude: 78.22, longitude: 15.65, timeZoneOffset: 7200) == .day)
    }

    @Test("Wind speeds particles up and pushes them sideways")
    func wind() {
        let calm = ParticleConfig(
            birthRate: 2, maxParticles: 30, minSpeed: 5, maxSpeed: 10, minSize: 1, maxSize: 2,
            minOpacity: 0.1, maxOpacity: 0.2, colorRed: 1, colorGreen: 1, colorBlue: 1, wobbleAmount: 1
        )
        #expect(calm.scaled(forWindSpeed: 0.5) == calm)
        let windy = calm.scaled(forWindSpeed: 12)
        #expect(windy.maxSpeed == 22)
        #expect(windy.drift == 48)
    }
}
