import Foundation

/// One short line saying where a reading came from and how fresh it is:
/// "Battersea station · 40 min ago" or "Area estimate · 10 min ago".
public enum SourceDescription {
    /// - Parameter scale: the scale shown. The European and UK indices are always
    ///   worked out from the model, whatever supplied the US headline.
    public static func text(for quality: AirQuality, scale: AQIScale = .usEPA, now: Date = Date()) -> String {
        let shownSource = scale.displayReading(for: quality).scale == .usEPA ? quality.source : .model
        switch shownSource {
        case .station:
            let station = quality.station.map { "\(shortName($0.name)) station" } ?? "Nearby station"
            return "\(station) · \(ago(quality.timestamp, now: now))"
        case .model:
            return "Area estimate · \(ago(quality.model?.fetchedAt ?? quality.timestamp, now: now))"
        }
    }

    /// Station names run long ("Battersea, Wandsworth, London, UK"); the first part says enough.
    static func shortName(_ name: String) -> String {
        name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
    }

    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours) hr ago"
    }
}
