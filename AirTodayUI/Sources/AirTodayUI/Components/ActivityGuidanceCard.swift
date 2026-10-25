import SwiftUI
import AirTodayCore

/// Every activity's recommendation, with today's outlook and the advice's basis as a footer.
/// The verdict itself is the hero's, so it isn't repeated here.
public struct ActivityGuidanceCard: View {
    let guidance: ActivityGuidance
    /// The current band's colour, along the card's leading edge.
    let accent: Color
    let scale: AQIScale
    @State private var showingAbout = false

    public init(guidance: ActivityGuidance, accent: Color, scale: AQIScale) {
        self.guidance = guidance
        self.accent = accent
        self.scale = scale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activities")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.spacingXS)
                .accessibilityAddTraits(.isHeader)

            ForEach(guidance.activities) { rec in
                activityRow(rec)

                if rec.id != guidance.activities.last?.id {
                    DS.divider
                        .padding(.horizontal, DS.spacingLG)
                }
            }

            footer
        }
        .background { DS.cardBackground }
        .overlay {
            // The band colour runs along the card's leading edge and fades out.
            RoundedRectangle(cornerRadius: DS.cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.75), accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: UnitPoint(x: 0.35, y: 0.5)
                    ),
                    lineWidth: 1.5
                )
                .animation(DS.Motion.atmospheric, value: accent)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingAbout) {
            AdviceInfoSheet(scale: scale)
        }
    }

    private func activityRow(_ rec: ActivityRec) -> some View {
        HStack(spacing: DS.spacingMD) {
            Image(systemName: rec.activity.icon)
                .font(.body)
                .foregroundStyle(.white.opacity(DS.opacitySecondary))
                .frame(width: DS.iconMD)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            DS.divider

            if let outlook = guidance.peakWarning {
                Label(outlook, systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
            }

            Button {
                showingAbout = true
            } label: {
                HStack(spacing: DS.spacingXS) {
                    Text("General guidance, not medical advice.")
                    Text("About this advice")
                        .underline()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("General guidance, not medical advice. About this advice")
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.bottom, DS.spacingMD)
        .padding(.top, DS.spacingXS)
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
