import Foundation

/// Manages saved locations and their associated AirQualityStores.
@MainActor
@Observable
public final class LocationManager {
    public private(set) var locations: [SavedLocation] = []
    public var selectedLocationID: UUID?

    /// A lazily filled cache, created from inside view bodies. Not observed: views
    /// watch each store's own data, and a store being added must not invalidate them all.
    @ObservationIgnored
    private var stores: [UUID: AirQualityStore] = [:]
    private let reader: AirReadingService
    private let locationService: LocationService

    private static let maxLocations = 6

    public init(reader: AirReadingService, locationService: LocationService) {
        self.reader = reader
        self.locationService = locationService
        loadLocations()
        ensureCurrentLocation()
        // seedDemoCitiesIfEmpty() — removed: users should start with just their current location
    }

    // MARK: - Current Location

    /// Returns the "Current Location" entry, creating one if needed.
    private func ensureCurrentLocation() {
        if !locations.contains(where: \.isCurrentLocation) {
            let current = SavedLocation(
                name: "Current Location",
                coordinate: Coordinate(latitude: 0, longitude: 0),
                isCurrentLocation: true
            )
            locations.insert(current, at: 0)
            saveLocations()
        }
        if selectedLocationID == nil {
            selectedLocationID = locations.first?.id
        }
    }

    // MARK: - Store Access

    public func store(for location: SavedLocation) -> AirQualityStore {
        if let existing = stores[location.id] {
            return existing
        }
        let store = AirQualityStore(
            reader: reader,
            locationService: locationService,
            isCurrentLocation: location.isCurrentLocation
        )
        stores[location.id] = store
        return store
    }

    /// Refresh a specific location — uses GPS for current, coordinates for saved cities.
    public func refresh(location: SavedLocation) async {
        let locationStore = store(for: location)
        let before = locationStore.currentAQI?.timestamp
        if location.isCurrentLocation {
            await locationStore.refresh()
        } else {
            await locationStore.fetch(at: location.coordinate, stationID: location.stationID)
            if location.stationID == nil { adoptStationID(for: location) }
        }
        await processAlerts(for: location, previousTimestamp: before)
    }

    /// Cities saved before station IDs were stored are looked up by coordinate.
    /// Once a coordinate lookup lands on the station the city was saved from
    /// (within 2 km), remember its ID so future fetches stay on it.
    private func adoptStationID(for location: SavedLocation) {
        guard let station = store(for: location).currentAQI?.station,
              station.coordinate.distance(to: location.coordinate) <= 2_000,
              let index = locations.firstIndex(where: { $0.id == location.id })
        else { return }
        locations[index] = SavedLocation(
            id: location.id,
            name: location.name,
            coordinate: location.coordinate,
            stationID: station.id
        )
        saveLocations()
    }

    /// New measurements go through the alert engine (which also re-plans the
    /// daily notifications when it's the current location).
    private func processAlerts(for location: SavedLocation, previousTimestamp: Date?) async {
        guard let quality = store(for: location).currentAQI,
              quality.timestamp != previousTimestamp
        else { return }
        await AlertCoordinator.process([(location: location, quality: quality)])
    }

    public var canAddLocation: Bool {
        locations.count < Self.maxLocations
    }

    public var selectedStore: AirQualityStore? {
        guard let id = selectedLocationID,
              let location = locations.first(where: { $0.id == id })
        else { return nil }
        return store(for: location)
    }

    // MARK: - Add / Remove

    /// Adds a city, shows it, and fetches it straight away rather than waiting
    /// for the user to swipe to an empty page.
    public func addLocation(_ location: SavedLocation) {
        guard locations.count < Self.maxLocations else { return }
        guard !locations.contains(where: { $0.id == location.id }) else { return }
        locations.append(location)
        saveLocations()
        selectedLocationID = location.id
        Task { await refresh(location: location) }
    }

    public func removeLocation(at offsets: IndexSet) {
        // Don't allow removing current location
        let filtered = offsets.filter { !locations[$0].isCurrentLocation }
        let removed = filtered.map { locations[$0] }
        locations.remove(atOffsets: IndexSet(filtered))
        for location in removed {
            stores.removeValue(forKey: location.id)
            AlertCoordinator.forget(location)
        }
        saveLocations()
    }

    public func removeLocation(_ location: SavedLocation) {
        guard !location.isCurrentLocation else { return }
        stores.removeValue(forKey: location.id)
        locations.removeAll { $0.id == location.id }
        AlertCoordinator.forget(location)
        saveLocations()
    }

    // MARK: - Refresh

    public func refreshAll() async {
        for location in locations {
            await refresh(location: location)
        }
    }

    public func refreshIfNeeded() async {
        for location in locations where store(for: location).isStale {
            await refresh(location: location)
        }
    }

    // MARK: - Demo Seed

    /// Seeds 5 world capitals on first launch so the user can test multi-location paging.
    private func seedDemoCitiesIfEmpty() {
        // Only seed if we have just the current location (i.e. fresh install)
        let savedCount = locations.filter { !$0.isCurrentLocation }.count
        guard savedCount == 0 else { return }

        let cities: [(String, Double, Double)] = [
            ("London", 51.5074, -0.1278),
            ("Tokyo", 35.6762, 139.6503),
            ("New Delhi", 28.6139, 77.2090),
            ("New York", 40.7128, -74.0060),
            ("Beijing", 39.9042, 116.4074),
        ]

        for (name, lat, lng) in cities {
            let loc = SavedLocation(
                name: name,
                coordinate: Coordinate(latitude: lat, longitude: lng),
                isCurrentLocation: false
            )
            locations.append(loc)
        }
        saveLocations()
    }

    // MARK: - Persistence

    private func saveLocations() {
        SavedLocationStore.save(locations)
    }

    private func loadLocations() {
        locations = SavedLocationStore.load()
    }
}
