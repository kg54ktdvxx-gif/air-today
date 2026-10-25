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
    @AppStorage(DS.reduceVisualEffectsKey) private var reduceVisualEffects = false
    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA

    @AppStorage(NotificationPreferences.Key.dailyVerdict, store: .shared) private var dailyVerdict = false
    @AppStorage(NotificationPreferences.Key.dailyVerdictMinutes, store: .shared) private var dailyVerdictMinutes = NotificationPreferences().dailyVerdictMinutes
    @AppStorage(NotificationPreferences.Key.thresholdAlerts, store: .shared) private var thresholdAlerts = false
    @AppStorage(NotificationPreferences.Key.thresholdLevel, store: .shared) private var thresholdLevel: AQILevel = .sensitive
    @AppStorage(NotificationPreferences.Key.bestWindow, store: .shared) private var bestWindow = false
    @AppStorage(NotificationPreferences.Key.spikeAlerts, store: .shared) private var spikeAlerts = false
    @State private var notificationsDenied = false
    @AppStorage(AppConstants.temperatureUnitKey, store: .shared)
    private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false

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

                if locationManager.canAddLocation {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Add Location", systemImage: "plus")
                    }
                }
            }

            Section {
                Toggle(isOn: $hasRespiratoryCondition) {
                    Label("Asthma or respiratory condition", systemImage: "lungs.fill")
                }
                Toggle(isOn: $isOzoneSensitive) {
                    Label("Sensitive to ozone", systemImage: "sun.haze.fill")
                }
                Toggle(isOn: $hasChildren) {
                    Label("Children in household", systemImage: "figure.and.child.holdinghands")
                }
            } header: {
                Text("Your Health")
            } footer: {
                Text("Tailors verdicts and activity advice. Stays on this device.")
            }

            notificationsSection

            Section {
                Picker(selection: $scale) {
                    ForEach(AQIScale.allCases, id: \.self) { scale in
                        Text("\(scale.shortName) (\(scale.rangeDescription))").tag(scale)
                    }
                } label: {
                    Label("Scale", systemImage: "gauge.with.dots.needle.33percent")
                }
            } header: {
                Text("Air Quality Scale")
            } footer: {
                Text("World Air Quality Index stations report on the US EPA scale. EU CAQI and UK DAQI numbers are worked out from those readings, so they're close estimates rather than official figures. Verdicts and activity advice always follow the US EPA levels.")
            }

            Section {
                Picker(selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                } label: {
                    Label("Temperature Unit", systemImage: "thermometer.medium")
                }

                Toggle(isOn: $parallaxEnabled) {
                    Label("Parallax Effect", systemImage: "move.3d")
                }
                .disabled(reduceVisualEffects)

                Toggle(isOn: $reduceVisualEffects) {
                    Label("Reduce Visual Effects", systemImage: "sparkles")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Reduce Visual Effects turns off the haze, drifting particles and parallax — easier on the battery and on the eyes. Reduce Motion in iOS Settings is respected automatically.")
            }

            Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.white.opacity(DS.opacityTertiary))
                }

                NavigationLink(value: AppRoute.privacyPolicy) {
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
        .sheet(isPresented: $showingSearch) {
            LocationSearchView(locationManager: locationManager)
        }
        .confirmationDialog("Clear Cache", isPresented: $showingClearConfirmation) {
            Button("Clear Cache", role: .destructive) {
                clearCache()
                withAnimation(DS.Motion.quick) { cacheCleared = true }
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

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $dailyVerdict) {
                Label("Daily verdict", systemImage: "sun.horizon")
            }
            if dailyVerdict {
                DatePicker("Time", selection: dailyVerdictTime, displayedComponents: .hourAndMinute)
            }

            Toggle(isOn: $thresholdAlerts) {
                Label("When air gets worse", systemImage: "exclamationmark.triangle")
            }
            if thresholdAlerts {
                Picker("Alert from", selection: $thresholdLevel) {
                    ForEach([AQILevel.moderate, .sensitive, .unhealthy, .veryUnhealthy], id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
            }

            Toggle(isOn: $bestWindow) {
                Label("Best time to go out", systemImage: "clock.badge.checkmark")
            }

            Toggle(isOn: $spikeAlerts) {
                Label("Sudden spikes", systemImage: "flame")
            }
        } header: {
            Text("Notifications")
        } footer: {
            if notificationsDenied {
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text("Notifications are turned off for Air Today in iOS Settings.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else {
                Text("Alerts cover every saved location. iOS decides how often Air Today can check in the background, so they can arrive a little late. The daily verdict and best time use today's forecast where you are.")
            }
        }
        .onChange(of: [dailyVerdict, thresholdAlerts, bestWindow, spikeAlerts]) { old, new in
            let turnedOn = zip(old, new).contains { !$0 && $1 }
            Task {
                if turnedOn, !(await NotificationScheduler.requestAuthorization()) {
                    notificationsDenied = await NotificationScheduler.isDenied()
                }
                await AlertCoordinator.preferencesChanged()
            }
        }
        .onChange(of: dailyVerdictMinutes) {
            Task { await AlertCoordinator.preferencesChanged() }
        }
        .task {
            notificationsDenied = await NotificationScheduler.isDenied()
        }
    }

    /// The daily verdict time as a Date for the picker, stored as minutes after midnight.
    private var dailyVerdictTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: dailyVerdictMinutes / 60, minute: dailyVerdictMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            dailyVerdictMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
        }
    }

    private func clearCache() {
        SharedDataStore.clear()
    }
}
