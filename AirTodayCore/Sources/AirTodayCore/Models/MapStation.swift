import Foundation

/// Lightweight model for map-based station display.
public struct MapStation: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let coordinate: Coordinate
    public let aqi: Int?
    public let level: AQILevel?

    public init(id: String, name: String, coordinate: Coordinate, aqi: Int?) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.aqi = aqi
        self.level = aqi.map { AQILevel(aqi: $0) }
    }
}
