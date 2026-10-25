import Foundation

public protocol ModelAirServiceProtocol: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> ModelAirData
}

/// CAMS forecasts through Open-Meteo's air-quality API: ~11 km hourly in Europe,
/// ~45 km 3-hourly (interpolated to hourly) elsewhere. Current weather comes from
/// its forecast API alongside. Free for non-commercial use under CC BY 4.0; the app
/// must credit Open-Meteo next to the data.
/// https://open-meteo.com/en/docs/air-quality-api
public struct OpenMeteoAirService: ModelAirServiceProtocol {
    private let session: URLSession
    private static let baseURL = "https://air-quality-api.open-meteo.com/v1/air-quality"
    private static let weatherBaseURL = "https://api.open-meteo.com/v1/forecast"

    /// How far ahead to ask for. Europe returns 4 days, the global model 5.
    static let forecastDays = 5
    /// The station reading waits for this too, so a stalled request mustn't hold it
    /// up for URLSession's default minute.
    static let timeout: TimeInterval = 15

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Open-Meteo variable names for each pollutant: concentration, US sub-index, EU sub-index.
    static let variables: [(kind: Pollutant.Kind, concentration: String, us: String, european: String?)] = [
        (.pm25, "pm2_5", "us_aqi_pm2_5", "european_aqi_pm2_5"),
        (.pm10, "pm10", "us_aqi_pm10", "european_aqi_pm10"),
        (.o3, "ozone", "us_aqi_ozone", "european_aqi_ozone"),
        (.no2, "nitrogen_dioxide", "us_aqi_nitrogen_dioxide", "european_aqi_nitrogen_dioxide"),
        (.so2, "sulphur_dioxide", "us_aqi_sulphur_dioxide", "european_aqi_sulphur_dioxide"),
        (.co, "carbon_monoxide", "us_aqi_carbon_monoxide", nil),
    ]

    /// Two decimals (about 1 km). The grids are 11–45 km, so more precision changes
    /// nothing, and Open-Meteo's server logs keep request coordinates for up to 90 days.
    static func coarse(_ degrees: Double) -> String {
        String(format: "%.2f", degrees)
    }

    static var allVariableNames: [String] {
        ["us_aqi", "european_aqi", "uv_index"]
            + variables.flatMap { [$0.concentration, $0.us] + ($0.european.map { [$0] } ?? []) }
    }

    static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: baseURL)
        let names = allVariableNames.joined(separator: ",")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: Self.coarse(latitude)),
            URLQueryItem(name: "longitude", value: Self.coarse(longitude)),
            URLQueryItem(name: "current", value: names),
            URLQueryItem(name: "hourly", value: names),
            URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components?.url
    }

    /// Weather in the units WAQI used: °C, %, hPa at sea level, m/s.
    static func weatherURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: weatherBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: Self.coarse(latitude)),
            URLQueryItem(name: "longitude", value: Self.coarse(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,pressure_msl,wind_speed_10m,dew_point_2m"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components?.url
    }

    public func fetch(latitude: Double, longitude: Double) async throws -> ModelAirData {
        guard let url = Self.url(latitude: latitude, longitude: longitude),
              let weatherURL = Self.weatherURL(latitude: latitude, longitude: longitude)
        else {
            throw AirQualityError.apiError("Invalid URL")
        }
        async let weather = try? fetchWeather(from: weatherURL)
        let data = try await load(url)
        return try Self.parse(
            data,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            fetchedAt: Date(),
            weather: await weather
        )
    }

    private func fetchWeather(from url: URL) async throws -> Weather {
        try Self.parseWeather(await load(url))
    }

    private func load(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: Self.timeout))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let reason = (try? JSONDecoder().decode(OpenMeteoError.self, from: data))?.reason
            throw AirQualityError.apiError(reason ?? "Forecast service returned \(http.statusCode)")
        }
        return data
    }

    // MARK: - Parsing

    struct OpenMeteoError: Decodable {
        let reason: String
    }

    struct Response: Decodable {
        let utc_offset_seconds: Int
        let current: [String: Double?]
        let hourly: [String: [Double?]]
    }

    static func parse(_ data: Data, coordinate: Coordinate, fetchedAt: Date, weather: Weather? = nil) throws -> ModelAirData {
        let response = try JSONDecoder().decode(Response.self, from: data)

        guard let currentTime = response.current["time"] ?? nil else { throw AirQualityError.noData }
        let current = sample(time: currentTime) { response.current[$0] ?? nil }

        let times = response.hourly["time"] ?? []
        let hourly: [ModelSample] = times.indices.compactMap { index in
            guard let time = times[index] else { return nil }
            return sample(time: time) { name in
                guard let values = response.hourly[name], index < values.count else { return nil }
                return values[index]
            }
        }

        return ModelAirData(
            current: current,
            hourly: hourly,
            coordinate: coordinate,
            utcOffsetSeconds: response.utc_offset_seconds,
            fetchedAt: fetchedAt,
            weather: weather
        )
    }

    struct WeatherResponse: Decodable {
        let current: [String: Double?]
    }

    static func parseWeather(_ data: Data) throws -> Weather {
        let current = try JSONDecoder().decode(WeatherResponse.self, from: data).current
        func value(_ name: String) -> Double? { current[name] ?? nil }
        return Weather(
            temperature: value("temperature_2m"),
            humidity: value("relative_humidity_2m"),
            pressure: value("pressure_msl"),
            windSpeed: value("wind_speed_10m"),
            dewPoint: value("dew_point_2m")
        )
    }

    private static func sample(time: Double, value: (String) -> Double?) -> ModelSample {
        var us: [Pollutant.Kind: Int] = [:]
        var european: [Pollutant.Kind: Int] = [:]
        var concentrations: [Pollutant.Kind: Double] = [:]
        for variable in variables {
            if let v = value(variable.us) { us[variable.kind] = Int(v.rounded()) }
            if let name = variable.european, let v = value(name) { european[variable.kind] = Int(v.rounded()) }
            if let v = value(variable.concentration) { concentrations[variable.kind] = v }
        }
        return ModelSample(
            time: Date(timeIntervalSince1970: time),
            usAQI: value("us_aqi").map { Int($0.rounded()) },
            europeanAQI: value("european_aqi").map { Int($0.rounded()) },
            usSubIndices: us,
            europeanSubIndices: european,
            concentrations: concentrations,
            uvIndex: value("uv_index")
        )
    }
}
