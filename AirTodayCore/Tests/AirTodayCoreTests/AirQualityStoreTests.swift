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

/// Shares the app-group cache, so these tests must not run in parallel.
@Suite("AirQualityStore shared cache", .serialized)
@MainActor
struct AirQualityStoreTests {
    private static func quality(stationName: String) -> AirQuality {
        AirQuality(
            aqi: 42,
            dominantPollutant: .pm25,
            pollutants: [],
            weather: Weather(),
            station: Station(id: 1, name: stationName, coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            forecast: [],
            timestamp: Date(timeIntervalSince1970: 0),
            attribution: []
        )
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
            service: StubService(quality: Self.quality(stationName: "Tokyo")),
            locationService: LocationService(),
            isCurrentLocation: false
        )

        await store.fetchForStation(latitude: 35.68, longitude: 139.65)

        #expect(store.currentAQI?.station.name == "Tokyo")
        #expect(SharedDataStore.load() == nil)
    }

    @Test("The current location writes the shared cache")
    func currentLocationWritesSharedCache() async {
        Self.clearSharedCache()
        let store = AirQualityStore(
            service: StubService(quality: Self.quality(stationName: "Here")),
            locationService: LocationService(),
            isCurrentLocation: true
        )

        await store.refresh()

        #expect(SharedDataStore.load()?.station.name == "Here")
        Self.clearSharedCache()
    }

    @Test("Staleness uses fetch time, not the station's measurement time")
    func stalenessUsesFetchTime() async {
        // The stub's measurement timestamp is 1970; a fresh fetch must still count as fresh.
        let store = AirQualityStore(
            service: StubService(quality: Self.quality(stationName: "Old reading")),
            locationService: LocationService(),
            isCurrentLocation: false
        )

        await store.fetchForStation(latitude: 0, longitude: 0)

        #expect(store.isStale == false)
    }
}
