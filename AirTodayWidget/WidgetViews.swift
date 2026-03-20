import SwiftUI
import WidgetKit
import AirTodayCore

struct AQIWidgetEntryView: View {
    let entry: AQIWidgetEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if entry.isStale && entry.aqi == 0 {
                noDataView
            } else {
                contentView
            }
        }
        .widgetURL(URL(string: "airtoday://open"))
    }

    @ViewBuilder
    private var contentView: some View {
        switch family {
        case .systemSmall:
            systemSmallView
        case .systemMedium:
            systemMediumView
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryInline:
            accessoryInlineView
        case .accessoryRectangular:
            accessoryRectangularView
        default:
            systemSmallView
        }
    }

    // MARK: - No Data

    private var noDataView: some View {
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
    }

    // MARK: - System Small

    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AQI")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if entry.isStale {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Text("\(entry.aqi)")
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Spacer()

            Text(entry.level.verdict)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Text(entry.stationName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - System Medium

    private var systemMediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AQI")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text("\(entry.aqi)")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(entry.level.shortLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                Label(entry.dominantPollutant, systemImage: "aqi.medium")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))

                Label(entry.level.verdict, systemImage: entry.level.verdictIcon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)

                Spacer()

                HStack {
                    Text(entry.stationName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)

                    if entry.isStale {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Accessory Circular

    private var accessoryCircularView: some View {
        Gauge(value: Double(min(entry.aqi, 500)), in: 0...500) {
            Text("AQI")
        } currentValueLabel: {
            Text("\(entry.aqi)")
                .font(.system(.body, design: .rounded, weight: .medium))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(entry.level.color)
    }

    // MARK: - Accessory Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(entry.aqi)")
                    .font(.headline.weight(.semibold))
                Text(entry.level.shortLabel)
                    .font(.caption)
            }
            Text(entry.level.verdict)
                .font(.caption2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accessory Inline

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "aqi.medium")
            Text("AQI \(entry.aqi) · \(entry.level.shortLabel)")
        }
    }
}
