import Foundation

public struct PlannedNotification: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

/// Plans the scheduled notifications (daily verdict, best window) from the
/// current location's latest data. Re-run after every refresh so a pending
/// notification always carries the freshest forecast available.
public enum DailyPlanner {
    public static let dailyVerdictID = "daily-verdict"
    public static let bestWindowID = "best-window"

    public static func plan(
        for quality: AirQuality,
        preferences: NotificationPreferences,
        profile: HealthProfile,
        scale: AQIScale,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        if preferences.dailyVerdictEnabled,
           let fire = nextOccurrence(minutes: preferences.dailyVerdictMinutes, after: now, calendar: calendar),
           let outlook = outlook(for: quality, on: fire, now: now) {
            let guidance = ActivityGuidanceService().guidance(for: outlook.quality, at: fire, profile: profile)
            let shown = scale.displayReading(for: outlook.quality)
            let source = outlook.isForecast ? "Forecast" : "Latest reading"
            planned.append(PlannedNotification(
                id: dailyVerdictID,
                title: "Today's air: \(shown.reading.band.name)",
                body: "\(guidance.verdict). \(source): \(shown.scale.shortName) \(shown.reading.value)\(dominantSuffix(outlook.quality.dominantPollutant)).",
                fireDate: fire
            ))
        }

        if preferences.bestWindowEnabled, let window = bestWindow(for: quality, now: now, calendar: calendar) {
            planned.append(window)
        }

        return planned
    }

    // MARK: - Outlook

    struct Outlook {
        /// A stand-in reading built from the forecast, so guidance and scales apply as usual.
        let quality: AirQuality
        let isForecast: Bool
    }

    /// The expected air on `date`'s station-local day: the worst forecast daily
    /// average across pollutants, or the latest reading if there's no forecast
    /// and `date` is still today.
    static func outlook(for quality: AirQuality, on date: Date, now: Date) -> Outlook? {
        let day = AirQuality.todayDateString(timeZoneOffset: quality.timeZoneOffset, now: date)
        let entries = quality.forecast.filter { $0.day == day }

        guard let worst = entries.max(by: { $0.avg < $1.avg }) else {
            let today = AirQuality.todayDateString(timeZoneOffset: quality.timeZoneOffset, now: now)
            return day == today ? Outlook(quality: quality, isForecast: false) : nil
        }

        let stand = AirQuality(
            aqi: worst.avg,
            dominantPollutant: worst.pollutant,
            pollutants: entries.map { Pollutant(kind: $0.pollutant, aqi: Double($0.avg)) },
            weather: Weather(),
            station: quality.station,
            forecast: quality.forecast,
            timestamp: date,
            attribution: quality.attribution,
            timeZoneOffset: quality.timeZoneOffset
        )
        return Outlook(quality: stand, isForecast: true)
    }

    // MARK: - Best Window

    /// WAQI forecasts are daily, so the window comes from how each pollutant
    /// usually behaves through the day (as the activity card's "best window"):
    /// ozone builds in afternoon sun, traffic particles ease after midday.
    /// Only planned when the day isn't Good — on a good day any time is fine.
    static func bestWindow(for quality: AirQuality, now: Date, calendar: Calendar) -> PlannedNotification? {
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let outlook = outlook(for: quality, on: day, now: now),
                  outlook.quality.level.rawValue >= AQILevel.moderate.rawValue
            else { continue }

            let window: (hour: Int, body: String)
            switch outlook.quality.dominantPollutant {
            case .o3:
                window = (7, "Ozone builds through the afternoon — get outside before 10 AM.")
            case .pm25, .pm10:
                window = (12, "Particles usually ease after midday — early afternoon is likely the clearest time today.")
            default:
                continue
            }

            guard let fire = calendar.date(bySettingHour: window.hour, minute: 0, second: 0, of: day),
                  fire > now
            else { continue }

            return PlannedNotification(
                id: bestWindowID,
                title: "Best time outside today",
                body: window.body,
                fireDate: fire
            )
        }
        return nil
    }

    // MARK: - Helpers

    static func nextOccurrence(minutes: Int, after now: Date, calendar: Calendar) -> Date? {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    private static func dominantSuffix(_ kind: Pollutant.Kind?) -> String {
        kind.map { " (\($0.displayName))" } ?? ""
    }
}
