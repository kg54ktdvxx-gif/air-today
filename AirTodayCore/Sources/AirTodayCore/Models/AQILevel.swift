import SwiftUI

/// US EPA AQI categories with breakpoints and associated colors.
public enum AQILevel: Int, CaseIterable, Codable, Sendable {
    case good
    case moderate
    case sensitive
    case unhealthy
    case veryUnhealthy
    case hazardous

    public init(aqi: Int) {
        switch aqi {
        case ...50: self = .good
        case 51...100: self = .moderate
        case 101...150: self = .sensitive
        case 151...200: self = .unhealthy
        case 201...300: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    public var label: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .sensitive: "Unhealthy for Sensitive Groups"
        case .unhealthy: "Unhealthy"
        case .veryUnhealthy: "Very Unhealthy"
        case .hazardous: "Hazardous"
        }
    }

    public var shortLabel: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .sensitive: "Sensitive"
        case .unhealthy: "Unhealthy"
        case .veryUnhealthy: "Very Unhealthy"
        case .hazardous: "Hazardous"
        }
    }

    public var color: Color {
        switch self {
        case .good: Color(.sRGB, red: 0.0, green: 0.78, blue: 0.33)
        case .moderate: Color(.sRGB, red: 1.0, green: 0.87, blue: 0.0)
        case .sensitive: Color(.sRGB, red: 1.0, green: 0.55, blue: 0.0)
        case .unhealthy: Color(.sRGB, red: 1.0, green: 0.0, blue: 0.0)
        case .veryUnhealthy: Color(.sRGB, red: 0.56, green: 0.14, blue: 0.56)
        case .hazardous: Color(.sRGB, red: 0.5, green: 0.0, blue: 0.13)
        }
    }

    // MARK: - Health Tips

    public struct HealthTip: Sendable {
        public let icon: String
        public let text: String
    }

    public var healthTip: HealthTip {
        switch self {
        case .good:
            HealthTip(icon: "figure.run", text: "Great day for outdoor activities")
        case .moderate:
            HealthTip(icon: "figure.walk", text: "Acceptable for most people")
        case .sensitive:
            HealthTip(icon: "exclamationmark.triangle", text: "Sensitive groups should limit outdoor exertion")
        case .unhealthy:
            HealthTip(icon: "exclamationmark.triangle.fill", text: "Everyone should reduce prolonged outdoor exertion")
        case .veryUnhealthy:
            HealthTip(icon: "xmark.shield", text: "Avoid prolonged outdoor activity")
        case .hazardous:
            HealthTip(icon: "xmark.shield.fill", text: "Everyone should avoid all outdoor activity")
        }
    }

    public var verdict: String {
        switch self {
        case .good: "Great day to be outside"
        case .moderate: "Fine for most, sensitive groups take care"
        case .sensitive: "Limit prolonged outdoor exertion"
        case .unhealthy: "Reduce outdoor activity"
        case .veryUnhealthy: "Avoid prolonged outdoor activity"
        case .hazardous: "Stay indoors"
        }
    }

    public var verdictIcon: String {
        switch self {
        case .good: "sun.max.fill"
        case .moderate: "cloud.sun.fill"
        case .sensitive: "aqi.medium"
        case .unhealthy: "aqi.high"
        case .veryUnhealthy: "exclamationmark.triangle.fill"
        case .hazardous: "xmark.shield.fill"
        }
    }

    /// Asset catalog image name for background photo.
    public var backgroundImageName: String {
        switch self {
        case .good: "good"
        case .moderate: "moderate"
        case .sensitive: "sensitive"
        case .unhealthy: "unhealthy"
        case .veryUnhealthy: "veryUnhealthy"
        case .hazardous: "hazardous"
        }
    }

    /// AQI range for this level.
    public var range: ClosedRange<Int> {
        switch self {
        case .good: 0...50
        case .moderate: 51...100
        case .sensitive: 101...150
        case .unhealthy: 151...200
        case .veryUnhealthy: 201...300
        case .hazardous: 301...500
        }
    }
}
