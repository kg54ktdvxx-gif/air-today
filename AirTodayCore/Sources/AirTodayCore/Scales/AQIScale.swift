import SwiftUI

/// The index the app displays. Verdicts, activity advice, alerts and the atmosphere
/// all follow the chosen scale through its `severity` (see `Severity`).
public enum AQIScale: String, CaseIterable, Sendable {
    case usEPA
    case euEAQI
    case ukDAQI

    public static let storageKey = "aqi_scale"

    public static var current: AQIScale {
        UserDefaults.shared.string(forKey: storageKey).flatMap(AQIScale.init(rawValue:)) ?? .usEPA
    }

    public var shortName: String {
        switch self {
        case .usEPA: "US EPA AQI"
        case .euEAQI: "European AQI"
        case .ukDAQI: "UK DAQI"
        }
    }

    /// For tight spaces: "AQI 42", "EAQI 23", "DAQI 3".
    public var compactName: String {
        switch self {
        case .usEPA: "AQI"
        case .euEAQI: "EAQI"
        case .ukDAQI: "DAQI"
        }
    }

    public var rangeDescription: String {
        switch self {
        case .usEPA: "0–500"
        case .euEAQI: "0–100+"
        case .ukDAQI: "1–10"
        }
    }

    /// The value a full gauge stands for (complications and Lock Screen widgets).
    public var gaugeTop: Double {
        switch self {
        case .usEPA: 500
        case .euEAQI: 100
        case .ukDAQI: 10
        }
    }

    /// e.g. "US EPA AQI · Scale 0–500 · Lower is better"
    public var caption: String {
        "\(shortName) · Scale \(rangeDescription) · Lower is better"
    }

    /// Spoken form of `caption`.
    public var accessibilityName: String {
        switch self {
        case .usEPA: "US EPA Air Quality Index, out of 500"
        case .euEAQI: "European Air Quality Index, out of 100"
        case .ukDAQI: "UK Daily Air Quality Index, out of 10"
        }
    }

    /// Who publishes the scale, for the "About this advice" sheet.
    public var authority: (name: String, url: URL) {
        switch self {
        case .usEPA: ("US Environmental Protection Agency (AirNow)", URL(string: "https://www.airnow.gov/aqi/aqi-basics/")!)
        case .euEAQI: ("European Environment Agency", URL(string: "https://airindex.eea.europa.eu/")!)
        case .ukDAQI: ("Defra UK-AIR", URL(string: "https://uk-air.defra.gov.uk/air-pollution/daqi")!)
        }
    }

    /// Pollutants the scale's index is built from.
    public var pollutants: Set<Pollutant.Kind> {
        switch self {
        case .usEPA: Set(Pollutant.Kind.allCases)
        case .euEAQI, .ukDAQI: [.pm25, .pm10, .o3, .no2, .so2]
        }
    }

    // MARK: - Readings

    /// The reading on this scale. US EPA comes from the headline source; the EU and
    /// UK indices need the model's concentrations, so they're nil without model data.
    public func reading(for quality: AirQuality) -> ScaledReading? {
        switch self {
        case .usEPA:
            return ScaledReading(scale: self, value: quality.aqi, dominantPollutant: quality.dominantPollutant)
        case .euEAQI:
            guard let current = quality.model?.current, let value = current.europeanAQI else { return nil }
            let dominant = current.europeanSubIndices.max { $0.value < $1.value }?.key
            return ScaledReading(scale: self, value: value, dominantPollutant: dominant)
        case .ukDAQI:
            guard let model = quality.model,
                  let index = model.hourIndex(atOrBefore: model.current.time)
            else { return nil }
            let perPollutant = DAQICalculator.indices(at: index, in: model.hourly)
            guard let top = perPollutant.max(by: { $0.value < $1.value }) else { return nil }
            return ScaledReading(scale: self, value: top.value, dominantPollutant: top.key)
        }
    }

    /// The reading to show: this scale's, or US EPA's (with `scale` saying so) when
    /// this scale needs model data that isn't available.
    public func displayReading(for quality: AirQuality) -> (scale: AQIScale, reading: ScaledReading) {
        if let reading = reading(for: quality) { return (self, reading) }
        return (.usEPA, AQIScale.usEPA.reading(for: quality)!)
    }

