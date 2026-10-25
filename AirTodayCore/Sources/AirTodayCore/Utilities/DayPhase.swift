import Foundation

/// Where the station is in its day, for tinting the atmosphere: warm around
/// sunrise and sunset, cool at night.
public enum DayPhase: Equatable, Sendable {
    case day
    /// Near sunrise or sunset; 1 at the moment of the event, fading to 0 at the window's edge.
    case golden(intensity: Double)
    case night

    /// Half-width of the golden window around sunrise and sunset.
    static let goldenWindow: TimeInterval = 50 * 60

    public static func at(
        _ date: Date,
        latitude: Double,
        longitude: Double,
        timeZoneOffset: Int
    ) -> DayPhase {
        guard let sunrise = SunCalculator.sunrise(latitude: latitude, longitude: longitude, date: date, timeZoneOffset: timeZoneOffset),
              let sunset = SunCalculator.sunset(latitude: latitude, longitude: longitude, date: date, timeZoneOffset: timeZoneOffset)
        else {
            // Polar day or night: no sunrise/sunset to tint around.
            return .day
        }

        let nearest = min(abs(date.timeIntervalSince(sunrise)), abs(date.timeIntervalSince(sunset)))
        if nearest < goldenWindow {
            // Tenths, so the value (and anything keyed on it) changes every few minutes,
            // not on every render.
            let intensity = ((1 - nearest / goldenWindow) * 10).rounded() / 10
            return intensity > 0 ? .golden(intensity: intensity) : (date > sunrise && date < sunset ? .day : .night)
        }
        return date > sunrise && date < sunset ? .day : .night
    }
}
