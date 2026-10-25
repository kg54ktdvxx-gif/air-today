import SwiftUI
import WidgetKit
import AirTodayCore

struct AQIWidgetEntryView: View {
    let entry: AQIWidgetEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let quality = entry.quality, let shown = entry.reading, let guidance = entry.guidance {
                content(quality: quality, scale: shown.scale, reading: shown.reading, verdict: guidance.verdict)
            } else {
                WidgetNoDataView(family: family)
            }
        }
        .widgetURL(URL(string: "airtoday://open"))
    }

    @ViewBuilder
    private func content(quality: AirQuality, scale: AQIScale, reading: ScaledReading, verdict: String) -> some View {
        switch family {
        case .systemMedium:
            systemMedium(quality: quality, scale: scale, reading: reading, verdict: verdict)
        case .accessoryCircular:
            accessoryCircular(scale: scale, reading: reading)
        case .accessoryInline:
            accessoryInline(scale: scale, reading: reading)
        case .accessoryRectangular:
            accessoryRectangular(scale: scale, reading: reading, verdict: verdict)
        default:
            systemSmall(quality: quality, scale: scale, reading: reading, verdict: verdict)
        }
    }

    private func spokenSummary(quality: AirQuality, scale: AQIScale, reading: ScaledReading, verdict: String) -> String {
        "\(verdict). \(scale.accessibilityName): \(reading.value), \(reading.band.longName)\(placeText(quality).map { ". \($0)" } ?? "")\(entry.isStale ? ". Data may be outdated." : "")"
    }

    private func placeText(_ quality: AirQuality) -> String? {
        quality.locationLabel
    }

    // MARK: - System Small

    private func systemSmall(quality: AirQuality, scale: AQIScale, reading: ScaledReading, verdict: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(scale.shortName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                if entry.isStale {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                WidgetRefreshButton()
            }

            Text("\(reading.value)")
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Spacer(minLength: 0)

            Text(verdict)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)

            HStack(spacing: 4) {
                if let place = placeText(quality) {
                    Text(place)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.usesModelData {
                    OpenMeteoCredit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary(quality: quality, scale: scale, reading: reading, verdict: verdict))
    }

    // MARK: - System Medium

    private func systemMedium(quality: AirQuality, scale: AQIScale, reading: ScaledReading, verdict: String) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scale.shortName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text("\(reading.value)")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(reading.band.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let dominant = reading.dominantPollutant {
                        Label(dominant.displayName, systemImage: "aqi.medium")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    WidgetRefreshButton()
                }

                Label(verdict, systemImage: reading.severityLevel.verdictIcon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack {
                    if let place = placeText(quality) {
                        Text(place)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    if entry.isStale {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.7))
                    }

                    Spacer(minLength: 0)
                    if entry.usesModelData {
                        OpenMeteoCredit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary(quality: quality, scale: scale, reading: reading, verdict: verdict))
    }

    // MARK: - Accessory Circular

    private func accessoryCircular(scale: AQIScale, reading: ScaledReading) -> some View {
        Gauge(value: gaugeFraction(scale: scale, value: reading.value)) {
            Text(scale.compactName)
        } currentValueLabel: {
            Text("\(reading.value)")
                .font(.system(.body, design: .rounded, weight: .medium))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(reading.band.color)
        .accessibilityLabel("\(scale.accessibilityName): \(reading.value), \(reading.band.longName)")
    }

    /// How full the gauge is on the scale's own range.
    private func gaugeFraction(scale: AQIScale, value: Int) -> Double {
        min(Double(value) / scale.gaugeTop, 1)
    }

    // MARK: - Accessory Rectangular

    private func accessoryRectangular(scale: AQIScale, reading: ScaledReading, verdict: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(reading.value)")
                    .font(.headline.weight(.semibold))
                Text(reading.band.name)
                    .font(.caption)
            }
            Text(verdict)
                .font(.caption2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scale.accessibilityName): \(reading.value), \(reading.band.longName). \(verdict)")
    }

    // MARK: - Accessory Inline

    private func accessoryInline(scale: AQIScale, reading: ScaledReading) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "aqi.medium")
            Text("\(scale.compactName) \(reading.value) · \(reading.band.name)")
        }
        .accessibilityLabel("\(scale.accessibilityName): \(reading.value), \(reading.band.longName)")
    }
}

/// Shown before the app has ever loaded a reading.
struct WidgetNoDataView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "aqi.medium")
                    .font(.title3)
            }
            .accessibilityLabel("Air quality data unavailable")
        case .accessoryInline:
            Text("AQI — No Data")
                .accessibilityLabel("Air quality data unavailable")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Air Quality")
                    .font(.headline)
                Text("Open app to load data")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Air quality data unavailable. Open app to load data.")
        default:
            VStack(spacing: 8) {
                Image(systemName: "aqi.medium")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Open Air Today")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text("to load air quality data")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Air quality data unavailable. Open Air Today to load data.")
        }
    }
}
