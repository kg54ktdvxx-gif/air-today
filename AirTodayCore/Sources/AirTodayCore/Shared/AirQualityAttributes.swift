import ActivityKit
import Foundation

public struct AirQualityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let aqi: Int
        public let level: AQILevel
        public let dominantPollutant: String
        public let trend: Trend
        public let stationName: String

        public init(aqi: Int, level: AQILevel, dominantPollutant: String, trend: Trend, stationName: String) {
            self.aqi = aqi
            self.level = level
            self.dominantPollutant = dominantPollutant
            self.trend = trend
            self.stationName = stationName
        }
    }

    /// The user's selected location name (persists across updates).
    public let locationName: String

    public init(locationName: String) {
        self.locationName = locationName
    }
}

extension AirQualityAttributes.ContentState {
    public init(from quality: AirQuality) {
        self.aqi = quality.aqi
        self.level = quality.level
        self.dominantPollutant = quality.dominantPollutant?.displayName ?? "PM2.5"
        self.trend = quality.trend
        self.stationName = quality.station.name
    }
}
