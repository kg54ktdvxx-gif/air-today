import AppIntents
import AirTodayCore

/// "What's the air quality?" — today's verdict and number where the user is.
struct CheckAirQualityIntent: AppIntent {
    static var title: LocalizedStringResource { "Check Air Quality" }
    static var description: IntentDescription { "Hear today's verdict and air quality where you are." }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let quality = await CurrentAirRefresher.latest() else { throw IntentError.noReading }

        let verdict = ActivityGuidanceService().guidance(for: quality, profile: HealthProfile.load()).verdict
        let shown = AQIScale.current.displayReading(for: quality)
        let place = quality.station.name.components(separatedBy: ",").first ?? quality.station.name
        return .result(dialog: "\(verdict). \(shown.scale.shortName) \(shown.reading.value), \(shown.reading.band.longName), at \(place).")
    }
}

/// "Should I run today?" — one activity's recommendation, personalised.
struct CheckActivityIntent: AppIntent {
    static var title: LocalizedStringResource { "Check an Activity" }
    static var description: IntentDescription { "Find out whether now is a good time for running, cycling, walking and more." }

    @Parameter(title: "Activity", default: .running)
    var activity: ActivityOption

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$activity)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let quality = await CurrentAirRefresher.latest() else { throw IntentError.noReading }

        let guidance = ActivityGuidanceService().guidance(for: quality, profile: HealthProfile.load())
        guard let rec = guidance.activities.first(where: { $0.activity == activity.activity }) else {
            throw IntentError.noReading
        }
        var answer = "\(rec.activity.displayName): \(rec.recommendation.label). \(rec.reason)."
        if let window = rec.bestWindow { answer += " \(window)." }
        return .result(dialog: "\(answer)")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noReading

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noReading: "Air Today couldn't get a reading right now. Try again in a moment."
        }
    }
}

struct AirTodayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckAirQualityIntent(),
            phrases: [
                "What's the air quality in \(.applicationName)",
                "Check the air with \(.applicationName)",
                "\(.applicationName) air quality",
            ],
            shortTitle: "Air Quality",
            systemImageName: "aqi.medium"
        )
        AppShortcut(
            intent: CheckActivityIntent(),
            phrases: [
                "Should I run today with \(.applicationName)",
                "Can I go \(\.$activity) with \(.applicationName)",
                "Is it a good time for \(\.$activity) in \(.applicationName)",
            ],
            shortTitle: "Activity Check",
            systemImageName: "figure.run"
        )
    }
}
