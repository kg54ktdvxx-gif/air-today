import SwiftUI
import AirTodayCore

/// Swipe and scroll positions, which change every frame.
///
/// They live in their own observable object, read only by the views that draw from
/// them (backdrop, top-bar blur, refresh spinner). Kept as the pager's own state they
/// re-rendered the pager — and with it every page's hero, cards and charts — on every
/// frame of a swipe, which is what made swiping stutter.
@MainActor
@Observable
final class PagerScrollState {
    /// Fractional horizontal page index (1.5 = halfway between pages 1 and 2).
    var pagePosition: CGFloat = 0
    /// Each page's vertical scroll offset, keyed by location.
    var pageOffsets: [UUID: CGFloat] = [:]

    /// The page closest to the centre of the screen.
    func nearestLocation(in locations: [SavedLocation]) -> SavedLocation? {
        guard !locations.isEmpty else { return nil }
        let index = min(max(Int(pagePosition.rounded()), 0), locations.count - 1)
        return locations[index]
    }
}

/// Horizontal paged navigation across saved locations.
/// One shared atmosphere sits behind full-width LocationPages, so the scene
/// carries across swipes instead of cutting from page to page.
public struct LocationPager: View {
    @Bindable var locationManager: LocationManager
    let locationService: LocationService
    @State private var showingSearch = false
    @State private var scrollState = PagerScrollState()
    @AppStorage(DS.launchCountKey) private var launchCount = 0
    @State private var launchCounted = false
    @AppStorage(NotificationPreferences.Key.alertsOffered, store: .shared) private var alertsOffered = false
    @AppStorage(NotificationPreferences.Key.thresholdAlerts, store: .shared) private var thresholdAlerts = false
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA

