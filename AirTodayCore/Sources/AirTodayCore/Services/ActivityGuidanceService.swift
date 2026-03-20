import Foundation

/// Pure computation — no network. Takes AirQuality + Date → ActivityGuidance.
public struct ActivityGuidanceService: Sendable {
    public init() {}

    public func guidance(for quality: AirQuality, at date: Date = Date()) -> ActivityGuidance {
        let aqi = quality.aqi
        let level = quality.level
        let weather = quality.weather
        let dominant = quality.dominantPollutant

        // Use station timezone for hour extraction so guidance is correct
        // even when the device is in a different timezone than the station.
        var calendar = Calendar.current
        if let offset = quality.timeZoneOffset,
           let tz = TimeZone(secondsFromGMT: offset) {
            calendar.timeZone = tz
        }
        let hour = calendar.component(.hour, from: date)

        let verdict = buildVerdict(level: level, weather: weather, dominant: dominant, hour: hour)
        let peakWarning = buildPeakWarning(dominant: dominant, hour: hour, aqi: aqi)
        let activities = Activity.allCases.map { activity in
            buildRec(activity: activity, aqi: aqi, level: level, weather: weather, dominant: dominant, hour: hour)
        }

        return ActivityGuidance(
            verdict: verdict,
            verdictIcon: level.verdictIcon,
            activities: activities,
            peakWarning: peakWarning
        )
    }

    // MARK: - Verdict

    private func buildVerdict(level: AQILevel, weather: Weather, dominant: Pollutant.Kind?, hour: Int) -> String {
        if let temp = weather.temperature, temp > 35 {
            return "Extreme heat — limit time outdoors"
        }

        switch level {
        case .good:
            if let temp = weather.temperature, temp >= 10, temp <= 28 {
                return "Great day to be outside"
            }
            return "Air quality is good"
        case .moderate:
            if dominant == .o3, hour >= 12, hour <= 19 {
                return "Fine for most, ozone rising this afternoon"
            }
            return "Fine for most, sensitive groups take care"
        case .sensitive:
            return "Limit prolonged outdoor exertion"
        case .unhealthy:
            return "Reduce outdoor activity"
        case .veryUnhealthy:
            return "Avoid prolonged outdoor activity"
        case .hazardous:
            return "Stay indoors"
        }
    }

    // MARK: - Peak Warning

    private func buildPeakWarning(dominant: Pollutant.Kind?, hour: Int, aqi: Int) -> String? {
        if dominant == .o3, hour < 15 {
            return "Ozone peaks 3–7 PM, exercise in the morning"
        }
        if dominant == .pm25, aqi > 80, hour < 12 {
            return "PM2.5 may improve by afternoon"
        }
        return nil
    }

    // MARK: - Per-Activity Recommendation

    private func buildRec(
        activity: Activity,
        aqi: Int,
        level: AQILevel,
        weather: Weather,
        dominant: Pollutant.Kind?,
        hour: Int
    ) -> ActivityRec {
        let threshold = activityThreshold(for: activity)
        let rec: Rec
        var reason: String
        var bestWindow: String?

        if aqi <= threshold.great {
            rec = .great
            reason = "Low pollution"
        } else if aqi <= threshold.ok {
            rec = .ok
            reason = "Moderate air quality"
        } else if aqi <= threshold.caution {
            rec = .caution
            reason = level.label
        } else {
            rec = .avoid
            reason = "AQI too high"
        }

        // Weather modifiers
        if let temp = weather.temperature {
            if temp > 35 {
                reason += ", extreme heat"
            } else if temp < 5, activity == .running || activity == .cycling {
                reason += ", cold conditions"
            }
        }

        if let wind = weather.windSpeed, wind > 15, activity == .cycling {
            reason += ", high winds"
        }

        // Best window
        if rec == .caution || rec == .ok {
            if dominant == .o3 {
                bestWindow = "Before 10 AM"
            } else if dominant == .pm25 {
                bestWindow = "Afternoon may be better"
            }
        }

        return ActivityRec(
            activity: activity,
            recommendation: rec,
            reason: reason,
            bestWindow: bestWindow
        )
    }

    private struct Threshold {
        let great: Int
        let ok: Int
        let caution: Int
    }

    private func activityThreshold(for activity: Activity) -> Threshold {
        switch activity {
        case .running:
            Threshold(great: 40, ok: 80, caution: 120)
        case .cycling:
            Threshold(great: 40, ok: 80, caution: 120)
        case .walking:
            Threshold(great: 50, ok: 100, caution: 150)
        case .playgroundWithKids:
            Threshold(great: 35, ok: 70, caution: 100)
        case .outdoorDining:
            Threshold(great: 50, ok: 100, caution: 150)
        }
    }
}
