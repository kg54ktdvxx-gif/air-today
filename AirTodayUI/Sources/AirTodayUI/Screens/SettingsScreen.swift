import SwiftUI
import AirTodayCore

/// Settings screen — locations, preferences, about.
public struct SettingsScreen: View {
    let locationManager: LocationManager
    @State private var showingSearch = false
    @State private var showingClearConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var cacheCleared = false
    @AppStorage("parallax_enabled") private var parallaxEnabled = true
    @AppStorage("temp_unit") private var temperatureUnit = "celsius"

    public init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    public var body: some View {
        List {
            Section("Locations") {
                ForEach(locationManager.locations) { location in
                    HStack {
                        if location.isCurrentLocation {
                            Label("Current Location", systemImage: "location.fill")
                        } else {
                            Label(location.name, systemImage: "mappin")
                        }

                        Spacer()

                        if let quality = locationManager.store(for: location).currentAQI {
                            Text("\(quality.aqi)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(quality.level.color)
                        }
                    }
                }
                .onDelete { offsets in
                    pendingDeleteOffsets = offsets
                    showingDeleteConfirmation = true
                }

                if locationManager.locations.count < 6 {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Add Location", systemImage: "plus")
                    }
                }
            }

            Section("Display") {
                Picker(selection: $temperatureUnit) {
                    Text("Celsius").tag("celsius")
                    Text("Fahrenheit").tag("fahrenheit")
                } label: {
                    Label("Temperature Unit", systemImage: "thermometer.medium")
                }

                Toggle(isOn: $parallaxEnabled) {
                    Label("Parallax Effect", systemImage: "move.3d")
                }
            }

            Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.white.opacity(DS.opacityTertiary))
                }

                NavigationLink(value: "privacy") {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: URL(string: "https://waqi.info")!) {
                    Label("World Air Quality Index", systemImage: "globe")
                }

                Link(destination: URL(string: "mailto:busiest-21.qualm@icloud.com")!) {
                    Label("Contact & Feedback", systemImage: "envelope")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label(cacheCleared ? "Cache Cleared" : "Clear Cache", systemImage: cacheCleared ? "checkmark" : "trash")
                }
                .disabled(cacheCleared)
            } footer: {
                if let lastUpdated = SharedDataStore.lastUpdated() {
                    Text("Last synced \(lastUpdated, style: .relative) ago")
                }
            }

            Section("Data") {
                if let store = locationManager.selectedStore,
                   let quality = store.currentAQI {
                    AttributionView(attributions: quality.attribution)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: String.self) { destination in
            if destination == "privacy" {
                PrivacyPolicyView()
            }
        }
        .sheet(isPresented: $showingSearch) {
            LocationSearchView(locationManager: locationManager)
        }
        .confirmationDialog("Clear Cache", isPresented: $showingClearConfirmation) {
            Button("Clear Cache", role: .destructive) {
                clearCache()
                withAnimation { cacheCleared = true }
            }
        } message: {
            Text("This will remove cached air quality data. Fresh data will be fetched on next refresh.")
        }
        .confirmationDialog("Remove Location", isPresented: $showingDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    locationManager.removeLocation(at: offsets)
                    pendingDeleteOffsets = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteOffsets = nil
            }
        } message: {
            Text("This location will be removed from your list.")
        }
    }

    private func clearCache() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        defaults.removeObject(forKey: "cached_air_quality")
        defaults.removeObject(forKey: "cached_timestamp")
    }
}
