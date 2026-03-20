import Foundation

/// Chart-ready forecast data point with proper Date.
public struct ForecastPoint: Sendable, Identifiable {
    public var id: String { "\(pollutant.rawValue)-\(date.timeIntervalSince1970)" }

    public let pollutant: Pollutant.Kind
    public let date: Date
    public let avg: Int
    public let min: Int
    public let max: Int

    public init(pollutant: Pollutant.Kind, date: Date, avg: Int, min: Int, max: Int) {
        self.pollutant = pollutant
        self.date = date
        self.avg = avg
        self.min = min
        self.max = max
    }

    public var level: AQILevel {
        AQILevel(aqi: avg)
    }
}

/// UVI forecast point — separate scale (0-11+), not AQI (0-500).
public struct UVIForecastPoint: Codable, Sendable, Identifiable {
    public var id: String { day }

    public let day: String
    public let avg: Int
    public let min: Int
    public let max: Int

    public init(day: String, avg: Int, min: Int, max: Int) {
        self.day = day
        self.avg = avg
        self.min = min
        self.max = max
    }

    public var date: Date? {
        Self.dayFormatter.date(from: day)
    }

    public var riskLevel: String {
        switch max {
        case 0...2: "Low"
        case 3...5: "Moderate"
        case 6...7: "High"
        case 8...10: "Very High"
        default: "Extreme"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
}
