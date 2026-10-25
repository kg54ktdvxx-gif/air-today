import WidgetKit
import SwiftUI
import AppIntents
import AirTodayCore

@main
struct AirTodayComplicationsBundle: WidgetBundle {
    var body: some Widget {
        AirQualityComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let quality: AirQuality?
    let scale: AQIScale
    let profile: HealthProfile

    var shown: (scale: AQIScale, reading: ScaledReading)? {
        quality.map { scale.displayReading(for: $0) }
    }

    var verdict: String? {
        quality.map { ActivityGuidanceService().guidance(for: $0, scale: scale, at: date, profile: profile).verdict }
    }
}

/// Nothing to configure; an intent configuration gives the provider async APIs.
struct ComplicationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Air Quality" }
    static var description: IntentDescription { "Air quality where you are." }
}

struct ComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, quality: nil, scale: .usEPA, profile: .none)
    }

    func snapshot(for configuration: ComplicationIntent, in context: Context) async -> ComplicationEntry {
        ComplicationEntry(date: .now, quality: SharedDataStore.load(), scale: AQIScale.current, profile: HealthProfile.load())
    }

    func timeline(for configuration: ComplicationIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        let quality = await CurrentAirRefresher.latest()
        let entry = ComplicationEntry(date: .now, quality: quality, scale: AQIScale.current, profile: HealthProfile.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        return Timeline(entries: [entry], policy: .after(next))
    }

    func recommendations() -> [AppIntentRecommendation<ComplicationIntent>] {
        [AppIntentRecommendation(intent: ComplicationIntent(), description: "Air Quality")]
    }
}

struct AirQualityComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.airtoday.watch.complication", intent: ComplicationIntent.self, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Air Quality")
        .description("Today's air quality where you are.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let shown = entry.shown {
            switch family {
            case .accessoryCorner: corner(shown.scale, shown.reading)
            case .accessoryInline: inline(shown.scale, shown.reading)
            case .accessoryRectangular: rectangular(shown.scale, shown.reading)
            default: circular(shown.scale, shown.reading)
            }
        } else {
            Image(systemName: "aqi.medium")
                .accessibilityLabel("Air quality unavailable")
        }
    }

    private func fraction(_ scale: AQIScale, _ value: Int) -> Double {
        min(Double(value) / scale.gaugeTop, 1)
    }

    private func spoken(_ scale: AQIScale, _ reading: ScaledReading) -> String {
        "\(scale.accessibilityName): \(reading.value), \(reading.band.longName)"
    }

    private func circular(_ scale: AQIScale, _ reading: ScaledReading) -> some View {
        Gauge(value: fraction(scale, reading.value)) {
            Image(systemName: "aqi.medium")
        } currentValueLabel: {
            Text("\(reading.value)")
                .font(.system(.body, design: .rounded, weight: .medium))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(reading.band.color)
        .accessibilityLabel(spoken(scale, reading))
    }

    private func corner(_ scale: AQIScale, _ reading: ScaledReading) -> some View {
        Text("\(reading.value)")
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: fraction(scale, reading.value)) {
                    Text(reading.band.name)
                }
                .tint(reading.band.color)
            }
            .accessibilityLabel(spoken(scale, reading))
    }

    private func inline(_ scale: AQIScale, _ reading: ScaledReading) -> some View {
        Text("\(scale.compactName) \(reading.value) · \(reading.band.name)")
            .accessibilityLabel(spoken(scale, reading))
    }

    private func rectangular(_ scale: AQIScale, _ reading: ScaledReading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("\(reading.value)")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .widgetAccentable()
                Text(reading.band.name)
                    .font(.caption)
            }
            if let verdict = entry.verdict {
                Text(verdict)
                    .font(.caption2)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spoken(scale, reading)). \(entry.verdict ?? "")")
    }
}
