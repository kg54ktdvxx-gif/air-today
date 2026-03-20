import Foundation

public struct ActivityGuidance: Sendable {
    public let verdict: String
    public let verdictIcon: String
    public let activities: [ActivityRec]
    public let peakWarning: String?

    public init(verdict: String, verdictIcon: String, activities: [ActivityRec], peakWarning: String?) {
        self.verdict = verdict
        self.verdictIcon = verdictIcon
        self.activities = activities
        self.peakWarning = peakWarning
    }
}

public struct ActivityRec: Sendable, Identifiable {
    public let id = UUID()
    public let activity: Activity
    public let recommendation: Rec
    public let reason: String
    public let bestWindow: String?

    public init(activity: Activity, recommendation: Rec, reason: String, bestWindow: String? = nil) {
        self.activity = activity
        self.recommendation = recommendation
        self.reason = reason
        self.bestWindow = bestWindow
    }
}

public enum Activity: String, CaseIterable, Sendable {
    case running
    case cycling
    case walking
    case playgroundWithKids
    case outdoorDining

    public var displayName: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .walking: "Walking"
        case .playgroundWithKids: "Playground"
        case .outdoorDining: "Outdoor Dining"
        }
    }

    public var icon: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .walking: "figure.walk"
        case .playgroundWithKids: "figure.and.child.holdinghands"
        case .outdoorDining: "fork.knife"
        }
    }
}

public enum Rec: Int, Comparable, Sendable {
    case great
    case ok
    case caution
    case avoid

    public static func < (lhs: Rec, rhs: Rec) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .great: "Great"
        case .ok: "OK"
        case .caution: "Caution"
        case .avoid: "Avoid"
        }
    }

    public var icon: String {
        switch self {
        case .great: "checkmark.circle.fill"
        case .ok: "checkmark.circle"
        case .caution: "exclamationmark.triangle.fill"
        case .avoid: "xmark.circle.fill"
        }
    }
}
