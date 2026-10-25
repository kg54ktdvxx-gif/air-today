import WidgetKit
import SwiftUI
import AppIntents
import AirTodayCore

struct BestWindowWidget: Widget {
    let kind = "com.airtoday.widget.bestwindow"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AirQualityWidgetIntent.self, provider: AQIWidgetProvider()) { entry in
            BestWindowView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPhotoBackground(level: entry.level)
                }
        }
        .configurationDisplayName("Best Window")
        .description("When the air should be cleanest, from Open-Meteo's hourly forecast.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BestWindowView: View {
    let entry: AQIWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var window: BestWindow? {
        entry.quality.flatMap { BestWindow.next(for: $0, scale: entry.scale, now: entry.date) }
    }

    var body: some View {
        Group {
            if let window {
                switch family {
                case .systemMedium: medium(window)
                case .accessoryRectangular: rectangular(window)
                case .accessoryInline: inline(window)
                default: small(window)
                }
            } else if entry.quality != nil {
                noForecast
            } else {
                WidgetNoDataView(family: family)
            }
        }
        .widgetURL(URL(string: "airtoday://open"))
    }

    /// "Best time today" — short enough for the small and Lock Screen sizes.
    private func title(_ window: BestWindow) -> String {
        "Best time \(window.dayName(now: entry.date))"
    }

    /// The window's level in the chosen scale's words.
    private func levelName(_ window: BestWindow) -> String {
        entry.scale == .usEPA ? window.level.shortLabel : entry.scale.bandName(for: window.level)
    }

    private func spoken(_ window: BestWindow) -> String {
        "Best time outside \(window.dayName(now: entry.date)): \(window.headline). \(window.detail) Expected \(levelName(window))."
    }

    /// There's a reading but no hourly forecast to plan from.
    private var noForecast: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Best time outside", systemImage: "clock.badge.checkmark")
                .font(.caption.weight(.medium))
            Text("No forecast right now")
                .font(.caption2)
                .opacity(0.75)
        }
        .foregroundStyle(family == .systemSmall || family == .systemMedium ? .white : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func small(_ window: BestWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title beside the refresh button, so the detail and credit have room.
            HStack {
                Text(title(window))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 4)
                WidgetRefreshButton()
            }
            Text(window.headline)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(window.detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
            // The window always comes from Open-Meteo's forecast.
            OpenMeteoCredit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(window))
    }

    private func medium(_ window: BestWindow) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(window))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text(window.headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(window.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                WidgetRefreshButton()
                Spacer(minLength: 0)
                Text(window.dayName(now: entry.date).capitalized)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(levelName(window))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(window.level.color)
                OpenMeteoCredit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(window))
    }

    private func rectangular(_ window: BestWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title(window), systemImage: "clock.badge.checkmark")
                .font(.caption2)
            Text(window.headline)
                .font(.headline)
            Text(window.detail)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(window))
    }

    private func inline(_ window: BestWindow) -> some View {
        Label("Outside: \(window.headline)", systemImage: "clock.badge.checkmark")
            .accessibilityLabel(spoken(window))
    }
}
