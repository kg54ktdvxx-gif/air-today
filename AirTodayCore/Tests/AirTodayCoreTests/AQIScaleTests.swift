import Foundation
import Testing
@testable import AirTodayCore

/// Expected values are worked by hand from WAQI's EPA tables, the CITEAIR
/// hourly grid and Defra's DAQI bands.
@Suite("AQI scale conversion")
struct AQIScaleTests {
    @Test("EPA sub-index inverts to WAQI's (2016) concentrations")
    func epaInversion() throws {
        #expect(try #require(EPABreakpoints.concentration(of: .pm25, fromAQI: 50)) == 12)
        #expect(try #require(EPABreakpoints.concentration(of: .pm25, fromAQI: 100)) == 35.5)
        #expect(try #require(EPABreakpoints.concentration(of: .pm10, fromAQI: 50)) == 55)
        // 0.060 ppm ozone = 60 ppb × 48.00 / 24.04 ≈ 119.8 µg/m³
        #expect(abs(try #require(EPABreakpoints.concentration(of: .o3, fromAQI: 50)) - 119.8) < 0.1)
        // 0.101 ppm NO₂ = 101 ppb × 46.01 / 24.04 ≈ 193.3 µg/m³
        #expect(abs(try #require(EPABreakpoints.concentration(of: .no2, fromAQI: 100)) - 193.3) < 0.1)
        #expect(EPABreakpoints.concentration(of: .co, fromAQI: 50) == nil)
    }

    @Test("CAQI interpolates within the hourly grid")
    func caqi() throws {
        // PM2.5 12 µg/m³ → 12/15 of the first band → 20
        #expect(abs(try #require(AQIScale.euCAQI.subIndex(for: .pm25, epaAQI: 50)) - 20) < 0.01)
        // PM10 55 µg/m³ → 50 + 5/40 × 25 ≈ 53.1
        #expect(abs(try #require(AQIScale.euCAQI.subIndex(for: .pm10, epaAQI: 50)) - 53.125) < 0.01)
        // CAQI doesn't use SO₂
        #expect(AQIScale.euCAQI.subIndex(for: .so2, epaAQI: 80) == nil)
        #expect(AQIScale.euCAQI.band(forValue: 20).name == "Very low")
        #expect(AQIScale.euCAQI.band(forValue: 101).name == "Very high")
    }

    @Test("DAQI bands whole µg/m³")
    func daqi() {
        #expect(AQIScale.ukDAQI.subIndex(for: .pm25, epaAQI: 50) == 2)    // 12 → 12–23
        #expect(AQIScale.ukDAQI.subIndex(for: .pm10, epaAQI: 50) == 4)    // 55 → 51–58
        #expect(AQIScale.ukDAQI.subIndex(for: .o3, epaAQI: 50) == 4)      // 119.8 → 120 → 101–120
        #expect(AQIScale.ukDAQI.subIndex(for: .no2, epaAQI: 100) == 3)    // 193.3 → 135–200
        #expect(AQIScale.ukDAQI.subIndex(for: .pm25, epaAQI: 300) == 10)  // 250.5 → ≥ 71
        #expect(AQIScale.ukDAQI.band(forValue: 5).name == "Moderate")
    }

    @Test("Overall reading is the worst pollutant on the chosen scale")
    func overallReading() throws {
        let quality = AirQuality(
            aqi: 50,
            dominantPollutant: .pm25,
            pollutants: [Pollutant(kind: .pm25, aqi: 50), Pollutant(kind: .pm10, aqi: 50), Pollutant(kind: .co, aqi: 80)],
            weather: Weather(),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            forecast: [],
            timestamp: Date(),
            attribution: []
        )
        // DAQI: PM2.5 → 2, PM10 → 4; CO isn't in DAQI. PM10 drives it.
        let daqi = try #require(AQIScale.ukDAQI.reading(for: quality))
        #expect(daqi.value == 4)
        #expect(daqi.dominantPollutant == .pm10)

        let epa = try #require(AQIScale.usEPA.reading(for: quality))
        #expect(epa.value == 50)
        #expect(epa.dominantPollutant == .pm25)
    }

    @Test("No usable pollutants gives no reading, so the UI can fall back")
    func noReading() {
        let quality = AirQuality(
            aqi: 40,
            dominantPollutant: .co,
            pollutants: [Pollutant(kind: .co, aqi: 40)],
            weather: Weather(),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            forecast: [],
            timestamp: Date(),
            attribution: []
        )
        #expect(AQIScale.euCAQI.reading(for: quality) == nil)
    }
}
