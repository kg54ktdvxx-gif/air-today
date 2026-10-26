import SwiftUI
import AirTodayCore

/// Hero section: the place, then the verdict as primary readout and the number secondary,
/// then one quiet line for the band and one for where the reading came from.
public struct VerdictHero: View {
    let quality: AirQuality?
    let state: LoadingState
    let hasScrolled: Bool
    /// The page's place: the town (or "My Location") or the saved city's name.
    let placeName: String
    let isCurrentLocation: Bool
    let onRetry: () async -> Void

    @AppStorage(AQIScale.storageKey, store: .shared)
    private var scale: AQIScale = .usEPA
    /// Launches so far; the scale caption shows for the first few, then on tapping the number.
    @AppStorage(DS.launchCountKey) private var launchCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DS.reduceVisualEffectsKey) private var reduceVisualEffects = false
    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false
    @State private var showingScale = false
    /// The big number follows the reader's text size, within reason.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 96

    private var healthProfile: HealthProfile {
        HealthProfile(
            hasRespiratoryCondition: hasRespiratoryCondition,
            isOzoneSensitive: isOzoneSensitive,
            hasChildren: hasChildren
        )
    }

    private static let guidanceService = ActivityGuidanceService()
    /// Launches during which the scale caption shows under the number.
    static let captionLaunches = 3

    public init(
        quality: AirQuality?,
        state: LoadingState,
        hasScrolled: Bool,
        placeName: String,
        isCurrentLocation: Bool,
        onRetry: @escaping () async -> Void
    ) {
        self.quality = quality
        self.state = state
        self.hasScrolled = hasScrolled
        self.placeName = placeName
        self.isCurrentLocation = isCurrentLocation
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 0) {
            placeHeader
                // Clears the status bar and the top bar.
                .padding(.top, 112)

            if let quality {
                loadedContent(quality)
            } else if case .loading = state {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            } else if case .error(let message) = state {
                Spacer()
                errorContent(message)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "aqi.medium")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Checking air quality...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Place

    /// The place, large, so each page is clearly somewhere. Other cities show their
    /// local time beside it.
    private var placeHeader: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                if isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.footnote.weight(.semibold))
                        .accessibilityLabel("Your location:")
                }
                Text(placeName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !isCurrentLocation, let offset = quality?.timeZoneOffset {
                TimelineView(.everyMinute) { _ in
                    Text(SunCalculator.localTime(timeZoneOffset: offset))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        .accessibilityLabel("Local time \(SunCalculator.localTime(timeZoneOffset: offset))")
                }
            }
        }
        .skyTextShadow()
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, scale: scale, profile: healthProfile)
        let (shownScale, reading) = scale.displayReading(for: quality)

        Spacer()

        VStack(spacing: 6) {
            Text(guidance.verdict)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.spacingLG)

            Button {
                showingScale = true
            } label: {
                Text("\(reading.value)")
                    .font(.system(size: min(numberSize, 150), weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(reading.value)))
                    .animation(DS.Motion.standard, value: reading.value)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shownScale.accessibilityName): \(reading.value), \(reading.band.longName). Lower is better.")
            .accessibilityHint("Explains the scale")

            // Without the standard and direction, "82" means nothing to newcomers.
            if launchCount <= Self.captionLaunches {
                Text(shownScale.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, -8)
                    .accessibilityHidden(true)
            }

            Text(reading.dominantPollutant.map { "\(reading.band.name) · \($0.displayName)" } ?? reading.band.name)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Text(SourceDescription.text(for: quality, scale: scale))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .skyTextShadow()
        .sheet(isPresented: $showingScale) {
            ScaleExplainerSheet(scale: shownScale, reading: reading)
        }

        Spacer()

        Image(systemName: "chevron.compact.down")
            .font(.title2)
            .foregroundStyle(.white.opacity(0.4))
            .symbolEffect(.pulse, isActive: !hasScrolled && !reduceMotion && !reduceVisualEffects)
            .opacity(hasScrolled ? 0 : 1)
            .animation(DS.Motion.quick, value: hasScrolled)
            .padding(.bottom, 40)
            .accessibilityHidden(true)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text("Couldn't load air quality")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                Task { await onRetry() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding()
    }
}
