import Foundation
import ActivityKit

/// Manages Live Activity lifecycle for AQI alerts.
@MainActor
@Observable
public final class LiveActivityManager {
    public private(set) var isActive = false
    public var alwaysOn = false

    @ObservationIgnored
    private var currentActivity: ActivityKit.Activity<AirQualityAttributes>?
    private var consecutiveGoodReadings = 0

    public init() {}

    // MARK: - Start / Update / Stop

    public func update(with quality: AirQuality) {
        let contentState = AirQualityAttributes.ContentState(from: quality)

        if quality.aqi > 100 || alwaysOn {
            if currentActivity == nil {
                start(quality: quality, state: contentState)
            } else {
                updateExisting(state: contentState)
            }
            consecutiveGoodReadings = 0
        } else {
            consecutiveGoodReadings += 1
            if consecutiveGoodReadings >= 4 {
                stop()
            } else if currentActivity != nil {
                updateExisting(state: contentState)
            }
        }
    }

    private func start(quality: AirQuality, state: AirQualityAttributes.ContentState) {
        let attributes = AirQualityAttributes(locationName: quality.station.name)
        let initialContent = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: AppConstants.liveActivityStaleMinutes))

        do {
            currentActivity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: initialContent,
                pushType: nil
            )
            isActive = true
        } catch {
            isActive = false
        }
    }

    private func updateExisting(state: AirQualityAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: AppConstants.liveActivityStaleMinutes))
        Task {
            await activity.update(content)
        }
    }

    public func stop() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        isActive = false
        consecutiveGoodReadings = 0
    }
}
