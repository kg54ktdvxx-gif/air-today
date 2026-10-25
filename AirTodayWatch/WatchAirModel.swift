import Foundation
import CoreLocation
import WidgetKit
import AirTodayCore

/// The Watch app's view of the air where you are.
///
/// Readings come from three places, newest wins: the Watch's own fetch (using its
/// location when allowed), the iPhone via `WatchSync`, and the shared cache the
/// complications also read.
@MainActor
@Observable
final class WatchAirModel {
    private(set) var quality: AirQuality?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let locationService = LocationService()
    private let service = AirQualityService(token: AppConstants.waqiToken)

    init() {
        quality = SharedDataStore.load()
        WatchSync.shared.onReceive = { [weak self] in
            Task { @MainActor in self?.reloadFromStore() }
        }
        WatchSync.shared.activate()
    }

    func reloadFromStore() {
        if let stored = SharedDataStore.load(),
           quality.map({ stored.timestamp >= $0.timestamp }) ?? true {
            quality = stored
        }
    }

    /// Refreshes when the cache is old or missing; `force` always fetches.
    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, quality != nil, SharedDataStore.isCacheValid { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let here = locationService.coordinate.map(Coordinate.init) {
                let fresh = try await service.fetchCurrent(latitude: here.latitude, longitude: here.longitude)
                SharedDataStore.save(fresh, queryCoordinate: here)
                quality = fresh
            } else {
                // No fix on the Watch: use where the iPhone last checked (or WAQI's IP lookup).
                quality = try await CurrentAirRefresher.refresh(service: service)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestLocationIfAllowed() {
        switch locationService.authorizationStatus {
        case .notDetermined: locationService.requestPermission()
        case .authorizedWhenInUse, .authorizedAlways: locationService.requestLocation()
        default: break
        }
    }
}
