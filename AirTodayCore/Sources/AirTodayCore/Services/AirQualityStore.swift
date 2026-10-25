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
    /// The town name and the coordinate it was looked up for, so it's only looked
    /// up again after moving.
    @ObservationIgnored
    private var place: (name: String, coordinate: Coordinate)?
    @ObservationIgnored
    private var placeLookup: Task<Void, Never>?

    private let reader: AirReadingService
    private let locationService: LocationService
    public let isCurrentLocation: Bool

    public init(reader: AirReadingService, locationService: LocationService, isCurrentLocation: Bool = true) {
        self.reader = reader
        self.locationService = locationService
        self.isCurrentLocation = isCurrentLocation

        // Only load shared cache for current location store
        if isCurrentLocation, let cached = SharedDataStore.load() {
            self.currentAQI = cached
            self.lastRefreshed = SharedDataStore.lastUpdated()
            self.lastQueryCoordinate = SharedDataStore.queryCoordinate()
            if let name = cached.placeName, let coordinate = lastQueryCoordinate {
                self.place = (name, coordinate)
            }
            self.state = .loaded
        }
    }

    /// The current location's reading: GPS when available, otherwise WAQI's IP lookup.
    public func refresh() async {
        let queryCoordinate = locationService.coordinate.map(Coordinate.init)
        let applied = await load(queryCoordinate: queryCoordinate) {
            try await self.reader.reading(at: queryCoordinate)
        }
        // At launch the IP lookup usually starts before GPS answers, and the refresh the
        // fix triggers is turned away while that's loading. Catch up with it now.
        if applied, hasMovedSinceLastFetch {
            await refresh()
        }
    }

    /// A saved city's reading. `stationID` is the station the user picked, if any.
    public func fetch(at coordinate: Coordinate, stationID: Int?) async {
        await load(queryCoordinate: coordinate) {
            try await self.reader.reading(at: coordinate, stationID: stationID)
        }
    }

    /// - Returns: whether a new reading was applied.
    @discardableResult
    private func load(queryCoordinate: Coordinate?, _ read: () async throws -> AirQuality) async -> Bool {
        guard !state.isLoading else { return false }
        state = .loading
        do {
            var quality = try await read()
            if isCurrentLocation {
                quality.placeName = knownPlaceName(near: queryCoordinate)
            }
            apply(quality, queryCoordinate: queryCoordinate)
            if isCurrentLocation, quality.placeName == nil, let queryCoordinate {
                lookUpPlaceName(for: queryCoordinate)
            }
            return true
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    /// The town already looked up for this spot, if any.
    private func knownPlaceName(near coordinate: Coordinate?) -> String? {
        guard let coordinate, let place,
              place.coordinate.distance(to: coordinate) <= AppConstants.relocationThreshold
        else { return nil }
        return place.name
    }

    /// Fills in the town name when Apple Maps answers. The reading doesn't wait for it:
    /// the lookup can be slow, or never answer offline.
    private func lookUpPlaceName(for coordinate: Coordinate) {
        placeLookup?.cancel()
        placeLookup = Task {
            guard let name = await PlaceNameResolver.name(for: coordinate), !Task.isCancelled else { return }
            place = (name, coordinate)
            // Only while the reading is still for this spot.
            guard var quality = currentAQI, lastQueryCoordinate == coordinate else { return }
            quality.placeName = name
            currentAQI = quality
            SharedDataStore.save(quality, queryCoordinate: coordinate, fetchedAt: lastRefreshed ?? Date())
            #if os(iOS)
            WatchSync.shared.push()
            #endif
        }
    }

    /// Whether this store's data is missing, older than the cache TTL, or —
    /// for the current location — no longer describes where the device is.
    public var isStale: Bool {
        guard let lastRefreshed else { return true }
        let age = Date().timeIntervalSince(lastRefreshed)
        if age >= AppConstants.cacheTTL { return true }
        if currentAQI?.model == nil, age >= AppConstants.incompleteReadingRetry { return true }
        return hasMovedSinceLastFetch
    }

    private var hasMovedSinceLastFetch: Bool {
        guard isCurrentLocation, let here = locationService.coordinate.map(Coordinate.init) else { return false }
        // A reading from the IP lookup is superseded as soon as GPS is available.
        guard let lastQueryCoordinate else { return true }
        return here.distance(to: lastQueryCoordinate) > AppConstants.relocationThreshold
    }

    private func apply(_ quality: AirQuality, queryCoordinate: Coordinate?) {
        currentAQI = quality
        lastRefreshed = Date()
        lastQueryCoordinate = queryCoordinate
        state = .loaded

        // The shared cache feeds the widgets, Watch and background refresh, which
        // all describe the user's own location — saved cities must not overwrite it.
        if isCurrentLocation {
            SharedDataStore.save(quality, queryCoordinate: queryCoordinate)
            #if os(iOS)
            WatchSync.shared.push()
            #endif
        }
    }
}
