import Testing
@testable import AirTodayCore

@Suite("Temperature formatting")
struct TemperatureUnitTests {
    @Test("Celsius rounds to the nearest degree instead of truncating")
    func celsiusRounds() {
        #expect(TemperatureUnit.celsius.format(celsius: 8.9) == "9°C")
        #expect(TemperatureUnit.celsius.format(celsius: -0.4) == "0°C")
    }

    @Test("Fahrenheit converts before rounding")
    func fahrenheitConverts() {
        #expect(TemperatureUnit.fahrenheit.format(celsius: 24) == "75°F")
        #expect(TemperatureUnit.fahrenheit.format(celsius: -40) == "-40°F")
    }
}
