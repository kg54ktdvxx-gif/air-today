import Foundation

/// Single source of truth for air quality data, observed by all UI layers.
@MainActor
@Observable
public final class AirQualityStore {
    public private(set) var currentAQI: AirQuality?
    public private(set) var state: LoadingState = .idle
    /// When this store last fetched from the API. Drives cache staleness only;
    /// the age shown to users comes from `AirQuality.timestamp` (measurement time).
    public private(set) var lastRefreshed: Date?
    /// Where the current reading was requested from; nil when it came from the IP lookup.
    @ObservationIgnored
    private var lastQueryCoordinate: Coordinate?

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
            self.lastQueryCoordinate = SharedDataStore.queryCoordinate()
            self.state = .loaded
        }
    }

    public func refresh() async {
        guard !state.isLoading else { return }
        state = .loading

        do {
            let quality: AirQuality
            let queryCoordinate = locationService.coordinate.map(Coordinate.init)

            if let queryCoordinate {
                quality = try await service.fetchCurrent(
                    latitude: queryCoordinate.latitude,
                    longitude: queryCoordinate.longitude
                )
            } else {
                // Fallback to IP-based location
                quality = try await service.fetchCurrent(city: "here")
            }

            apply(quality, queryCoordinate: queryCoordinate)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Whether this store's data is missing, older than the cache TTL, or —
    /// for the current location — no longer describes where the device is.
    public var isStale: Bool {
        guard let lastRefreshed else { return true }
        if Date().timeIntervalSince(lastRefreshed) >= AppConstants.cacheTTL { return true }
        return hasMovedSinceLastFetch
    }

    private var hasMovedSinceLastFetch: Bool {
        guard isCurrentLocation, let here = locationService.coordinate.map(Coordinate.init) else { return false }
        // A reading from the IP lookup is superseded as soon as GPS is available.
        guard let lastQueryCoordinate else { return true }
        return here.distance(to: lastQueryCoordinate) > AppConstants.relocationThreshold
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

    /// Fetch the nearest active station to a coordinate. WAQI answers with the
    /// nearest station that's *reporting*, however far; `maxDistance` (metres)
    /// rejects one too far away to describe this place.
    public func fetchForStation(latitude: Double, longitude: Double, maxDistance: Double? = nil) async {
        guard !state.isLoading else { return }
        state = .loading
        do {
            let requested = Coordinate(latitude: latitude, longitude: longitude)
            let quality = try await service.fetchCurrent(latitude: latitude, longitude: longitude)
            if let maxDistance, quality.station.coordinate.distance(to: requested) > maxDistance {
                throw AirQualityError.noNearbyStation
            }
            apply(quality, queryCoordinate: requested)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fetch one WAQI station by uid (saved cities).
    public func fetchStation(id: Int, coordinate: Coordinate) async {
        guard !state.isLoading else { return }
        state = .loading
        do {
            let quality = try await service.fetchStation(id: id)
            apply(quality, queryCoordinate: coordinate)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func apply(_ quality: AirQuality, queryCoordinate: Coordinate?) {
        currentAQI = quality
        lastRefreshed = Date()
        lastQueryCoordinate = queryCoordinate
        state = .loaded

        // The shared cache feeds the widget, Live Activity and background refresh,
        // which all describe the user's own location — saved cities must not overwrite it.
        if isCurrentLocation {
            SharedDataStore.save(quality, queryCoordinate: queryCoordinate)
        }
    }
}