    /// One pollutant's index on this scale. Nil if the scale doesn't use it or the
    /// data isn't there.
    public func subIndex(for kind: Pollutant.Kind, in quality: AirQuality) -> Int? {
        guard pollutants.contains(kind) else { return nil }
        switch self {
        case .usEPA:
            return quality.pollutants.first { $0.kind == kind }.map { Int($0.aqi.rounded()) }
        case .euEAQI:
            return quality.model?.current.europeanSubIndices[kind]
        case .ukDAQI:
            guard let model = quality.model, let index = model.hourIndex(atOrBefore: model.current.time) else { return nil }
            return DAQICalculator.indices(at: index, in: model.hourly)[kind]
        }
    }

    // MARK: - Forecast

    /// Hourly values on this scale from the current hour on — overall, or one pollutant.
    public func hourlySeries(for quality: AirQuality, pollutant: Pollutant.Kind? = nil, now: Date = Date()) -> [(time: Date, value: Int)] {
        guard let model = quality.model else { return [] }
        let start = now.addingTimeInterval(-3599)
        return model.hourly.indices.compactMap { index -> (time: Date, value: Int)? in
            let sample = model.hourly[index]
            guard sample.time >= start else { return nil }
            let value: Int?
            switch self {
            case .usEPA:
                value = pollutant.map { sample.usSubIndices[$0] } ?? sample.usAQI
            case .euEAQI:
                value = pollutant.map { sample.europeanSubIndices[$0] } ?? sample.europeanAQI
            case .ukDAQI:
                let indices = DAQICalculator.indices(at: index, in: model.hourly)
                value = pollutant.map { indices[$0] } ?? indices.values.max()
            }
            return value.map { (sample.time, $0) }
        }
    }

    // MARK: - Bands

    public func band(forValue value: Int) -> ScaleBand {
        switch self {
        case .usEPA:
            let level = AQILevel(aqi: value)
            return ScaleBand(name: level.shortLabel, longName: level.label, color: level.color)
        case .euEAQI:
            return EAQIBands.band(forIndex: value)
        case .ukDAQI:
            return DAQIBands.band(forIndex: value)
        }
    }

    /// Every band with its range, best first, for explaining the scale.
    public var bands: [(range: String, band: ScaleBand)] {
        let ranges: [(String, Int)] = switch self {
        case .usEPA: [("0–50", 25), ("51–100", 75), ("101–150", 125), ("151–200", 175), ("201–300", 250), ("301+", 400)]
        case .euEAQI: [("0–20", 10), ("20–40", 30), ("40–60", 50), ("60–80", 70), ("80–100", 90), ("100+", 120)]
        case .ukDAQI: [("1–3", 2), ("4–6", 5), ("7–9", 8), ("10", 10)]
        }
        return ranges.map { ($0.0, band(forValue: $0.1)) }
    }

    /// The scale's own name for a severity level, for the alert-level picker.
    /// Several scales have fewer bands than the ladder, so some levels share a name.
    public func bandName(for level: AQILevel) -> String {
        switch self {
        case .usEPA:
            return level.label
        case .euEAQI:
            switch level {
            case .good: return "Good / Fair"
            case .moderate: return "Moderate"
            case .sensitive: return "Poor"
            case .unhealthy: return "Very poor"
            case .veryUnhealthy, .hazardous: return "Extremely poor"
            }
        case .ukDAQI:
            switch level {
            case .good: return "Low (1–3)"
            case .moderate: return "Moderate (4–6)"
            case .sensitive: return "High (7–9)"
            case .unhealthy, .veryUnhealthy, .hazardous: return "Very High (10)"
            }
        }
    }

    /// Alert levels worth offering on this scale (one per distinct band from Moderate up).
    public var alertLevels: [AQILevel] {
        switch self {
        case .usEPA: [.moderate, .sensitive, .unhealthy, .veryUnhealthy]
        case .euEAQI: [.moderate, .sensitive, .unhealthy, .veryUnhealthy]
        case .ukDAQI: [.moderate, .sensitive, .unhealthy]
        }
    }

    /// Band boundaries drawn on the forecast chart: (value, label, colour).
    public var chartThresholds: [(value: Double, label: String, color: Color)] {
        switch self {
        case .usEPA:
            [(50, "Good", AQILevel.good.color), (100, "Moderate", AQILevel.moderate.color), (150, "Sensitive", AQILevel.sensitive.color)]
        case .euEAQI:
            [(20, "Good", EAQIBands.colors[0]), (40, "Fair", EAQIBands.colors[1]), (60, "Moderate", EAQIBands.colors[2])]
        case .ukDAQI:
            // Mid-band colours: the top-of-band ones (dark red at 9) vanish on a dark card.
            [(3, "Low", DAQIBands.colors[1]), (6, "Moderate", DAQIBands.colors[4]), (9, "High", DAQIBands.colors[6])]
        }
    }

