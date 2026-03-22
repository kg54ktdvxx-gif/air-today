import SwiftUI
import AirTodayCore

/// A single location's page — atmosphere background + vertical scroll content.
/// Extracted from the former HomeScreen.swift.
public struct LocationPage: View {
    let store: AirQualityStore
    let location: SavedLocation
    let onRetry: () async -> Void

    @State private var renderQuality = RenderQuality()
    @State private var scrollOffset: CGFloat = 0
    @State private var hasScrolled = false
    @State private var nearbyStations: [MapStation] = []
    @AppStorage("parallax_enabled") private var parallaxEnabled = true
    @AppStorage("temp_unit") private var temperatureUnit = "celsius"

    private static let guidanceService = ActivityGuidanceService()

    public init(store: AirQualityStore, location: SavedLocation, onRetry: @escaping () async -> Void) {
        self.store = store
        self.location = location
        self.onRetry = onRetry
    }

    private var atmosphereParams: AtmosphereParameters {
        guard let quality = store.currentAQI else { return .placeholder }
        return AtmosphereParameters(from: quality)
    }

    public var body: some View {
        pageContent
            .task(id: store.currentAQI?.station.id) {
                await loadNearbyStations()
            }
            .sensoryFeedback(.impact(flexibility: .solid), trigger: store.currentAQI?.level) { old, new in
                old != nil && old != new
            }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                renderQuality.update()
            }
    }

    private var pageContent: some View {
        ZStack {
            // Dark base so scrolled content never reveals black void
            Color(red: 0.08, green: 0.08, blue: 0.1)
                .ignoresSafeArea()
            atmosphereBackground
            heroScrim
            scrollContent
        }
    }

    // MARK: - Atmosphere Background

    private var currentLevel: AQILevel {
        store.currentAQI?.level ?? .good
    }

    private var atmosphereBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Photo background — the primary visual
                let parallaxShift = parallaxEnabled ? scrollOffset * 0.8 : 0
                Image(currentLevel.backgroundImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height + 400)
                    .offset(y: -parallaxShift)
                    .clipped()
                    .animation(.easeInOut(duration: 1.0), value: currentLevel)

                // Soft blur + darken scrim for text readability
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.35)

                // Gradient scrim — darker at top for status bar / hero text readability
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.6), .black.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 350)

                    Spacer()
                }

                // Optional shader/particle overlay for extra atmosphere
                if renderQuality.tier.shadersEnabled {
                    ShaderOverlay(params: atmosphereParams)
                        .opacity(0.4)

                    ParticleOverlay(
                        config: atmosphereParams.particleConfig,
                        tier: renderQuality.tier
                    )
                    .opacity(0.5)
                }
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
                    .frame(minHeight: UIScreen.main.bounds.height)

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
        .preference(key: ScrollOffsetKey.self, value: scrollOffset)
    }

    // MARK: - Hero

    private var heroSection: some View {
        let heroOpacity = min(1, max(0, 1 - scrollOffset / 150))
        return VerdictHero(
            quality: store.currentAQI,
            state: store.state,
            lastRefreshed: store.lastRefreshed,
            heroOpacity: heroOpacity,
            hasScrolled: hasScrolled,
            onRetry: onRetry
        )
    }

    // MARK: - Detail Cards

    private func detailCards(quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality)

        return VStack(spacing: DS.spacingXL) {
            ActivityGuidanceCard(guidance: guidance, level: quality.level)

            if !quality.pollutants.isEmpty {
                pollutantCard(quality: quality)
            }

            if !quality.forecast.isEmpty {
                ForecastGraphCard(
                    forecasts: quality.forecast,
                    dominantPollutant: quality.dominantPollutant ?? .pm25,
                    currentAQI: quality.aqi
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
                HStack(spacing: 0) {
                    if pollutant.kind == quality.dominantPollutant {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(quality.level.color)
                            .frame(width: 3)
                            .padding(.vertical, 2)
                    }

                    PollutantRow(pollutant: pollutant)
                        .padding(.horizontal, DS.spacingLG)
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
                    let displayTemp = temperatureUnit == "fahrenheit" ? Int(temp * 9 / 5 + 32) : Int(temp)
                    let unit = temperatureUnit == "fahrenheit" ? "F" : "C"
                    conditionItem(icon: "thermometer.medium", value: "\(displayTemp)\u{00B0}\(unit)", label: "Temperature")
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
                    let displayDew = temperatureUnit == "fahrenheit" ? Int(dew * 9 / 5 + 32) : Int(dew)
                    let unit = temperatureUnit == "fahrenheit" ? "F" : "C"
                    conditionItem(icon: "drop.fill", value: "\(displayDew)\u{00B0}\(unit)", label: "Dew Point")
                }
                if let tzOffset = quality.timeZoneOffset {
                    let lat = quality.station.coordinate.latitude
                    let lng = quality.station.coordinate.longitude
                    if let sunsetDate = SunCalculator.sunset(latitude: lat, longitude: lng, timeZoneOffset: tzOffset) {
                        conditionItem(icon: "sunset.fill", value: SunCalculator.formatTime(sunsetDate, timeZoneOffset: tzOffset), label: "Sunset")
                    }
                }
            }
            .padding(DS.spacingLG)

            // UV Index removed — WAQI only provides daily forecast (avg/min/max),
            // not real-time UV. Showing forecast peak was misleading vs Apple Weather.
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
