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
           let outlook = outlook(for: quality, scale: scale, on: fire, now: now) {
            // Advice for the hour it describes ("ozone rising this afternoon" at a 3 PM peak).
            let guidance = ActivityGuidanceService().guidance(for: outlook.quality, scale: scale, at: outlook.peak ?? fire, profile: profile)
            let shown = scale.displayReading(for: outlook.quality)
            let detail = outlook.peak.map {
                "Forecast at worst, around \(ActivityGuidanceService.hourText($0, calendar: quality.model?.calendar ?? calendar))"
            } ?? "Latest reading"
            planned.append(PlannedNotification(
                id: dailyVerdictID,
                title: "Today's air: \(shown.reading.band.name)",
                body: "\(guidance.verdict). \(detail): \(shown.scale.shortName) \(shown.reading.value)\(dominantSuffix(shown.reading.dominantPollutant)).",
                fireDate: fire
            ))
        }

        if preferences.bestWindowEnabled, let window = bestWindow(for: quality, scale: scale, now: now) {
            planned.append(window)
        }

        return planned
    }

    // MARK: - Outlook

    struct Outlook {
        /// A stand-in reading for the model hour, so guidance and scales apply as usual.
        let quality: AirQuality
        /// The forecast hour it describes; nil when it's the latest reading.
        let peak: Date?
    }

    /// The air to expect on `date`'s local day: the worst daylight hour from `date`
    /// on, on the chosen scale. Without forecast hours for it (no model data, or a
    /// notification set after dark), the latest reading if `date` is still today.
    static func outlook(for quality: AirQuality, scale: AQIScale, on date: Date, now: Date) -> Outlook? {
        if let model = quality.model {
            let calendar = model.calendar
            let shownScale = scale.reading(for: quality) == nil ? AQIScale.usEPA : scale
            let hours = shownScale.hourlySeries(for: quality, now: date).filter {
                calendar.isDate($0.time, inSameDayAs: date)
                    && BestWindow.daylight.contains(calendar.component(.hour, from: $0.time))
            }
            // max(by:) keeps the first of equal values: the earliest worst hour, so the
            // warning comes before it.
            if let worst = hours.max(by: { $0.value < $1.value }),
               let sample = model.hourly.first(where: { $0.time == worst.time }),
               let stand = quality.atModelHour(sample) {
                return Outlook(quality: stand, peak: worst.time)
            }
        }
        let day = AirQuality.todayDateString(timeZoneOffset: quality.timeZoneOffset, now: date)
        let today = AirQuality.todayDateString(timeZoneOffset: quality.timeZoneOffset, now: now)
        return day == today ? Outlook(quality: quality, peak: nil) : nil
    }

    // MARK: - Best Window

    /// A reminder at the start of today's (or tomorrow's) best window. Only when
    /// there's something to plan around: the day isn't Good throughout and the
    /// window is better than the rest of it.
    static func bestWindow(for quality: AirQuality, scale: AQIScale, now: Date) -> PlannedNotification? {
        guard let calendar = quality.model?.calendar else { return nil }
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let window = BestWindow.on(day, for: quality, scale: scale, now: now),
                  let start = window.start,
                  start > now,
                  window.level < window.dayWorstLevel
            else { continue }

            return PlannedNotification(
                id: bestWindowID,
                title: "Best time outside: \(window.headline)",
                body: window.detail,
                fireDate: start
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
