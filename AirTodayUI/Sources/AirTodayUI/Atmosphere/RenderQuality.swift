import SwiftUI

/// Adaptive rendering quality based on device thermal state and power mode.
@MainActor
@Observable
public final class RenderQuality {
    public private(set) var tier: QualityTier = .high

    public enum QualityTier: Sendable {
        case high    // 120fps, full shaders, all effects
        case medium  // 60fps, simplified shaders
        case low     // 30fps, no shaders, MeshGradient only

        public var frameInterval: Double {
            switch self {
            case .high: 1.0 / 120.0
            case .medium: 1.0 / 60.0
            case .low: 1.0 / 30.0
            }
        }

        public var shadersEnabled: Bool {
            self != .low
        }

        public var particleMultiplier: Double {
            switch self {
            case .high: 1.0
            case .medium: 0.5
            case .low: 0.0
            }
        }
    }

    public init() {}

    /// Call periodically (e.g., from TimelineView) to adapt quality.
    public func update() {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        if thermal == .critical || lowPower {
            tier = .low
        } else if thermal == .serious {
            tier = .medium
        } else {
            tier = .high
        }
    }
}
