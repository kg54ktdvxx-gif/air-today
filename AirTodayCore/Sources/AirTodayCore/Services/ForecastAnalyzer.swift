import Foundation

/// Analyzes forecast data for trends and insights.
public struct ForecastAnalyzer: Sendable {
    public init() {}

    /// Converts DailyForecast array to chart-ready ForecastPoints.
    public func forecastPoints(from forecasts: [DailyForecast]) -> [ForecastPoint] {
        forecasts.compactMap { forecast in
            guard let date = forecast.date else { return nil }
            return ForecastPoint(
                pollutant: forecast.pollutant,
                date: date,
                avg: forecast.avg,
                min: forecast.min,
                max: forecast.max
            )
        }
    }

    /// Finds the first future day where AQI drops below the given level's threshold.
    /// Returns e.g. "Improves by Wednesday" or nil.
    public func improvementSummary(
        forecasts: [DailyForecast],
        currentAQI: Int,
        pollutant: Pollutant.Kind
    ) -> String? {
        let currentLevel = AQILevel(aqi: currentAQI)
        guard currentLevel.rawValue >= AQILevel.moderate.rawValue else { return nil }

        let threshold = currentLevel.range.lowerBound
        let relevant = forecasts
            .filter { $0.pollutant == pollutant }
            .sorted { $0.day < $1.day }

        // Skip today, find first day below threshold
        for forecast in relevant.dropFirst() {
            if forecast.avg < threshold {
                if let date = forecast.date {
                    let dayName = Self.dayNameFormatter.string(from: date)
                    return "Improves by \(dayName)"
                }
            }
        }
        return nil
    }

    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = .current
        return f
    }()
}
