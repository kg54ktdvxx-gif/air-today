import AppIntents
import WidgetKit
import AirTodayCore

/// The widgets' refresh button. Runs in whichever process hosts it (the widget
/// extension for a widget tap), fetches the current location's reading and
/// reloads every widget.
struct RefreshAirQualityIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh Air Quality" }
    static var description: IntentDescription { "Fetches the latest reading for your location." }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        _ = try? await CurrentAirRefresher.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
