import SwiftUI
import MapKit
import AirTodayCore

/// Full-screen map showing all nearby monitoring stations.
public struct MapScreen: View {
    let stations: [MapStation]
    let center: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStation: MapStation?
    @State private var position: MapCameraPosition

    public init(stations: [MapStation], center: CLLocationCoordinate2D) {
        self.stations = stations
        self.center = center
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )))
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position, selection: $selectedStation) {
                ForEach(stations) { station in
                    Annotation(
                        station.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: station.coordinate.latitude,
                            longitude: station.coordinate.longitude
                        ),
                        anchor: .bottom
                    ) {
                        stationMarker(station)
                    }
                    .tag(station)
                }

                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(DS.spacingSM + 2)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(DS.spacingLG)

            // Selected station callout
            if let station = selectedStation {
                VStack {
                    Spacer()
                    stationCallout(station)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: selectedStation)
            }
        }
    }

    private func stationMarker(_ station: MapStation) -> some View {
        VStack(spacing: 0) {
            if let aqi = station.aqi {
                Text("\(aqi)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.spacingXS + 2)
                    .padding(.vertical, DS.spacingXS)
                    .background(station.level?.color ?? .gray, in: RoundedRectangle(cornerRadius: DS.cornerRadiusXS))
            } else {
                Circle()
                    .fill(.gray)
                    .frame(width: 12, height: 12)
            }

            // Arrow pointing down
            Triangle()
                .fill(station.level?.color ?? .gray)
                .frame(width: 8, height: 4)
        }
    }

    private func stationCallout(_ station: MapStation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.spacingXS) {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let aqi = station.aqi, let level = station.level {
                    HStack(spacing: DS.spacingXS + 2) {
                        Text("AQI \(aqi)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(level.shortLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(level.color)
                    }
                }
            }

            Spacer()
        }
        .padding(DS.spacingLG)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.cornerRadius))
        .padding(DS.spacingLG)
    }
}

/// Simple triangle shape for map markers.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
