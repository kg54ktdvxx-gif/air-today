import Foundation
@testable import AirTodayCore

/// Readings and model data for tests, in UTC unless a test says otherwise.
enum Fixture {
    static let london = Coordinate(latitude: 51.5, longitude: -0.12)

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// 25 October 2026 (day 25) at `hour` UTC.
    static func date(day: Int = 25, hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func station(
        aqi: Int,
        at timestamp: Date,
        id: Int = 1,
        name: String = "Test",
        coordinate: Coordinate = london,
        dominant: Pollutant.Kind = .pm25,
        pollutants: [Pollutant]? = nil,
        weather: Weather = Weather(),
        model: ModelAirData? = nil
    ) -> AirQuality {
        AirQuality(
            aqi: aqi,
            dominantPollutant: dominant,
            pollutants: pollutants ?? [Pollutant(kind: dominant, aqi: Double(aqi))],
            weather: weather,
            station: Station(id: id, name: name, coordinate: coordinate, url: ""),
            source: .station,
            model: model,
            timestamp: timestamp,
            attribution: [],
            timeZoneOffset: 0
        )
    }

    static func sample(
        _ time: Date,
        us: Int?,
        eu: Int? = nil,
        dominant: Pollutant.Kind = .pm25,
        concentrations: [Pollutant.Kind: Double] = [:],
        uv: Double? = nil
    ) -> ModelSample {
        ModelSample(
            time: time,
            usAQI: us,
            europeanAQI: eu,
            usSubIndices: us.map { [dominant: $0] } ?? [:],
            europeanSubIndices: eu.map { [dominant: $0] } ?? [:],
            concentrations: concentrations,
            uvIndex: uv
        )
    }

    /// Hourly samples from 00:00 on day 24 (a day of history, as the API sends)
    /// to the end of day 27. `sample` gets each hour's time; `current` picks the
    /// latest hour at or before it.
    static func model(
        current: Date,
        coordinate: Coordinate = london,
        utcOffset: Int = 0,
        weather: Weather? = nil,
        sample: (Date) -> ModelSample
    ) -> ModelAirData {
        let start = date(day: 24, hour: 0)
        let hourly = (0..<(4 * 24)).map { sample(start.addingTimeInterval(TimeInterval($0 * 3600))) }
        let now = hourly.last { $0.time <= current } ?? hourly[0]
        return ModelAirData(
            current: now,
            hourly: hourly,
            coordinate: coordinate,
            utcOffsetSeconds: utcOffset,
            fetchedAt: current,
            weather: weather
        )
    }

    /// A model-sourced reading, as `ReadingComposer` builds one.
    static func modelled(_ model: ModelAirData) -> AirQuality {
        ReadingComposer.compose(station: nil, model: model, query: model.coordinate, stationChosenByUser: false, now: model.fetchedAt)!
    }
}
