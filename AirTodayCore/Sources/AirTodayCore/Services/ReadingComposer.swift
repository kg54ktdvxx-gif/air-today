import Foundation

/// Chooses the headline reading for a place from a WAQI station and the CAMS model.
///
/// 1. The station, if it reported within 2 hours and is within 20 km (or the user
///    picked it) — a recent local measurement beats a ~11–45 km model cell.
/// 2. Otherwise the model's current estimate, which is always current.
/// 3. Otherwise that station anyway (under 24 hours old; its age is shown). A
///    station farther away is another place's air, so then there's no reading.
///
/// Weather comes from Open-Meteo when it answered — always current — else from the
/// station shown.
public enum ReadingComposer {
    public static func compose(
        station: AirQuality?,
        model: ModelAirData?,
        query: Coordinate?,
        stationChosenByUser: Bool,
        now: Date = Date()
    ) -> AirQuality? {
        let local = station.flatMap { isLocal($0, query: query, chosen: stationChosenByUser) ? $0 : nil }
        if let local, isRecent(local, now: now) {
            return attaching(model, to: local)
        }
        // A local station that isn't recent stays attached for reference.
        if let model, let fromModel = headline(from: model, station: local) {
            return fromModel
        }
        return local.map { attaching(model, to: $0) }
    }

    static func isRecent(_ station: AirQuality, now: Date) -> Bool {
        now.timeIntervalSince(station.timestamp) <= AppConstants.stationMaxAgeForHeadline
    }

    /// The user's pick, or near enough to the place to describe it. With no query
    /// (the IP lookup) the station is the place.
    static func isLocal(_ station: AirQuality, query: Coordinate?, chosen: Bool) -> Bool {
        guard !chosen, let query, let coordinate = station.station?.coordinate else { return true }
        return coordinate.distance(to: query) <= AppConstants.stationMaxDistanceForHeadline
    }

    private static func attaching(_ model: ModelAirData?, to station: AirQuality) -> AirQuality {
        AirQuality(
            aqi: station.aqi,
            dominantPollutant: station.dominantPollutant,
            pollutants: station.pollutants,
            weather: model?.weather ?? station.weather,
            station: station.station,
            source: .station,
            model: model,
            timestamp: station.timestamp,
            attribution: station.attribution,
            timeZoneOffset: station.timeZoneOffset ?? model?.utcOffsetSeconds
        )
    }

    private static func headline(from model: ModelAirData, station: AirQuality?) -> AirQuality? {
        let current = model.current
        guard let aqi = current.usAQI else { return nil }
        return AirQuality(
            aqi: aqi,
            dominantPollutant: current.usDominant,
            pollutants: current.usSubIndices
                .map { Pollutant(kind: $0.key, aqi: Double($0.value)) }
                .sorted { $0.aqi > $1.aqi },
            weather: model.weather ?? Weather(),
            station: station?.station,
            source: .model,
            model: model,
            timestamp: current.time,
            attribution: station?.attribution ?? [],
            timeZoneOffset: model.utcOffsetSeconds
        )
    }
}

/// Fetches a place's station reading and model data together and composes them.
public struct AirReadingService: Sendable {
    let stations: AirQualityServiceProtocol
    let model: ModelAirServiceProtocol

    public init(
        stations: AirQualityServiceProtocol,
        model: ModelAirServiceProtocol = OpenMeteoAirService()
    ) {
        self.stations = stations
        self.model = model
    }

    public init(token: String = AppConstants.waqiToken) {
        self.init(stations: AirQualityService(token: token))
    }

    /// Stations matching a name, for adding a city.
    public func search(keyword: String) async throws -> [StationSummary] {
        try await stations.search(keyword: keyword)
    }

    /// - Parameters:
    ///   - coordinate: where to read; nil means "here" by IP (current location without GPS).
    ///   - stationID: a station the user picked (saved cities).
    public func reading(at coordinate: Coordinate?, stationID: Int? = nil) async throws -> AirQuality {
        if let coordinate {
            async let stationResult = Self.capture {
                if let stationID { try await stations.fetchStation(id: stationID) }
                else { try await stations.fetchCurrent(latitude: coordinate.latitude, longitude: coordinate.longitude) }
            }
            async let modelResult = Self.capture { try await model.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude) }
            return try Self.compose(await stationResult, await modelResult, query: coordinate, chosen: stationID != nil)
        }

        // No coordinate: WAQI places us by IP; the model then reads at that station.
        let stationResult = await Self.capture { try await stations.fetchCurrent(city: "here") }
        var modelResult: Result<ModelAirData, Error> = .failure(AirQualityError.noData)
        if case .success(let station) = stationResult, let spot = station.station?.coordinate {
            modelResult = await Self.capture { try await model.fetch(latitude: spot.latitude, longitude: spot.longitude) }
        }
        return try Self.compose(stationResult, modelResult, query: nil, chosen: false)
    }

    private static func compose(
        _ station: Result<AirQuality, Error>,
        _ model: Result<ModelAirData, Error>,
        query: Coordinate?,
        chosen: Bool
    ) throws -> AirQuality {
        if let reading = ReadingComposer.compose(
            station: try? station.get(),
            model: try? model.get(),
            query: query,
            stationChosenByUser: chosen
        ) {
            return reading
        }
        // Neither source worked: report the station's reason, which is the more specific one.
        if case .failure(let error) = station { throw error }
        if case .failure(let error) = model { throw error }
        throw AirQualityError.noData
    }

    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
