import Foundation

extension UserDefaults {
    /// App-group defaults, readable by the app, widgets, Live Activity and intents.
    /// Use this for any preference an extension needs; `.standard` is app-only.
    public static var shared: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }
}

public enum Preferences {
    /// 1.0 kept the temperature unit in `.standard`, where extensions can't see it.
    /// Copies it into the app group once so existing choices survive the move.
    public static func migrateToSharedDefaults() {
        let shared = UserDefaults.shared
        for key in [AppConstants.temperatureUnitKey] where shared.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }
    }
}

public enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius
    case fahrenheit

    public var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    public var displayName: String {
        switch self {
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    /// Formats a WAQI temperature (always Celsius), rounded to whole degrees, e.g. "24°C".
    public func format(celsius: Double) -> String {
        let value = switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
        return "\(Int(value.rounded()))\(symbol)"
    }
}
