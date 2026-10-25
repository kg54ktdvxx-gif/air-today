import Foundation

public struct SavedLocation: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let coordinate: Coordinate
    public let isCurrentLocation: Bool
    /// The WAQI station the user picked. Fetching by ID keeps the city on that
    /// station; a coordinate lookup returns the nearest *active* station, which
    /// for an offline one can be another country. Nil for cities saved by 1.0.
    public let stationID: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        coordinate: Coordinate,
        isCurrentLocation: Bool = false,
        stationID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.isCurrentLocation = isCurrentLocation
        self.stationID = stationID
    }
}
