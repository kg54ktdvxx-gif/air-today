import Foundation

/// One line saying where a reading came from and how fresh it is:
/// "Measured at Battersea · 3 km away · 40 min ago" or
/// "Estimated for this area · updated 10 min ago".
public enum SourceDescription {
    /// - Parameters:
    ///   - distance: metres from the device to the station; nil when it doesn't apply
    ///     (a saved city is looked up at its own station).
    ///   - scale: the scale shown. The European and UK indices are always worked out
    ///     from the model, whatever supplied the US headline.
    public static func text(for quality: AirQuality, distance: Double?, scale: AQIScale = .usEPA, now: Date = Date()) -> String {
        let shownSource = scale.displayReading(for: quality).scale == .usEPA ? quality.source : .model
        switch shownSource {
        case .station:
            var parts = [quality.station.map { "Measured at \(shortName($0.name))" } ?? "Measured nearby"]
            if let distance { parts.append(distanceText(distance)) }
            parts.append(ago(quality.timestamp, now: now))
            return parts.joined(separator: " · ")
        case .model:
            return "Estimated for this area · updated \(ago(quality.model?.fetchedAt ?? quality.timestamp, now: now))"
        }
    }

    /// Station names run long ("Battersea, Wandsworth, London, UK"); the first part says enough.
    static func shortName(_ name: String) -> String {
        name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
    }

    /// Station coordinates are approximate, so "40 m" would claim false precision.
    /// Under 1 km to the nearest 10 m ("660 m"), under 10 km to a tenth ("2.4 km"),
    /// then whole kilometres ("18 km").
    static func distanceText(_ metres: Double) -> String {
        guard metres >= 100 else { return "under 100 m away" }
        let isShort = metres < 1_000
        let value = isShort ? (metres / 10).rounded() * 10 : metres
        let formatted = Measurement(value: value, unit: UnitLength.meters).formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(metres < 10_000 && !isShort ? 0...1 : 0...0))
            )
        )
        return "\(formatted) away"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours) hr ago"
    }
}
