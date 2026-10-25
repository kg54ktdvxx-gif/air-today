import Foundation

/// CAMS air-quality model output for one place (via Open-Meteo): the current
/// estimate plus an hourly series from 24 hours ago to several days ahead, and the
/// current weather from Open-Meteo's forecast models.
public struct ModelAirData: Codable, Sendable, Equatable {
    public let current: ModelSample
    /// Ascending by time. Starts a day in the past so running means (UK DAQI) work from the first hour.
    public let hourly: [ModelSample]
    /// Where the model was asked about.
    public let coordinate: Coordinate
    /// The place's offset from GMT, for local-hour logic.
    public let utcOffsetSeconds: Int
    public let fetchedAt: Date
    /// Nil if the weather request failed; the air data stands on its own.
    public let weather: Weather?

    public init(
        current: ModelSample,
        hourly: [ModelSample],
        coordinate: Coordinate,
        utcOffsetSeconds: Int,
        fetchedAt: Date,
        weather: Weather? = nil
    ) {
        self.current = current
        self.hourly = hourly
        self.coordinate = coordinate
        self.utcOffsetSeconds = utcOffsetSeconds
        self.fetchedAt = fetchedAt
        self.weather = weather
    }

    /// Hours from the current hour onwards.
    public func upcoming(from now: Date) -> [ModelSample] {
        let hourStart = now.addingTimeInterval(-3599)
        return hourly.filter { $0.time >= hourStart }
    }

    /// Index of the last hourly sample at or before `date`.
    func hourIndex(atOrBefore date: Date) -> Int? {
        hourly.lastIndex { $0.time <= date }
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
        return calendar
    }
}

/// One step of model output.
public struct ModelSample: Codable, Sendable, Equatable {
    public let time: Date
    /// Overall US EPA AQI (EPA averaging periods, computed by Open-Meteo).
    public let usAQI: Int?
    /// Overall European AQI (EEA bands, revised 2024).
    public let europeanAQI: Int?
    public let usSubIndices: [Pollutant.Kind: Int]
    public let europeanSubIndices: [Pollutant.Kind: Int]
    /// µg/m³.
    public let concentrations: [Pollutant.Kind: Double]
    public let uvIndex: Double?

    public init(
        time: Date,
        usAQI: Int?,
        europeanAQI: Int?,
        usSubIndices: [Pollutant.Kind: Int] = [:],
        europeanSubIndices: [Pollutant.Kind: Int] = [:],
        concentrations: [Pollutant.Kind: Double] = [:],
        uvIndex: Double? = nil
    ) {
        self.time = time
        self.usAQI = usAQI
        self.europeanAQI = europeanAQI
        self.usSubIndices = usSubIndices
        self.europeanSubIndices = europeanSubIndices
        self.concentrations = concentrations
        self.uvIndex = uvIndex
    }

    /// The pollutant with the highest US sub-index.
    public var usDominant: Pollutant.Kind? {
        usSubIndices.max { $0.value < $1.value }?.key
    }
}
