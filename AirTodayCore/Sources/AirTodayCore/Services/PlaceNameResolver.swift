import CoreLocation
import MapKit

/// The town name for a coordinate, looked up on the device through Apple Maps.
/// Nil when offline or the lookup finds nothing — callers fall back to a generic name.
@MainActor
public enum PlaceNameResolver {
    public static func name(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, watchOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first
            else { return nil }
            return item.addressRepresentations?.cityName ?? item.name
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name
        }
    }
}
