import Foundation

/// When the air should be cleanest today. WAQI forecasts are daily averages, so
/// the timing comes from how the day's main pollutant usually behaves (the same
/// rule as the activity card's "best window"): ozone builds in afternoon sun,
/// traffic particles ease after midday.
public struct BestWindow: Equatable, Sendable {
    public enum Timing: Equatable, Sendable {
        /// Good all day — no need to plan around it.
        case anyTime
        case morning
        case afternoon
        /// The pollutant driving the day has no reliable daily pattern.
        case noClearTime
    }

    public let timing: Timing
    /// The day's expected US EPA level.
    public let level: AQILevel
    public let dominantPollutant: Pollutant.Kind?

    /// Local hour the window starts, for scheduling a reminder.
    public var startHour: Int? {
        switch timing {
        case .morning: 7
        case .afternoon: 12
        case .anyTime, .noClearTime: nil
        }
    }

    public var headline: String {
        switch timing {
        case .anyTime: "Any time today"
        case .morning: "Before 10 AM"
        case .afternoon: "Early afternoon"
        case .noClearTime: "No clear best time"
        }
    }

    public var detail: String {
        let base = switch timing {
        case .anyTime: "Air should stay good all day."
        case .morning: "Ozone builds through the afternoon."
        case .afternoon: "Particles usually ease after midday."
        case .noClearTime: "Keep time outside short if you're sensitive."
        }
        // A better hour on a bad day is still a bad day.
        return level.rawValue >= AQILevel.unhealthy.rawValue
            ? "\(base) Even then it's \(level.label.lowercased()) — keep it brief."
            : base
    }

    /// Today's (station-local) window from the forecast, or the latest reading if
    /// there's no forecast for today. Nil when there's nothing to go on.
    public static func today(for quality: AirQuality, now: Date = Date()) -> BestWindow? {
        on(now, for: quality, now: now)
    }

    /// The window for `date`'s station-local day (today or a forecast day).
    public static func on(_ date: Date, for quality: AirQuality, now: Date) -> BestWindow? {
        guard let outlook = DailyPlanner.outlook(for: quality, on: date, now: now) else { return nil }
        let level = outlook.quality.level
        let dominant = outlook.quality.dominantPollutant

        let timing: Timing
        if level == .good {
            timing = .anyTime
        } else {
            switch dominant {
            case .o3: timing = .morning
            case .pm25, .pm10: timing = .afternoon
            default: timing = .noClearTime
            }
        }
        return BestWindow(timing: timing, level: level, dominantPollutant: dominant)
    }
}
