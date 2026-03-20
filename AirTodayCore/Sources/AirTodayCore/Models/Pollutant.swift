import Foundation

public struct Pollutant: Codable, Sendable, Identifiable {
    public var id: Kind { kind }

    public let kind: Kind
    public let aqi: Double

    public init(kind: Kind, aqi: Double) {
        self.kind = kind
        self.aqi = aqi
    }

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case pm25
        case pm10
        case o3
        case no2
        case so2
        case co

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .pm25: "PM2.5"
            case .pm10: "PM10"
            case .o3: "O\u{2083}"
            case .no2: "NO\u{2082}"
            case .so2: "SO\u{2082}"
            case .co: "CO"
            }
        }

        public var description: String {
            switch self {
            case .pm25: "Fine particulate matter"
            case .pm10: "Coarse particulate matter"
            case .o3: "Ozone"
            case .no2: "Nitrogen dioxide"
            case .so2: "Sulfur dioxide"
            case .co: "Carbon monoxide"
            }
        }
    }
}
