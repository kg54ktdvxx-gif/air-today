import SwiftUI
import AirTodayCore

/// Hero section: the place, then the verdict as primary readout and the number secondary,
/// then where the reading came from.
public struct VerdictHero: View {
    let quality: AirQuality?
    let state: LoadingState
    let hasScrolled: Bool
    /// The page's place: the town (or "My Location") or the saved city's name.
    let placeName: String
    let isCurrentLocation: Bool
    /// Metres from the device to the reporting station; nil for saved cities
    /// (their coordinate is the station itself) or without a location fix.
    let distanceFromUser: Double?
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
        distanceFromUser: Double? = nil,
        onRetry: @escaping () async -> Void
    ) {
        self.quality = quality
        self.state = state
        self.hasScrolled = hasScrolled
        self.placeName = placeName
        self.isCurrentLocation = isCurrentLocation
        self.distanceFromUser = distanceFromUser
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
                        .font(.system(.footnote, weight: .semibold))
                        .accessibilityLabel("Your location:")
                }
                Text(placeName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(.title, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !isCurrentLocation, let offset = quality?.timeZoneOffset {
                TimelineView(.everyMinute) { _ in
                    Text(SunCalculator.localTime(timeZoneOffset: offset))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .accessibilityLabel("Local time \(SunCalculator.localTime(timeZoneOffset: offset))")
                }
            }
        }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, scale: scale, profile: healthProfile)
        let (shownScale, reading) = scale.displayReading(for: quality)

        Spacer()

        // === ZONE 1: Air Quality (vertically centered) ===
        VStack(spacing: 0) {
            Text(guidance.verdict)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.spacingLG)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Button {
                showingScale = true
            } label: {
                Text("\(reading.value)")
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(reading.value)))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    .animation(DS.Motion.standard, value: reading.value)
                    .background { halo(reading.band.color) }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("\(shownScale.accessibilityName): \(reading.value), \(reading.band.longName). Lower is better.")
            .accessibilityHint("Explains the scale")

            // Without the standard and direction, "82" means nothing to newcomers.
            if launchCount <= Self.captionLaunches {
                Text(shownScale.caption)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .padding(.top, -6)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                Text(reading.band.name)
                if let dominant = reading.dominantPollutant {
                    Text("·")
                    Text(dominant.displayName)
                }
            }
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
        .sheet(isPresented: $showingScale) {
            ScaleExplainerSheet(scale: shownScale, reading: reading)
        }

        Spacer()

        // === ZONE 2: Source + scroll hint (bottom) ===
        VStack(spacing: 6) {
            Text(SourceDescription.text(for: quality, distance: distanceFromUser, scale: scale))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

            Image(systemName: "chevron.compact.down")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .symbolEffect(.pulse, isActive: !hasScrolled && !reduceMotion && !reduceVisualEffects)
                .opacity(hasScrolled ? 0 : 1)
                .animation(DS.Motion.quick, value: hasScrolled)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 40)
    }

    /// A soft glow of the level colour behind the number, so the eye lands on the
    /// verdict and feels the colour at the same moment.
    private func halo(_ color: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.5), color.opacity(0.15), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 130
                )
            )
            .frame(width: 260, height: 260)
            .blur(radius: 16)
            .animation(DS.Motion.atmospheric, value: color)
            .allowsHitTesting(false)
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
