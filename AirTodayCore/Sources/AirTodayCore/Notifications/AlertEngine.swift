import Foundation

/// What the engine remembers about one location between readings.
public struct AlertState: Codable, Equatable, Sendable {
    /// US EPA AQI, for spike detection.
    public var lastAQI: Int
    public var lastMeasuredAt: Date
    /// Worst severity level (on the chosen scale) already alerted for. Cleared once
    /// the air is comfortably back below the threshold, so the next crossing alerts again.
    public var alertedLevel: AQILevel?
    public var lastSpikeAlertAt: Date?
    /// Where the last reading came from. Nil in states saved before 1.2, which were all stations.
    public var lastSource: ReadingSource?
    public var lastStationID: Int?

    public init(
        lastAQI: Int,
        lastMeasuredAt: Date,
        alertedLevel: AQILevel? = nil,
        lastSpikeAlertAt: Date? = nil,
        lastSource: ReadingSource? = nil,
        lastStationID: Int? = nil
    ) {
        self.lastAQI = lastAQI
        self.lastMeasuredAt = lastMeasuredAt
        self.alertedLevel = alertedLevel
        self.lastSpikeAlertAt = lastSpikeAlertAt
        self.lastSource = lastSource
        self.lastStationID = lastStationID
    }

    /// Whether `reading` comes from the same source as the last one, so the two can
    /// be compared: a station and the model differ by tens of points at the same moment.
    func isSameSource(as reading: AirQuality) -> Bool {
        let source = lastSource ?? .station
        guard source == reading.source else { return false }
        return source == .model || lastStationID == nil || lastStationID == reading.station?.id
    }
}

public struct AlertContent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case threshold
        case spike
    }

    public let kind: Kind
    public let title: String
    public let body: String
    /// `AlertCoordinator.key(for:)` of the location, so a tap can open its page.
    public let locationKey: String
}

/// Decides threshold and spike alerts from successive readings. Pure: the
/// caller loads and stores `AlertState` and delivers the alerts.
public enum AlertEngine {
    /// A rise of at least this many US EPA points…
    static let spikeRise = 50
    /// …within this long counts as a spike.
    static let spikeWindow: TimeInterval = 3 * 3600
    /// One spike alert per location per this long.
    static let spikeCooldown: TimeInterval = 6 * 3600
    /// Severity must fall this far below the threshold (in ladder positions, ~10 US
    /// AQI points) before it can alert again, so air hovering on the line doesn't
    /// alert every hour.
    static let rearmMargin = 0.2

    public static func evaluate(
        reading: AirQuality,
        locationName: String,
        locationKey: String,
        previous: AlertState?,
        preferences: NotificationPreferences,
        profile: HealthProfile,
        scale: AQIScale,
        now: Date
    ) -> (alerts: [AlertContent], state: AlertState) {
        let comparable = previous?.isSameSource(as: reading) ?? false
        // The same measurement fetched twice tells us nothing new.
        if let previous, comparable, reading.timestamp <= previous.lastMeasuredAt {
            return ([], previous)
        }

        var state = AlertState(
            lastAQI: reading.aqi,
            lastMeasuredAt: reading.timestamp,
            alertedLevel: previous?.alertedLevel,
            lastSpikeAlertAt: previous?.lastSpikeAlertAt,
            lastSource: reading.source,
            lastStationID: reading.station?.id
        )
        // Thresholds follow the scale shown, like the advice does.
        let shown = scale.displayReading(for: reading)
        let severity = shown.reading.severity
        let level = shown.reading.severityLevel
        let valueText = "\(shown.scale.shortName) \(shown.reading.value), \(shown.reading.band.longName)"

        var alerts: [AlertContent] = []

        // Spike: a fast rise into at least Moderate, at most once per cooldown. On US
        // AQI, whose fine-grained numbers show a fast rise best. Only between readings
        // from the same source — switching source isn't the air changing.
        if preferences.spikeAlertsEnabled,
           let previous, comparable,
           reading.aqi - previous.lastAQI >= spikeRise,
           reading.timestamp.timeIntervalSince(previous.lastMeasuredAt) <= spikeWindow,
           level.rawValue >= AQILevel.moderate.rawValue,
           previous.lastSpikeAlertAt.map({ now.timeIntervalSince($0) > spikeCooldown }) ?? true {
            let hours = max(1, Int((reading.timestamp.timeIntervalSince(previous.lastMeasuredAt) / 3600).rounded()))
            let rise = shown.scale == .usEPA ? " — US EPA \(previous.lastAQI) to \(reading.aqi)" : ""
            alerts.append(AlertContent(
                kind: .spike,
                title: "Sudden rise in \(locationName)",
                body: "Air quality worsened fast\(rise) in about \(hours) hr. This can mean smoke from a fire nearby. Now \(valueText).",
                locationKey: locationKey
            ))
            state.lastSpikeAlertAt = now
        }

        // Threshold: crossing into the chosen level, or getting worse past it. Capped
        // at the scale's top alert level: UK DAQI's highest band sits at Unhealthy.
        let threshold = min(preferences.thresholdLevel, shown.scale.alertLevels.last ?? preferences.thresholdLevel)
        if level >= threshold {
            let isNewOrWorse = state.alertedLevel.map { level > $0 } ?? true
            if preferences.thresholdAlertsEnabled, isNewOrWorse, alerts.isEmpty {
                let verdict = ActivityGuidanceService().guidance(for: reading, scale: scale, at: now, profile: profile).verdict
                alerts.append(AlertContent(
                    kind: .threshold,
                    title: thresholdTitle(shown.reading, in: locationName),
                    body: "\(verdict). Now \(valueText).",
                    locationKey: locationKey
                ))
            }
            // Remember it even when the spike alert spoke for this reading.
            if isNewOrWorse { state.alertedLevel = level }
        } else if severity <= Double(threshold.rawValue) - rearmMargin {
            state.alertedLevel = nil
        }

        return (alerts, state)
    }

    /// In each scale's own words: "Unhealthy in Paris", "Poor air quality in Paris",
    /// "High air pollution in London" (Defra describes DAQI bands as pollution levels).
    static func thresholdTitle(_ reading: ScaledReading, in place: String) -> String {
        switch reading.scale {
        case .usEPA: "\(reading.severityLevel.label) in \(place)"
        case .euEAQI: "\(reading.band.longName) air quality in \(place)"
        case .ukDAQI: "\(reading.band.longName) air pollution in \(place)"
        }
    }
}
