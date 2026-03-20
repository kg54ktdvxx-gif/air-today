import SwiftUI
import MapKit
import AirTodayCore

/// Inline MapKit card showing nearby stations with colored AQI pins.
public struct NearbyStationsCard: View {
    let stations: [MapStation]
    let userCoordinate: Coordinate?
    @State private var showingFullMap = false

    public init(stations: [MapStation], userCoordinate: Coordinate?) {
        self.stations = stations
        self.userCoordinate = userCoordinate
    }

    private var mapCenter: CLLocationCoordinate2D {
        if let coord = userCoordinate {
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
        guard let first = stations.first else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nearby Stations")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    showingFullMap = true
                } label: {
                    HStack(spacing: DS.spacingXS) {
                        Text("Explore")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
                }
            }
            .padding(.horizontal, DS.spacingLG)
            .padding(.top, DS.cardHeaderTop)
            .padding(.bottom, DS.cardHeaderBottom)

            Map {
                ForEach(stations) { station in
                    Annotation(
                        station.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.coordinate.latitude,
                            longitude: station.coordinate.longitude
                        )
                    ) {
                        stationPin(station)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadiusSM))
            .padding(.horizontal, DS.spacingLG)
            .padding(.bottom, DS.spacingMD)
            .allowsHitTesting(false)
        }
        .background { DS.cardBackground }
        .fullScreenCover(isPresented: $showingFullMap) {
            MapScreen(stations: stations, center: mapCenter)
        }
    }

    private func stationPin(_ station: MapStation) -> some View {
        VStack(spacing: 2) {
            if let aqi = station.aqi {
                Text("\(aqi)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.spacingXS + 2)
                    .padding(.vertical, DS.spacingXS)
                    .background((station.level?.color ?? .gray), in: Capsule())
            } else {
                Circle()
                    .fill(.gray)
                    .frame(width: 10, height: 10)
            }
        }
    }
}
