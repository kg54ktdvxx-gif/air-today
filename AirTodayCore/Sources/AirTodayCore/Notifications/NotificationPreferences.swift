import Foundation

/// Which alerts the user wants. Each is independent and off until they opt in.
/// Stored in app-group defaults so background refresh can read them.
public struct NotificationPreferences: Equatable, Sendable {
    public var dailyVerdictEnabled: Bool
    /// Minutes after local midnight for the daily verdict (default 07:30).
    public var dailyVerdictMinutes: Int
    public var thresholdAlertsEnabled: Bool
    /// Alert when a location reaches this US EPA level or worse.
    public var thresholdLevel: AQILevel
    public var bestWindowEnabled: Bool
    public var spikeAlertsEnabled: Bool

    public init(
        dailyVerdictEnabled: Bool = false,
        dailyVerdictMinutes: Int = 7 * 60 + 30,
        thresholdAlertsEnabled: Bool = false,
        thresholdLevel: AQILevel = .sensitive,
        bestWindowEnabled: Bool = false,
        spikeAlertsEnabled: Bool = false
    ) {
        self.dailyVerdictEnabled = dailyVerdictEnabled
        self.dailyVerdictMinutes = dailyVerdictMinutes
        self.thresholdAlertsEnabled = thresholdAlertsEnabled
        self.thresholdLevel = thresholdLevel
        self.bestWindowEnabled = bestWindowEnabled
        self.spikeAlertsEnabled = spikeAlertsEnabled
    }

    public var anyEnabled: Bool {
        dailyVerdictEnabled || thresholdAlertsEnabled || bestWindowEnabled || spikeAlertsEnabled
    }

    public enum Key {
        public static let dailyVerdict = "notify_daily_verdict"
        public static let dailyVerdictMinutes = "notify_daily_verdict_minutes"
        public static let thresholdAlerts = "notify_threshold"
        public static let thresholdLevel = "notify_threshold_level"
        public static let bestWindow = "notify_best_window"
        public static let spikeAlerts = "notify_spikes"
    }

    public static func load(from defaults: UserDefaults = .shared) -> NotificationPreferences {
        let defaultValues = NotificationPreferences()
        return NotificationPreferences(
            dailyVerdictEnabled: defaults.bool(forKey: Key.dailyVerdict),
            dailyVerdictMinutes: defaults.object(forKey: Key.dailyVerdictMinutes) as? Int ?? defaultValues.dailyVerdictMinutes,
            thresholdAlertsEnabled: defaults.bool(forKey: Key.thresholdAlerts),
            thresholdLevel: (defaults.object(forKey: Key.thresholdLevel) as? Int).flatMap(AQILevel.init(rawValue:)) ?? defaultValues.thresholdLevel,
            bestWindowEnabled: defaults.bool(forKey: Key.bestWindow),
            spikeAlertsEnabled: defaults.bool(forKey: Key.spikeAlerts)
        )
    }
}
