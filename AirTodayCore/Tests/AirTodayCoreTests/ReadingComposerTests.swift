import Foundation
import Testing
@testable import AirTodayCore

@Suite("Choosing the headline reading")
struct ReadingComposerTests {
    private let now = Fixture.date(hour: 12)
    private let modelWeather = Weather(temperature: 14, windSpeed: 3)

    private var model: ModelAirData {
        Fixture.model(current: now, weather: modelWeather) { Fixture.sample($0, us: 33, eu: 23) }
    }

    /// 3 km from the query point.
    private let nearby = Coordinate(latitude: 51.527, longitude: -0.12)
    /// About 30 km away.
    private let distant = Coordinate(latitude: 51.77, longitude: -0.12)

    private func compose(_ station: AirQuality?, model: ModelAirData?, chosen: Bool = false) -> AirQuality? {
        ReadingComposer.compose(station: station, model: model, query: Fixture.london, stationChosenByUser: chosen, now: now)
    }

    @Test("A recent nearby station is the headline, with the model alongside and current weather")
    func recentLocalStation() throws {
        let station = Fixture.station(aqi: 18, at: now.addingTimeInterval(-40 * 60), coordinate: nearby, weather: Weather(temperature: 9))
        let reading = try #require(compose(station, model: model))
        #expect(reading.source == .station)
        #expect(reading.aqi == 18)
        #expect(reading.model == model)
        #expect(reading.weather == modelWeather)
    }

    @Test("An hours-old station gives way to the model, but stays attached")
    func oldStation() throws {
        let station = Fixture.station(aqi: 18, at: now.addingTimeInterval(-3 * 3600), coordinate: nearby)
        let reading = try #require(compose(station, model: model))
        #expect(reading.source == .model)
        #expect(reading.aqi == 33)
        #expect(reading.timestamp == now)
        #expect(reading.station?.id == 1)
    }

    @Test("A distant station is another place's air: model headline, station dropped")
    func distantStation() throws {
        let station = Fixture.station(aqi: 80, at: now, coordinate: distant)
        let reading = try #require(compose(station, model: model))
        #expect(reading.source == .model)
        #expect(reading.station == nil)
        // …and with no model there's nothing to show.
        #expect(compose(station, model: nil) == nil)
    }

    @Test("A station the user picked counts wherever it is")
    func chosenStation() throws {
        let station = Fixture.station(aqi: 80, at: now, coordinate: distant)
        #expect(try #require(compose(station, model: model, chosen: true)).source == .station)
    }

    @Test("Without the model, a local station is used even when old")
    func noModel() throws {
        let station = Fixture.station(aqi: 18, at: now.addingTimeInterval(-6 * 3600), coordinate: nearby, weather: Weather(temperature: 9))
        let reading = try #require(compose(station, model: nil))
        #expect(reading.source == .station)
        #expect(reading.weather.temperature == 9)
    }

    @Test("A model hour without a US AQI can't be a headline")
    func modelWithoutAQI() {
        let empty = Fixture.model(current: now) { Fixture.sample($0, us: nil) }
        #expect(compose(nil, model: empty) == nil)
    }
}

// MARK: - Fetching both sources

private struct StubStations: AirQualityServiceProtocol {
    var result: Result<AirQuality, AirQualityError>

    func fetchCurrent(latitude: Double, longitude: Double) async throws -> AirQuality { try result.get() }
    func fetchCurrent(city: String) async throws -> AirQuality { try result.get() }
    func fetchStation(id: Int) async throws -> AirQuality { try result.get() }
    func search(keyword: String) async throws -> [StationSummary] { [] }
    func fetchMapBounds(lat1: Double, lng1: Double, lat2: Double, lng2: Double) async throws -> [MapStation] { [] }
}

private final class StubModel: ModelAirServiceProtocol, @unchecked Sendable {
    let result: Result<ModelAirData, AirQualityError>
    private(set) var requested: Coordinate?

    init(_ result: Result<ModelAirData, AirQualityError>) { self.result = result }

    func fetch(latitude: Double, longitude: Double) async throws -> ModelAirData {
        requested = Coordinate(latitude: latitude, longitude: longitude)
        return try result.get()
    }
}

@Suite("Reading service")
struct AirReadingServiceTests {
    private let station = Fixture.station(aqi: 18, at: Date(), coordinate: Coordinate(latitude: 48.85, longitude: 2.35))

    @Test("Without a coordinate, the model is read where the IP lookup's station is")
    func ipLookup() async throws {
        let model = StubModel(.success(Fixture.model(current: Date()) { Fixture.sample($0, us: 30) }))
        let service = AirReadingService(stations: StubStations(result: .success(station)), model: model)
        _ = try await service.reading(at: nil)
        #expect(model.requested == Coordinate(latitude: 48.85, longitude: 2.35))
    }

    @Test("When both sources fail, the station's error is the one reported")
    func bothFail() async {
        let service = AirReadingService(
            stations: StubStations(result: .failure(.noNearbyStation)),
            model: StubModel(.failure(.apiError("model down")))
        )
        await #expect(throws: AirQualityError.noNearbyStation) {
            try await service.reading(at: Fixture.london)
        }
    }

    @Test("Either source alone is enough")
    func oneFails() async throws {
        let modelOnly = AirReadingService(
            stations: StubStations(result: .failure(.noNearbyStation)),
            model: StubModel(.success(Fixture.model(current: Date()) { Fixture.sample($0, us: 30) }))
        )
        #expect(try await modelOnly.reading(at: Fixture.london).source == .model)

        let stationOnly = AirReadingService(
            stations: StubStations(result: .success(station)),
            model: StubModel(.failure(.apiError("model down")))
        )
        #expect(try await stationOnly.reading(at: station.coordinate, stationID: 1).aqi == 18)
    }
}

