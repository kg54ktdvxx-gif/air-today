import Foundation

/// Gets the current-location reading from outside the app's UI — widgets,
/// Siri, background refresh — where there's no fresh GPS fix to ask for.
public enum CurrentAirRefresher {
    /// Fetches for the coordinate the last foreground reading used (or WAQI's IP
    /// lookup if there's none) and updates the shared cache.
    public static func refresh(
        service: AirQualityServiceProtocol = AirQualityService(token: AppConstants.waqiToken)
    ) async throws -> AirQuality {
        let coordinate = SharedDataStore.queryCoordinate()
        let quality: AirQuality = if let coordinate {
            try await service.fetchCurrent(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } else {
            try await service.fetchCurrent(city: "here")
        }
        SharedDataStore.save(quality, queryCoordinate: coordinate)
        return quality
    }

    /// The cached reading while it's younger than `maxAge`, otherwise a fresh one;
    /// falls back to the cache if fetching fails. Nil only with no cache and no network.
    public static func latest(
        maxAge: TimeInterval = AppConstants.cacheTTL,
        service: AirQualityServiceProtocol = AirQualityService(token: AppConstants.waqiToken)
    ) async -> AirQuality? {
        let cached = SharedDataStore.load()
        if let cached, let fetched = SharedDataStore.lastUpdated(), Date().timeIntervalSince(fetched) < maxAge {
            return cached
        }
        return (try? await refresh(service: service)) ?? cached
    }
}
