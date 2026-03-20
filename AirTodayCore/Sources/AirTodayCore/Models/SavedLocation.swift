import Foundation

public struct SavedLocation: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let coordinate: Coordinate
    public let isCurrentLocation: Bool

    public init(id: UUID = UUID(), name: String, coordinate: Coordinate, isCurrentLocation: Bool = false) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.isCurrentLocation = isCurrentLocation
    }
}
