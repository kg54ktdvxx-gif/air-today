import Foundation

/// The air at one place: a headline US EPA reading plus everything shown around it.
///
/// The headline comes from the nearest WAQI station when it's recent and close, and
/// from the CAMS model otherwise (`ReadingComposer`). The model's hourly data rides
/// along for the forecast, best time and the EU/UK scales.
public struct AirQuality: Codable, Sendable {
    /// Overall US EPA AQI of the headline source.
    public let aqi: Int
    public let level: AQILevel
    public let dominantPollutant: Pollutant.Kind?
    /// US EPA sub-index per pollutant, from the headline source.
    public let pollutants: [Pollutant]
    /// From the station feed when there is one.
    public let weather: Weather
    /// The WAQI station that reported, if any — even when the model supplied the headline.
    public let station: Station?
    public let source: ReadingSource
    public let model: ModelAirData?
    /// When the headline was measured (station) or valid (model).
    public let timestamp: Date
    public let attribution: [Attribution]
    /// Offset from GMT in seconds for the place's local time.
    public let timeZoneOffset: Int?
    /// Town name for the current location (looked up on device); nil for saved cities.
    public var placeName: String?

    public init(
        aqi: Int,
        dominantPollutant: Pollutant.Kind?,
        pollutants: [Pollutant],
        weather: Weather,
        station: Station?,
        source: ReadingSource = .station,
        model: ModelAirData? = nil,
        timestamp: Date,
        attribution: [Attribution],
        timeZoneOffset: Int? = nil,
        placeName: String? = nil
    ) {
        self.aqi = aqi
        self.level = AQILevel(aqi: aqi)
        self.dominantPollutant = dominantPollutant
        self.pollutants = pollutants
        self.weather = weather
        self.station = station
        self.source = source
        self.model = model
        self.timestamp = timestamp
        self.attribution = attribution
        self.timeZoneOffset = timeZoneOffset
        self.placeName = placeName
    }

    /// What to call the current location: the looked-up town, else the reporting
    /// station's name up to its first comma.
    public var locationLabel: String? {
        placeName ?? station.map { $0.name.components(separatedBy: ",").first ?? $0.name }
    }

    /// Where this reading is for: the station's position, else the model's.
    public var coordinate: Coordinate? {
        station?.coordinate ?? model?.coordinate
    }

    /// Today's highest forecast UV index at this place, from the model.
    public func todayUVPeak(now: Date = Date()) -> Double? {
        guard let model else { return nil }
        let calendar = model.calendar
        return model.hourly
            .filter { calendar.isDate($0.time, inSameDayAs: now) }
            .compactMap(\.uvIndex)
            .max()
    }

    /// This place as the model sees it at another hour — for forecast verdicts.
    /// Station details are dropped: they describe now, not then.
    public func atModelHour(_ sample: ModelSample) -> AirQuality? {
        guard let model, let aqi = sample.usAQI else { return nil }
        return AirQuality(
            aqi: aqi,
            dominantPollutant: sample.usDominant,
            pollutants: sample.usSubIndices.map { Pollutant(kind: $0.key, aqi: Double($0.value)) },
            weather: Weather(),
            station: nil,
            source: .model,
            model: ModelAirData(current: sample, hourly: model.hourly, coordinate: model.coordinate, utcOffsetSeconds: model.utcOffsetSeconds, fetchedAt: model.fetchedAt, weather: model.weather),
            timestamp: sample.time,
            attribution: attribution,
            timeZoneOffset: model.utcOffsetSeconds,
            placeName: placeName
        )
    }

    /// Returns today's date string (yyyy-MM-dd) in the place's local timezone.
    static func todayDateString(timeZoneOffset: Int?, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        if let offset = timeZoneOffset {
            f.timeZone = TimeZone(secondsFromGMT: offset) ?? .current
        } else {
            f.timeZone = .current
        }
        return f.string(from: now)
    }
}

/// Where the headline reading came from.
public enum ReadingSource: String, Codable, Sendable {
    /// A WAQI monitoring station's measurement.
    case station
    /// The CAMS model's estimate for the area.
    case model
}

public enum LoadingState: Sendable {
    case idle
    case loading
    case loaded
    case error(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
