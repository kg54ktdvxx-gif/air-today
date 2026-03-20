import WidgetKit
import SwiftUI
import AirTodayCore

struct AQIWidgetEntry: TimelineEntry {
    let date: Date
    let aqi: Int
    let level: AQILevel
    let stationName: String
    let dominantPollutant: String
    let isStale: Bool

    static let placeholder = AQIWidgetEntry(
        date: .now,
        aqi: 42,
        level: .good,
        stationName: "Loading...",
        dominantPollutant: "PM2.5",
        isStale: false
    )

    static let noData = AQIWidgetEntry(
        date: .now,
        aqi: 0,
        level: .good,
        stationName: "No data",
        dominantPollutant: "--",
        isStale: true
    )
}

struct AQIWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AQIWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AQIWidgetEntry) -> Void) {
        if let quality = SharedDataStore.load() {
            completion(entryFromQuality(quality))
        } else {
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AQIWidgetEntry>) -> Void) {
        let entry: AQIWidgetEntry
        if let quality = SharedDataStore.load() {
            entry = entryFromQuality(quality)
        } else {
            entry = .noData
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func entryFromQuality(_ quality: AirQuality) -> AQIWidgetEntry {
        let isStale: Bool
        if let lastUpdated = SharedDataStore.lastUpdated() {
            isStale = Date().timeIntervalSince(lastUpdated) > AppConstants.cacheTTL * 2
        } else {
            isStale = false
        }

        return AQIWidgetEntry(
            date: quality.timestamp,
            aqi: quality.aqi,
            level: quality.level,
            stationName: quality.station.name,
            dominantPollutant: quality.dominantPollutant?.displayName ?? "PM2.5",
            isStale: isStale
        )
    }
}
