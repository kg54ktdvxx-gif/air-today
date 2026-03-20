import Foundation

public struct Weather: Codable, Sendable {
    public let temperature: Double?
    public let humidity: Double?
    public let pressure: Double?
    public let windSpeed: Double?
    public let dewPoint: Double?

    public init(
        temperature: Double? = nil,
        humidity: Double? = nil,
        pressure: Double? = nil,
        windSpeed: Double? = nil,
        dewPoint: Double? = nil
    ) {
        self.temperature = temperature
        self.humidity = humidity
        self.pressure = pressure
        self.windSpeed = windSpeed
        self.dewPoint = dewPoint
    }
}
