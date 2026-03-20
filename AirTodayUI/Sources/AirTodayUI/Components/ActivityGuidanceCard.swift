import SwiftUI
import AirTodayCore

/// Expandable activity guidance card showing per-activity recommendations.
public struct ActivityGuidanceCard: View {
    let guidance: ActivityGuidance
    let level: AQILevel
    @State private var isExpanded = false

    public init(guidance: ActivityGuidance, level: AQILevel) {
        self.guidance = guidance
        self.level = level
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { DS.cardBackground }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.spacingMD) {
            Image(systemName: guidance.verdictIcon)
                .font(.title2)
                .foregroundStyle(level.color)
                .frame(width: DS.iconMD + 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(guidance.verdict)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))

                if let warning = guidance.peakWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                }
            }

            Spacer()
        }
        .padding(DS.spacingLG)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            DS.divider
                .padding(.horizontal, DS.spacingLG)

            ForEach(guidance.activities) { rec in
                activityRow(rec)

                if rec.id != guidance.activities.last?.id {
                    DS.divider
                        .padding(.horizontal, DS.spacingLG)
                }
            }
        }
        .padding(.bottom, DS.spacingSM)
    }

    private func activityRow(_ rec: ActivityRec) -> some View {
        HStack(spacing: DS.spacingMD) {
            Image(systemName: rec.activity.icon)
                .font(.body)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .frame(width: DS.iconMD)

            VStack(alignment: .leading, spacing: DS.spacingXS) {
                HStack(spacing: DS.spacingXS + 2) {
                    Text(rec.activity.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Text(rec.recommendation.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(recColor(rec.recommendation))
                        .padding(.horizontal, DS.spacingXS + 2)
                        .padding(.vertical, 2)
                        .background(recColor(rec.recommendation).opacity(0.15), in: Capsule())
                }

                Text(rec.reason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))

                if let window = rec.bestWindow {
                    Text(window)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.vertical, DS.spacingSM)
    }

    private func recColor(_ rec: Rec) -> Color {
        switch rec {
        case .great: .green
        case .ok: .blue
        case .caution: .orange
        case .avoid: .red
        }
    }
}
