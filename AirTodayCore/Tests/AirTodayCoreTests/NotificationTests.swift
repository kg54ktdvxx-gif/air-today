import Foundation
import Testing
@testable import AirTodayCore

@Suite("Alert engine and daily planner")
struct NotificationTests {
    private let t0 = Date(timeIntervalSince1970: 1_792_900_000)

    private func reading(_ aqi: Int, at date: Date, dominant: Pollutant.Kind = .pm25) -> AirQuality {
        Fixture.station(aqi: aqi, at: date, dominant: dominant)
    }

    private func evaluate(
        _ quality: AirQuality,
        previous: AlertState?,
        preferences: NotificationPreferences,
        scale: AQIScale = .usEPA,
        now: Date? = nil
    ) -> (alerts: [AlertContent], state: AlertState) {
        AlertEngine.evaluate(
            reading: quality, locationName: "Paris", locationKey: "k", previous: previous,
            preferences: preferences, profile: .none, scale: scale, now: now ?? quality.timestamp
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

    @Test("Switching between station and model is never a spike, and an older station time isn't ignored")
    func sourceSwitch() {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true, spikeAlertsEnabled: true)
        // Last time the model said 45 at 10:00; now a station measured at 09:30 says 130.
        let before = AlertState(lastAQI: 45, lastMeasuredAt: t0 + 3600, lastSource: .model)
        let result = evaluate(reading(130, at: t0 + 1800), previous: before, preferences: prefs)
        #expect(result.alerts.map(\.kind) == [.threshold])
        #expect(result.state.lastSource == .station)
    }

    // MARK: - Other scales

    /// US AQI 40 while the EEA index is 65 (Poor) and PM10 has been 135 µg/m³ (DAQI 10).
    private func disagreeing(at date: Date) -> AirQuality {
        let model = Fixture.model(current: date) { time in
            Fixture.sample(time, us: 40, eu: 65, dominant: .pm10, concentrations: [.pm10: 135])
        }
        return Fixture.station(aqi: 40, at: date, dominant: .pm10, model: model)
    }

    @Test("Thresholds follow the chosen scale, in its own words")
    func scaleThreshold() throws {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true, thresholdLevel: .sensitive)
        #expect(evaluate(disagreeing(at: t0), previous: nil, preferences: prefs).alerts.isEmpty)

        let eu = try #require(evaluate(disagreeing(at: t0), previous: nil, preferences: prefs, scale: .euEAQI).alerts.first)
        #expect(eu.title == "Poor air quality in Paris")
        #expect(eu.body == "Limit prolonged outdoor exertion. Now European AQI 65, Poor.")
    }

    @Test("A level the UK scale can't reach is capped at its top band")
    func ukCap() throws {
        let prefs = NotificationPreferences(thresholdAlertsEnabled: true, thresholdLevel: .veryUnhealthy)
        let alert = try #require(evaluate(disagreeing(at: t0), previous: nil, preferences: prefs, scale: .ukDAQI).alerts.first)
        #expect(alert.title == "Very High air pollution in Paris")
        #expect(alert.body.hasSuffix("Now UK DAQI 10, Very High."))
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

    /// Today (25th) Good from 09:00; tomorrow Good at dawn, then ozone builds to 95 by 15:00.
    private func forecastReading(now: Date) -> AirQuality {
        Fixture.modelled(Fixture.model(current: now) { time in
            let parts = Fixture.utc.dateComponents([.day, .hour], from: time)
            guard parts.day == 26 else { return Fixture.sample(time, us: 40) }
            switch parts.hour! {
            case ..<8: return Fixture.sample(time, us: 35, dominant: .o3)
            case 15: return Fixture.sample(time, us: 95, dominant: .o3)
            default: return Fixture.sample(time, us: 70, dominant: .o3)
            }
        })
    }

    @Test("Daily verdict fires at the chosen time with the day's worst forecast hour")
    func dailyVerdict() throws {
        let prefs = NotificationPreferences(dailyVerdictEnabled: true, dailyVerdictMinutes: 7 * 60 + 30)
        // It's 09:00 on the 25th, so the next 07:30 is tomorrow, the 26th.
        let planned = DailyPlanner.plan(
            for: forecastReading(now: date(day: 25, hour: 9)),
            preferences: prefs, profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        let verdict = try #require(planned.first { $0.id == DailyPlanner.dailyVerdictID })
        #expect(verdict.fireDate == date(day: 26, hour: 7, minute: 30))
        #expect(verdict.title == "Today's air: Moderate")
        #expect(verdict.body == "Fine for most, ozone rising this afternoon. Forecast at worst, around 3 PM: US EPA AQI 95 (O₃).")
    }

    @Test("Without forecast hours, the daily verdict uses the latest reading — only for today")
    func dailyVerdictLatest() throws {
        let prefs = NotificationPreferences(dailyVerdictEnabled: true, dailyVerdictMinutes: 21 * 60 + 30)
        let planned = DailyPlanner.plan(
            for: forecastReading(now: date(day: 25, hour: 9)),
            preferences: prefs, profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        let verdict = try #require(planned.first { $0.id == DailyPlanner.dailyVerdictID })
        #expect(verdict.body.hasSuffix("Latest reading: US EPA AQI 40 (PM2.5)."))
    }

    @Test("Best window only when part of the day is clearly better")
    func bestWindow() throws {
        let prefs = NotificationPreferences(bestWindowEnabled: true)
        // Today is Good throughout → nothing; tomorrow's dawn is the cleanest → 06:00.
        let planned = DailyPlanner.plan(
            for: forecastReading(now: date(day: 25, hour: 9)),
            preferences: prefs, profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        let window = try #require(planned.first { $0.id == DailyPlanner.bestWindowID })
        #expect(window.fireDate == date(day: 26, hour: 6))
        #expect(window.title == "Best time outside: 6–8 AM")
        #expect(window.body == "The cleanest air left today.")
    }

    @Test("Nothing planned when nothing is enabled")
    func nothingEnabled() {
        let planned = DailyPlanner.plan(
            for: forecastReading(now: date(day: 25, hour: 9)),
            preferences: NotificationPreferences(), profile: .none, scale: .usEPA,
            now: date(day: 25, hour: 9), calendar: utcCalendar
        )
        #expect(planned.isEmpty)
    }
}
