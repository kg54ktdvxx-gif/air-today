import SwiftUI
import AirTodayCore

/// One page's vertical scroll offset. Read only by the views that fade with it, so
/// scrolling into the cards doesn't rebuild the hero, cards and chart every frame.
@MainActor
@Observable
final class PageScrollState {
    var offset: CGFloat = 0
}

/// A single location's page — hero and detail cards over the shared atmosphere.
public struct LocationPage: View {
    let store: AirQualityStore
    let location: SavedLocation
    /// The device's position, passed only for the current-location page.
    let userCoordinate: Coordinate?
    /// Reports the vertical scroll offset every frame (for the pager's parallax and top bar).
    let onScrollOffsetChange: (CGFloat) -> Void
    let onRetry: () async -> Void

    @State private var scroll = PageScrollState()
    @State private var hasScrolled = false
    @State private var nearbyStations: [MapStation] = []
    @AppStorage(AppConstants.temperatureUnitKey, store: .shared)
    private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage(AQIScale.storageKey, store: .shared)
    private var scale: AQIScale = .usEPA
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
        onScrollOffsetChange: @escaping (CGFloat) -> Void = { _ in },
        onRetry: @escaping () async -> Void
    ) {
        self.store = store
        self.location = location
        self.userCoordinate = userCoordinate
        self.onScrollOffsetChange = onScrollOffsetChange
        self.onRetry = onRetry
    }

    public var body: some View {
        pageContent
            .task(id: store.currentAQI?.coordinate) {
                await loadNearbyStations()
            }
            .sensoryFeedback(.impact(flexibility: .solid), trigger: store.currentAQI.map { scale.displayReading(for: $0).reading.severityLevel }) { old, new in
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
        FadesOnScroll(scroll: scroll, distance: Self.heroFadeDistance) {
            RadialGradient(
                colors: [.black.opacity(0.2), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Scroll distance over which the hero fades out.
    private static let heroFadeDistance: CGFloat = 150

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
            scroll.offset = newValue
            onScrollOffsetChange(newValue)
            // Only write on a real change, so this doesn't invalidate the page each frame.
            if newValue > 20, !hasScrolled { hasScrolled = true }
            else if newValue < 5, hasScrolled { hasScrolled = false }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        FadesOnScroll(scroll: scroll, distance: Self.heroFadeDistance) {
            VerdictHero(
                quality: store.currentAQI,
                state: store.state,
                hasScrolled: hasScrolled,
                placeName: placeName,
                isCurrentLocation: location.isCurrentLocation,
                distanceFromUser: distanceFromUser,
                onRetry: onRetry
            )
        }
    }

    /// The town for the current location (looked up on device), else "My Location";
    /// a saved city's own name up to its first comma.
    private var placeName: String {
        if location.isCurrentLocation {
            return store.currentAQI?.placeName ?? "My Location"
        }
        return location.name.components(separatedBy: ",").first ?? location.name
    }

    private var distanceFromUser: Double? {
        guard let userCoordinate, let station = store.currentAQI?.station?.coordinate else { return nil }
        return userCoordinate.distance(to: station)
    }

    // MARK: - Detail Cards

    private func detailCards(quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, scale: scale, profile: healthProfile)
        let shown = scale.displayReading(for: quality)
        let rows = pollutantRows(quality: quality, scale: shown.scale)

        return VStack(spacing: DS.spacingXL) {
            ActivityGuidanceCard(guidance: guidance, accent: shown.reading.band.color, scale: scale)

            if !rows.isEmpty {
                pollutantCard(quality: quality, rows: rows, shown: shown)
            }

            if let forecast = ForecastGraphCard(quality: quality, scale: shown.scale, accent: shown.reading.band.color) {
                forecast
            }

            if !nearbyStations.isEmpty {
                NearbyStationsCard(stations: nearbyStations, userCoordinate: quality.coordinate)
            }

            conditionsCard(quality: quality)

            DS.divider
                .padding(.horizontal, 40)

            AttributionView(attributions: quality.attribution, showsModelData: quality.model != nil)
                .padding(.top, DS.spacingSM)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.spacingXL)
    }

    // MARK: - Pollutant Card

    private func pollutantCard(
        quality: AirQuality,
        rows: [(kind: Pollutant.Kind, value: Int)],
        shown: (scale: AQIScale, reading: ScaledReading)
    ) -> some View {
        let reading = shown.reading
        return VStack(alignment: .leading, spacing: 0) {
            Text("Pollutants")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.cardHeaderBottom)

            ForEach(Array(rows.enumerated()), id: \.element.kind) { index, row in
                PollutantRow(kind: row.kind, value: row.value, scale: shown.scale)
                    .padding(.horizontal, DS.spacingLG)
                    .overlay(alignment: .leading) {
                        // An overlay, so the marker doesn't push this row out of line.
                        if row.kind == reading.dominantPollutant {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(reading.band.color)
                                .frame(width: 3)
                                .padding(.vertical, 2)
                        }
                    }

                if index < rows.count - 1 {
                    DS.divider
                        .padding(.horizontal, DS.spacingLG)
                }
            }

            let excluded = quality.pollutants.filter { !shown.scale.pollutants.contains($0.kind) }
            if !excluded.isEmpty {
                Text("\(ListFormatter.localizedString(byJoining: excluded.map(\.kind.displayName))) \(excluded.count == 1 ? "isn't" : "aren't") part of the \(shown.scale.shortName).")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))
                    .padding(.horizontal, DS.spacingLG)
                    .padding(.top, DS.spacingXS)
            }

            Spacer().frame(height: DS.spacingSM)
        }
        .background { DS.cardBackground }
    }

    /// The scale's pollutants with a value, the one driving its index first, then worst to best.
    private func pollutantRows(quality: AirQuality, scale: AQIScale) -> [(kind: Pollutant.Kind, value: Int)] {
        let dominant = scale.displayReading(for: quality).reading.dominantPollutant
        return Pollutant.Kind.allCases
            .compactMap { kind in scale.subIndex(for: kind, in: quality).map { (kind: kind, value: $0) } }
            .sorted { a, b in
                if a.kind == dominant { return true }
                if b.kind == dominant { return false }
                return a.value > b.value
            }
    }

    // MARK: - Conditions Card

    @ViewBuilder
    private func conditionsCard(quality: AirQuality) -> some View {
        let weather = quality.weather
        let sunset = quality.coordinate.flatMap { coordinate in
            quality.timeZoneOffset.flatMap { offset in
                SunCalculator.sunset(latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneOffset: offset)
                    .map { SunCalculator.formatTime($0, timeZoneOffset: offset) }
            }
        }
        let uvPeak = quality.todayUVPeak()

        if weather != Weather() || sunset != nil || uvPeak != nil {
            VStack(alignment: .leading, spacing: 0) {
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
                    if let sunset {
                        conditionItem(icon: "sunset.fill", value: sunset, label: "Sunset")
                    }
                    // Today's highest hour from the forecast, so it's useful all day — not
                    // the current UV, which is 0 every evening.
                    if let uvPeak {
                        UVIndexRow(uvIndex: Int(uvPeak.rounded()), caption: "Today's UV peak")
                    }
                }
                .padding(DS.spacingLG)
            }
            .background { DS.cardBackground }
        }
    }

    // MARK: - Nearby Stations

    private func loadNearbyStations() async {
        guard let center = store.currentAQI?.coordinate else { return }
        let lat = center.latitude
        let lng = center.longitude
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

/// Fades its content out over the first `distance` points of scrolling. It reads the
/// offset itself, so only it — not the page around it — updates on each scroll frame.
private struct FadesOnScroll<Content: View>: View {
    let scroll: PageScrollState
    let distance: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content.opacity(Double(min(1, max(0, 1 - scroll.offset / distance))))
    }
}
