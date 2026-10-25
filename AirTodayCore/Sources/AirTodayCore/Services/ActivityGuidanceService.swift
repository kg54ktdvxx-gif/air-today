import Foundation

/// Pure computation — no network. Takes AirQuality + scale + Date (+ health profile) → ActivityGuidance.
///
/// Everything keys off the reading's position on the shared severity ladder, so the
/// advice matches whichever scale is shown. Thresholds are written in US EPA AQI
/// numbers (where they came from) and converted to ladder positions.
public struct ActivityGuidanceService: Sendable {
    public init() {}

    public func guidance(
        for quality: AirQuality,
        scale: AQIScale = .usEPA,
        at date: Date = Date(),
        profile: HealthProfile = .none
    ) -> ActivityGuidance {
        let reading = scale.displayReading(for: quality).reading
        let severity = reading.severity
        let level = reading.severityLevel
        let weather = quality.weather
        let dominant = reading.dominantPollutant

        // Use the place's timezone for hour extraction so guidance is correct
        // even when the device is in a different timezone.
        var calendar = Calendar.current
        if let offset = quality.timeZoneOffset,
           let tz = TimeZone(secondsFromGMT: offset) {
            calendar.timeZone = tz
        }
        let hour = calendar.component(.hour, from: date)

        let ozoneMatters = profile.isOzoneSensitive && Self.ozoneIsElevated(in: quality)
        let window = BestWindow.next(for: quality, scale: scale, now: date)

        let verdict = buildVerdict(
            level: level, weather: weather, dominant: dominant, hour: hour,
            profile: profile, ozoneMatters: ozoneMatters
        )
        let activities = Activity.allCases.map { activity in
            buildRec(
                activity: activity, severity: severity, reading: reading, weather: weather,
                profile: profile, ozoneMatters: ozoneMatters, window: window
            )
        }

        return ActivityGuidance(
            verdict: verdict,
            verdictIcon: level.verdictIcon,
            activities: activities,
            peakWarning: Self.outlook(for: quality, scale: scale, from: reading, now: date)
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

    // MARK: - Outlook

    /// How the rest of today's daylight compares with now, from the hourly forecast:
    /// "Worse from 3 PM — Poor" or "Clearing from 2 PM — Good". Nil without a
    /// forecast, or when the level holds.
    ///
    /// Compared with the model's own current hour, not the headline: a station and
    /// the model can disagree by a band at the same moment, and that isn't a change.
    static func outlook(for quality: AirQuality, scale: AQIScale, from reading: ScaledReading, now: Date) -> String? {
        guard let model = quality.model else { return nil }
        let calendar = model.calendar
        let series = reading.scale.hourlySeries(for: quality, now: now)
        guard let current = series.first else { return nil }
        func level(_ value: Int) -> AQILevel { Severity.level(at: Severity.position(of: value, on: reading.scale)) }

        let currentLevel = level(current.value)
        let upcoming = series.dropFirst().filter {
            calendar.isDate($0.time, inSameDayAs: now)
                && BestWindow.daylight.contains(calendar.component(.hour, from: $0.time))
        }
        guard let change = upcoming.first(where: { level($0.value) != currentLevel }) else { return nil }

        let time = Self.hourText(change.time, calendar: calendar)
        let band = reading.scale.band(forValue: change.value).name
        return level(change.value) > currentLevel
            ? "Worse from \(time) — \(band)"
            : "Clearing from \(time) — \(band)"
    }

    /// "3 PM" in `calendar`'s time zone.
    public static func hourText(_ date: Date, calendar: Calendar) -> String {
        let h = calendar.component(.hour, from: date)
        return "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")"
    }

    // MARK: - Per-Activity Recommendation

    private func buildRec(
        activity: Activity,
        severity: Double,
        reading: ScaledReading,
        weather: Weather,
        profile: HealthProfile,
        ozoneMatters: Bool,
        window: BestWindow?
    ) -> ActivityRec {
        let base = Self.baseThreshold(for: activity)
        let baseRec = Self.recommendation(severity: severity, threshold: base)
        let shift = Self.thresholdShift(for: activity, profile: profile, ozoneMatters: ozoneMatters)
        let rec = Self.recommendation(severity: severity, threshold: base.lowered(by: shift))

        var reason: String
        switch rec {
        case .great: reason = "Low pollution"
        case .ok: reason = "Moderate air quality"
        case .caution: reason = reading.band.longName
        case .avoid: reason = "Too polluted"
        }

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

        // When it isn't great now, say when it'll be best — if some of the day is
        // clearly better than the rest.
        var bestWindow: String?
        if rec != .great, let window, window.level < window.dayWorstLevel {
            bestWindow = "Best around \(window.headline)"
        }

        return ActivityRec(
            activity: activity,
            recommendation: rec,
            reason: reason,
            bestWindow: bestWindow
        )
    }

    /// Boundaries as ladder positions.
    struct Threshold {
        let great: Double
        let ok: Double
        let caution: Double

        /// From US EPA AQI numbers.
        init(usAQI great: Int, _ ok: Int, _ caution: Int) {
            self.great = Severity.position(usAQI: great)
            self.ok = Severity.position(usAQI: ok)
            self.caution = Severity.position(usAQI: caution)
        }

        private init(great: Double, ok: Double, caution: Double) {
            self.great = great
            self.ok = ok
            self.caution = caution
        }

        /// Moves every boundary down so warnings arrive sooner. Floors at 0.2 so even
        /// a heavily shifted profile still has a "great" band.
        func lowered(by shift: Double) -> Threshold {
            Threshold(great: max(0.2, great - shift), ok: max(0.2, ok - shift), caution: max(0.2, caution - shift))
        }
    }

    private static func recommendation(severity: Double, threshold: Threshold) -> Rec {
        if severity <= threshold.great { return .great }
        if severity <= threshold.ok { return .ok }
        if severity <= threshold.caution { return .caution }
        return .avoid
    }

    private static func baseThreshold(for activity: Activity) -> Threshold {
        switch activity {
        case .running, .cycling:
            Threshold(usAQI: 40, 80, 120)
        case .walking, .outdoorDining:
            Threshold(usAQI: 50, 100, 150)
        case .playgroundWithKids:
            Threshold(usAQI: 35, 70, 100)
        }
    }

    /// How far to move an activity's boundaries down for this profile, in ladder
    /// positions (one EPA band ≈ 1.0, so 0.5 ≈ 25 AQI points).
    /// Respiratory conditions affect everything; ozone sensitivity affects hard
    /// exertion while ozone is up; children tighten playground advice further.
    private static func thresholdShift(for activity: Activity, profile: HealthProfile, ozoneMatters: Bool) -> Double {
        var shift = 0.0
        if profile.hasRespiratoryCondition { shift += 0.5 }
        if ozoneMatters, activity == .running || activity == .cycling { shift += 0.4 }
        if profile.hasChildren, activity == .playgroundWithKids { shift += 0.3 }
        return shift
    }
}
