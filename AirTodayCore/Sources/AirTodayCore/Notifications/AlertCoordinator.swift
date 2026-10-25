import Foundation
import UserNotifications

/// Runs fresh readings through the alert engine and keeps scheduled
/// notifications current. Called after foreground and background refreshes.
public enum AlertCoordinator {
    private static let statesKey = "alert_states"
    public static let currentLocationKey = "current"
    public static let locationKeyInfo = "locationKey"

    /// The current location gets a new ID every launch, so it's keyed by role.
    public static func key(for location: SavedLocation) -> String {
        location.isCurrentLocation ? currentLocationKey : location.id.uuidString
    }

    public static func process(_ readings: [(location: SavedLocation, quality: AirQuality)], now: Date = Date()) async {
        let preferences = NotificationPreferences.load()
        let profile = HealthProfile.load()
        let scale = AQIScale.current
        var states = loadStates()

        for (location, quality) in readings {
            let key = key(for: location)
            let name = location.isCurrentLocation ? "your area" : shortName(location.name)
            let result = AlertEngine.evaluate(
                reading: quality,
                locationName: name,
                locationKey: key,
                previous: states[key],
                preferences: preferences,
                profile: profile,
                scale: scale,
                now: now
            )
            states[key] = result.state
            for alert in result.alerts {
                await NotificationScheduler.post(alert)
            }
        }
        saveStates(states)

        // Daily notifications describe where the user is.
        if let current = readings.first(where: { $0.location.isCurrentLocation })?.quality {
            let planned = DailyPlanner.plan(for: current, preferences: preferences, profile: profile, scale: scale, now: now)
            await NotificationScheduler.replaceScheduled(with: planned)
        }
    }

    /// Re-plans scheduled notifications after a preference change.
    public static func preferencesChanged() async {
        let preferences = NotificationPreferences.load()
        guard let current = SharedDataStore.load() else {
            if !preferences.anyEnabled { await NotificationScheduler.replaceScheduled(with: []) }
            return
        }
        let planned = DailyPlanner.plan(
            for: current,
            preferences: preferences,
            profile: HealthProfile.load(),
            scale: AQIScale.current,
            now: Date()
        )
        await NotificationScheduler.replaceScheduled(with: planned)
    }

    public static func forget(_ location: SavedLocation) {
        var states = loadStates()
        states[key(for: location)] = nil
        saveStates(states)
    }

    private static func shortName(_ name: String) -> String {
        name.components(separatedBy: ",").first ?? name
    }

    private static func loadStates() -> [String: AlertState] {
        guard let data = UserDefaults.shared.data(forKey: statesKey),
              let states = try? JSONDecoder().decode([String: AlertState].self, from: data)
        else { return [:] }
        return states
    }

    private static func saveStates(_ states: [String: AlertState]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.shared.set(data, forKey: statesKey)
        }
    }
}

/// Thin wrapper over UNUserNotificationCenter.
public enum NotificationScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    /// Asks once; afterwards returns the existing answer.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    static func post(_ alert: AlertContent) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.locationKey
        content.userInfo = [AlertCoordinator.locationKeyInfo: alert.locationKey]
        let request = UNNotificationRequest(
            identifier: "\(alert.kind.rawValue)-\(alert.locationKey)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func replaceScheduled(with planned: [PlannedNotification]) async {
        let ids = [DailyPlanner.dailyVerdictID, DailyPlanner.bestWindowID]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        for notification in planned {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.userInfo = [AlertCoordinator.locationKeyInfo: AlertCoordinator.currentLocationKey]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notification.fireDate)
            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
