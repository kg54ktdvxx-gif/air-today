import Foundation
import CoreLocation

@MainActor
@Observable
public final class LocationService: NSObject {
    public private(set) var coordinate: CLLocationCoordinate2D?
    public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public private(set) var error: String?

    private let manager = CLLocationManager()

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    public func requestLocation() {
        error = nil
        manager.requestLocation()
    }

    public var hasPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    public var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

extension LocationService: CLLocationManagerDelegate {
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.coordinate = location?.coordinate
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error.localizedDescription
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let shouldRequest = status == .authorizedWhenInUse || status == .authorizedAlways
        Task { @MainActor in
            self.authorizationStatus = status
            if shouldRequest {
                self.manager.requestLocation()
            }
        }
    }
}
