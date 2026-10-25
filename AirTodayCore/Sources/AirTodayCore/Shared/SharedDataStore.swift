import Foundation

/// Shared data store for app, widget, and Live Activity via App Groups.
public struct SharedDataStore: Sendable {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }

    private static let airQualityKey = "cached_air_quality"
    private static let timestampKey = "cached_timestamp"
    private static let queryCoordinateKey = "cached_query_coordinate"

    /// - Parameter queryCoordinate: the device coordinate the reading was requested for,
    ///   or nil when it came from WAQI's IP-based lookup.
    public static func save(_ quality: AirQuality, queryCoordinate: Coordinate?) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(quality) {
            defaults.set(data, forKey: airQualityKey)
            defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
            if let queryCoordinate, let coordinateData = try? JSONEncoder().encode(queryCoordinate) {
                defaults.set(coordinateData, forKey: queryCoordinateKey)
            } else {
                defaults.removeObject(forKey: queryCoordinateKey)
            }
        }
    }

    public static func load() -> AirQuality? {
        guard let defaults,
              let data = defaults.data(forKey: airQualityKey),
              let quality = try? JSONDecoder().decode(AirQuality.self, from: data)
        else { return nil }
        return quality
    }

    /// The device coordinate the cached reading was requested for (nil if IP-based).
    public static func queryCoordinate() -> Coordinate? {
        guard let defaults,
              let data = defaults.data(forKey: queryCoordinateKey)
        else { return nil }
        return try? JSONDecoder().decode(Coordinate.self, from: data)
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

    /// Removes the cached reading so the next refresh fetches fresh data.
    public static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: airQualityKey)
        defaults.removeObject(forKey: timestampKey)
        defaults.removeObject(forKey: queryCoordinateKey)
    }
}
