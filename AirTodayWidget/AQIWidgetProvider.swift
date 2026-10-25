import WidgetKit
import SwiftUI
import AppIntents
import AirTodayCore

/// Everything any Air Today widget draws from.
struct AQIWidgetEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has ever loaded a reading.
    let quality: AirQuality?
    /// When the reading was fetched; drives the "may be outdated" marker.
    let fetchedAt: Date?
    let scale: AQIScale
    let profile: HealthProfile

    /// Severity on the chosen scale; picks the background photo.
    var level: AQILevel { reading?.reading.severityLevel ?? .good }

    var isStale: Bool {
        guard let fetchedAt else { return true }
        return date.timeIntervalSince(fetchedAt) > AppConstants.cacheTTL * 2
    }

    var guidance: ActivityGuidance? {
        quality.map { ActivityGuidanceService().guidance(for: $0, scale: scale, at: date, profile: profile) }
    }

    var reading: (scale: AQIScale, reading: ScaledReading)? {
        quality.map { scale.displayReading(for: $0) }
    }

    static let placeholder = AQIWidgetEntry(
        date: .now,
        quality: AirQuality(
            aqi: 42,
            dominantPollutant: .pm25,
            pollutants: [Pollutant(kind: .pm25, aqi: 42)],
            weather: Weather(temperature: 18),
            station: nil,
            source: .model,
            timestamp: .now,
            attribution: [],
            placeName: "Your area"
        ),
        fetchedAt: .now,
        scale: .usEPA,
        profile: .none
    )
}

enum AQIWidgetTimeline {
    /// Uses the shared cache while it's fresh and fetches otherwise, so widgets
    /// stay current even when the app hasn't been opened.
    static func entry(at date: Date = .now) async -> AQIWidgetEntry {
        let quality = await CurrentAirRefresher.latest()
        return AQIWidgetEntry(
            date: date,
            quality: quality,
            fetchedAt: SharedDataStore.lastUpdated(),
            scale: AQIScale.current,
            profile: HealthProfile.load()
        )
    }

    static func timeline() async -> Timeline<AQIWidgetEntry> {
        let entry = await entry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        return Timeline(entries: [entry], policy: .after(next))
    }
}

/// The plain air-quality and best-window widgets have nothing to configure.
struct AirQualityWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Air Quality" }
    static var description: IntentDescription { "Air quality where you are." }
}

struct AQIWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AQIWidgetEntry { .placeholder }

    func snapshot(for configuration: AirQualityWidgetIntent, in context: Context) async -> AQIWidgetEntry {
        context.isPreview && SharedDataStore.load() == nil ? .placeholder : await AQIWidgetTimeline.entry()
    }

    func timeline(for configuration: AirQualityWidgetIntent, in context: Context) async -> Timeline<AQIWidgetEntry> {
        await AQIWidgetTimeline.timeline()
    }
}

/// Open-Meteo's CC BY 4.0 licence asks for a credit wherever its data is shown.
/// Shown on Home Screen widgets whose reading includes model data (estimate,
/// forecast or weather); Lock Screen widgets are too small, so their gallery
/// descriptions carry it instead.
struct OpenMeteoCredit: View {
    var body: some View {
        Text("Open-Meteo")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Data from Open-Meteo")
    }
}

extension AQIWidgetEntry {
    /// Whether anything shown came from Open-Meteo.
    var usesModelData: Bool { quality?.model != nil }
}

/// Small circular refresh control for the Home Screen widgets.
struct WidgetRefreshButton: View {
    var body: some View {
        Button(intent: RefreshAirQualityIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh air quality")
    }
}
