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
    /// Column or panes, chosen by the pager for the space every page has.
    let layout: PlaceLayout
    /// Reports the vertical scroll offset every frame (for the pager's parallax and top bar).
    let onScrollOffsetChange: (CGFloat) -> Void
    let onRetry: () async -> Void

    @State private var scroll = PageScrollState()
    @State private var hasScrolled = false
    @State private var nearbyStations: [MapStation] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DS.reduceVisualEffectsKey) private var reduceVisualEffects = false
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

    // Internal: only the pager builds pages, and it hands them the layout it chose.
    init(
        store: AirQualityStore,
        location: SavedLocation,
        layout: PlaceLayout = .fullHeightColumn,
        onScrollOffsetChange: @escaping (CGFloat) -> Void = { _ in },
        onRetry: @escaping () async -> Void
    ) {
        self.store = store
        self.location = location
        self.layout = layout
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

    /// The atmosphere and the hero's scrim behind this content are drawn once by
    /// `LocationPager`, so they carry across swipes and reach under a side status bar.
    @ViewBuilder
    private var pageContent: some View {
        switch layout {
        case .column(let heroHeight, let foldGap):
            scrolling(ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if let heroHeight {
                        // Above a horizontal fold, with the cards starting below it.
                        heroSection
                            .frame(height: heroHeight)
                        Color.clear.frame(height: foldGap)
                    } else {
                        heroSection
                            .containerRelativeFrame(.vertical)
                    }

                    if let quality = store.currentAQI {
                        detailCards(quality: quality)
                    }
                }
            })
        case .panes(let heroWidth, let gap):
            // The answer stays in view beside the detail; only the cards scroll.
            HStack(spacing: 0) {
                hero(showsScrollHint: false)
                    .frame(width: heroWidth)
                Color.clear.frame(width: gap)
                scrolling(ScrollView(.vertical) {
                    if let quality = store.currentAQI {
                        detailCards(quality: quality)
                    }
                })
            }
        }
    }

    /// Scroll distance over which the hero (and the pager's scrim behind it) fades out.
    static let heroFadeDistance: CGFloat = 150

    // MARK: - Scrolling

    /// What every page's scroll view shares: refresh, and reporting its offset.
    private func scrolling(_ scrollView: some View) -> some View {
        scrollView
            .scrollIndicators(.hidden)
            .accessibilityIdentifier(layout.accessibilityIdentifier)
            // The hero runs to the bottom of the screen and the last card clears the home
            // indicator with its own padding (`spacingPageEnd`); the top and sides stay inset.
            .ignoresSafeArea(edges: .bottom)
            .refreshable {
                await onRetry()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                // Measured from the top of the content, not the top of the scroll view: the
                // content starts below the top bar, which `contentOffset` counts as negative.
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newValue in
                scroll.offset = newValue
                onScrollOffsetChange(newValue)
                // Only write on a real change, so this doesn't invalidate the page each frame.
                if newValue > 20, !hasScrolled { hasScrolled = true }
                else if newValue < 5, hasScrolled { hasScrolled = false }
            }
    }

    // MARK: - Hero

    /// The hero in a column, fading as the cards scroll up over it.
    private var heroSection: some View {
        FadesOnScroll(scroll: scroll, distance: Self.heroFadeDistance) {
            hero(showsScrollHint: true)
        }
    }

    private func hero(showsScrollHint: Bool) -> some View {
        VerdictHero(
            quality: store.currentAQI,
            state: store.state,
            hasScrolled: hasScrolled,
            showsScrollHint: showsScrollHint,
            placeName: placeName,
            isCurrentLocation: location.isCurrentLocation,
            onRetry: onRetry
        )
    }

    /// The town for the current location (looked up on device), else "My Location";
    /// a saved city's own name up to its first comma.
    private var placeName: String {
        if location.isCurrentLocation {
            return store.currentAQI?.placeName ?? "My Location"
        }
        return location.name.components(separatedBy: ",").first ?? location.name
    }

    // MARK: - Detail Cards

    private func detailCards(quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, scale: scale, profile: healthProfile)
        let shown = scale.displayReading(for: quality)
        let details = DetailsCard(quality: quality, stations: nearbyStations, temperatureUnit: temperatureUnit, scale: scale)

        return VStack(spacing: DS.spacingXL) {
            // Each card rises in once, the first time it scrolls into view.
            let reveal = !reduceMotion && !reduceVisualEffects
            ActivityGuidanceCard(guidance: guidance, scale: scale, shownScale: shown.scale)
                .revealOnScroll(reveal)

            ForecastGraphCard(quality: quality, scale: shown.scale, accent: shown.reading.band.color, drawsIn: reveal)
                .revealOnScroll(reveal)

            if !details.isEmpty {
                details
                    .revealOnScroll(reveal)
            }

            DS.divider
                .padding(.horizontal, DS.spacingPageEnd)

            AttributionView(attributions: quality.attribution, showsModelData: quality.model != nil)
                .padding(.top, DS.spacingSM)
                .padding(.bottom, DS.spacingPageEnd)
        }
        .frame(maxWidth: DS.readableWidth)
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.spacingXL)
        .frame(maxWidth: .infinity)
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
