import Foundation

/// Computes sunrise and sunset times using the NOAA solar calculator algorithm.
public enum SunCalculator {
    /// Returns the sunset time for a given location and date, in the specified timezone.
    public static func sunset(
        latitude: Double,
        longitude: Double,
        date: Date = Date(),
        timeZoneOffset: Int
    ) -> Date? {
        return solarEvent(
            latitude: latitude,
            longitude: longitude,
            date: date,
            timeZoneOffset: timeZoneOffset,
            isSunrise: false
        )
    }

    /// Returns the sunrise time for a given location and date, in the specified timezone.
    public static func sunrise(
        latitude: Double,
        longitude: Double,
        date: Date = Date(),
        timeZoneOffset: Int
    ) -> Date? {
        return solarEvent(
            latitude: latitude,
            longitude: longitude,
            date: date,
            timeZoneOffset: timeZoneOffset,
            isSunrise: true
        )
    }

    private static func solarEvent(
        latitude: Double,
        longitude: Double,
        date: Date,
        timeZoneOffset: Int,
        isSunrise: Bool
    ) -> Date? {
        let tz = TimeZone(secondsFromGMT: timeZoneOffset) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let year = calendar.component(.year, from: date)
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let daysInYear = isLeap ? 366.0 : 365.0

        // Fractional year (radians)
        let gamma = 2.0 * .pi / daysInYear * (Double(dayOfYear) - 1.0)

        // Equation of time (minutes)
        let eqtime = 229.18 * (0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma))

        // Solar declination (radians)
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        // Official zenith for sunrise/sunset
        let zenith = 90.833 * .pi / 180.0
        let latRad = latitude * .pi / 180.0

        let cosHA = (cos(zenith) / (cos(latRad) * cos(decl))) - tan(latRad) * tan(decl)

        // No sunrise/sunset in polar regions
        guard cosHA >= -1 && cosHA <= 1 else { return nil }

        let ha = acos(cosHA) * 180.0 / .pi // degrees

        // Time in minutes from midnight UTC
        let eventMinutes: Double
        if isSunrise {
            eventMinutes = 720.0 - 4.0 * (longitude + ha) - eqtime
        } else {
            eventMinutes = 720.0 - 4.0 * (longitude - ha) - eqtime
        }

        // Convert UTC minutes to local time
        let tzOffsetMinutes = Double(timeZoneOffset) / 60.0
        let localMinutes = eventMinutes + tzOffsetMinutes

        // Build Date from local midnight + localMinutes
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let midnight = calendar.date(from: components) else { return nil }

        return midnight.addingTimeInterval(localMinutes * 60.0)
    }

    /// Formats a time for display like "6:42 PM".
    public static func formatTime(_ date: Date, timeZoneOffset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(secondsFromGMT: timeZoneOffset) ?? .current
        return formatter.string(from: date)
    }

    /// Returns the current local time string for a timezone offset.
    public static func localTime(timeZoneOffset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(secondsFromGMT: timeZoneOffset) ?? .current
        return formatter.string(from: Date())
    }
}
