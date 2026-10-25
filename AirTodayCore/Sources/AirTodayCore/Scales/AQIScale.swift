import SwiftUI

/// The index the app displays. Guidance, verdicts and the atmosphere stay on
/// US EPA levels whatever is chosen; only the numbers and bands shown change.
public enum AQIScale: String, CaseIterable, Sendable {
    case usEPA
    case euCAQI
    case ukDAQI

    public static let storageKey = "aqi_scale"

    public static var current: AQIScale {
        UserDefaults.shared.string(forKey: storageKey).flatMap(AQIScale.init(rawValue:)) ?? .usEPA
    }

    public var shortName: String {
        switch self {
        case .usEPA: "US EPA AQI"
        case .euCAQI: "EU CAQI"
        case .ukDAQI: "UK DAQI"
        }
    }

    public var rangeDescription: String {
        switch self {
        case .usEPA: "0–500"
        case .euCAQI: "0–100+"
        case .ukDAQI: "1–10"
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
        case .euCAQI: "European Common Air Quality Index, out of 100"
        case .ukDAQI: "UK Daily Air Quality Index, out of 10"
        }
    }

    /// Pollutants WAQI forecasts (PM2.5, PM10, O₃) are on every scale; these are
    /// the ones this scale's index is built from.
    public var pollutants: Set<Pollutant.Kind> {
        switch self {
        case .usEPA: Set(Pollutant.Kind.allCases)
        case .euCAQI: [.no2, .pm10, .o3, .pm25]
        case .ukDAQI: [.o3, .no2, .so2, .pm25, .pm10]
        }
    }

    // MARK: - Readings

    /// Today's index on this scale. Nil when the station reports none of the
    /// pollutants this scale is built from (callers fall back to US EPA).
    public func reading(for quality: AirQuality) -> ScaledReading? {
        if self == .usEPA {
            return ScaledReading(
                value: quality.aqi,
                band: band(forValue: Double(quality.aqi)),
                dominantPollutant: quality.dominantPollutant
            )
        }

        let subIndices = quality.pollutants.compactMap { pollutant -> (Pollutant.Kind, Double)? in
            subIndex(for: pollutant.kind, epaAQI: pollutant.aqi).map { (pollutant.kind, $0) }
        }
        guard let top = subIndices.max(by: { $0.1 < $1.1 }) else { return nil }
        let value = Int(top.1.rounded())
        return ScaledReading(value: value, band: band(forValue: Double(value)), dominantPollutant: top.0)
    }

    /// The reading to show: this scale's, or US EPA's (with `scale` saying so)
    /// when the station doesn't report anything this scale is built from.
    public func displayReading(for quality: AirQuality) -> (scale: AQIScale, reading: ScaledReading) {
        if let reading = reading(for: quality) { return (self, reading) }
        let epa = ScaledReading(
            value: quality.aqi,
            band: AQIScale.usEPA.band(forValue: Double(quality.aqi)),
            dominantPollutant: quality.dominantPollutant
        )
        return (.usEPA, epa)
    }

    /// One pollutant's index on this scale, from WAQI's US EPA sub-index.
    /// Nil if this scale doesn't use that pollutant.
    public func subIndex(for kind: Pollutant.Kind, epaAQI: Double) -> Double? {
        if self == .usEPA { return epaAQI }
        guard pollutants.contains(kind),
              let concentration = EPABreakpoints.concentration(of: kind, fromAQI: epaAQI)
        else { return nil }

        switch self {
        case .usEPA:
            return epaAQI
        case .euCAQI:
            return CAQIGrid.subIndex(of: kind, microgramsPerCubicMetre: concentration)
        case .ukDAQI:
            return DAQIBands.index(of: kind, microgramsPerCubicMetre: concentration).map(Double.init)
        }
    }

    // MARK: - Bands

    public func band(forValue value: Double) -> ScaleBand {
        switch self {
        case .usEPA:
            let level = AQILevel(aqi: Int(value.rounded()))
            return ScaleBand(name: level.shortLabel, longName: level.label, color: level.color)
        case .euCAQI:
            return CAQIGrid.band(forIndex: value)
        case .ukDAQI:
            return DAQIBands.band(forIndex: Int(value.rounded()))
        }
    }

    /// Band boundaries drawn on the forecast chart: (value, label, colour).
    public var chartThresholds: [(value: Double, label: String, color: Color)] {
        switch self {
        case .usEPA:
            [(50, "Good", AQILevel.good.color), (100, "Moderate", AQILevel.moderate.color), (150, "Sensitive", AQILevel.sensitive.color)]
        case .euCAQI:
            [(25, "Very low", CAQIGrid.colors[0]), (50, "Low", CAQIGrid.colors[1]), (75, "Medium", CAQIGrid.colors[2])]
        case .ukDAQI:
            // Mid-band colours: the top-of-band ones (dark red at 9) vanish on a dark card.
            [(3, "Low", DAQIBands.colors[1]), (6, "Moderate", DAQIBands.colors[4]), (9, "High", DAQIBands.colors[6])]
        }
    }

    /// Smallest top of the forecast chart's y axis, so the threshold lines always show.
    public var chartMinimumTop: Double {
        switch self {
        case .usEPA: 160
        case .euCAQI: 85
        case .ukDAQI: 10
        }
    }
}

public struct ScaledReading: Equatable, Sendable {
    public let value: Int
    public let band: ScaleBand
    public let dominantPollutant: Pollutant.Kind?
}