    public init(locationManager: LocationManager, locationService: LocationService) {
        self.locationManager = locationManager
        self.locationService = locationService
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if locationManager.locations.isEmpty {
                    emptyStateView
                } else {
                    PagerBackdrop(locationManager: locationManager, scrollState: scrollState)
                    pagerContent
                }

                // Top bar: city dots (and menu) + settings
                VStack(spacing: 0) {
                    HStack {
                        pageIndicator
                        Spacer()
                        NavigationLink(value: AppRoute.settings) {
                            topBarIcon("gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, DS.spacingLG)
                    .padding(.vertical, DS.spacingSM)
                    .background {
                        TopBarBlur(selectedID: locationManager.selectedLocationID, scrollState: scrollState)
                    }

                    PagerRefreshIndicator(locationManager: locationManager, scrollState: scrollState)
                        // Below the page's place name.
                        .padding(.top, DS.spacingHuge)
                    Spacer()
                }

                // Once, for people updating from 1.1 (new installs see it in onboarding).
                if !alertsOffered, !thresholdAlerts, !locationManager.locations.isEmpty {
                    VStack {
                        Spacer()
                        AlertsOfferCard {
                            withAnimation(DS.Motion.standard) { alertsOffered = true }
                        }
                        .frame(maxWidth: DS.readableWidth)
                        .padding(.horizontal, DS.spacingLG)
                        .padding(.bottom, DS.spacingXL)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Location permission banner
                if locationService.isDenied {
                    VStack {
                        locationPermissionBanner
                            .frame(maxWidth: DS.readableWidth)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .padding(.top, DS.spacingHuge)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .settings:
                    SettingsScreen(locationManager: locationManager)
                case .privacyPolicy:
                    PrivacyPolicyView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSearch) {
                LocationSearchView(locationManager: locationManager)
            }
            .task {
                // This runs again whenever the pager reappears (back from Settings),
                // which isn't another launch. Counting it here rather than in the app's
                // init also keeps background refresh launches out of the count.
                if !launchCounted {
                    launchCounted = true
                    launchCount += 1
                }
                await locationManager.refreshIfNeeded()
            }
            .onChange(of: locationService.coordinate.map(Coordinate.init)) {
                // A new GPS fix (first grant, or the device moved) can make the
                // current-location reading stale before its cache TTL runs out.
                Task { await locationManager.refreshIfNeeded() }
            }
            .onChange(of: locationManager.selectedLocationID) { _, newID in
                guard let newID,
                      let location = locationManager.locations.first(where: { $0.id == newID }),
                      locationManager.store(for: location).currentAQI == nil
                else { return }
                Task { await locationManager.refresh(location: location) }
            }
            .sensoryFeedback(.selection, trigger: locationManager.selectedLocationID) { old, new in
                old != nil && old != new
            }
        }
    }

    // MARK: - Pager

    private var pagerContent: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(locationManager.locations) { location in
                    let store = locationManager.store(for: location)
                    LocationPage(
                        store: store,
                        location: location,
                        onScrollOffsetChange: { scrollState.pageOffsets[location.id] = $0 }
                    ) {
                        await locationManager.refresh(location: location)
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(location.id)
                }
            }
            // Without this, scrollPosition(id:) can't tell which page is showing and
            // writes nil on every swipe, dropping the selection (and the top-bar name).
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $locationManager.selectedLocationID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.x / max(geo.containerSize.width, 1)
        } action: { _, position in
            scrollState.pagePosition = position
        }
    }

    private func topBarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 20, height: 20)
            .padding(DS.spacingSM)
            .background(.black.opacity(0.2), in: Circle())
    }

    // MARK: - Page Indicator

    private func shortName(_ location: SavedLocation) -> String {
        location.isCurrentLocation
            ? "My Location"
            : location.name.components(separatedBy: ",").first ?? location.name
    }

    /// The current location is an arrow (as in Weather) so it's always findable; every
    /// other city is a dot in its own air-quality colour. The page showing is the
    /// widest, like the system page control; its name is the page's own title.
    @ViewBuilder
    private func marker(for location: SavedLocation, color: Color, isSelected: Bool) -> some View {
        if location.isCurrentLocation {
            Image(systemName: "location.fill")
                .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                .foregroundStyle(color.opacity(isSelected ? 1 : 0.55))
                .frame(width: 11, height: 11)
        } else {
            Capsule()
                .fill(color.opacity(isSelected ? 1 : 0.55))
                .frame(width: isSelected ? 16 : 7, height: 7)
        }
    }

    /// Where you are in your cities, and a menu of all of them.
    ///
    /// A marker per city (arrow for your location, dots in each city's AQI colour).
    /// Tapping it lists every city by name with its reading — colour alone can't tell
    /// two Good cities apart — and is where cities are added.
    private var pageIndicator: some View {
        let locations = locationManager.locations
        let selectedIndex = locations.firstIndex { $0.id == locationManager.selectedLocationID }
        let selectedName = selectedIndex.map { shortName(locations[$0]) } ?? ""

        return Menu {
            ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                Button {
                    withAnimation(DS.Motion.standard) {
                        locationManager.selectedLocationID = location.id
                    }
                } label: {
                    // Menus render a second Text as the subtitle.
                    Text(shortName(location))
                    Text(menuSubtitle(for: location))
                    Image(systemName: index == selectedIndex
                        ? "checkmark"
                        : location.isCurrentLocation ? "location.fill" : "mappin")
                }
            }
            if locationManager.canAddLocation {
                Divider()
                Button {
                    showingSearch = true
                } label: {
                    Label("Add City…", systemImage: "plus")
                }
            }
        } label: {
            indicatorCapsule(locations: locations, selectedIndex: selectedIndex)
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier("cityPicker")
        .accessibilityLabel("Cities")
        .accessibilityValue(selectedIndex.map { "\(selectedName), \($0 + 1) of \(locations.count)" } ?? "")
        .accessibilityHint("Shows all your cities")
    }

    /// e.g. "AQI 26 · Good", on the chosen scale.
    private func menuSubtitle(for location: SavedLocation) -> String {
        guard let quality = locationManager.store(for: location).currentAQI else { return "Loading…" }
        let shown = scale.displayReading(for: quality)
        return "\(shown.scale.compactName) \(shown.reading.value) · \(shown.reading.band.name)"
    }

    /// The city's band colour on the chosen scale; white while it loads.
    private func bandColor(for location: SavedLocation) -> Color {
        locationManager.store(for: location).currentAQI.map { scale.displayReading(for: $0).reading.band.color } ?? .white
    }

    private func indicatorCapsule(locations: [SavedLocation], selectedIndex: Int?) -> some View {
        HStack(spacing: DS.spacingSM) {
            ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                marker(for: location, color: bandColor(for: location), isSelected: index == selectedIndex)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
        }
        .padding(.horizontal, DS.spacingMD)
        .padding(.vertical, DS.spacingSM)
        .background(.black.opacity(0.2), in: Capsule())
        // Full-height hit area: the visible capsule is shorter than a comfortable tap.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(DS.Motion.quick, value: selectedIndex)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: DS.spacingXL) {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.3))

                Text("No places yet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Add a city, or turn on location to see the air where you are.")
                    .font(DS.Typeface.body)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    .multilineTextAlignment(.center)

                VStack(spacing: DS.spacingMD) {
                    if locationService.isDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Enable Location", systemImage: "location")
                                .frame(maxWidth: 220)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    Button {
                        showingSearch = true
                    } label: {
                        Label("Add a City", systemImage: "plus")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.selectedFill)
                }
                .padding(.top, DS.spacingSM)
            }
        }
    }

    // MARK: - Permission Banner

    private var locationPermissionBanner: some View {
        HStack(spacing: DS.spacingMD) {
            Image(systemName: "location.slash.fill")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: DS.spacingXXS) {
                Text("Location access is off")
                    .font(DS.Typeface.rowTitle)
                    .foregroundStyle(.white)
                Text("Turn it on in Settings to see the air where you are.")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }

            Spacer()

            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(DS.Typeface.captionStrong)
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(DS.spacingMD)
        .background { DS.glass(in: RoundedRectangle(cornerRadius: DS.cornerRadiusSM)) }
        .padding(.horizontal, DS.spacingLG)
    }
}

