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
    private let reader = AirReadingService()

    init() {
        quality = SharedDataStore.load()
        WatchSync.shared.onReceive = { [weak self] in
            Task { @MainActor in self?.reloadFromStore() }
        }
        WatchSync.shared.activate()
    }

    /// The store holds whichever reading was fetched last, here or on the iPhone.
    func reloadFromStore() {
        if let stored = SharedDataStore.load() {
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
                var fresh = try await reader.reading(at: here)
                fresh.placeName = SharedDataStore.cachedPlaceName(near: here)
                SharedDataStore.save(fresh, queryCoordinate: here)
                quality = fresh
                if fresh.placeName == nil {
                    Task { await fillInPlaceName(for: here) }
                }
            } else {
                // No fix on the Watch: use where the iPhone last checked (or WAQI's IP lookup).
                quality = try await CurrentAirRefresher.refresh(reader: reader)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The town name arrives after the reading; it doesn't hold the reading up.
    private func fillInPlaceName(for coordinate: Coordinate) async {
        guard let name = await PlaceNameResolver.name(for: coordinate),
              var stored = SharedDataStore.load(),
              SharedDataStore.queryCoordinate() == coordinate
        else { return }
        stored.placeName = name
        SharedDataStore.save(stored, queryCoordinate: coordinate, fetchedAt: SharedDataStore.lastUpdated() ?? Date())
        quality = stored
        WidgetCenter.shared.reloadAllTimelines()
    }

    func requestLocationIfAllowed() {
        switch locationService.authorizationStatus {
        case .notDetermined: locationService.requestPermission()
        case .authorizedWhenInUse, .authorizedAlways: locationService.requestLocation()
        default: break
        }
    }
}
