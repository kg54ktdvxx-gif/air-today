import Foundation

public struct AirQuality: Codable, Sendable {
    public let aqi: Int
    public let level: AQILevel
    public let dominantPollutant: Pollutant.Kind?
    public let pollutants: [Pollutant]
    public let weather: Weather
    public let station: Station
    public let forecast: [DailyForecast]
    public let uviForecast: [UVIForecastPoint]
    public let timestamp: Date
    public let attribution: [Attribution]
    /// Timezone offset in seconds from GMT (parsed from WAQI `tz` field).
    public let timeZoneOffset: Int?

    public init(
        aqi: Int,
        dominantPollutant: Pollutant.Kind?,
        pollutants: [Pollutant],
        weather: Weather,
        station: Station,
        forecast: [DailyForecast],
        uviForecast: [UVIForecastPoint] = [],
        timestamp: Date,
        attribution: [Attribution],
        timeZoneOffset: Int? = nil
    ) {
        self.aqi = aqi
        self.level = AQILevel(aqi: aqi)
        self.dominantPollutant = dominantPollutant
        self.pollutants = pollutants
        self.weather = weather
        self.station = station
        self.forecast = forecast
        self.uviForecast = uviForecast
        self.timestamp = timestamp
        self.attribution = attribution
        self.timeZoneOffset = timeZoneOffset
    }

    /// Trend based on forecast data for dominant pollutant.
    public var trend: Trend {
        let todayString = Self.todayDateString(timeZoneOffset: timeZoneOffset)
        let relevant = forecast
            .filter { $0.pollutant == (dominantPollutant ?? .pm25) && $0.day >= todayString }
            .sorted { $0.day < $1.day }
        guard relevant.count >= 2,
              let today = relevant.first,
              let tomorrow = relevant.dropFirst().first else {
            return .stable
        }

        let delta = tomorrow.avg - today.avg
        if delta > 10 { return .worsening }
        if delta < -10 { return .improving }
        return .stable
    }

    /// Returns today's date string (yyyy-MM-dd) in the station's local timezone.
    private static func todayDateString(timeZoneOffset: Int?) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        if let offset = timeZoneOffset {
            f.timeZone = TimeZone(secondsFromGMT: offset) ?? .current
        } else {
            f.timeZone = .current
        }
        return f.string(from: Date())
    }
}

public enum Trend: String, Codable, Sendable {
    case improving
    case stable
    case worsening

    public var symbol: String {
        switch self {
        case .improving: "arrow.down.right"
        case .stable: "arrow.right"
        case .worsening: "arrow.up.right"
        }
    }
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
