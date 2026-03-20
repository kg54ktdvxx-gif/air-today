import Foundation

/// Shared data store for app, widget, and Live Activity via App Groups.
public struct SharedDataStore: Sendable {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }

    private static let airQualityKey = "cached_air_quality"
    private static let timestampKey = "cached_timestamp"

    public static func save(_ quality: AirQuality) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(quality) {
            defaults.set(data, forKey: airQualityKey)
            defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        }
    }

    public static func load() -> AirQuality? {
        guard let defaults,
              let data = defaults.data(forKey: airQualityKey),
              let quality = try? JSONDecoder().decode(AirQuality.self, from: data)
        else { return nil }
        return quality
    }

    public static func lastUpdated() -> Date? {
        guard let defaults else { return nil }
        let timestamp = defaults.double(forKey: timestampKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public static var isCacheValid: Bool {
        guard let lastUpdated = lastUpdated() else { return false }
        return Date().timeIntervalSince(lastUpdated) < AppConstants.cacheTTL
    }
}
