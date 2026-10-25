import Foundation
import ActivityKit

/// Manages Live Activity lifecycle for AQI alerts.
@MainActor
@Observable
public final class LiveActivityManager {
    public private(set) var isActive = false
    public var alwaysOn = false

    /// `ActivityKit.Activity` is not Sendable, so only its ID is stored here and the
    /// instance is looked up inside nonisolated helpers when it needs updating.
    @ObservationIgnored
    private var currentActivityID: String?
    private var consecutiveGoodReadings = 0

    public init() {
        // Adopt an activity left running by a previous launch so it keeps being
        // updated and ended, rather than orphaned alongside a duplicate.
        let running = ActivityKit.Activity<AirQualityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        currentActivityID = running.first?.id
        isActive = currentActivityID != nil

        for extra in running.dropFirst() {
            let id = extra.id
            Task { await Self.end(activityID: id) }
        }
    }

    // MARK: - Start / Update / Stop

    public func update(with quality: AirQuality) {
        let contentState = AirQualityAttributes.ContentState(from: quality)

        if quality.aqi > 100 || alwaysOn {
            if currentActivityID == nil {
                start(quality: quality, state: contentState)
            } else {
                updateExisting(state: contentState)
            }
            consecutiveGoodReadings = 0
        } else {
            consecutiveGoodReadings += 1
            if consecutiveGoodReadings >= 4 {
                stop()
            } else if currentActivityID != nil {
                updateExisting(state: contentState)
            }
        }
    }

    private func start(quality: AirQuality, state: AirQualityAttributes.ContentState) {
        let attributes = AirQualityAttributes(locationName: quality.station.name)
        let initialContent = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: AppConstants.liveActivityStaleMinutes))

        do {
            currentActivityID = try ActivityKit.Activity.request(
                attributes: attributes,
                content: initialContent,
                pushType: nil
            ).id
            isActive = true
        } catch {
            isActive = false
        }
    }

    private func updateExisting(state: AirQualityAttributes.ContentState) {
        guard let id = currentActivityID else { return }
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: AppConstants.liveActivityStaleMinutes))
        Task {
            await Self.update(activityID: id, with: content)
        }
    }

    public func stop() {
        guard let id = currentActivityID else { return }
        Task {
            await Self.end(activityID: id)
        }
        currentActivityID = nil
        isActive = false
        consecutiveGoodReadings = 0
    }

    // MARK: - ActivityKit Calls

    private nonisolated static func activity(withID id: String) -> ActivityKit.Activity<AirQualityAttributes>? {
        ActivityKit.Activity<AirQualityAttributes>.activities.first { $0.id == id }
    }

    private nonisolated static func update(activityID: String, with content: ActivityContent<AirQualityAttributes.ContentState>) async {
        await activity(withID: activityID)?.update(content)
    }

    private nonisolated static func end(activityID: String) async {
        await activity(withID: activityID)?.end(nil, dismissalPolicy: .immediate)
    }
}
