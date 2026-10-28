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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(locationManager: LocationManager, locationService: LocationService) {
        self.locationManager = locationManager
        self.locationService = locationService
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if locationManager.locations.isEmpty {
                    Color.black.ignoresSafeArea()
                } else {
                    PagerBackdrop(locationManager: locationManager, scrollState: scrollState)
                }

                // One layout for every page, from the space they share (and the fold, if any).
                GeometryReader { proxy in
                    let layout = PlaceLayout.resolve(in: proxy, sizeClass: horizontalSizeClass)
                    ZStack {
                        if locationManager.locations.isEmpty {
                            emptyStateView
                                .within(.hero, of: layout)
                        } else {
                            PagerScrim(locations: locationManager.locations, scrollState: scrollState, layout: layout, size: proxy.size)
                            pagerContent(layout)
                        }

                        VStack(spacing: 0) {
                            PagerRefreshIndicator(locationManager: locationManager, scrollState: scrollState)
                                // Below the page's place name.
                                .padding(.top, DS.spacingHuge)
                            Spacer()
                        }
                        .within(.hero, of: layout)

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
                            .within(.cards, of: layout)
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
                            .padding(.top, DS.spacingSM)
                            .within(.cards, of: layout)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .modifier(PagerBars(topBar: topBar, cityMenu: cityMenu(inVerticalBar: true)))
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .settings:
                    SettingsScreen(locationManager: locationManager)
                case .privacyPolicy:
                    PrivacyPolicyView()
                }
            }
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

    private func pagerContent(_ layout: PlaceLayout) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(locationManager.locations) { location in
                    let store = locationManager.store(for: location)
                    LocationPage(
                        store: store,
                        location: location,
                        layout: layout,
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
        // A scroll view draws into the safe area, so beside a vertical status bar
        // (iPhone Duo) the next page would show under it. Clip at the sides only:
        // pages still scroll beneath the top bar and run to the bottom edge.
        .mask {
            Rectangle().ignoresSafeArea(edges: .vertical)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            // Pages are as wide as the bounds (inside the insets), not the whole scroll view,
            // which also spans the space under a side status bar.
            (geo.contentOffset.x + geo.contentInsets.leading) / max(geo.bounds.width, 1)
        } action: { _, position in
            scrollState.pagePosition = position
        }
    }

    /// City dots (and menu) and settings, across the top.
    private var topBar: some View {
        HStack {
            cityMenu(inVerticalBar: false)
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
    ///
    /// In a vertical bar (iPhone Duo) the label is one symbol, as Apple advises for those
    /// bars: the showing place's (the bar draws it in its own colour).
    private func cityMenu(inVerticalBar: Bool) -> some View {
        let locations = locationManager.locations
        let selectedIndex = locations.firstIndex { $0.id == locationManager.selectedLocationID }
        let selectedName = selectedIndex.map { shortName(locations[$0]) } ?? ""
        let spokenValue = selectedIndex.map { "\(selectedName), \($0 + 1) of \(locations.count)" } ?? ""

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
                // A section, not a Divider: in a toolbar's menu (iPhone Duo's vertical bar) an
                // item after a Divider never ran its action (checked on the simulator).
                Section {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Add City…", systemImage: "plus")
                    }
                }
            }
        } label: {
            if inVerticalBar {
                let isCurrentLocation = selectedIndex.map { locations[$0].isCurrentLocation } ?? false
                Label("Cities", systemImage: isCurrentLocation ? "location.fill" : "mappin.and.ellipse")
            } else {
                indicatorCapsule(locations: locations, selectedIndex: selectedIndex)
            }
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier("cityPicker")
        // A bar builds its own button from the menu and keeps its label but not its value
        // (checked on the Duo simulator), so there the place showing goes in the label.
        .accessibilityLabel(inVerticalBar && !spokenValue.isEmpty ? "Cities, \(spokenValue)" : "Cities")
        .accessibilityValue(spokenValue)
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

// MARK: - Bars

/// The city menu and settings: a bar across the top, or on iPhone Duo, where the system
/// puts its bars down the side, items in that vertical bar below the status bar. Apple's
/// guidance for custom bars is to follow `toolbarVerticalEdge`.
private struct PagerBars<TopBar: View, CityMenu: View>: ViewModifier {
    let topBar: TopBar
    /// The city menu laid out for a vertical bar.
    let cityMenu: CityMenu

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(VerticalAwareBars(topBar: topBar, cityMenu: cityMenu))
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalAwareBars<TopBar: View, CityMenu: View>: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    let topBar: TopBar
    let cityMenu: CityMenu

    func body(content: Content) -> some View {
        // One structure for both, so a change of edge (rotating the inner display)
        // re-places the controls without rebuilding the pages under them.
        let isVertical = verticalEdge != nil
        content
            // The bar is a safe-area inset, so pages start below it and scroll beneath it.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !isVertical { topBar }
            }
            .toolbar {
                if isVertical {
                    // Navigation at the top of the bar, then the action.
                    ToolbarItem(placement: .topBarLeading) { cityMenu }
                        .axisBehavior(.verticalPreferred)
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: AppRoute.settings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .toolbar(isVertical ? .automatic : .hidden, for: .navigationBar)
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

/// Quiet darkening where the hero's text sits — behind the place name at the top and
/// the verdict and number in the middle — so the text needs only a soft shadow. Fades
/// as the visible page scrolls into its cards, blended across a swipe between pages.
private struct PagerScrim: View {
    let locations: [SavedLocation]
    let scrollState: PagerScrollState
    let layout: PlaceLayout
    /// The space the pages fill, inside the safe area.
    let size: CGSize

    private static let radius: CGFloat = 360

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch layout {
            case .column:
                radial
                    .ignoresSafeArea()
            case .panes(let heroWidth, _):
                // Behind the hero pane, not the middle of the screen (which is the fold).
                radial
                    .frame(width: Self.radius * 2, height: Self.radius * 2)
                    .position(x: heroWidth / 2, y: size.height / 2)
            }
        }
        // Beside the cards the hero never scrolls away, so neither does its scrim.
        .opacity(isColumn ? opacity : 1)
        .allowsHitTesting(false)
    }

    private var radial: some View {
        RadialGradient(colors: [.black.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: Self.radius)
    }

    private var isColumn: Bool {
        if case .column = layout { true } else { false }
    }

    private var opacity: Double {
        guard !locations.isEmpty else { return 1 }
        let position = min(max(scrollState.pagePosition, 0), CGFloat(locations.count - 1))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, locations.count - 1)
        let progress = position - CGFloat(lower)
        return Double(fade(locations[lower]) * (1 - progress) + fade(locations[upper]) * progress)
    }

    private func fade(_ location: SavedLocation) -> CGFloat {
        let offset = scrollState.pageOffsets[location.id] ?? 0
        return 1 - min(1, max(0, offset / LocationPage.heroFadeDistance))
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
/// relocation), in the AQI colour. While a page is pulled down the system's spinner
/// shows above it; once it settles the system's is hidden behind the place name (the
/// page doesn't stay held open for it), so this one takes over.
private struct PagerRefreshIndicator: View {
    let locationManager: LocationManager
    let scrollState: PagerScrollState
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA

    var body: some View {
        let location = scrollState.nearestLocation(in: locationManager.locations)
        let store = location.map { locationManager.store(for: $0) }
        let isPulledDown = (location.flatMap { scrollState.pageOffsets[$0.id] } ?? 0) < -1
        let isRefreshing = !isPulledDown && (store.map { $0.state.isLoading && $0.currentAQI != nil } ?? false)

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
