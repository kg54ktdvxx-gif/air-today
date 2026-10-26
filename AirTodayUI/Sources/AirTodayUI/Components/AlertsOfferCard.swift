import SwiftUI
import AirTodayCore

/// Offered once to people updating from 1.1, who never saw onboarding's alerts step.
struct AlertsOfferCard: View {
    let onDone: () -> Void

    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA
    @AppStorage(NotificationPreferences.Key.alertsOffered, store: .shared) private var alertsOffered = false

    private var level: AQILevel {
        NotificationPreferences.suggestedThreshold(for: HealthProfile.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingMD) {
            HStack(alignment: .top, spacing: DS.spacingMD) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Get warned when air gets worse")
                        .font(DS.Typeface.rowTitle)
                        .foregroundStyle(.white)
                    Text("At \(scale.bandName(for: level)) on the \(scale.shortName), here and in the places you save.")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: DS.spacingSM) {
                Button {
                    let level = level
                    Task {
                        await NotificationPreferences.enableThresholdAlerts(at: level)
                        onDone()
                    }
                } label: {
                    Text("Turn On")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.selectedFill)

                Button {
                    alertsOffered = true
                    onDone()
                } label: {
                    Text("Not Now")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(DS.spacingLG)
        .background { DS.cardBackground }
    }
}
