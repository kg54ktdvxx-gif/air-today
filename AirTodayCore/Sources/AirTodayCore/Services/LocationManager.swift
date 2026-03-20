import Foundation

/// Manages saved locations and their associated AirQualityStores.
@MainActor
@Observable
public final class LocationManager {
    public private(set) var locations: [SavedLocation] = []
    public var selectedLocationID: UUID?

    private var stores: [UUID: AirQualityStore] = [:]
    private let service: AirQualityServiceProtocol
    private let locationService: LocationService

    private static let maxLocations = 6
    private static let storageKey = "saved_locations"

    public init(service: AirQualityServiceProtocol, locationService: LocationService) {
        self.service = service
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
            service: service,
            locationService: locationService,
            isCurrentLocation: location.isCurrentLocation
        )
        stores[location.id] = store
        return store
    }

    /// Refresh a specific location — uses GPS for current, coordinates for saved cities.
    public func refresh(location: SavedLocation) async {
        let locationStore = store(for: location)
        if location.isCurrentLocation {
            await locationStore.refresh()
        } else {
            await locationStore.fetchForStation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    public var selectedStore: AirQualityStore? {
        guard let id = selectedLocationID,
              let location = locations.first(where: { $0.id == id })
        else { return nil }
        return store(for: location)
    }

    // MARK: - Add / Remove

    public func addLocation(_ location: SavedLocation) {
        guard locations.count < Self.maxLocations else { return }
        guard !locations.contains(where: { $0.id == location.id }) else { return }
        locations.append(location)
        saveLocations()
    }

    public func removeLocation(at offsets: IndexSet) {
        let idsToRemove = offsets.map { locations[$0].id }
        // Don't allow removing current location
        let filtered = offsets.filter { !locations[$0].isCurrentLocation }
        locations.remove(atOffsets: IndexSet(filtered))
        for id in idsToRemove {
            stores.removeValue(forKey: id)
        }
        saveLocations()
    }

    public func removeLocation(_ location: SavedLocation) {
        guard !location.isCurrentLocation else { return }
        stores.removeValue(forKey: location.id)
        locations.removeAll { $0.id == location.id }
        saveLocations()
    }

    // MARK: - Refresh

    public func refreshAll() async {
        for location in locations {
            await refresh(location: location)
        }
    }

    public func refreshIfNeeded() async {
        for location in locations {
            let locationStore = store(for: location)
            if location.isCurrentLocation {
                await locationStore.refreshIfNeeded()
            } else if locationStore.isStale {
                await locationStore.fetchForStation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
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
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        let nonCurrent = locations.filter { !$0.isCurrentLocation }
        if let data = try? JSONEncoder().encode(nonCurrent) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func loadLocations() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
              let data = defaults.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([SavedLocation].self, from: data)
        else { return }
        locations = saved
    }
}
