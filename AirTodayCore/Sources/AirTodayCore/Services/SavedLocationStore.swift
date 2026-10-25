import Foundation

/// Saved cities (never the current location, which is re-created each launch),
/// in app-group defaults so background refresh can read them too.
public enum SavedLocationStore {
    static let storageKey = "saved_locations"

    public static func load(from defaults: UserDefaults = .shared) -> [SavedLocation] {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SavedLocation].self, from: data)
        else { return [] }
        return saved
    }

    public static func save(_ locations: [SavedLocation], to defaults: UserDefaults = .shared) {
        let nonCurrent = locations.filter { !$0.isCurrentLocation }
        if let data = try? JSONEncoder().encode(nonCurrent) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