public struct ScaleBand: Equatable, Sendable {
    /// Short form for tight spaces ("Sensitive").
    public let name: String
    /// Full name ("Unhealthy for Sensitive Groups").
    public let longName: String
    public let color: Color
}

// MARK: - US EPA (as WAQI computes it)

/// WAQI's sub-indices use the US EPA tables from its own calculator (the 2016
/// standard — PM2.5 "Good" runs to 12 µg/m³, not the 2024 revision's 9), so
/// those are the tables to invert. Verified against
/// aqicn.org/air-cache/calculator/dist/calculator.js on 2026-10-25.
enum EPABreakpoints {
    private static let indices: [Double] = [0, 50, 100, 150, 200, 300, 400, 500]

    /// Concentration in µg/m³ (gases converted from ppb/ppm at 20 °C, the EU/UK
    /// reference), or nil for CO, which neither European index uses.
    static func concentration(of kind: Pollutant.Kind, fromAQI aqi: Double) -> Double? {
        let aqi = max(0, aqi)
        switch kind {
        case .pm25:
            return interpolate(aqi, indices, [0, 12, 35.5, 55.5, 150.5, 250.5, 350.5, 500.5])
        case .pm10:
            return interpolate(aqi, indices, [0, 55, 155, 255, 355, 425, 505, 605])
        case .o3:
            // 8-hour table up to 300; above that EPA (and WAQI) switch to 1-hour ozone.
            let ppm = aqi <= 300
                ? interpolate(aqi, [0, 50, 100, 150, 200, 300], [0, 0.06, 0.076, 0.096, 0.116, 0.375])
                : interpolate(aqi, [300, 400, 500], [0.405, 0.505, 0.605])
            return GasConversion.ozone.microgramsPerCubicMetre(ppb: ppm * 1000)
        case .no2:
            let ppm = interpolate(aqi, indices, [0, 0.054, 0.101, 0.361, 0.65, 1.25, 1.65, 2.049])
            return GasConversion.nitrogenDioxide.microgramsPerCubicMetre(ppb: ppm * 1000)
        case .so2:
            // 1-hour table below 200; 24-hour table from 200 up.
            let ppb = aqi < 200
                ? interpolate(aqi, [0, 50, 100, 150, 200], [0, 36, 76, 186, 304])
                : interpolate(aqi, [200, 300, 400, 500], [304, 605, 805, 1004])
            return GasConversion.sulphurDioxide.microgramsPerCubicMetre(ppb: ppb)
        case .co:
            return nil
        }
    }

    /// Piecewise-linear lookup of `x` on `xs` → `ys`, extrapolating past the last segment.
    static func interpolate(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        precondition(xs.count == ys.count && xs.count >= 2)
        var i = 0
        while i < xs.count - 2 && x > xs[i + 1] { i += 1 }
        let t = (x - xs[i]) / (xs[i + 1] - xs[i])
        return ys[i] + t * (ys[i + 1] - ys[i])
    }
}

/// ppb → µg/m³ at 20 °C and 101.325 kPa (molar volume 24.04 L), the reference
/// EU directive 2008/50/EC and UK DAQI use for gases.
enum GasConversion: Double {
    case ozone = 48.00
    case nitrogenDioxide = 46.01
    case sulphurDioxide = 64.07

    func microgramsPerCubicMetre(ppb: Double) -> Double {
        ppb * rawValue / 24.04
    }
}

// MARK: - EU CAQI (CITEAIR hourly background grid)

enum CAQIGrid {
    /// Index boundaries 0/25/50/75/100 against each pollutant's µg/m³ grid.
    private static let indices: [Double] = [0, 25, 50, 75, 100]

    static func subIndex(of kind: Pollutant.Kind, microgramsPerCubicMetre c: Double) -> Double? {
        let grid: [Double]
        switch kind {
        case .no2: grid = [0, 50, 100, 200, 400]
        case .pm10: grid = [0, 25, 50, 90, 180]
        case .o3: grid = [0, 60, 120, 180, 240]
        case .pm25: grid = [0, 15, 30, 55, 110]
        case .so2, .co: return nil
        }
        // Above the grid CAQI keeps climbing past 100 ("Very high").
        return EPABreakpoints.interpolate(max(0, c), grid, indices)
    }

    static let colors: [Color] = [
        Color(.sRGB, red: 0.475, green: 0.737, blue: 0.416),  // Very low
        Color(.sRGB, red: 0.725, green: 0.808, blue: 0.271),  // Low
        Color(.sRGB, red: 0.929, green: 0.757, blue: 0.000),  // Medium
        Color(.sRGB, red: 0.965, green: 0.573, blue: 0.031),  // High
        Color(.sRGB, red: 0.941, green: 0.212, blue: 0.404),  // Very high
    ]

    static func band(forIndex value: Double) -> ScaleBand {
        let names = ["Very low", "Low", "Medium", "High", "Very high"]
        let i = value < 25 ? 0 : value < 50 ? 1 : value < 75 ? 2 : value <= 100 ? 3 : 4
        return ScaleBand(name: names[i], longName: names[i], color: colors[i])
    }
}

// MARK: - UK DAQI (Defra bands)

/// Defra's Daily Air Quality Index bands, µg/m³. DAQI averages ozone over 8 hours
/// and particles over 24; WAQI gives current readings, so this is an estimate.
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
