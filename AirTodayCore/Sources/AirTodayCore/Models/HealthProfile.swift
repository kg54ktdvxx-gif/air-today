import Foundation

/// The optional answers from onboarding that personalise guidance.
///
/// Kept on-device only, in app-group defaults so the widgets, alerts and app agree.
/// Each answer is its own Bool key so views can bind to it with `@AppStorage`.
public struct HealthProfile: Equatable, Sendable {
    /// Asthma or another respiratory condition.
    public var hasRespiratoryCondition: Bool
    /// Notices ozone more than most people (tight chest, coughing on hot afternoons).
    public var isOzoneSensitive: Bool
    /// Children in the household, who breathe more air per kilo than adults.
    public var hasChildren: Bool

    public init(hasRespiratoryCondition: Bool = false, isOzoneSensitive: Bool = false, hasChildren: Bool = false) {
        self.hasRespiratoryCondition = hasRespiratoryCondition
        self.isOzoneSensitive = isOzoneSensitive
        self.hasChildren = hasChildren
    }

    public static let none = HealthProfile()

    public enum Key {
        public static let respiratory = "health_respiratory"
        public static let ozoneSensitive = "health_ozone_sensitive"
        public static let children = "health_children"
    }

    public static func load(from defaults: UserDefaults = .shared) -> HealthProfile {
        HealthProfile(
            hasRespiratoryCondition: defaults.bool(forKey: Key.respiratory),
            isOzoneSensitive: defaults.bool(forKey: Key.ozoneSensitive),
            hasChildren: defaults.bool(forKey: Key.children)
        )
    }
}
