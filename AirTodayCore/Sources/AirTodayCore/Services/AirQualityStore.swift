import Foundation

/// Single source of truth for air quality data, observed by all UI layers.
@MainActor
@Observable
public final class AirQualityStore {
    public private(set) var currentAQI: AirQuality?
    public private(set) var state: LoadingState = .idle
    public private(set) var lastRefreshed: Date?

    private let service: AirQualityServiceProtocol
    private let locationService: LocationService
    public let isCurrentLocation: Bool

    public init(service: AirQualityServiceProtocol, locationService: LocationService, isCurrentLocation: Bool = true) {
        self.service = service
        self.locationService = locationService
        self.isCurrentLocation = isCurrentLocation

        // Only load shared cache for current location store
        if isCurrentLocation, let cached = SharedDataStore.load() {
            self.currentAQI = cached
            self.lastRefreshed = SharedDataStore.lastUpdated()
            self.state = .loaded
        }
    }

    public func refresh() async {
        guard !state.isLoading else { return }
        state = .loading

        do {
            let quality: AirQuality

            if let coord = locationService.coordinate {
                quality = try await service.fetchCurrent(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
            } else {
                // Fallback to IP-based location
                quality = try await service.fetchCurrent(city: "here")
            }

            currentAQI = quality
            lastRefreshed = Date()
            state = .loaded

            // Persist for widget/Live Activity
            SharedDataStore.save(quality)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Whether this store's data is stale (older than cache TTL) or missing.
    public var isStale: Bool {
        guard let lastRefreshed else { return true }
        return Date().timeIntervalSince(lastRefreshed) >= AppConstants.cacheTTL
    }

    /// Auto-refresh if cache is stale.
    public func refreshIfNeeded() async {
        if isStale {
            await refresh()
        }
    }

    /// Search for stations.
    public func search(keyword: String) async throws -> [StationSummary] {
        try await service.search(keyword: keyword)
    }

    /// Fetch data for a specific station by coordinates.
    public func fetchForStation(latitude: Double, longitude: Double) async {
        state = .loading
        do {
            let quality = try await service.fetchCurrent(latitude: latitude, longitude: longitude)
            currentAQI = quality
            lastRefreshed = Date()
            state = .loaded
            SharedDataStore.save(quality)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
