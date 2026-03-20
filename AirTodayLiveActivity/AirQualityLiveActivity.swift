import ActivityKit
import WidgetKit
import SwiftUI
import AirTodayCore

struct AirQualityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AirQualityAttributes.self) { context in
            // Lock Screen / StandBy banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.level.color)
                            .frame(width: 10, height: 10)
                        Text("AQI")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.aqi)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.level.verdict)
                            .font(.subheadline.weight(.medium))

                        HStack(spacing: 8) {
                            Label(context.state.dominantPollutant, systemImage: "aqi.medium")
                                .font(.caption2)

                            Image(systemName: context.state.trend.symbol)
                                .font(.caption2)

                            Text(context.state.stationName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {}
            } compactLeading: {
                // Compact leading — colored dot
                Circle()
                    .fill(context.state.level.color)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                // Compact trailing — AQI number
                Text("\(context.state.aqi)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(context.state.level.color)
            } minimal: {
                // Minimal — just the colored dot
                Circle()
                    .fill(context.state.level.color)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AirQualityAttributes>) -> some View {
        HStack(spacing: 16) {
            // Left: AQI + level
            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.state.aqi)")
                    .font(.system(size: 36, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(context.state.level.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.level.color)
            }

            // Divider
            Rectangle()
                .fill(.secondary.opacity(0.3))
                .frame(width: 1)

            // Right: verdict + details
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.level.verdict)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: context.state.trend.symbol)
                        .font(.caption2)
                    Text(context.state.dominantPollutant)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(context.state.stationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
        .background {
            LinearGradient(
                colors: [context.state.level.color.opacity(0.3), context.state.level.color.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
