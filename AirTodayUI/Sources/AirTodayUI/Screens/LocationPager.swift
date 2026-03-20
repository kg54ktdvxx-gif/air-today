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
                    Color.black.ignoresSafeArea()
                } else {
                    pagerContent
                }

                // Top bar: page dots + settings
                VStack {
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
                    .opacity(Double(max(0, 1 - scrollOffset / 100)))
                    .animation(.easeOut(duration: 0.3), value: scrollOffset)
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
        HStack(spacing: 6) {
            ForEach(locationManager.locations) { location in
                let isSelected = locationManager.selectedLocationID == location.id
                let levelColor = locationManager.store(for: location).currentAQI?.level.color ?? .white

                if isSelected {
                    // Selected: pill with dot + location name
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle()
                                    .stroke(levelColor, lineWidth: 2)
                                    .frame(width: 14, height: 14)
                            }

                        Text(location.isCurrentLocation ? "My Location" : location.name)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    // Unselected: small dot
                    Circle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 5)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.2), in: Capsule())
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: locationManager.selectedLocationID)
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
