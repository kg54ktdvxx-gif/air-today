import SwiftUI
import AirTodayCore

/// Horizontal paged navigation across saved locations.
/// One shared atmosphere sits behind full-width LocationPages, so the scene
/// carries across swipes instead of cutting from page to page.
public struct LocationPager: View {
    @Bindable var locationManager: LocationManager
    let locationService: LocationService
    @State private var showingSearch = false
    /// Each page's vertical scroll offset, keyed by location.
    @State private var pageOffsets: [UUID: CGFloat] = [:]
    /// Fractional horizontal page index (1.5 = halfway between pages 1 and 2).
    @State private var pagePosition: CGFloat = 0
    @State private var renderQuality = RenderQuality()
    @AppStorage("parallax_enabled") private var parallaxEnabled = true
    @AppStorage(DS.reduceVisualEffectsKey) private var reduceVisualEffects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    backdrop
                    pagerContent
                }

                // Top bar: page dots + settings
                VStack(spacing: 0) {
                    HStack {
                        pageIndicator
                        Spacer()
                        if locationManager.canAddLocation {
                            Button {
                                showingSearch = true
                            } label: {
                                topBarIcon("plus")
                            }
                            .accessibilityLabel("Add City")
                        }
                        NavigationLink(value: AppRoute.settings) {
                            topBarIcon("gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, DS.spacingLG)
                    .padding(.vertical, 8)
                    .background {
                        // Glass blur appears as user scrolls into detail cards
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(Double(min(1, max(0, selectedPageOffset / 200))))
                            .ignoresSafeArea(edges: .top)
                    }

                    refreshIndicator
                    Spacer()
                }

                // Location permission banner
                if locationService.isDenied {
                    VStack {
                        locationPermissionBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .padding(.top, 50)
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
            .onPreferenceChange(PageScrollOffsetsKey.self) { pageOffsets = $0 }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                renderQuality.update()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSearch) {
                LocationSearchView(locationManager: locationManager)
            }
            .task {
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

    // MARK: - Atmosphere

    private var selectedPageOffset: CGFloat {
        locationManager.selectedLocationID.flatMap { pageOffsets[$0] } ?? 0
    }

    /// The page closest to the centre of the screen, which owns haze and particles.
    private var nearestLocation: SavedLocation? {
        let locations = locationManager.locations
        guard !locations.isEmpty else { return nil }
        let index = min(max(Int(pagePosition.rounded()), 0), locations.count - 1)
        return locations[index]
    }

    private var backdrop: some View {
        let nearestStore = nearestLocation.map { locationManager.store(for: $0) }
        return AtmosphereBackdrop(
            layers: locationManager.locations.map { location in
                AtmosphereBackdrop.Layer(
                    id: location.id,
                    level: locationManager.store(for: location).currentAQI?.level ?? .good,
                    scrollOffset: pageOffsets[location.id] ?? 0
                )
            },
            pagePosition: pagePosition,
            params: nearestStore?.currentAQI.map { AtmosphereParameters(from: $0) } ?? .placeholder,
            isStirred: nearestStore?.state.isLoading ?? false,
            parallaxEnabled: parallaxEnabled,
            motionEnabled: !reduceMotion && !reduceVisualEffects,
            effectsEnabled: !reduceVisualEffects,
            tier: renderQuality.tier
        )
    }

    /// Shown while the visible page re-fetches data it already had (pull to refresh,
    /// relocation). The system refresh control sits under the status bar in this
    /// full-bleed layout and can't be seen, so the pager draws its own, in the AQI colour.
    @ViewBuilder
    private var refreshIndicator: some View {
        let store = nearestLocation.map { locationManager.store(for: $0) }
        let isRefreshing = store.map { $0.state.isLoading && $0.currentAQI != nil } ?? false

        ZStack {
            if isRefreshing {
                ProgressView()
                    .tint(store?.currentAQI?.level.color ?? .white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel("Refreshing")
            }
        }
        .animation(DS.Motion.quick, value: isRefreshing)
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
                        userCoordinate: location.isCurrentLocation
                            ? locationService.coordinate.map(Coordinate.init)
                            : nil
                    ) {
                        await locationManager.refresh(location: location)
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(location.id)
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $locationManager.selectedLocationID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.x / max(geo.containerSize.width, 1)
        } action: { _, position in
            pagePosition = position
        }
    }

    private func topBarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 20, height: 20)
            .padding(8)
            .background(.black.opacity(0.25), in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 4)
    }

    // MARK: - Page Indicator

    private func shortName(_ location: SavedLocation) -> String {
        location.isCurrentLocation
            ? "My Location"
            : location.name.components(separatedBy: ",").first ?? location.name
    }

    private var pageIndicator: some View {
        let locations = locationManager.locations
        return HStack(spacing: 2) {
            ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                let isSelected = locationManager.selectedLocationID == location.id
                let levelColor = locationManager.store(for: location).currentAQI?.level.color ?? .white
                let name = shortName(location)
                // Position only means something once there's more than one place.
                let position = locations.count > 1 ? " \(index + 1)/\(locations.count)" : ""

                Button {
                    withAnimation(DS.Motion.quick) {
                        locationManager.selectedLocationID = location.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? levelColor : .white.opacity(0.4))
                            .frame(width: 7, height: 7)

                        if isSelected {
                            HStack(spacing: 0) {
                                Text(name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(position)
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                                    .fixedSize()
                            }
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, isSelected ? 10 : 6)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            // The page's AQI colour, quietly, behind its name.
                            Capsule()
                                .fill(.black.opacity(0.35))
                                .overlay(Capsule().fill(levelColor.opacity(0.22)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), location \(index + 1) of \(locations.count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.2), in: Capsule())
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .animation(DS.Motion.quick, value: locationManager.selectedLocationID)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.3))

                Text("No Locations")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Add a city or enable location access\nto see air quality data")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
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
                        .tint(.blue)
                    }

                    Button {
                        showingSearch = true
                    } label: {
                        Label("Add a City", systemImage: "plus")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Permission Banner

    private var locationPermissionBanner: some View {
        HStack(spacing: DS.spacingMD) {
            Image(systemName: "location.slash.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Location Access Disabled")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text("Enable location for accurate local air quality")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }

            Spacer()

            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(DS.spacingMD)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.cornerRadiusSM))
        .padding(.horizontal, DS.spacingLG)
    }
}
