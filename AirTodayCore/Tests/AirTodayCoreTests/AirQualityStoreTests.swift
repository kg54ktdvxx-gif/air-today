import Foundation
import Testing
@testable import AirTodayCore

private struct StubService: AirQualityServiceProtocol {
    let quality: AirQuality

    func fetchCurrent(latitude: Double, longitude: Double) async throws -> AirQuality { quality }
    func fetchCurrent(city: String) async throws -> AirQuality { quality }
    func fetchStation(id: Int) async throws -> AirQuality { quality }
    func search(keyword: String) async throws -> [StationSummary] { [] }
    func fetchMapBounds(lat1: Double, lng1: Double, lat2: Double, lng2: Double) async throws -> [MapStation] { [] }
}

/// The model is offline, so the station alone decides.
private struct NoModel: ModelAirServiceProtocol {
    func fetch(latitude: Double, longitude: Double) async throws -> ModelAirData { throw AirQualityError.noData }
}

private func reader(_ quality: AirQuality) -> AirReadingService {
    AirReadingService(stations: StubService(quality: quality), model: NoModel())
}

/// Every suite that reads or writes the app-group store nests in here, so they
/// run one at a time instead of racing each other.
@Suite("Shared store", .serialized)
enum SharedStoreSuites {}

extension SharedStoreSuites {
@Suite("AirQualityStore shared cache")
@MainActor
struct AirQualityStoreTests {
    /// Measured two hours ago: older than the cache lifetime, well within the 24 hours a station reading lasts.
    private static func quality(stationName: String) -> AirQuality {
        Fixture.station(aqi: 42, at: Date().addingTimeInterval(-2 * 3600), name: stationName)
    }

    private static func clearSharedCache() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        defaults?.removeObject(forKey: "cached_air_quality")
        defaults?.removeObject(forKey: "cached_timestamp")
    }

    @Test("A saved city never overwrites the widget's current-location cache")
    func savedCityDoesNotWriteSharedCache() async {
        Self.clearSharedCache()
        let store = AirQualityStore(
            reader: reader(Self.quality(stationName: "Tokyo")),
            locationService: LocationService(),
            isCurrentLocation: false
        )

        await store.fetch(at: Fixture.london, stationID: 1)

        #expect(store.currentAQI?.station?.name == "Tokyo")
        #expect(SharedDataStore.load() == nil)
    }

    @Test("The current location writes the shared cache")
    func currentLocationWritesSharedCache() async {
        Self.clearSharedCache()
        let store = AirQualityStore(
            reader: reader(Self.quality(stationName: "Here")),
            locationService: LocationService(),
            isCurrentLocation: true
        )

        await store.refresh()

        #expect(SharedDataStore.load()?.station?.name == "Here")
        Self.clearSharedCache()
    }

    @Test("Staleness uses fetch time, not the station's measurement time")
    func stalenessUsesFetchTime() async {
        // The measurement is older than the cache lifetime; a fresh fetch must still count as fresh.
        let store = AirQualityStore(
            reader: reader(Self.quality(stationName: "Old reading")),
            locationService: LocationService(),
            isCurrentLocation: false
        )

        await store.fetch(at: Fixture.london, stationID: 1)

        #expect(store.currentAQI != nil)
        #expect(store.isStale == false)
    }
}
}
