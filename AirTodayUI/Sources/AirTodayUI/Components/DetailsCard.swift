import SwiftUI
import MapKit
import AirTodayCore

/// The weather in a line or two, and the monitoring stations nearby, which open the map.
struct DetailsCard: View {
    let quality: AirQuality
    let stations: [MapStation]
    let temperatureUnit: TemperatureUnit
    let scale: AQIScale
    @State private var showingMap = false

    /// Temperature, humidity and wind.
    private var weatherLine: String? {
        let weather = quality.weather
        let parts = [
            weather.temperature.map { temperatureUnit.format(celsius: $0) },
            weather.humidity.map { "Humidity \(Int($0))%" },
            weather.windSpeed.map { String(format: "Wind %.1f m/s", $0) },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Sunset, and today's highest UV from the forecast — useful all day, unlike the
    /// current UV, which is 0 every evening.
    private var sunLine: String? {
        let sunset = quality.coordinate.flatMap { coordinate in
            quality.timeZoneOffset.flatMap { offset in
                SunCalculator.sunset(latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneOffset: offset)
                    .map { "Sunset \(SunCalculator.formatTime($0, timeZoneOffset: offset))" }
            }
        }
        let uv = quality.todayUVPeak().map { peak in
            let index = Int(peak.rounded())
            return "UV peak \(index) (\(Self.uvRisk(index)))"
        }
        let parts = [sunset, uv].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isEmpty: Bool { weatherLine == nil && sunLine == nil && stations.isEmpty }

    private var mapCenter: CLLocationCoordinate2D {
        let coordinate = quality.coordinate ?? stations.first?.coordinate
        return CLLocationCoordinate2D(latitude: coordinate?.latitude ?? 0, longitude: coordinate?.longitude ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Details")
                .font(DS.Typeface.cardTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.cardHeaderBottom)
                .accessibilityAddTraits(.isHeader)

            if weatherLine != nil || sunLine != nil {
                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    if let weatherLine { Text(weatherLine) }
                    if let sunLine { Text(sunLine) }
                }
                .font(DS.Typeface.body)
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
                .padding(.horizontal, DS.spacingLG)
                .padding(.bottom, DS.spacingMD)
                .accessibilityElement(children: .combine)
            }

            if !stations.isEmpty {
                DS.divider
                    .padding(.horizontal, DS.spacingLG)
                stationsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DS.cardBackground }
        .fullScreenCover(isPresented: $showingMap) {
            MapScreen(stations: stations, center: mapCenter)
        }
    }

    private var stationsRow: some View {
        Button {
            showingMap = true
        } label: {
            HStack(spacing: DS.spacingMD) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stations.count == 1 ? "1 station nearby" : "\(stations.count) stations nearby")
                        .foregroundStyle(.white)
                    // WAQI's map only has US EPA values.
                    if scale != .usEPA {
                        Text("Readings on the US EPA AQI")
                            .font(DS.Typeface.caption)
                            .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    }
                }
                Spacer(minLength: DS.spacingSM)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(DS.opacityTertiary))
            }
            .font(DS.Typeface.body)
            .padding(.horizontal, DS.spacingLG)
            .padding(.vertical, DS.spacingMD)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the map")
    }

    static func uvRisk(_ index: Int) -> String {
        switch index {
        case ...2: "low"
        case 3...5: "moderate"
        case 6...7: "high"
        case 8...10: "very high"
        default: "extreme"
        }
    }
}
