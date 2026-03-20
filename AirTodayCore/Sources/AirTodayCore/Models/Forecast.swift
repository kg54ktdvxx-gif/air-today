import Foundation

public struct DailyForecast: Codable, Sendable, Identifiable {
    public var id: String { "\(pollutant.rawValue)-\(day)" }

    public let pollutant: Pollutant.Kind
    public let day: String
    public let avg: Int
    public let min: Int
    public let max: Int

    public init(pollutant: Pollutant.Kind, day: String, avg: Int, min: Int, max: Int) {
        self.pollutant = pollutant
        self.day = day
        self.avg = avg
        self.min = min
        self.max = max
    }

    public var date: Date? {
        Self.dayFormatter.date(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    public var level: AQILevel {
        AQILevel(aqi: avg)
    }
}
