import SwiftUI
import AirTodayCore

/// A glanceable verdict and number, then today's activities and best time.
struct WatchHomeView: View {
    let model: WatchAirModel

    @AppStorage(AQIScale.storageKey, store: .shared) private var scale: AQIScale = .usEPA
    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false

    private var profile: HealthProfile {
        HealthProfile(hasRespiratoryCondition: hasRespiratoryCondition, isOzoneSensitive: isOzoneSensitive, hasChildren: hasChildren)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let quality = model.quality {
                    content(quality)
                } else if model.isLoading {
                    ProgressView()
                } else {
                    unavailable
                }
            }
            .containerBackground(backgroundGradient, for: .navigation)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh(force: true) }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        let color = model.quality.map { scale.displayReading(for: $0).reading.band.color } ?? .gray
        return LinearGradient(colors: [color.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Content

    private func content(_ quality: AirQuality) -> some View {
        let guidance = ActivityGuidanceService().guidance(for: quality, scale: scale, profile: profile)
        let shown = scale.displayReading(for: quality)

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(guidance.verdict)
                    .font(.system(.headline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(shown.reading.value)")
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown.reading.value)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(shown.reading.band.name)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(shown.reading.band.color)
                        if let dominant = shown.reading.dominantPollutant {
                            Text(dominant.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(shown.scale.accessibilityName): \(shown.reading.value), \(shown.reading.band.longName)")

                Text(shown.scale.caption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if let window = BestWindow.next(for: quality, scale: scale) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Best \(window.dayName()): \(window.headline)")
                                .font(.footnote.weight(.semibold))
                            Text(window.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.checkmark")
                    }
                    .padding(.top, 2)
                }

                Divider()

                ForEach(guidance.activities) { rec in
                    activityRow(rec)
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    if let place = quality.locationLabel {
                        Text(place)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                    }
                    Text(SourceDescription.text(for: quality, distance: nil, scale: scale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // Credits the licences ask for wherever the data is shown.
                    Text(quality.model == nil
                        ? "Data: World Air Quality Index"
                        : quality.station == nil
                            ? "Data: Open-Meteo, CAMS"
                            : "Data: World Air Quality Index, Open-Meteo, CAMS")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Air Today")
    }

    private func activityRow(_ rec: ActivityRec) -> some View {
        HStack(spacing: 8) {
            Image(systemName: rec.activity.icon)
                .frame(width: 20)
            Text(rec.activity.displayName)
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(rec.recommendation.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: rec.recommendation))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rec.activity.displayName): \(rec.recommendation.label). \(rec.reason)")
    }

    private func color(for rec: Rec) -> Color {
        switch rec {
        case .great: .green
        case .ok: .blue
        case .caution: .orange
        case .avoid: .red
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "aqi.medium")
                .font(.title2)
            Text(model.errorMessage ?? "Open Air Today on your iPhone, or allow location on your Watch.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.refresh(force: true) }
            }
        }
    }
}
