import Foundation

/// What the engine remembers about one location between readings.
public struct AlertState: Codable, Equatable, Sendable {
    public var lastAQI: Int
    public var lastMeasuredAt: Date
    /// Worst US EPA level already alerted for. Cleared once the air is
    /// comfortably back below the threshold, so the next crossing alerts again.
    public var alertedLevel: AQILevel?
    public var lastSpikeAlertAt: Date?

    public init(lastAQI: Int, lastMeasuredAt: Date, alertedLevel: AQILevel? = nil, lastSpikeAlertAt: Date? = nil) {
        self.lastAQI = lastAQI
        self.lastMeasuredAt = lastMeasuredAt
        self.alertedLevel = alertedLevel
        self.lastSpikeAlertAt = lastSpikeAlertAt
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
    /// AQI must fall this far below the threshold before it can alert again,
    /// so a reading hovering on the line doesn't alert every hour.
    static let rearmMargin = 10

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
        // The same measurement fetched twice tells us nothing new.
        if let previous, reading.timestamp <= previous.lastMeasuredAt {
            return ([], previous)
        }

        var state = AlertState(
            lastAQI: reading.aqi,
            lastMeasuredAt: reading.timestamp,
            alertedLevel: previous?.alertedLevel,
            lastSpikeAlertAt: previous?.lastSpikeAlertAt
        )
        let level = reading.level
        let shown = scale.displayReading(for: reading)
        // Alerts trigger on US EPA levels; on another scale the two can disagree a lot
        // (UK DAQI rates PM10 far more strictly), so say both rather than mix them.
        let valueText = shown.scale == .usEPA
            ? "US EPA AQI \(reading.aqi), \(level.label)"
            : "\(shown.scale.shortName) \(shown.reading.value) (\(shown.reading.band.name)); US EPA AQI \(reading.aqi) (\(level.label))"

        var alerts: [AlertContent] = []

        // Spike: a fast rise into at least Moderate, at most once per cooldown.
        if preferences.spikeAlertsEnabled,
           let previous,
           reading.aqi - previous.lastAQI >= spikeRise,
           reading.timestamp.timeIntervalSince(previous.lastMeasuredAt) <= spikeWindow,
           level.rawValue >= AQILevel.moderate.rawValue,
           previous.lastSpikeAlertAt.map({ now.timeIntervalSince($0) > spikeCooldown }) ?? true {
            let hours = max(1, Int((reading.timestamp.timeIntervalSince(previous.lastMeasuredAt) / 3600).rounded()))
            alerts.append(AlertContent(
                kind: .spike,
                title: "Sudden rise in \(locationName)",
                body: "Air quality worsened fast — US EPA \(previous.lastAQI) to \(reading.aqi) in about \(hours) hr. This can mean smoke from a fire nearby. Now \(valueText).",
                locationKey: locationKey
            ))
            state.lastSpikeAlertAt = now
        }

        // Threshold: crossing into the chosen level, or getting worse past it.
        let threshold = preferences.thresholdLevel
        if level.rawValue >= threshold.rawValue {
            let isNewOrWorse = state.alertedLevel.map { level.rawValue > $0.rawValue } ?? true
            if preferences.thresholdAlertsEnabled, isNewOrWorse, alerts.isEmpty {
                let verdict = ActivityGuidanceService().guidance(for: reading, at: now, profile: profile).verdict
                alerts.append(AlertContent(
                    kind: .threshold,
                    title: shown.scale == .usEPA ? "\(level.label) in \(locationName)" : "Air quality alert in \(locationName)",
                    body: "\(verdict). Now \(valueText).",
                    locationKey: locationKey
                ))
            }
            // Remember it even when the spike alert spoke for this reading.
            if isNewOrWorse { state.alertedLevel = level }
        } else if reading.aqi <= threshold.range.lowerBound - rearmMargin {
            state.alertedLevel = nil
        }

        return (alerts, state)
    }
}
