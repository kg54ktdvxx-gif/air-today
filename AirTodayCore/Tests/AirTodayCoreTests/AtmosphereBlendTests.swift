import Foundation
import Testing
@testable import AirTodayCore

@Suite("Atmosphere blending across a swipe")
struct AtmosphereBlendTests {
    private func params(aqi: Int, wind: Double = 0) -> AtmosphereParameters {
        let quality = AirQuality(
            aqi: aqi,
            dominantPollutant: .pm25,
            pollutants: [],
            weather: Weather(windSpeed: wind),
            station: Station(id: 1, name: "Test", coordinate: Coordinate(latitude: 0, longitude: 0), url: ""),
            timestamp: Date(timeIntervalSince1970: 1_792_900_000),
            attribution: [],
            timeZoneOffset: 0
        )
        return AtmosphereParameters(from: quality, at: Date(timeIntervalSince1970: 1_792_900_000))
    }

    @Test("Endpoints are exactly the two cities")
    func endpoints() {
        let clean = params(aqi: 20), smoggy = params(aqi: 180, wind: 8)
        #expect(clean.blended(with: smoggy, fraction: 0) == clean)
        #expect(clean.blended(with: smoggy, fraction: 1).hazeDensity == smoggy.hazeDensity)
        #expect(clean.blended(with: smoggy, fraction: 1).particleConfig == smoggy.particleConfig)
    }

    @Test("Haze and particles move smoothly through the middle")
    func midpoint() {
        let clean = params(aqi: 20), smoggy = params(aqi: 180)
        let quarter = clean.blended(with: smoggy, fraction: 0.25)
        let threeQuarters = clean.blended(with: smoggy, fraction: 0.75)

        // Monotonic, with no jump at 0.5.
        #expect(clean.hazeDensity < quarter.hazeDensity)
        #expect(quarter.hazeDensity < threeQuarters.hazeDensity)
        #expect(threeQuarters.hazeDensity < smoggy.hazeDensity)
        let justBefore = clean.blended(with: smoggy, fraction: 0.49).particleConfig.birthRate
        let justAfter = clean.blended(with: smoggy, fraction: 0.51).particleConfig.birthRate
        #expect(abs(justAfter - justBefore) < 2)
    }

    @Test("The atmosphere follows the chosen scale's severity")
    func followsScale() {
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        // US AQI 40 (Good) while the EEA index is 85 (Very poor).
        let model = Fixture.model(current: now) { Fixture.sample($0, us: 40, eu: 85) }
        let quality = Fixture.station(aqi: 40, at: now, model: model)
        let us = AtmosphereParameters(from: quality, scale: .usEPA, at: now)
        let eu = AtmosphereParameters(from: quality, scale: .euEAQI, at: now)
        #expect(us.hazeDensity < eu.hazeDensity)
        #expect(eu == AtmosphereParameters(from: Fixture.station(aqi: Severity.equivalentUSAQI(at: Severity.position(of: 85, on: .euEAQI)), at: now), at: now))
    }

    @Test("Fractions outside 0…1 are clamped")
    func clamped() {
        let a = params(aqi: 20), b = params(aqi: 180)
        #expect(a.blended(with: b, fraction: -0.3) == a)
        #expect(a.blended(with: b, fraction: 1.4).hazeDensity == b.hazeDensity)
    }
}
