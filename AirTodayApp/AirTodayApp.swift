import SwiftUI
import AirTodayCore
import AirTodayUI
import BackgroundTasks
import WidgetKit

@main
struct AirTodayApp: App {
    @State private var locationManager: LocationManager
    @State private var locationService: LocationService
    @State private var liveActivityManager = LiveActivityManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    private static let backgroundTaskID = "com.airtoday.app.refresh"

    init() {
        let location = LocationService()
        let service = AirQualityService(token: AppConstants.waqiToken)
        _locationService = State(initialValue: location)
        _locationManager = State(initialValue: LocationManager(service: service, locationService: location))

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
                        withAnimation {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Self.scheduleBackgroundRefresh()
            case .active:
                Task {
                    await locationManager.refreshIfNeeded()
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

    // MARK: - Background Refresh

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.backgroundRefreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let fetchTask = Task {
            let service = AirQualityService(token: AppConstants.waqiToken)

            let quality: AirQuality
            if let cached = SharedDataStore.load() {
                quality = try await service.fetchCurrent(
                    latitude: cached.station.coordinate.latitude,
                    longitude: cached.station.coordinate.longitude
                )
            } else {
                quality = try await service.fetchCurrent(city: "here")
            }

            SharedDataStore.save(quality)
            WidgetCenter.shared.reloadAllTimelines()
        }

        task.expirationHandler = {
            fetchTask.cancel()
        }

        Task {
            do {
                _ = try await fetchTask.value
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }
}