    /// Smallest top of the forecast chart's y axis, so the threshold lines always show.
    public var chartMinimumTop: Double {
        switch self {
        case .usEPA: 160
        case .euEAQI: 70
        case .ukDAQI: 10
        }
    }
}

public struct ScaledReading: Equatable, Sendable {
    public let scale: AQIScale
    public let value: Int
    public let dominantPollutant: Pollutant.Kind?

    public var band: ScaleBand { scale.band(forValue: value) }
    /// Position on the shared severity ladder (0 good … 6 hazardous).
    public var severity: Double { Severity.position(of: value, on: scale) }
    public var severityLevel: AQILevel { Severity.level(at: severity) }
}

public struct ScaleBand: Equatable, Sendable {
    /// Short form for tight spaces ("Sensitive").
    public let name: String
    /// Full name ("Unhealthy for Sensitive Groups").
    public let longName: String
    public let color: Color
}

// MARK: - Severity ladder

/// One scale-independent measure of how bad the air is, so advice, alerts and the
/// atmosphere mean the same thing whichever index is shown.
///
/// The ladder's whole-number levels are the US EPA categories (as `AQILevel`). Each
/// scale's bands are placed on it by what its publisher advises, not by numbers:
/// EEA "Good" and "Fair" both advise usual activity for everyone, so both sit in
/// the first level; Defra's DAQI "Very High" tells at-risk people to avoid strenuous
/// activity and everyone else to reduce it — EPA's "Unhealthy". Within a level the
/// position rises with the value, so per-activity thresholds stay fine-grained.
public enum Severity {
    /// 0 ≤ position < 6; whole part is the level.
    public static func position(of value: Int, on scale: AQIScale) -> Double {
        switch scale {
        case .usEPA:
            let bands = [(0, 50), (51, 100), (101, 150), (151, 200), (201, 300), (301, 500)]
            guard let index = bands.firstIndex(where: { value <= $0.1 }) else { return 5.99 }
            let (low, high) = bands[index]
            // +1 so a band's top value stays below the next band's first (50 < 51).
            return Double(index) + Double(max(value, low) - low) / Double(high - low + 1)
        case .euEAQI:
            let v = Double(max(value, 0))
            switch v {
            case ..<40: return v / 40 * 0.99            // Good + Fair
            case ..<60: return 1 + (v - 40) / 20 * 0.99 // Moderate
            case ..<80: return 2 + (v - 60) / 20 * 0.99 // Poor
            case ..<100: return 3 + (v - 80) / 20 * 0.99 // Very poor
            default: return 4 + min((v - 100) / 100, 0.99) // Extremely poor
            }
        case .ukDAQI:
            switch min(max(value, 1), 10) {
            case let i where i <= 3: return Double(i - 1) / 3     // Low
            case let i where i <= 6: return 1 + Double(i - 4) / 3 // Moderate
            case let i where i <= 9: return 2 + Double(i - 7) / 3 // High
            default: return 3.5                                    // Very High
            }
        }
    }

    public static func level(at position: Double) -> AQILevel {
        AQILevel(rawValue: min(max(Int(position), 0), 5)) ?? .good
    }

    /// A US EPA AQI as a position, for thresholds written in AQI numbers.
    public static func position(usAQI: Int) -> Double {
        position(of: usAQI, on: .usEPA)
    }

    /// The US EPA AQI at a position — for visuals tuned on AQI numbers (haze density).
    public static func equivalentUSAQI(at position: Double) -> Int {
        let bands = [(0, 50), (51, 100), (101, 150), (151, 200), (201, 300), (301, 500)]
        let index = min(max(Int(position), 0), 5)
        let (low, high) = bands[index]
        let fraction = min(max(position - Double(index), 0), 1)
        // The epsilon absorbs float error, so a US value maps back to itself (25 not 24).
        return low + Int(fraction * Double(high - low + 1) + 1e-9)
    }
}

// MARK: - European AQI (EEA, 2024 bands)

