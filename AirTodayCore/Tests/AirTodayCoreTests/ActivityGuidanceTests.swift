import Foundation
import Testing
@testable import AirTodayCore

@Suite("Activity guidance and health profile")
struct ActivityGuidanceTests {
    private let service = ActivityGuidanceService()

    /// A UTC station, so `hour` below is the station's local hour.
    private func quality(aqi: Int, dominant: Pollutant.Kind = .pm25, ozone: Double? = nil, temp: Double = 20) -> AirQuality {
        var pollutants = [Pollutant(kind: dominant, aqi: Double(aqi))]
        if let ozone, dominant != .o3 { pollutants.append(Pollutant(kind: .o3, aqi: ozone)) }
        return AirQuality(
            aqi: aqi,
            dominantPollutant: dominant,
            pollutants: pollutants,
            weather: Weather(temperature: temp),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            forecast: [],
            timestamp: Date(),
            attribution: [],
            timeZoneOffset: 0
        )
    }

    private func date(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour))!
    }

    private func rec(_ guidance: ActivityGuidance, _ activity: Activity) -> Rec? {
        guidance.activities.first { $0.activity == activity }?.recommendation
    }

    @Test("No profile keeps the general verdicts")
    func noProfileUnchanged() {
        #expect(service.guidance(for: quality(aqi: 30), at: date(hour: 10)).verdict == "Great day to be outside")
        #expect(service.guidance(for: quality(aqi: 70), at: date(hour: 10)).verdict == "Fine for most, sensitive groups take care")
        #expect(service.guidance(for: quality(aqi: 120), at: date(hour: 10)).verdict == "Limit prolonged outdoor exertion")
        #expect(service.guidance(for: quality(aqi: 350), at: date(hour: 10)).verdict == "Stay indoors")
    }

    @Test("Good air stays general whatever the profile")
    func goodAirIgnoresProfile() {
        let everyone = HealthProfile(hasRespiratoryCondition: true, isOzoneSensitive: true, hasChildren: true)
        #expect(service.guidance(for: quality(aqi: 30), at: date(hour: 10), profile: everyone).verdict == "Great day to be outside")
    }

    @Test("Respiratory condition switches to second person and tightens every activity")
    func respiratory() {
        let profile = HealthProfile(hasRespiratoryCondition: true)
        let guidance = service.guidance(for: quality(aqi: 120), at: date(hour: 10), profile: profile)
        #expect(guidance.verdict == "You should limit time outdoors")
        // Running is "caution" at 120 for everyone, "avoid" once shifted by 25.
        #expect(rec(guidance, .running) == .avoid)
        #expect(guidance.activities.first { $0.activity == .running }?.reason.contains("stricter for you") == true)
    }

    @Test("Ozone sensitivity only matters when ozone is up")
    func ozone() {
        let profile = HealthProfile(isOzoneSensitive: true)

        let ozoneMorning = service.guidance(for: quality(aqi: 70, dominant: .o3), at: date(hour: 9), profile: profile)
        #expect(ozoneMorning.verdict == "Ozone may bother you later — go out this morning")

        let ozoneAfternoon = service.guidance(for: quality(aqi: 70, dominant: .o3), at: date(hour: 15), profile: profile)
        #expect(ozoneAfternoon.verdict == "Ozone may bother you — keep exertion light")

        // PM2.5-driven day with low ozone: nothing personal to say.
        let pmDay = service.guidance(for: quality(aqi: 70, dominant: .pm25, ozone: 20), at: date(hour: 15), profile: profile)
        #expect(pmDay.verdict == "Fine for most, sensitive groups take care")
        #expect(rec(pmDay, .running) == rec(service.guidance(for: quality(aqi: 70, dominant: .pm25, ozone: 20), at: date(hour: 15)), .running))
    }

    @Test("Children tighten playground advice and the verdict at sensitive levels")
    func children() {
        let profile = HealthProfile(hasChildren: true)
        let sensitive = service.guidance(for: quality(aqi: 120), at: date(hour: 10), profile: profile)
        #expect(sensitive.verdict == "Keep kids' outdoor play short today")

        // Playground is "ok" at 60 for everyone (≤70) but "caution" with kids (≤55 shifted).
        let moderate = service.guidance(for: quality(aqi: 60), at: date(hour: 10), profile: profile)
        #expect(rec(moderate, .playgroundWithKids) == .caution)
        #expect(moderate.activities.first { $0.activity == .playgroundWithKids }?.reason.contains("stricter for kids") == true)
        // Running isn't affected by the children answer.
        #expect(rec(moderate, .running) == .ok)
    }

    @Test("Extreme heat outranks personal copy")
    func heatFirst() {
        let profile = HealthProfile(hasRespiratoryCondition: true)
        #expect(service.guidance(for: quality(aqi: 120, temp: 38), at: date(hour: 14), profile: profile).verdict == "Extreme heat — limit time outdoors")
    }
}
