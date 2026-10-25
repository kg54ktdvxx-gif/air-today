import Foundation

/// Gets the current-location reading from outside the app's UI — widgets,
/// Siri, background refresh — where there's no fresh GPS fix to ask for.
public enum CurrentAirRefresher {
    /// Fetches for the coordinate the last foreground reading used (or WAQI's IP
    /// lookup if there's none) and updates the shared cache.
    public static func refresh(reader: AirReadingService = AirReadingService()) async throws -> AirQuality {
        let coordinate = SharedDataStore.queryCoordinate()
        let previous = SharedDataStore.load()
        var quality = try await reader.reading(at: coordinate)
        // Same coordinate, same town: the name was looked up in the foreground.
        if coordinate != nil {
            quality.placeName = previous?.placeName
        }
        SharedDataStore.save(quality, queryCoordinate: coordinate)
        return quality
    }

    /// The cached reading while it's younger than `maxAge`, otherwise a fresh one;
    /// falls back to the cache if fetching fails. Nil only with no cache and no network.
    public static func latest(
        maxAge: TimeInterval = AppConstants.cacheTTL,
        reader: AirReadingService = AirReadingService()
    ) async -> AirQuality? {
        let cached = SharedDataStore.load()
        // A reading without the forecast is worth another try sooner.
        let limit = cached?.model == nil ? min(maxAge, AppConstants.incompleteReadingRetry) : maxAge
        if let cached, let fetched = SharedDataStore.lastUpdated(), Date().timeIntervalSince(fetched) < limit {
            return cached
        }
        return (try? await refresh(reader: reader)) ?? cached
    }
}