// MARK: - Views that follow the scroll

/// The shared atmosphere. Re-renders every frame of a swipe — on its own.
private struct PagerBackdrop: View {
    let locationManager: LocationManager
    let scrollState: PagerScrollState

    @State private var renderQuality = RenderQuality()
    @AppStorage(DS.reduceVisualEffectsKey) private var reduceVisualEffects = false
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let locations = locationManager.locations
        let nearestStore = scrollState.nearestLocation(in: locations).map { locationManager.store(for: $0) }

        AtmosphereBackdrop(
            layers: locations.map { location in
                let quality = locationManager.store(for: location).currentAQI
                return AtmosphereBackdrop.Layer(
                    id: location.id,
                    level: quality.map { scale.displayReading(for: $0).reading.severityLevel } ?? .good,
                    params: quality.map { AtmosphereParameters(from: $0, scale: scale) } ?? .placeholder,
                    scrollOffset: scrollState.pageOffsets[location.id] ?? 0
                )
            },
            pagePosition: scrollState.pagePosition,
            isStirred: nearestStore?.state.isLoading ?? false,
            motionEnabled: !reduceMotion && !reduceVisualEffects,
            effectsEnabled: !reduceVisualEffects,
            tier: renderQuality.tier
        )
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            renderQuality.update()
        }
    }
}

/// Glass behind the top bar, appearing as the visible page scrolls into its cards.
private struct TopBarBlur: View {
    let selectedID: UUID?
    let scrollState: PagerScrollState

    var body: some View {
        let offset = selectedID.flatMap { scrollState.pageOffsets[$0] } ?? 0
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(Double(min(1, max(0, offset / 200))))
            .ignoresSafeArea(edges: .top)
    }
}

/// Shown while the visible page re-fetches data it already had (pull to refresh,
/// relocation). The system refresh control sits under the status bar in this
/// full-bleed layout and can't be seen, so the pager draws its own, in the AQI colour.
private struct PagerRefreshIndicator: View {
    let locationManager: LocationManager
    let scrollState: PagerScrollState
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA

    var body: some View {
        let store = scrollState.nearestLocation(in: locationManager.locations).map { locationManager.store(for: $0) }
        let isRefreshing = store.map { $0.state.isLoading && $0.currentAQI != nil } ?? false

        ZStack {
            if isRefreshing {
                ProgressView()
                    .tint(store?.currentAQI.map { scale.displayReading(for: $0).reading.band.color } ?? .white)
                    .padding(DS.spacingMD)
                    .background { DS.glass(in: Circle()) }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel("Refreshing")
            }
        }
        .animation(DS.Motion.quick, value: isRefreshing)
    }
}
