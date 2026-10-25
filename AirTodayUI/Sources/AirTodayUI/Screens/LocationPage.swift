import SwiftUI
import AirTodayCore

/// A single location's page — hero and detail cards over the shared atmosphere.
public struct LocationPage: View {
    let store: AirQualityStore
    let location: SavedLocation
    /// The device's position, passed only for the current-location page.
    let userCoordinate: Coordinate?
    let onRetry: () async -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var hasScrolled = false
    @State private var nearbyStations: [MapStation] = []
    @AppStorage(AppConstants.temperatureUnitKey, store: .shared)
    private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false

    private var healthProfile: HealthProfile {
        HealthProfile(
            hasRespiratoryCondition: hasRespiratoryCondition,
            isOzoneSensitive: isOzoneSensitive,
            hasChildren: hasChildren
        )
    }

    private static let guidanceService = ActivityGuidanceService()

    public init(
        store: AirQualityStore,
        location: SavedLocation,
        userCoordinate: Coordinate? = nil,
        onRetry: @escaping () async -> Void
    ) {
        self.store = store
        self.location = location
        self.userCoordinate = userCoordinate
        self.onRetry = onRetry
    }

    public var body: some View {
        pageContent
            .task(id: store.currentAQI?.station.id) {
                await loadNearbyStations()
            }
            .sensoryFeedback(.impact(flexibility: .solid), trigger: store.currentAQI?.level) { old, new in
                old != nil && old != new
            }
    }

    /// The atmosphere behind this content is drawn once by `LocationPager`
    /// (`AtmosphereBackdrop`), so it can carry across swipes between pages.
    private var pageContent: some View {
        ZStack {
            heroScrim
            scrollContent
        }
    }

    // MARK: - Hero Scrim

    /// Additional center vignette for hero text contrast.
    private var heroScrim: some View {
        RadialGradient(
            colors: [.black.opacity(0.2), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(Double(min(1, max(0, 1 - scrollOffset / 150))))
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                heroSection
                    .containerRelativeFrame(.vertical)

                if let quality = store.currentAQI {
                    detailCards(quality: quality)
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await onRetry()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newValue in
            scrollOffset = newValue
            if newValue > 20 { hasScrolled = true }
            else if newValue < 5 { hasScrolled = false }
        }
        .preference(key: PageScrollOffsetsKey.self, value: [location.id: scrollOffset])
    }

    // MARK: - Hero

    private var heroSection: some View {
        let heroOpacity = min(1, max(0, 1 - scrollOffset / 150))
        return VerdictHero(
            quality: store.currentAQI,
            state: store.state,
            heroOpacity: heroOpacity,
            hasScrolled: hasScrolled,
            distanceFromUser: distanceFromUser,
            onRetry: onRetry
        )
    }

    private var distanceFromUser: Double? {
        guard let userCoordinate, let station = store.currentAQI?.station.coordinate else { return nil }
        return userCoordinate.distance(to: station)
    }

    // MARK: - Detail Cards

    private func detailCards(quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, profile: healthProfile)

        return VStack(spacing: DS.spacingXL) {
            ActivityGuidanceCard(guidance: guidance, level: quality.level)

            if !quality.pollutants.isEmpty {
                pollutantCard(quality: quality)
            }

            if !quality.forecast.isEmpty {
                ForecastGraphCard(
                    forecasts: quality.forecast,
                    dominantPollutant: quality.dominantPollutant,
                    currentAQI: quality.aqi,
                    accent: quality.level.color
                )
            }

            if !nearbyStations.isEmpty {
                NearbyStationsCard(
                    stations: nearbyStations,
                    userCoordinate: Coordinate(
                        latitude: quality.station.coordinate.latitude,
                        longitude: quality.station.coordinate.longitude
                    )
                )
            }

            if quality.weather.temperature != nil {
                conditionsCard(quality: quality)
            }

            DS.divider
                .padding(.horizontal, 40)

            AttributionView(attributions: quality.attribution)
                .padding(.top, DS.spacingSM)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.spacingXL)
    }

    // MARK: - Pollutant Card

    private func pollutantCard(quality: AirQuality) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pollutants")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.cardHeaderBottom)

            let sorted = sortedPollutants(quality: quality)
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, pollutant in
                PollutantRow(pollutant: pollutant)
                    .padding(.horizontal, DS.spacingLG)
                    .overlay(alignment: .leading) {
                        // An overlay, so the marker doesn't push this row out of line.
                        if pollutant.kind == quality.dominantPollutant {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(quality.level.color)
                                .frame(width: 3)
                                .padding(.vertical, 2)
                        }
                    }

                if index < sorted.count - 1 {
                    DS.divider
                        .padding(.horizontal, DS.spacingLG)
                }
            }

            Spacer().frame(height: DS.spacingSM)
        }
        .background { DS.cardBackground }
    }

    private func sortedPollutants(quality: AirQuality) -> [Pollutant] {
        let dominant = quality.dominantPollutant
        return quality.pollutants.sorted { a, b in
            if a.kind == dominant { return true }
            if b.kind == dominant { return false }
            return a.aqi > b.aqi
        }
    }

    // MARK: - Conditions Card

    private func conditionsCard(quality: AirQuality) -> some View {
        let weather = quality.weather

        return VStack(alignment: .leading, spacing: 0) {
            Text("Conditions")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.spacingXS)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.spacingMD) {
                if let temp = weather.temperature {
                    conditionItem(icon: "thermometer.medium", value: temperatureUnit.format(celsius: temp), label: "Temperature")
                }
                if let humidity = weather.humidity {
                    conditionItem(icon: "humidity.fill", value: "\(Int(humidity))%", label: "Humidity")
                }
                if let wind = weather.windSpeed {
                    conditionItem(icon: "wind", value: String(format: "%.1f m/s", wind), label: "Wind")
                }
                if let pressure = weather.pressure {
                    conditionItem(icon: "gauge.medium", value: "\(Int(pressure)) hPa", label: "Pressure")
                }
                if let dew = weather.dewPoint {
                    conditionItem(icon: "drop.fill", value: temperatureUnit.format(celsius: dew), label: "Dew Point")
                }
                if let tzOffset = quality.timeZoneOffset {
                    let lat = quality.station.coordinate.latitude
                    let lng = quality.station.coordinate.longitude
                    if let sunsetDate = SunCalculator.sunset(latitude: lat, longitude: lng, timeZoneOffset: tzOffset) {
                        conditionItem(icon: "sunset.fill", value: SunCalculator.formatTime(sunsetDate, timeZoneOffset: tzOffset), label: "Sunset")
                    }
                }
                // WAQI has no live UV, only a daily forecast — so this is labelled as
                // today's forecast peak rather than competing with hourly UV readings.
                if let uv = quality.todayUVForecast {
                    UVIndexRow(uvIndex: uv.max, caption: "Forecast UV peak")
                }
            }
            .padding(DS.spacingLG)
        }
        .background { DS.cardBackground }
    }

    // MARK: - Nearby Stations

    private func loadNearbyStations() async {
        guard let quality = store.currentAQI else { return }
        let lat = quality.station.coordinate.latitude
        let lng = quality.station.coordinate.longitude
        let delta = 0.5 // ~50km radius
        let service = AirQualityService(token: AppConstants.waqiToken)
        do {
            nearbyStations = try await service.fetchMapBounds(
                lat1: lat - delta, lng1: lng - delta,
                lat2: lat + delta, lng2: lng + delta
            )
        } catch {
            nearbyStations = []
        }
    }

    private func conditionItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DS.spacingSM) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))
                .frame(width: DS.iconMD)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
