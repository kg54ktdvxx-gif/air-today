import Foundation
import Testing
@testable import AirTodayCore

/// Bands from EPA AirNow's AQI basics, the EEA's European Air Quality Index (2024
/// revision) and Defra's DAQI tables; the ladder placement from each publisher's advice.
@Suite("AQI scales and the severity ladder")
struct AQIScaleTests {
    // MARK: - Severity ladder

    @Test("US EPA values sit inside their own category on the ladder")
    func usLadder() {
        #expect(Severity.position(usAQI: 0) == 0)
        #expect(Severity.position(usAQI: 50) < 1)
        #expect(Severity.position(usAQI: 51) == 1)
        #expect(Severity.level(at: Severity.position(usAQI: 100)) == .moderate)
        #expect(Severity.level(at: Severity.position(usAQI: 101)) == .sensitive)
        #expect(Severity.level(at: Severity.position(usAQI: 500)) == .hazardous)
        #expect(Severity.position(usAQI: 650) < 6)
    }

    @Test("EEA bands map by advice: Good and Fair both advise usual activity")
    func europeanLadder() {
        let levels = [10, 39, 40, 59, 60, 80, 100, 250].map { Severity.level(at: Severity.position(of: $0, on: .euEAQI)) }
        #expect(levels == [.good, .good, .moderate, .moderate, .sensitive, .unhealthy, .veryUnhealthy, .veryUnhealthy])
    }

    @Test("DAQI bands map by advice: Very High is EPA's Unhealthy")
    func ukLadder() {
        let levels = (1...10).map { Severity.level(at: Severity.position(of: $0, on: .ukDAQI)) }
        #expect(levels == [.good, .good, .good, .moderate, .moderate, .moderate, .sensitive, .sensitive, .sensitive, .unhealthy])
    }

    @Test("Equivalent US AQI round-trips US values and places other scales")
    func equivalentAQI() {
        for aqi in [0, 25, 51, 75, 101, 149, 180, 250, 400] {
            #expect(Severity.equivalentUSAQI(at: Severity.position(usAQI: aqi)) == aqi)
        }
        // EEA 50 is halfway through Moderate.
        #expect(Severity.equivalentUSAQI(at: Severity.position(of: 50, on: .euEAQI)) == 75)
    }

    // MARK: - Bands

