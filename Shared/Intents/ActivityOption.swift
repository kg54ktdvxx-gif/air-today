import AppIntents
import AirTodayCore

/// The activities Siri and the Activity Check widget can ask about.
///
/// Compiled into both the app and the widget extension (see project.yml) so each
/// target's App Intents metadata includes it.
enum ActivityOption: String, AppEnum {
    case running
    case cycling
    case walking
    case playground
    case outdoorDining

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Activity" }

    static var caseDisplayRepresentations: [ActivityOption: DisplayRepresentation] {
        [
            .running: DisplayRepresentation(title: "Running", image: .init(systemName: "figure.run"), synonyms: ["run", "a run", "jogging"]),
            .cycling: DisplayRepresentation(title: "Cycling", image: .init(systemName: "figure.outdoor.cycle"), synonyms: ["cycle", "a bike ride", "biking"]),
            .walking: DisplayRepresentation(title: "Walking", image: .init(systemName: "figure.walk"), synonyms: ["walk", "a walk"]),
            .playground: DisplayRepresentation(title: "Playground with kids", image: .init(systemName: "figure.and.child.holdinghands"), synonyms: ["the playground", "the park with the kids"]),
            .outdoorDining: DisplayRepresentation(title: "Outdoor dining", image: .init(systemName: "fork.knife"), synonyms: ["eating outside", "dinner outside"]),
        ]
    }

    var activity: Activity {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .playground: .playgroundWithKids
        case .outdoorDining: .outdoorDining
        }
    }
}
