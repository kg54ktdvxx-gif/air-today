import WidgetKit
import SwiftUI
import AppIntents
import AirTodayCore

struct ActivityCheckIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Activity Check" }
    static var description: IntentDescription { "Choose the activity to check." }

    @Parameter(title: "Activity", default: .running)
    var activity: ActivityOption
}

struct ActivityCheckEntry: TimelineEntry {
    let base: AQIWidgetEntry
    let activity: ActivityOption

    var date: Date { base.date }

    var recommendation: ActivityRec? {
        base.guidance?.activities.first { $0.activity == activity.activity }
    }
}

struct ActivityCheckProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityCheckEntry {
        ActivityCheckEntry(base: .placeholder, activity: .running)
    }

    func snapshot(for configuration: ActivityCheckIntent, in context: Context) async -> ActivityCheckEntry {
        let base = context.isPreview && SharedDataStore.load() == nil ? .placeholder : await AQIWidgetTimeline.entry()
        return ActivityCheckEntry(base: base, activity: configuration.activity)
    }

    func timeline(for configuration: ActivityCheckIntent, in context: Context) async -> Timeline<ActivityCheckEntry> {
        let base = await AQIWidgetTimeline.timeline()
        return Timeline(
            entries: base.entries.map { ActivityCheckEntry(base: $0, activity: configuration.activity) },
            policy: base.policy
        )
    }
}

struct ActivityCheckWidget: Widget {
    let kind = "com.airtoday.widget.activity"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ActivityCheckIntent.self, provider: ActivityCheckProvider()) { entry in
            ActivityCheckView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPhotoBackground(level: entry.base.level)
                }
        }
        .configurationDisplayName("Activity Check")
        .description("Is now a good time for running, cycling, a walk or the playground? Data from the World Air Quality Index and Open-Meteo.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct ActivityCheckView: View {
    let entry: ActivityCheckEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let rec = entry.recommendation {
                switch family {
                case .accessoryCircular: circular(rec)
                case .accessoryRectangular: rectangular(rec)
                default: small(rec)
                }
            } else {
                WidgetNoDataView(family: family)
            }
        }
        .widgetURL(URL(string: "airtoday://open"))
    }

    private func spoken(_ rec: ActivityRec) -> String {
        "\(rec.activity.displayName): \(rec.recommendation.label). \(rec.reason)\(rec.bestWindow.map { ". \($0)" } ?? "")"
    }

    private func small(_ rec: ActivityRec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: rec.activity.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                Spacer()
                WidgetRefreshButton()
            }

            Text(rec.activity.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: rec))
                    .frame(width: 12, height: 12)
                Text(rec.recommendation.label)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(rec.bestWindow ?? rec.reason)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if entry.base.usesModelData {
                    OpenMeteoCredit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(rec))
    }

    /// The shown scale's colour for the advice, as in the app.
    private func color(for rec: ActivityRec) -> Color {
        (entry.base.reading?.scale ?? entry.base.scale).color(for: rec.recommendation.level)
    }

    private func rectangular(_ rec: ActivityRec) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("\(rec.activity.displayName): \(rec.recommendation.label)")
                    .font(.headline)
            } icon: {
                Image(systemName: rec.recommendation.icon)
            }
            Text(rec.bestWindow ?? rec.reason)
                .font(.caption2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(rec))
    }

    private func circular(_ rec: ActivityRec) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: rec.activity.icon)
                    .font(.title3)
                Image(systemName: rec.recommendation.icon)
                    .font(.caption2)
            }
        }
        .widgetAccentable()
        .accessibilityLabel(spoken(rec))
    }
}
