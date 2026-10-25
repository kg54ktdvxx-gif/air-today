import Foundation
import Testing
@testable import AirTodayCore

/// Fixtures mirror a real WAQI demo-token response for Shanghai (2026-10-25).
@Suite("WAQI feed parsing")
struct WAQIParsingTests {
    private static let shanghaiTime = WAQITime(
        s: "2026-10-25 10:00:00",
        tz: "+08:00",
        v: 1_792_922_400,
        iso: "2026-10-25T10:00:00+08:00"
    )

    private static let forecastJSON = """
    {"daily": {
      "pm25": [
        {"avg": 61, "day": "2026-10-24", "max": 70, "min": 50},
        {"avg": 55, "day": "2026-10-25", "max": 68, "min": 42},
        {"avg": 48, "day": "2026-10-26", "max": 59, "min": 35}
      ],
      "uvi": [
        {"avg": 2, "day": "2026-10-24", "max": 5, "min": 0},
        {"avg": 3, "day": "2026-10-25", "max": 6, "min": 0}
      ]
    }}
    """

    private static func forecast() throws -> WAQIForecast {
        try JSONDecoder().decode(WAQIForecast.self, from: Data(forecastJSON.utf8))
    }

    @Test("Measurement time comes from the offset-qualified iso field")
    func measurementTimeFromISO() {
        let date = AirQualityService.parseMeasurementTime(Self.shanghaiTime, timeZoneOffset: 8 * 3600)
        // 10:00 in Shanghai is 02:00 UTC.
        #expect(date == Date(timeIntervalSince1970: 1_792_893_600))
    }

    @Test("Without iso, v is corrected by the station offset")
    func measurementTimeFromLocalEpoch() {
        let time = WAQITime(s: nil, tz: "+08:00", v: 1_792_922_400, iso: nil)
        let date = AirQualityService.parseMeasurementTime(time, timeZoneOffset: 8 * 3600)
        #expect(date == Date(timeIntervalSince1970: 1_792_893_600))
    }

    @Test("Timezone offsets parse with sign and minutes")
    func timeZoneOffsets() {
        #expect(AirQualityService.parseTimeZoneOffset("+08:00") == 28_800)
        #expect(AirQualityService.parseTimeZoneOffset("-03:30") == -12_600)
        #expect(AirQualityService.parseTimeZoneOffset("+05:45") == 20_700)
        #expect(AirQualityService.parseTimeZoneOffset(nil) == nil)
    }

    @Test("Station today follows the station's timezone, not the device's")
    func stationToday() {
        // 2026-10-24 20:00 UTC is already the 25th in Shanghai but still the 24th in New York.
        let instant = Date(timeIntervalSince1970: 1_792_872_000)
        #expect(AirQuality.todayDateString(timeZoneOffset: 8 * 3600, now: instant) == "2026-10-25")
        #expect(AirQuality.todayDateString(timeZoneOffset: -4 * 3600, now: instant) == "2026-10-24")
    }

    @Test("Forecast drops days before the station's today")
    func forecastFiltersPastDays() throws {
        let days = AirQualityService.parseForecast(from: try Self.forecast(), today: "2026-10-25")
            .filter { $0.pollutant == .pm25 }
            .map(\.day)
        #expect(days == ["2026-10-25", "2026-10-26"])
    }

    @Test("UV forecast drops days before the station's today")
    func uvForecastFiltersPastDays() throws {
        let uv = AirQualityService.parseUVIForecast(from: try Self.forecast(), today: "2026-10-25")
        #expect(uv.map(\.day) == ["2026-10-25"])
        #expect(uv.first?.max == 6)
    }
}

@Suite("Reading freshness")
struct FreshnessTests {
    private func quality(measuredAt date: Date) -> AirQuality {
        AirQuality(
            aqi: 172,
            dominantPollutant: .pm25,
            pollutants: [],
            weather: Weather(),
            station: Station(id: 7021, name: "Kolkata US Consulate", coordinate: Coordinate(latitude: 22.5, longitude: 88.3), url: ""),
            forecast: [],
            timestamp: date,
            attribution: []
        )
    }

    @Test("A reading from hours ago is still current")
    func recentIsFresh() throws {
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        try AirQualityService.checkFreshness(quality(measuredAt: now.addingTimeInterval(-3 * 3600)), now: now)
    }

    @Test("A station's months-old last reading is rejected as stale")
    func oldIsStale() {
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        // Kolkata US Consulate's last report, still served by WAQI in Oct 2026.
        let lastReport = Date(timeIntervalSince1970: 1_740_151_800)
        #expect(throws: AirQualityError.self) {
            try AirQualityService.checkFreshness(quality(measuredAt: lastReport), now: now)
        }
    }
}
