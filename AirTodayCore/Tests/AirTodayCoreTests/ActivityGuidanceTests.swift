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

    // MARK: - Following the chosen scale

    /// US AQI 40 (Good) while the EEA index is 65 (Poor) and PM10 has been 75 µg/m³
    /// all day (DAQI 6, Moderate) — the scales disagree, as they do in real data.
    private func disagreeing(now: Date) -> AirQuality {
        let model = Fixture.model(current: now) { time in
            Fixture.sample(time, us: 40, eu: 65, dominant: .pm10, concentrations: [.pm10: 75])
        }
        return Fixture.station(aqi: 40, at: now, dominant: .pm10, weather: Weather(temperature: 20), model: model)
    }

    @Test("The verdict follows the scale shown, so the number and the advice agree")
    func verdictFollowsScale() {
        let now = date(hour: 10)
        let q = disagreeing(now: now)
        #expect(service.guidance(for: q, scale: .usEPA, at: now).verdict == "Great day to be outside")
        #expect(service.guidance(for: q, scale: .euEAQI, at: now).verdict == "Limit prolonged outdoor exertion")
        #expect(service.guidance(for: q, scale: .ukDAQI, at: now).verdict == "Fine for most, sensitive groups take care")

        let running = service.guidance(for: q, scale: .euEAQI, at: now).activities.first { $0.activity == .running }
        #expect(running?.recommendation == .caution)
        #expect(running?.reason == "Poor")
    }

    @Test("DAQI 10 never reads as okay for someone with asthma")
    func veryHighDAQI() {
        let now = date(hour: 10)
        let model = Fixture.model(current: now) { time in
            Fixture.sample(time, us: 95, eu: 70, dominant: .pm10, concentrations: [.pm10: 135])
        }
        let q = Fixture.station(aqi: 95, at: now, dominant: .pm10, model: model)
        let profile = HealthProfile(hasRespiratoryCondition: true)
        #expect(service.guidance(for: q, scale: .usEPA, at: now, profile: profile).verdict == "Okay for you — keep exertion moderate")
        #expect(service.guidance(for: q, scale: .ukDAQI, at: now, profile: profile).verdict == "You should stay indoors if you can")
    }

    @Test("Outlook says when the level changes later today")
    func outlook() {
        let now = date(hour: 9)
        let worse = Fixture.modelled(Fixture.model(current: now) { time in
            Fixture.sample(time, us: Fixture.utc.component(.hour, from: time) >= 15 ? 120 : 70)
        })
        #expect(service.guidance(for: worse, at: now).peakWarning == "Worse from 3 PM — Sensitive")

        let clearing = Fixture.modelled(Fixture.model(current: now) { time in
            Fixture.sample(time, us: Fixture.utc.component(.hour, from: time) >= 14 ? 30 : 70)
        })
        #expect(service.guidance(for: clearing, at: now).peakWarning == "Clearing from 2 PM — Good")

        let steady = Fixture.modelled(Fixture.model(current: now) { Fixture.sample($0, us: 70) })
        #expect(service.guidance(for: steady, at: now).peakWarning == nil)
    }

    @Test("Activities that aren't great say when it's best")
    func bestWindowOnActivities() {
        let now = date(hour: 9)
        // 45 now, Moderate over lunch, cleanest in the evening.
        let q = Fixture.modelled(Fixture.model(current: now) { time in
            switch Fixture.utc.component(.hour, from: time) {
            case 12...16: Fixture.sample(time, us: 80)
            case 17...18: Fixture.sample(time, us: 20)
            default: Fixture.sample(time, us: 45)
            }
        })
        let guidance = service.guidance(for: q, at: now)
        // Running at 45 is "ok": worth knowing the evening is cleaner.
        #expect(guidance.activities.first { $0.activity == .running }?.bestWindow == "Best around 5–7 PM")
        // Walking at 45 is "great" already.
        #expect(guidance.activities.first { $0.activity == .walking }?.bestWindow == nil)

        // A flat day has no best time to point to.
        let flat = Fixture.modelled(Fixture.model(current: now) { Fixture.sample($0, us: 70) })
        #expect(service.guidance(for: flat, at: now).activities.allSatisfy { $0.bestWindow == nil })
    }
}
