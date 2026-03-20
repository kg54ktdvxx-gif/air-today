import Foundation

// MARK: - Protocol

public protocol AirQualityServiceProtocol: Sendable {
    func fetchCurrent(latitude: Double, longitude: Double) async throws -> AirQuality
    func fetchCurrent(city: String) async throws -> AirQuality
    func search(keyword: String) async throws -> [StationSummary]
    func fetchMapBounds(lat1: Double, lng1: Double, lat2: Double, lng2: Double) async throws -> [MapStation]
}

// MARK: - Station Summary (search results)

public struct StationSummary: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let aqi: Int?
    public let coordinate: Coordinate
}

// MARK: - Implementation

public struct AirQualityService: AirQualityServiceProtocol {
    private let token: String
    private let session: URLSession
    private let baseURL = "https://api.waqi.info"

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func fetchCurrent(latitude: Double, longitude: Double) async throws -> AirQuality {
        guard let url = URL(string: "\(baseURL)/feed/geo:\(latitude);\(longitude)/?token=\(token)") else {
            throw AirQualityError.apiError("Invalid URL")
        }
        return try await fetchFeed(url: url)
    }

    public func fetchCurrent(city: String) async throws -> AirQuality {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city
        guard let url = URL(string: "\(baseURL)/feed/\(encoded)/?token=\(token)") else {
            throw AirQualityError.apiError("Invalid URL")
        }
        return try await fetchFeed(url: url)
    }

    public func search(keyword: String) async throws -> [StationSummary] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "\(baseURL)/search/?keyword=\(encoded)&token=\(token)") else {
            throw AirQualityError.apiError("Invalid URL")
        }
        let data = try await fetchWithRetry(url: url)
        let response = try JSONDecoder().decode(WAQISearchResponse.self, from: data)

        guard response.status == "ok" else {
            throw AirQualityError.apiError(response.status)
        }

        return response.data.compactMap { item in
            let aqi = Int(item.aqi)
            guard let geo = item.station.geo, geo.count == 2 else { return nil }
            return StationSummary(
                id: item.uid,
                name: item.station.name,
                aqi: aqi,
                coordinate: Coordinate(latitude: geo[0], longitude: geo[1])
            )
        }
    }

    public func fetchMapBounds(lat1: Double, lng1: Double, lat2: Double, lng2: Double) async throws -> [MapStation] {
        guard let url = URL(string: "\(baseURL)/map/bounds/?latlng=\(lat1),\(lng1),\(lat2),\(lng2)&token=\(token)") else {
            throw AirQualityError.apiError("Invalid URL")
        }
        let data = try await fetchWithRetry(url: url)
        let response = try JSONDecoder().decode(WAQIMapResponse.self, from: data)

        guard response.status == "ok" else {
            throw AirQualityError.apiError(response.status)
        }

        return response.data.map { item in
            MapStation(
                id: "\(item.uid)",
                name: item.station.name,
                coordinate: Coordinate(latitude: item.lat, longitude: item.lon),
                aqi: Int(item.aqi)
            )
        }
    }

    // MARK: - Private

    private func fetchWithRetry(url: URL, maxAttempts: Int = 2) async throws -> Data {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw AirQualityError.apiError("Server returned error")
                }
                return data
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }
        throw lastError ?? AirQualityError.noData
    }

    private func fetchFeed(url: URL) async throws -> AirQuality {
        let data = try await fetchWithRetry(url: url)
        let response = try JSONDecoder().decode(WAQIFeedResponse.self, from: data)

        guard response.status == "ok", let feedData = response.data else {
            throw AirQualityError.apiError(response.data?.city?.name ?? "Unknown station")
        }

        return mapToAirQuality(feedData)
    }

    private func mapToAirQuality(_ data: WAQIFeedData) -> AirQuality {
        let pollutants = parsePollutants(from: data.iaqi)
        let weather = parseWeather(from: data.iaqi)
        let forecast = parseForecast(from: data.forecast)
        let uviForecast = parseUVIForecast(from: data.forecast)
        let dominantPollutant = Pollutant.Kind(rawValue: data.dominentpol ?? "")

        let timestamp: Date
        if let unix = data.time.v {
            timestamp = Date(timeIntervalSince1970: TimeInterval(unix))
        } else {
            timestamp = Date()
        }

        let station = Station(
            id: data.idx,
            name: data.city?.name ?? "Unknown",
            coordinate: Coordinate(
                latitude: data.city?.geo?.first ?? 0,
                longitude: data.city?.geo?.last ?? 0
            ),
            url: data.city?.url ?? ""
        )

        let attribution = (data.attributions ?? []).map {
            Attribution(name: $0.name, url: $0.url ?? "")
        }

        let timeZoneOffset = Self.parseTimeZoneOffset(data.time.tz)

        return AirQuality(
            aqi: data.aqi ?? 0,
            dominantPollutant: dominantPollutant,
            pollutants: pollutants,
            weather: weather,
            station: station,
            forecast: forecast,
            uviForecast: uviForecast,
            timestamp: timestamp,
            attribution: attribution,
            timeZoneOffset: timeZoneOffset
        )
    }

    private func parsePollutants(from iaqi: [String: WAQIValue]?) -> [Pollutant] {
        guard let iaqi else { return [] }
        let pollutantKeys: [String: Pollutant.Kind] = [
            "pm25": .pm25, "pm10": .pm10, "o3": .o3,
            "no2": .no2, "so2": .so2, "co": .co,
        ]
        return pollutantKeys.compactMap { key, kind in
            guard let value = iaqi[key]?.v else { return nil }
            return Pollutant(kind: kind, aqi: value)
        }
    }

    private func parseWeather(from iaqi: [String: WAQIValue]?) -> Weather {
        guard let iaqi else { return Weather() }
        return Weather(
            temperature: iaqi["t"]?.v,
            humidity: iaqi["h"]?.v,
            pressure: iaqi["p"]?.v,
            windSpeed: iaqi["w"]?.v,
            dewPoint: iaqi["dew"]?.v
        )
    }

    private func parseForecast(from forecast: WAQIForecast?) -> [DailyForecast] {
        guard let daily = forecast?.daily else { return [] }
        var results: [DailyForecast] = []

        let pollutantMap: [(String, Pollutant.Kind)] = [
            ("pm25", .pm25), ("pm10", .pm10), ("o3", .o3),
        ]

        for (key, kind) in pollutantMap {
            guard let entries = daily[key] else { continue }
            for entry in entries {
                results.append(DailyForecast(
                    pollutant: kind,
                    day: entry.day,
                    avg: entry.avg,
                    min: entry.min,
                    max: entry.max
                ))
            }
        }

        return results
    }

    /// Parse WAQI timezone string like "+05:30" or "-08:00" into seconds from GMT.
    private static func parseTimeZoneOffset(_ tz: String?) -> Int? {
        guard let tz, !tz.isEmpty else { return nil }
        let clean = tz.trimmingCharacters(in: .whitespaces)
        let sign: Int = clean.hasPrefix("-") ? -1 : 1
        let stripped = clean.dropFirst(clean.hasPrefix("+") || clean.hasPrefix("-") ? 1 : 0)
        let parts = stripped.split(separator: ":")
        guard let hours = Int(parts.first ?? "") else { return nil }
        let minutes = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return sign * (hours * 3600 + minutes * 60)
    }

    private func parseUVIForecast(from forecast: WAQIForecast?) -> [UVIForecastPoint] {
        guard let daily = forecast?.daily,
              let entries = daily["uvi"]
        else { return [] }

        return entries.map { entry in
            UVIForecastPoint(day: entry.day, avg: entry.avg, min: entry.min, max: entry.max)
        }
    }
}