@Suite("Open-Meteo parsing")
struct OpenMeteoParsingTests {
    /// Trimmed from a real response for London (25 Oct 2026), with a missing hour added.
    private static let json = """
    {"latitude":51.5,"longitude":-0.10000038,"utc_offset_seconds":0,"timezone":"Europe/London",
     "current":{"time":1792915200,"interval":3600,"us_aqi":33,"european_aqi":23,"pm2_5":2.4,
                "us_aqi_pm2_5":17,"european_aqi_pm2_5":10,"ozone":61,"us_aqi_ozone":33,"european_aqi_ozone":23,"uv_index":0.3},
     "hourly":{"time":[1792886400,1792890000,1792893600,1792897200],
               "us_aqi":[30,30,null,31],"european_aqi":[27,30,null,27],
               "pm2_5":[3.0,3.2,null,3.5],"us_aqi_pm2_5":[18,18,null,18],"european_aqi_pm2_5":[12,13,null,14],
               "uv_index":[0.0,0.0,null,0.0]}}
    """

    @Test("Current values, sub-indices and hourly samples, with gaps left empty")
    func parse() throws {
        let data = try OpenMeteoAirService.parse(Data(Self.json.utf8), coordinate: Fixture.london, fetchedAt: Date(timeIntervalSince1970: 1_792_916_000))
        #expect(data.current.time == Date(timeIntervalSince1970: 1_792_915_200))
        #expect(data.current.usAQI == 33)
        #expect(data.current.europeanAQI == 23)
        #expect(data.current.usDominant == .o3)
        #expect(data.current.concentrations[.o3] == 61)
        #expect(data.current.uvIndex == 0.3)
        #expect(data.coordinate == Fixture.london)

        #expect(data.hourly.count == 4)
        #expect(data.hourly[2].usAQI == nil)
        #expect(data.hourly[2].concentrations.isEmpty)
        #expect(data.hourly[3].europeanSubIndices[.pm25] == 14)
    }

    @Test("Weather parses into the units the app shows")
    func weather() throws {
        let json = #"{"current":{"time":1792915200,"temperature_2m":11.2,"relative_humidity_2m":61,"pressure_msl":1004.2,"wind_speed_10m":7.6,"dew_point_2m":4.1}}"#
        let weather = try OpenMeteoAirService.parseWeather(Data(json.utf8))
        #expect(weather == Weather(temperature: 11.2, humidity: 61, pressure: 1004.2, windSpeed: 7.6, dewPoint: 4.1))
    }

    @Test("The request asks for history, the forecast and local time")
    func url() throws {
        let url = try #require(OpenMeteoAirService.url(latitude: 51.5, longitude: -0.12))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("past_days") == "1")
        // About 1 km is all the grid can use.
        #expect(value("latitude") == "51.50")
        #expect(value("longitude") == "-0.12")
        #expect(value("timezone") == "auto")
        #expect(value("hourly")?.contains("european_aqi_nitrogen_dioxide") == true)
        #expect(value("hourly")?.contains("european_aqi_carbon_monoxide") == false)
    }
}

@Suite("Source line")
struct SourceDescriptionTests {
    private let now = Fixture.date(hour: 12)

    @Test("A station says where, how far and how long ago")
    func station() {
        let quality = Fixture.station(aqi: 18, at: now.addingTimeInterval(-40 * 60), name: "Battersea, Wandsworth, London")
        let text = SourceDescription.text(for: quality, distance: 3_240, now: now)
        #expect(text.hasPrefix("Measured at Battersea · "))
        #expect(text.hasSuffix(" · 40 min ago"))
        #expect(SourceDescription.text(for: quality, distance: nil, now: now) == "Measured at Battersea · 40 min ago")
    }

    @Test("Distances keep only the precision they have")
    func distances() {
        #expect(SourceDescription.distanceText(40) == "under 100 m away")
        #expect(!SourceDescription.distanceText(18_400).contains("."))
        #expect(!SourceDescription.distanceText(4_129_800).contains("."))
    }

    @Test("The European and UK indices are estimates even beside a station")
    func otherScales() {
        let model = Fixture.model(current: now) { Fixture.sample($0, us: 30, eu: 20) }
        let quality = Fixture.station(aqi: 18, at: now, model: model)
        #expect(SourceDescription.text(for: quality, distance: nil, scale: .euEAQI, now: now).hasPrefix("Estimated for this area"))
        #expect(SourceDescription.text(for: quality, distance: nil, scale: .usEPA, now: now).hasPrefix("Measured at"))
    }

    @Test("An estimate says when it was fetched")
    func model() {
        let model = Fixture.model(current: now.addingTimeInterval(-10 * 60)) { Fixture.sample($0, us: 30) }
        #expect(SourceDescription.text(for: Fixture.modelled(model), distance: 2_000, now: now) == "Estimated for this area · updated 10 min ago")
    }
}
