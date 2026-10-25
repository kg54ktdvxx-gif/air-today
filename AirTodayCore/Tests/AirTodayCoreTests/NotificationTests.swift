import Foundation
import Testing
@testable import AirTodayCore

@Suite("Alert engine and daily planner")
struct NotificationTests {
    private let t0 = Date(timeIntervalSince1970: 1_792_900_000)

    private func reading(_ aqi: Int, at date: Date, dominant: Pollutant.Kind = .pm25, forecast: [DailyForecast] = []) -> AirQuality {
        AirQuality(
            aqi: aqi,
            dominantPollutant: dominant,
            pollutants: [Pollutant(kind: dominant, aqi: Double(aqi))],
            weather: Weather(),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 51.5, longitude: -0.1), url: ""),
            forecast: forecast,
            timestamp: date,
            attribution: [],
            timeZoneOffset: 0
        )
    }

    private func evaluate(_ quality: AirQuality, previous: AlertState?, preferences: NotificationPreferences, now: Date? = nil) -> (alerts: [AlertContent], state: AlertState) {
        AlertEngine.evaluate(
            reading: quality, locationName: "Paris", locationKey: "k", previous: previous,
            preferences: preferences, profile: .none, scale: .usEPA, now: now ?? quality.timestamp
        )
    }

    // MARK: - Threshold

    @Test("Crossing the threshold alerts once, worsening alerts again, recovery re-arms")
    func thresholdLifecycle() {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true, thresholdLevel: .sensitive)

        let first = evaluate(reading(80, at: t0), previous: nil, preferences: prefs)
        #expect(first.alerts.isEmpty)

        let crossed = evaluate(reading(120, at: t0 + 3600), previous: first.state, preferences: prefs)
        #expect(crossed.alerts.map(\.kind) == [.threshold])
        #expect(crossed.alerts.first?.title == "Unhealthy for Sensitive Groups in Paris")

        let stillBad = evaluate(reading(130, at: t0 + 7200), previous: crossed.state, preferences: prefs)
        #expect(stillBad.alerts.isEmpty)

        let worse = evaluate(reading(170, at: t0 + 3 * 3600), previous: stillBad.state, preferences: prefs)
        #expect(worse.alerts.map(\.kind) == [.threshold])

        // Dipping just under the line doesn't re-arm; falling well below does.
        let hover = evaluate(reading(95, at: t0 + 4 * 3600), previous: worse.state, preferences: prefs)
        #expect(hover.state.alertedLevel == .unhealthy)
        let recovered = evaluate(reading(60, at: t0 + 5 * 3600), previous: hover.state, preferences: prefs)
        #expect(recovered.state.alertedLevel == nil)
        let again = evaluate(reading(115, at: t0 + 6 * 3600), previous: recovered.state, preferences: prefs)
        #expect(again.alerts.map(\.kind) == [.threshold])
    }

    @Test("The same measurement fetched twice changes nothing")
    func duplicateReading() {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true)
        let state = AlertState(lastAQI: 60, lastMeasuredAt: t0)
        let result = evaluate(reading(160, at: t0), previous: state, preferences: prefs)
        #expect(result.alerts.isEmpty)
        #expect(result.state == state)
    }

    @Test("Disabled alerts stay silent but still track state")
    func disabled() {
        let result = evaluate(reading(180, at: t0), previous: nil, preferences: NotificationPreferences())
        #expect(result.alerts.isEmpty)
        #expect(result.state.alertedLevel == .unhealthy)
    }

    // MARK: - Spike

    @Test("A fast rise alerts as a spike, once per cooldown, instead of a threshold alert")
    func spike() {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true, spikeAlertsEnabled: true)
        let before = AlertState(lastAQI: 45, lastMeasuredAt: t0)

        let spike = evaluate(reading(130, at: t0 + 2 * 3600), previous: before, preferences: prefs)
        #expect(spike.alerts.map(\.kind) == [.spike])
        #expect(spike.state.alertedLevel == .sensitive)

        // Another jump an hour later is within the cooldown.
        let soon = evaluate(reading(190, at: t0 + 3 * 3600), previous: AlertState(lastAQI: 130, lastMeasuredAt: t0 + 2 * 3600, alertedLevel: .sensitive, lastSpikeAlertAt: t0 + 2 * 3600), preferences: prefs)
        #expect(soon.alerts.map(\.kind) == [.threshold])
    }

    @Test("A slow rise isn't a spike")
    func slowRise() {
        let prefs = NotificationPreferences(spikeAlertsEnabled: true)
        let before = AlertState(lastAQI: 45, lastMeasuredAt: t0)
        #expect(evaluate(reading(130, at: t0 + 8 * 3600), previous: before, preferences: prefs).alerts.isEmpty)
    }

    // MARK: - Daily planner

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let forecast = [
        DailyForecast(pollutant: .pm25, day: "2026-10-25", avg: 40, min: 30, max: 55),
        DailyForecast(pollutant: .o3, day: "2026-10-25", avg: 30, min: 10, max: 40),
        DailyForecast(pollutant: .pm25, day: "2026-10-26", avg: 85, min: 60, max: 110),
        DailyForecast(pollutant: .o3, day: "2026-10-26", avg: 95, min: 40, max: 120),
    ]

    @Test("Daily verdict fires at the chosen time with that day's forecast")
    func dailyVerdict() throws {
        let prefs = NotificationPreferences(dailyVerdictEnabled: true, dailyVerdictMinutes: 7 * 60 + 30)
        // It's 09:00 on the 25th, so the next 07:30 is tomorrow, the 26th.
        let planned = DailyPlanner.plan(
            for: reading(40, at: date(day: 25, hour: 8), forecast: forecast),
            preferences: prefs, profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        let verdict = try #require(planned.first { $0.id == DailyPlanner.dailyVerdictID })
        #expect(verdict.fireDate == date(day: 26, hour: 7, minute: 30))
        #expect(verdict.title == "Today's air: Moderate")
        #expect(verdict.body.contains("Forecast: US EPA AQI 95 (O₃)"))
    }

    @Test("Best window only on days that aren't Good, timed by the pollutant")
    func bestWindow() throws {
        let prefs = NotificationPreferences(bestWindowEnabled: true)
        // Today (25th) is Good → nothing today; tomorrow is ozone-driven Moderate → 07:00.
        let planned = DailyPlanner.plan(
            for: reading(40, at: date(day: 25, hour: 8), forecast: forecast),
            preferences: prefs, profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        let window = try #require(planned.first { $0.id == DailyPlanner.bestWindowID })
        #expect(window.fireDate == date(day: 26, hour: 7))
        #expect(window.body.contains("before 10 AM"))
    }

    @Test("Nothing planned when nothing is enabled")
    func nothingEnabled() {
        let planned = DailyPlanner.plan(
            for: reading(40, at: date(day: 25, hour: 8), forecast: forecast),
            preferences: NotificationPreferences(), profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        #expect(planned.isEmpty)
    }
}

@Suite("Alert wording across scales")
struct AlertWordingTests {
    @Test("On a non-EPA scale the alert states both figures and a neutral title")
    func mixedScales() throws {
        let reading = AirQuality(
            aqi: 95,
            dominantPollutant: .pm10,
            pollutants: [Pollutant(kind: .pm10, aqi: 95)],
            weather: Weather(),
            station: Station(id: 1, name: "Delhi", coordinate: Coordinate(latitude: 28.6, longitude: 77.2), url: ""),
            forecast: [],
            timestamp: Date(timeIntervalSince1970: 1_792_900_000),
            attribution: [],
            timeZoneOffset: 19_800
        )
        let result = AlertEngine.evaluate(
            reading: reading, locationName: "your area", locationKey: "current", previous: nil,
            preferences: NotificationPreferences(thresholdAlertsEnabled: true, thresholdLevel: .moderate),
            profile: .none, scale: .ukDAQI, now: reading.timestamp
        )
        let alert = try #require(result.alerts.first)
        #expect(alert.title == "Air quality alert in your area")
        // PM10 at EPA 95 ≈ 135 µg/m³: Very High on DAQI, Moderate on EPA.
        #expect(alert.body.contains("UK DAQI 10 (Very High); US EPA AQI 95 (Moderate)"))
    }
}
