import Foundation

/// Pure computation — no network. Takes AirQuality + Date (+ health profile) → ActivityGuidance.
public struct ActivityGuidanceService: Sendable {
    public init() {}

    public func guidance(
        for quality: AirQuality,
        at date: Date = Date(),
        profile: HealthProfile = .none
    ) -> ActivityGuidance {
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

        let ozoneMatters = profile.isOzoneSensitive && Self.ozoneIsElevated(in: quality)

        let verdict = buildVerdict(
            level: level, weather: weather, dominant: dominant, hour: hour,
            profile: profile, ozoneMatters: ozoneMatters
        )
        let peakWarning = buildPeakWarning(dominant: dominant, hour: hour, aqi: aqi)
        let activities = Activity.allCases.map { activity in
            buildRec(
                activity: activity, aqi: aqi, level: level, weather: weather, dominant: dominant,
                profile: profile, ozoneMatters: ozoneMatters
            )
        }

        return ActivityGuidance(
            verdict: verdict,
            verdictIcon: level.verdictIcon,
            activities: activities,
            peakWarning: peakWarning
        )
    }

    /// Ozone is worth flagging to a sensitive person when it drives the AQI or is
    /// itself past the Good band.
    private static func ozoneIsElevated(in quality: AirQuality) -> Bool {
        if quality.dominantPollutant == .o3 { return true }
        let ozone = quality.pollutants.first { $0.kind == .o3 }?.aqi ?? 0
        return ozone > 50
    }

    // MARK: - Verdict

    private func buildVerdict(
        level: AQILevel,
        weather: Weather,
        dominant: Pollutant.Kind?,
        hour: Int,
        profile: HealthProfile,
        ozoneMatters: Bool
    ) -> String {
        if let temp = weather.temperature, temp > 35 {
            return "Extreme heat — limit time outdoors"
        }

        if let personal = personalVerdict(level: level, hour: hour, profile: profile, ozoneMatters: ozoneMatters) {
            return personal
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

    /// Second-person copy, used only when the profile changes what this person
    /// should do. Respiratory conditions take priority, then ozone, then children,
    /// following who EPA guidance names first at each level.
    private func personalVerdict(level: AQILevel, hour: Int, profile: HealthProfile, ozoneMatters: Bool) -> String? {
        switch level {
        case .good, .hazardous:
            // Good is good for everyone; Hazardous is "Stay indoors" for everyone.
            return nil
        case .moderate:
            if profile.hasRespiratoryCondition { return "Okay for you — keep exertion moderate" }
            if ozoneMatters {
                return hour < 12
                    ? "Ozone may bother you later — go out this morning"
                    : "Ozone may bother you — keep exertion light"
            }
            return nil
        case .sensitive:
            if profile.hasRespiratoryCondition { return "You should limit time outdoors" }
            if ozoneMatters { return "Ozone is high for you — skip hard exercise outside" }
            if profile.hasChildren { return "Keep kids' outdoor play short today" }
            return nil
        case .unhealthy:
            if profile.hasRespiratoryCondition { return "You should stay indoors if you can" }
            if profile.hasChildren { return "Keep kids indoors today" }
            if ozoneMatters { return "You should avoid exercising outside today" }
            return nil
        case .veryUnhealthy:
            if profile.hasRespiratoryCondition { return "Stay inside today and keep windows closed" }
            if profile.hasChildren { return "Keep yourself and the kids indoors today" }
            return nil
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
        profile: HealthProfile,
        ozoneMatters: Bool
    ) -> ActivityRec {
        let baseRec = Self.recommendation(aqi: aqi, threshold: Self.baseThreshold(for: activity))
        let shift = Self.thresholdShift(for: activity, profile: profile, ozoneMatters: ozoneMatters)
        let rec = Self.recommendation(aqi: aqi, threshold: Self.baseThreshold(for: activity).lowered(by: shift))

        var reason: String
        switch rec {
        case .great: reason = "Low pollution"
        case .ok: reason = "Moderate air quality"
        case .caution: reason = level.label
        case .avoid: reason = "AQI too high"
        }
        var bestWindow: String?

        // Say so when the profile made the advice stricter than it is for everyone else.
        if rec > baseRec {
            reason += activity == .playgroundWithKids && profile.hasChildren
                ? " · stricter for kids"
                : " · stricter for you"
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

        /// Moves every boundary down so warnings arrive at lower AQI. Floors at
        /// 10 so even a heavily shifted profile still has a "great" band.
        func lowered(by shift: Int) -> Threshold {
            Threshold(
                great: max(10, great - shift),
                ok: max(10, ok - shift),
                caution: max(10, caution - shift)
            )
        }
    }

    private static func recommendation(aqi: Int, threshold: Threshold) -> Rec {
        if aqi <= threshold.great { return .great }
        if aqi <= threshold.ok { return .ok }
        if aqi <= threshold.caution { return .caution }
        return .avoid
    }

    private static func baseThreshold(for activity: Activity) -> Threshold {
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

    /// AQI points to move an activity's boundaries down for this profile.
    /// Respiratory conditions affect everything; ozone sensitivity affects hard
    /// exertion while ozone is up; children tighten playground advice further.
    private static func thresholdShift(for activity: Activity, profile: HealthProfile, ozoneMatters: Bool) -> Int {
        var shift = 0
        if profile.hasRespiratoryCondition { shift += 25 }
        if ozoneMatters, activity == .running || activity == .cycling { shift += 20 }
        if profile.hasChildren, activity == .playgroundWithKids { shift += 15 }
        return shift
    }
}