// MARK: - Errors

public enum AirQualityError: LocalizedError, Sendable {
    case apiError(String)
    case stationOffline
    case noData

    public var errorDescription: String? {
        switch self {
        case .apiError(let message): "API error: \(message)"
        case .stationOffline: "Station is currently offline"
        case .noData: "No air quality data available"
        }
    }
}

// MARK: - WAQI JSON Response Models (internal)

struct WAQIFeedResponse: Decodable {
    let status: String
    let data: WAQIFeedData?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)

        // data can be a string (error message) or an object
        if let dataObj = try? container.decode(WAQIFeedData.self, forKey: .data) {
            data = dataObj
        } else {
            data = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, data
    }
}

struct WAQIFeedData: Decodable {
    let aqi: Int?
    let idx: Int
    let dominentpol: String?  // Their typo, not ours
    let attributions: [WAQIAttribution]?
    let city: WAQICity?
    let iaqi: [String: WAQIValue]?
    let time: WAQITime
    let forecast: WAQIForecast?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idx = try container.decode(Int.self, forKey: .idx)
        dominentpol = try container.decodeIfPresent(String.self, forKey: .dominentpol)
        attributions = try container.decodeIfPresent([WAQIAttribution].self, forKey: .attributions)
        city = try container.decodeIfPresent(WAQICity.self, forKey: .city)
        iaqi = try container.decodeIfPresent([String: WAQIValue].self, forKey: .iaqi)
        time = try container.decode(WAQITime.self, forKey: .time)
        forecast = try container.decodeIfPresent(WAQIForecast.self, forKey: .forecast)

        // aqi can be Int or "-" string when station offline
        if let intVal = try? container.decode(Int.self, forKey: .aqi) {
            aqi = intVal
        } else {
            aqi = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case aqi, idx, dominentpol, attributions, city, iaqi, time, forecast
    }
}

struct WAQICity: Decodable {
    let geo: [Double]?
    let name: String?
    let url: String?
}

struct WAQIValue: Decodable {
    let v: Double
}

struct WAQITime: Decodable {
    let s: String?
    let tz: String?
    let v: Int?
    let iso: String?
}

struct WAQIAttribution: Decodable {
    let url: String?
    let name: String
}

struct WAQIForecast: Decodable {
    let daily: [String: [WAQIForecastEntry]]?
}

struct WAQIForecastEntry: Decodable {
    let avg: Int
    let day: String
    let max: Int
    let min: Int
}

// MARK: - Search Response

struct WAQISearchResponse: Decodable {
    let status: String
    let data: [WAQISearchResult]
}

struct WAQISearchResult: Decodable {
    let uid: Int
    let aqi: String  // String in search results, not Int
    let station: WAQISearchStation
}

struct WAQISearchStation: Decodable {
    let name: String
    let geo: [Double]?
}

// MARK: - Map Response

struct WAQIMapResponse: Decodable {
    let status: String
    let data: [WAQIMapItem]
}

struct WAQIMapItem: Decodable {
    let uid: Int
    let aqi: String
    let lat: Double
    let lon: Double
    let station: WAQIMapStation
}

struct WAQIMapStation: Decodable {
    let name: String
}
