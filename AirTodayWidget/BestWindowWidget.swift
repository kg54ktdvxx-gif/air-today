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
        .description("When the air should be cleanest today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BestWindowView: View {
    let entry: AQIWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var window: BestWindow? {
        entry.quality.flatMap { BestWindow.today(for: $0, now: entry.date) }
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
            } else {
                WidgetNoDataView(family: family)
            }
        }
        .widgetURL(URL(string: "airtoday://open"))
    }

    private func spoken(_ window: BestWindow) -> String {
        "Best time outside today: \(window.headline). \(window.detail) Expected \(window.level.label)."
    }

    private func small(_ window: BestWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                Spacer()
                WidgetRefreshButton()
            }
            Text("Best time outside")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(window.headline)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(window.detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(window))
    }

    private func medium(_ window: BestWindow) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Best time outside")
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
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(window.level.shortLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(window.level.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(window))
    }

    private func rectangular(_ window: BestWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Best time outside", systemImage: "clock.badge.checkmark")
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
