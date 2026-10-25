import Foundation
import Testing
@testable import AirTodayCore

extension SharedStoreSuites {
@Suite("Watch sync merge rules")
struct WatchSyncTests {
    private func reading(aqi: Int, at seconds: TimeInterval) -> AirQuality {
        AirQuality(
            aqi: aqi,
            dominantPollutant: .pm25,
            pollutants: [],
            weather: Weather(),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            forecast: [],
            timestamp: Date(timeIntervalSince1970: seconds),
            attribution: []
        )
    }

    private func context(for quality: AirQuality, extra: [String: Any] = [:]) throws -> [String: Any] {
        var context = extra
        context["reading"] = try JSONEncoder().encode(quality)
        return context
    }

    @Test("A newer iPhone reading replaces the Watch's")
    func newerWins() throws {
        SharedDataStore.clear()
        SharedDataStore.save(reading(aqi: 40, at: 1_000), queryCoordinate: nil)
        WatchSync.apply(try context(for: reading(aqi: 90, at: 2_000)))
        #expect(SharedDataStore.load()?.aqi == 90)
        SharedDataStore.clear()
    }

    @Test("An older iPhone reading doesn't overwrite a fresher Watch one")
    func olderLoses() throws {
        SharedDataStore.clear()
        SharedDataStore.save(reading(aqi: 40, at: 3_000), queryCoordinate: nil)
        WatchSync.apply(try context(for: reading(aqi: 90, at: 2_000)))
        #expect(SharedDataStore.load()?.aqi == 40)
        SharedDataStore.clear()
    }

    @Test("Preferences are mirrored")
    func preferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "WatchSyncTests"))
        defaults.removePersistentDomain(forName: "WatchSyncTests")
        WatchSync.apply([
            HealthProfile.Key.respiratory: true,
            AQIScale.storageKey: AQIScale.ukDAQI.rawValue,
        ], defaults: defaults)
        #expect(defaults.bool(forKey: HealthProfile.Key.respiratory))
        #expect(defaults.string(forKey: AQIScale.storageKey) == "ukDAQI")
        defaults.removePersistentDomain(forName: "WatchSyncTests")
    }
}
}