    @Test("EEA band names and colours follow the 20-point bands")
    func europeanBands() {
        #expect([10, 20, 45, 65, 85, 120].map { AQIScale.euEAQI.band(forValue: $0).name }
            == ["Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"])
    }

    @Test("DAQI index bands whole µg/m³")
    func daqiBands() {
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 11) == 1)
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 11.4) == 1)
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 11.6) == 2)
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 36) == 4)
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 70) == 9)
        #expect(DAQIBands.index(of: .pm25, microgramsPerCubicMetre: 71) == 10)
        #expect(DAQIBands.index(of: .o3, microgramsPerCubicMetre: 100) == 3)
        #expect(DAQIBands.index(of: .o3, microgramsPerCubicMetre: 101) == 4)
        #expect(DAQIBands.index(of: .no2, microgramsPerCubicMetre: 68) == 2)
        #expect(DAQIBands.index(of: .co, microgramsPerCubicMetre: 500) == nil)
        #expect(AQIScale.ukDAQI.band(forValue: 5).name == "Moderate")
    }

    @Test("DAQI averages particles over 24 hours and ozone over 8")
    func daqiAveraging() {
        let start = Fixture.date(hour: 0)
        func hours(_ count: Int, _ concentrations: (Int) -> [Pollutant.Kind: Double]) -> [ModelSample] {
            (0..<count).map { Fixture.sample(start.addingTimeInterval(TimeInterval($0 * 3600)), us: nil, concentrations: concentrations($0)) }
        }

        // 23 clean hours then one at 80 µg/m³: the 24-hour mean is 5.6 → 1, not the hour's 10.
        let spike = hours(24) { [.pm25: $0 == 23 ? 80 : 2.5] }
        #expect(DAQICalculator.indices(at: 23, in: spike)[.pm25] == 1)

        // Too little history for a fair 24-hour mean.
        let short = hours(10) { _ in [.pm25: 40] }
        #expect(DAQICalculator.indices(at: 9, in: short)[.pm25] == nil)

        // Seven hours at 50 µg/m³ and one at 130: the 8-hour mean (60) is index 2.
        let ozone = hours(8) { [.o3: $0 == 7 ? 130 : 50] }
        #expect(DAQICalculator.indices(at: 7, in: ozone)[.o3] == 2)
        // NO₂ is hourly.
        let no2 = hours(3) { [.no2: $0 == 2 ? 300 : 10] }
        #expect(DAQICalculator.indices(at: 2, in: no2)[.no2] == 5)
    }

    // MARK: - Readings

    @Test("EU and UK readings come from the model; without it they're nil and the US scale stands in")
    func readings() throws {
        let now = Fixture.date(hour: 12)
        let model = Fixture.model(current: now) { time in
            Fixture.sample(time, us: 60, eu: 45, dominant: .pm10, concentrations: [.pm10: 62, .pm25: 8])
        }
        let quality = Fixture.station(aqi: 60, at: now.addingTimeInterval(-1800), dominant: .pm10, model: model)

        let eu = try #require(AQIScale.euEAQI.reading(for: quality))
        #expect(eu.value == 45)
        #expect(eu.dominantPollutant == .pm10)

        // PM10 62 µg/m³ for a day → DAQI 5; PM2.5 8 → 1.
        let uk = try #require(AQIScale.ukDAQI.reading(for: quality))
        #expect(uk.value == 5)
        #expect(uk.dominantPollutant == .pm10)

        let stationOnly = Fixture.station(aqi: 60, at: now)
        #expect(AQIScale.euEAQI.reading(for: stationOnly) == nil)
        let shown = AQIScale.ukDAQI.displayReading(for: stationOnly)
        #expect(shown.scale == .usEPA)
        #expect(shown.reading.value == 60)
    }

    @Test("Pollutant sub-indices per scale; CO isn't on the EU or UK index")
    func subIndices() {
        let now = Fixture.date(hour: 12)
        let model = Fixture.model(current: now) { time in
            ModelSample(time: time, usAQI: 60, europeanAQI: 45, usSubIndices: [.pm10: 60], europeanSubIndices: [.pm10: 45], concentrations: [.pm10: 62])
        }
        let quality = Fixture.station(
            aqi: 60, at: now, pollutants: [Pollutant(kind: .pm10, aqi: 60), Pollutant(kind: .co, aqi: 12)], model: model
        )
        #expect(AQIScale.usEPA.subIndex(for: .co, in: quality) == 12)
        #expect(AQIScale.euEAQI.subIndex(for: .pm10, in: quality) == 45)
        #expect(AQIScale.euEAQI.subIndex(for: .co, in: quality) == nil)
        #expect(AQIScale.ukDAQI.subIndex(for: .pm10, in: quality) == 5)
    }

    @Test("The hourly series starts at the current hour")
    func hourlySeries() throws {
        let now = Fixture.date(hour: 12, minute: 40)
        let model = Fixture.model(current: now) { time in
            Fixture.sample(time, us: Fixture.utc.component(.hour, from: time), eu: 10)
        }
        let series = AQIScale.usEPA.hourlySeries(for: Fixture.modelled(model), now: now)
        #expect(series.first?.time == Fixture.date(hour: 12))
        #expect(series.first?.value == 12)
        #expect(series.last?.time == Fixture.date(day: 27, hour: 23))
        #expect(AQIScale.euEAQI.hourlySeries(for: Fixture.modelled(model), pollutant: .pm25, now: now).first?.value == 10)
    }

    @Test("UK alert levels stop at Very High, which sits at Unhealthy")
    func alertLevels() {
        #expect(AQIScale.ukDAQI.alertLevels.last == .unhealthy)
        #expect(AQIScale.ukDAQI.bandName(for: .unhealthy) == "Very High (10)")
        #expect(AQIScale.euEAQI.bandName(for: .sensitive) == "Poor")
    }
}