enum EAQIBands {
    /// EEA's published colours, Good → Extremely poor.
    static let colors: [Color] = [
        Color(.sRGB, red: 80 / 255, green: 240 / 255, blue: 230 / 255),
        Color(.sRGB, red: 80 / 255, green: 204 / 255, blue: 170 / 255),
        Color(.sRGB, red: 240 / 255, green: 230 / 255, blue: 65 / 255),
        Color(.sRGB, red: 255 / 255, green: 80 / 255, blue: 80 / 255),
        Color(.sRGB, red: 150 / 255, green: 0, blue: 50 / 255),
        Color(.sRGB, red: 125 / 255, green: 33 / 255, blue: 129 / 255),
    ]

    static func band(forIndex value: Int) -> ScaleBand {
        let names = ["Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"]
        let i = min(max(value, 0) / 20, 5)
        return ScaleBand(name: names[i], longName: names[i], color: colors[i])
    }
}

// MARK: - UK DAQI (Defra bands)

/// Defra's Daily Air Quality Index, from µg/m³ with its averaging periods.
enum DAQICalculator {
    /// PM2.5 and PM10 use a 24-hour mean and ozone a running 8-hour mean; NO2 is
    /// hourly. SO2 is officially a 15-minute mean — hourly is the closest the model has.
    static func indices(at index: Int, in hourly: [ModelSample]) -> [Pollutant.Kind: Int] {
        var result: [Pollutant.Kind: Int] = [:]
        let rules: [(Pollutant.Kind, hours: Int, minimum: Int)] = [
            (.pm25, 24, 18), (.pm10, 24, 18), (.o3, 8, 6), (.no2, 1, 1), (.so2, 1, 1),
        ]
        for (kind, hours, minimum) in rules {
            let window = hourly[max(0, index - hours + 1)...index].compactMap { $0.concentrations[kind] }
            guard window.count >= minimum else { continue }
            let mean = window.reduce(0, +) / Double(window.count)
            result[kind] = DAQIBands.index(of: kind, microgramsPerCubicMetre: mean)
        }
        return result
    }
}

enum DAQIBands {
    /// Upper bound of indices 1–9 for each pollutant; above the last is index 10.
    private static func upperBounds(for kind: Pollutant.Kind) -> [Double]? {
        switch kind {
        case .o3: [33, 66, 100, 120, 140, 160, 187, 213, 240]
        case .no2: [67, 134, 200, 267, 334, 400, 467, 534, 600]
        case .so2: [88, 177, 266, 354, 443, 532, 710, 887, 1064]
        case .pm25: [11, 23, 35, 41, 47, 53, 58, 64, 70]
        case .pm10: [16, 33, 50, 58, 66, 75, 83, 91, 100]
        case .co: nil
        }
    }

    static func index(of kind: Pollutant.Kind, microgramsPerCubicMetre c: Double) -> Int? {
        guard let bounds = upperBounds(for: kind) else { return nil }
        // Bands are defined on whole µg/m³.
        let value = max(0, c).rounded()
        return (bounds.firstIndex { value <= $0 } ?? bounds.count) + 1
    }

    static let colors: [Color] = [
        Color(.sRGB, red: 0.612, green: 1.000, blue: 0.612),  // 1
        Color(.sRGB, red: 0.192, green: 1.000, blue: 0.000),  // 2
        Color(.sRGB, red: 0.192, green: 0.812, blue: 0.000),  // 3
        Color(.sRGB, red: 1.000, green: 1.000, blue: 0.000),  // 4
        Color(.sRGB, red: 1.000, green: 0.812, blue: 0.000),  // 5
        Color(.sRGB, red: 1.000, green: 0.604, blue: 0.000),  // 6
        Color(.sRGB, red: 1.000, green: 0.392, blue: 0.392),  // 7
        Color(.sRGB, red: 1.000, green: 0.000, blue: 0.000),  // 8
        Color(.sRGB, red: 0.600, green: 0.000, blue: 0.000),  // 9
        Color(.sRGB, red: 0.808, green: 0.188, blue: 1.000),  // 10
    ]

    static func band(forIndex index: Int) -> ScaleBand {
        let clamped = min(max(index, 1), 10)
        let name = switch clamped {
        case 1...3: "Low"
        case 4...6: "Moderate"
        case 7...9: "High"
        default: "Very High"
        }
        return ScaleBand(name: name, longName: name, color: colors[clamped - 1])
    }
}
