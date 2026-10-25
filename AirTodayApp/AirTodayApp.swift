import SwiftUI
import AirTodayCore
import AirTodayUI
import BackgroundTasks
import UserNotifications
import WidgetKit

@main
struct AirTodayApp: App {
    @State private var locationManager: LocationManager
    @State private var locationService: LocationService
    @State private var liveActivityManager = LiveActivityManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    private static let backgroundTaskID = "com.airtoday.app.refresh"
    private let notificationRouter: NotificationRouter

    init() {
        Preferences.migrateToSharedDefaults()
        #if DEBUG
        Self.applyUITestSeedIfRequested()
        #endif

        let location = LocationService()
        let service = AirQualityService(token: AppConstants.waqiToken)
        let manager = LocationManager(service: service, locationService: location)
        _locationService = State(initialValue: location)
        _locationManager = State(initialValue: manager)

        notificationRouter = NotificationRouter(locationManager: manager)
        UNUserNotificationCenter.current().delegate = notificationRouter
        WatchSync.shared.activate()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskID,
            using: nil
        ) { task in
            Self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    LocationPager(locationManager: locationManager, locationService: locationService)
                } else {
                    OnboardingView(locationService: locationService) {
                        withAnimation(DS.Motion.standard) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                // Handle widget deep link: airtoday://open
                guard url.scheme == "airtoday" else { return }
                // Ensure onboarding is complete so the pager is visible
                if !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                }
                // Trigger a refresh when opening from widget
                Task {
                    await locationManager.refreshIfNeeded()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Self.scheduleBackgroundRefresh()
                // Carries any Settings changes (scale, health, units) to the Watch.
                WatchSync.shared.push()
            case .active:
                // CLLocationManager only reports once per request; ask again so a
                // device that moved while backgrounded gets its new location's air.
                if locationService.hasPermission {
                    locationService.requestLocation()
                }
                Task {
                    await locationManager.refreshIfNeeded()
                    WidgetCenter.shared.reloadAllTimelines()
                    if let store = locationManager.selectedStore,
                       let quality = store.currentAQI {
                        liveActivityManager.update(with: quality)
                    }
                }
            default:
                break
            }
        }
    }

    #if DEBUG
    /// `-uitest-seed` (UI tests only): skip onboarding and start from three known
    /// reporting stations, so tests don't depend on what's on the simulator.
    private static func applyUITestSeedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed") else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        // XCTest waits for the app to go idle before every action; the drifting
        // particles, haze and pulsing hint never stop, so it stalls for ~20 s each time.
        UserDefaults.standard.set(true, forKey: DS.reduceVisualEffectsKey)
        // Alert banners cover the top bar, where the tests tap.
        for key in [
            NotificationPreferences.Key.dailyVerdict,
            NotificationPreferences.Key.thresholdAlerts,
            NotificationPreferences.Key.bestWindow,
            NotificationPreferences.Key.spikeAlerts,
        ] {
            UserDefaults.shared.set(false, forKey: key)
        }
        SavedLocationStore.save([
            SavedLocation(name: "Paris", coordinate: Coordinate(latitude: 48.856614, longitude: 2.3522219), stationID: 5722),
            SavedLocation(name: "Tashkent Chilanzar, Uzbekistan", coordinate: Coordinate(latitude: 41.31086, longitude: 69.24074), stationID: 14722),
            SavedLocation(name: "Sydney East, Australia", coordinate: Coordinate(latitude: -33.872468, longitude: 151.213337), stationID: 12417),
        ])
    }
    #endif

    // MARK: - Background Refresh

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.backgroundRefreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Refreshes every location so alerts can fire for saved cities too, then
    /// updates the widget cache and re-plans the daily notifications.
    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let fetchTask = Task {
            let service = AirQualityService(token: AppConstants.waqiToken)
            var readings: [(location: SavedLocation, quality: AirQuality)] = []

            // Background tasks can't get a fresh fix with when-in-use permission,
            // so reuse the coordinate the last foreground reading was requested for.
            let queryCoordinate = SharedDataStore.queryCoordinate()
            let current: AirQuality? = if let queryCoordinate {
                try? await service.fetchCurrent(latitude: queryCoordinate.latitude, longitude: queryCoordinate.longitude)
            } else {
                try? await service.fetchCurrent(city: "here")
            }
            if let current {
                SharedDataStore.save(current, queryCoordinate: queryCoordinate)
                let here = SavedLocation(
                    name: "Current Location",
                    coordinate: queryCoordinate ?? current.station.coordinate,
                    isCurrentLocation: true
                )
                readings.append((here, current))
            }

            for location in SavedLocationStore.load() {
                try Task.checkCancellation()
                let quality: AirQuality? = if let stationID = location.stationID {
                    try? await service.fetchStation(id: stationID)
                } else {
                    try? await service.fetchCurrent(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                }
                // Same rule as the foreground: a far-away station isn't this city's air.
                if let quality,
                   location.stationID != nil
                    || quality.station.coordinate.distance(to: location.coordinate) <= LocationManager.legacyStationMaxDistance {
                    readings.append((location, quality))
                }
            }

            await AlertCoordinator.process(readings)
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.push()
            return !readings.isEmpty
        }

        task.expirationHandler = {
            fetchTask.cancel()
        }

        Task {
            let succeeded = (try? await fetchTask.value) ?? false
            task.setTaskCompleted(success: succeeded)
        }
    }
}

/// Opens the right page when a notification is tapped, and shows alerts that
/// arrive while the app is open.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    private let locationManager: LocationManager

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let key = response.notification.request.content.userInfo[AlertCoordinator.locationKeyInfo] as? String
        await MainActor.run {
            guard let key,
                  let location = locationManager.locations.first(where: { AlertCoordinator.key(for: $0) == key })
            else { return }
            locationManager.selectedLocationID = location.id
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
