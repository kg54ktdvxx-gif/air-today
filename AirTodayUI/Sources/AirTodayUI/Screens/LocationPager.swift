import SwiftUI
import AirTodayCore

/// Horizontal paged navigation across saved locations.
/// Each page is a full-width LocationPage with its own atmosphere + data.
public struct LocationPager: View {
    @Bindable var locationManager: LocationManager
    let locationService: LocationService
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var scrollOffset: CGFloat = 0

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
                    pagerContent
                }

                // Top bar: page dots + settings
                VStack(spacing: 0) {
                    HStack {
                        pageIndicator
                        Spacer()
                        NavigationLink(value: "settings") {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(8)
                                .background(.black.opacity(0.25), in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }
                    }
                    .padding(.horizontal, DS.spacingLG)
                    .padding(.vertical, 8)
                    .background {
                        // Glass blur appears as user scrolls into detail cards
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(Double(min(1, max(0, scrollOffset / 200))))
                            .ignoresSafeArea(edges: .top)
                    }
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
            .navigationDestination(for: String.self) { destination in
                if destination == "settings" {
                    SettingsScreen(locationManager: locationManager)
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await locationManager.refreshIfNeeded()
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
                    LocationPage(store: store, location: location) {
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
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 2) {
            ForEach(locationManager.locations) { location in
                let isSelected = locationManager.selectedLocationID == location.id
                let levelColor = locationManager.store(for: location).currentAQI?.level.color ?? .white
                let name = location.isCurrentLocation ? "My Location" : location.name
                    .components(separatedBy: ",").first ?? location.name

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        locationManager.selectedLocationID = location.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? levelColor : .white.opacity(0.4))
                            .frame(width: 7, height: 7)

                        if isSelected {
                            Text(name)
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, isSelected ? 10 : 6)
                    .padding(.vertical, 5)
                    .background(isSelected ? .black.opacity(0.35) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.2), in: Capsule())
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: locationManager.selectedLocationID)
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
        .sheet(isPresented: $showingSearch) {
            LocationSearchView(locationManager: locationManager)
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
