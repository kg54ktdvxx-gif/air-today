import Foundation
import WatchConnectivity

/// Keeps the Watch in step with the iPhone: the latest current-location reading
/// and the preferences that change what it shows (scale, health profile, units).
///
/// The iPhone sends application context (only the newest copy is kept, delivered
/// when the Watch next wakes); the Watch writes it into its own app-group store so
/// its app and complications read it exactly as the iPhone's widgets do.
public final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchSync()

    /// Preference keys mirrored to the Watch.
    static let mirroredBoolKeys = [
        HealthProfile.Key.respiratory,
        HealthProfile.Key.ozoneSensitive,
        HealthProfile.Key.children,
    ]
    static let mirroredStringKeys = [AQIScale.storageKey, AppConstants.temperatureUnitKey]

    private enum ContextKey {
        static let reading = "reading"
        static let queryCoordinate = "queryCoordinate"
        static let fetchedAt = "fetchedAt"
    }

    /// Called on the Watch after a new context has been stored.
    public var onReceive: (@Sendable () -> Void)?

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - iPhone → Watch

    #if os(iOS)
    /// Sends the current shared state. Cheap to call often: iOS only keeps the latest.
    public func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(Self.makeContext())
    }

    static func makeContext(defaults: UserDefaults = .shared) -> [String: Any] {
        var context: [String: Any] = [:]
        for key in mirroredBoolKeys { context[key] = defaults.bool(forKey: key) }
        for key in mirroredStringKeys {
            if let value = defaults.string(forKey: key) { context[key] = value }
        }
        if let reading = SharedDataStore.load(), let data = try? JSONEncoder().encode(reading) {
            context[ContextKey.reading] = data
            context[ContextKey.fetchedAt] = SharedDataStore.lastUpdated()?.timeIntervalSince1970
        }
        if let coordinate = SharedDataStore.queryCoordinate(), let data = try? JSONEncoder().encode(coordinate) {
            context[ContextKey.queryCoordinate] = data
        }
        return context
    }
    #endif

    // MARK: - Watch ← iPhone

    /// Stores a received context. The iPhone's reading only replaces the Watch's own
    /// when it was fetched later, so a fresher reading fetched on the Watch isn't
    /// overwritten. Fetch time, not measurement time: a station measured at 13:20 and
    /// fetched at 14:05 is newer news than the model's 14:00 hour fetched at 13:50.
    static func apply(_ context: [String: Any], defaults: UserDefaults = .shared) {
        for key in mirroredBoolKeys {
            if let value = context[key] as? Bool { defaults.set(value, forKey: key) }
        }
        for key in mirroredStringKeys {
            if let value = context[key] as? String { defaults.set(value, forKey: key) }
        }

        guard let data = context[ContextKey.reading] as? Data,
              let reading = try? JSONDecoder().decode(AirQuality.self, from: data)
        else { return }
        let fetchedAt = (context[ContextKey.fetchedAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        if SharedDataStore.load() != nil, let localFetch = SharedDataStore.lastUpdated() {
            // An iPhone on an older version doesn't send its fetch time; its reading's own time is the best guess.
            if localFetch >= (fetchedAt ?? reading.timestamp) { return }
        }

        let coordinate = (context[ContextKey.queryCoordinate] as? Data)
            .flatMap { try? JSONDecoder().decode(Coordinate.self, from: $0) }
        SharedDataStore.save(reading, queryCoordinate: coordinate, fetchedAt: fetchedAt ?? Date())
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        if activationState == .activated { push() }
        #else
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            Self.apply(session.receivedApplicationContext)
            onReceive?()
        }
        #endif
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Self.apply(applicationContext)
        onReceive?()
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another Watch: start talking to the new one.
        session.activate()
    }
    #endif
}
