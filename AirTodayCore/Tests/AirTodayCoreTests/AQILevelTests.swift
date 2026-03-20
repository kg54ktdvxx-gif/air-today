import Testing
@testable import AirTodayCore

@Suite("AQI Level Mapping")
struct AQILevelTests {
    @Test("AQI breakpoints map correctly")
    func breakpoints() {
        #expect(AQILevel(aqi: 0) == .good)
        #expect(AQILevel(aqi: 50) == .good)
        #expect(AQILevel(aqi: 51) == .moderate)
        #expect(AQILevel(aqi: 100) == .moderate)
        #expect(AQILevel(aqi: 101) == .sensitive)
        #expect(AQILevel(aqi: 150) == .sensitive)
        #expect(AQILevel(aqi: 151) == .unhealthy)
        #expect(AQILevel(aqi: 200) == .unhealthy)
        #expect(AQILevel(aqi: 201) == .veryUnhealthy)
        #expect(AQILevel(aqi: 300) == .veryUnhealthy)
        #expect(AQILevel(aqi: 301) == .hazardous)
        #expect(AQILevel(aqi: 500) == .hazardous)
    }

    @Test("Negative AQI maps to good")
    func negativeAQI() {
        #expect(AQILevel(aqi: -1) == .good)
    }

    @Test("AQI above 500 maps to hazardous")
    func extremeAQI() {
        #expect(AQILevel(aqi: 999) == .hazardous)
    }
}
