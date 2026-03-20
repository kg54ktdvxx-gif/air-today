import Foundation
import CoreLocation

public struct Station: Codable, Sendable {
    public let id: Int
    public let name: String
    public let coordinate: Coordinate
    public let url: String

    public init(id: Int, name: String, coordinate: Coordinate, url: String) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.url = url
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

public struct Coordinate: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Attribution: Codable, Sendable, Identifiable {
    public var id: String { url }

    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}
