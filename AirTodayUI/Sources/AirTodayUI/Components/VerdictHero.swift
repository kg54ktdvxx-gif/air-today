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
    /// False until the first reading has risen into place.
    @State private var readingShown = false
    /// The big number follows the reader's text size, within reason.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 96

    private var healthProfile: HealthProfile {
        HealthProfile(
            hasRespiratoryCondition: hasRespiratoryCondition,
            isOzoneSensitive: isOzoneSensitive,
            hasChildren: hasChildren
        )
    }

    private var motionEnabled: Bool { !reduceMotion && !reduceVisualEffects }

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

            if let quality {
                loadedContent(quality)
            } else if case .loading = state {
                Spacer()
                HeroSkeleton()
                Spacer()
                // The loaded hero's scroll hint, unseen, so the skeleton sits exactly where
                // the reading will and nothing jumps when it arrives.
                Image(systemName: "chevron.compact.down")
                    .font(.title2)
                    .padding(.bottom, DS.spacingXXXL)
                    .hidden()
            } else if case .error(let message) = state {
                Spacer()
                errorContent(message)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: DS.spacingMD) {
                    Image(systemName: "aqi.medium")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Checking the air…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.spacingXL)
        // The hero has exactly one screen of height; past this size its lines would
        // be cut off. The cards below carry on growing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: - Place

    /// The place, large, so each page is clearly somewhere. Other cities show their
    /// local time beside it.
    /// The current band's colour, nearly black, so the text's shadow belongs to the sky.
    private var shadowTint: Color {
        DS.shadowTint(quality.map { scale.displayReading(for: $0).reading.band.color })
    }

    private var placeHeader: some View {
        VStack(spacing: DS.spacingXXS) {
            HStack(spacing: DS.spacingSM) {
                if isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.footnote.weight(.semibold))
                        .accessibilityLabel("Your location:")
                }
                Text(placeName)
                    .multilineTextAlignment(.center)
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
        .skyTextShadow(tint: shadowTint)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, scale: scale, profile: healthProfile)
        let (shownScale, reading) = scale.displayReading(for: quality)

        Spacer()

        VStack(spacing: DS.spacingSM) {
            Text(guidance.verdict)
                .font(.title.weight(.bold))
                .kerning(-0.4)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.spacingLG)
                .riseIn(readingShown || !motionEnabled)
                .animation(DS.Motion.entrance(), value: readingShown)

            Button {
                showingScale = true
            } label: {
                Text("\(reading.value)")
                    .font(.system(size: min(numberSize, 150), weight: .thin, design: .rounded))
                    .monospacedDigit()
                    // Large numerals read tighter; scaled with the size so it holds at any Dynamic Type.
                    .kerning(-min(numberSize, 150) * 0.03)
                    .contentTransition(.numericText(value: Double(reading.value)))
                    .animation(DS.Motion.standard, value: reading.value)
            }
            .buttonStyle(.pressable)
            .riseIn(readingShown || !motionEnabled)
            .animation(DS.Motion.entrance(delay: 0.09), value: readingShown)
            .accessibilityLabel("\(shownScale.accessibilityName): \(reading.value), \(reading.band.longName). Lower is better.")
            .accessibilityHint("Explains the scale")

            // Without the standard and direction, "82" means nothing to newcomers.
            if launchCount <= Self.captionLaunches {
                Text(shownScale.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    // Wraps rather than truncating "Lower is better" at large text sizes.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -DS.spacingSM)
                    .riseIn(readingShown || !motionEnabled)
                    .animation(DS.Motion.entrance(delay: 0.16), value: readingShown)
                    .accessibilityHidden(true)
            }

            Text(reading.dominantPollutant.map { "\(reading.band.name) · \($0.displayName)" } ?? reading.band.name)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .riseIn(readingShown || !motionEnabled)
                .animation(DS.Motion.entrance(delay: 0.22), value: readingShown)

            Text(SourceDescription.text(for: quality, scale: scale))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .riseIn(readingShown || !motionEnabled)
                .animation(DS.Motion.entrance(delay: 0.28), value: readingShown)
        }
        // The first reading rises in once, line by line; later readings just update.
        .onAppear { readingShown = true }
        .foregroundStyle(.white)
        .skyTextShadow(tint: shadowTint)
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
            .padding(.bottom, DS.spacingXXXL)
            .accessibilityHidden(true)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(_ message: String) -> some View {
        VStack(spacing: DS.spacingMD) {
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

/// The hero's shape before the first reading: the verdict, the number and the two
/// lines under it, as soft placeholders in the same places, so the reading resolves
/// into a layout that's already there instead of replacing a spinner.
private struct HeroSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 96

    var body: some View {
        // Same spacing and near-same heights as the loaded verdict, number and lines.
        VStack(spacing: DS.spacingSM) {
            bar(width: 220, height: 30)
            bar(width: 128, height: min(numberSize, 150) * 0.85)
                .padding(.vertical, DS.spacingXS)
            bar(width: 150, height: 18)
            bar(width: 180, height: 14)
        }
        // Without a trigger the phases loop for as long as the skeleton shows.
        .phaseAnimator([false, true]) { content, lit in
            content.opacity(reduceMotion ? 0.6 : (lit ? 0.8 : 0.45))
        } animation: { _ in
            // The skeleton's own slow breath; linear because it never stops.
            .linear(duration: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the air quality")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(height / 2, DS.cornerRadiusSM))
            .fill(.white.opacity(0.18))
            .frame(width: width, height: height)
    }
}
