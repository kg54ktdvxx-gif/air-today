import SwiftUI
import AirTodayCore

/// Hero section: verdict as primary readout, AQI number secondary.
public struct VerdictHero: View {
    let quality: AirQuality?
    let state: LoadingState
    let heroOpacity: Double
    let hasScrolled: Bool
    /// Metres from the device to the reporting station; nil for saved cities
    /// (their coordinate is the station itself) or without a location fix.
    let distanceFromUser: Double?
    let onRetry: () async -> Void

    @AppStorage(AppConstants.temperatureUnitKey, store: .shared)
    private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage(AQIScale.storageKey, store: .shared)
    private var scale: AQIScale = .usEPA
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HealthProfile.Key.respiratory, store: .shared) private var hasRespiratoryCondition = false
    @AppStorage(HealthProfile.Key.ozoneSensitive, store: .shared) private var isOzoneSensitive = false
    @AppStorage(HealthProfile.Key.children, store: .shared) private var hasChildren = false

    private var healthProfile: HealthProfile {
        HealthProfile(
            hasRespiratoryCondition: hasRespiratoryCondition,
            isOzoneSensitive: isOzoneSensitive,
            hasChildren: hasChildren
        )
    }

    private static let guidanceService = ActivityGuidanceService()

    public init(
        quality: AirQuality?,
        state: LoadingState,
        heroOpacity: Double,
        hasScrolled: Bool,
        distanceFromUser: Double? = nil,
        onRetry: @escaping () async -> Void
    ) {
        self.quality = quality
        self.state = state
        self.heroOpacity = heroOpacity
        self.hasScrolled = hasScrolled
        self.distanceFromUser = distanceFromUser
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 0) {
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
        .opacity(heroOpacity)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ quality: AirQuality) -> some View {
        let guidance = Self.guidanceService.guidance(for: quality, profile: healthProfile)
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

            Text("\(reading.value)")
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(reading.value)))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .padding(.top, 4)
                .animation(DS.Motion.standard, value: reading.value)
                .background { halo(reading.band.color) }

            // Without the standard and direction, "82" means nothing to most people.
            Text(shownScale.caption)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .padding(.top, -6)

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

            conditionsCapsule(quality)
                .padding(.top, 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(guidance.verdict). \(shownScale.accessibilityName): \(reading.value), \(reading.band.longName). Lower is better.")

        Spacer()

        // === ZONE 2: Location + swipe hint (bottom) ===
        VStack(spacing: 6) {
            Text(quality.station.name)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            Text(Self.freshnessText(measuredAt: quality.timestamp, distance: distanceFromUser))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

            Image(systemName: "chevron.compact.down")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .symbolEffect(.pulse, isActive: !hasScrolled && !reduceMotion)
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

    /// The station's local time and temperature in one quiet capsule.
    @ViewBuilder
    private func conditionsCapsule(_ quality: AirQuality) -> some View {
        let items = Self.conditionItems(quality, temperatureUnit: temperatureUnit)
        if !items.isEmpty {
            HStack(spacing: DS.spacingMD) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        Text(item.value)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.label): \(item.value)")
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(DS.opacityPrimary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
    }

    private static func conditionItems(
        _ quality: AirQuality,
        temperatureUnit: TemperatureUnit
    ) -> [(icon: String, value: String, label: String)] {
        var items: [(icon: String, value: String, label: String)] = []

        if let tzOffset = quality.timeZoneOffset {
            items.append(("clock.fill", SunCalculator.localTime(timeZoneOffset: tzOffset), "Local time"))
        }
        if let temp = quality.weather.temperature {
            items.append(("thermometer.medium", temperatureUnit.format(celsius: temp), "Temperature"))
        }
        return items
    }

    /// "Updated 12 min ago · 2.4 km away" — how fresh and how local the reading is.
    private static func freshnessText(measuredAt: Date, distance: Double?) -> String {
        let updated = updatedText(measuredAt)
        guard let distance else { return updated }
        // Station coordinates are approximate; "0 m" or "40 m" claims false precision.
        guard distance >= 100 else { return "\(updated) · under 100 m away" }
        // Short distances to the nearest 10 m ("660 m"), longer ones to a tenth ("2.4 km").
        let isShort = distance < 1_000
        let metres = isShort ? (distance / 10).rounded() * 10 : distance
        let formatted = Measurement(value: metres, unit: UnitLength.meters).formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(isShort ? 0...0 : 0...1))
            )
        )
        return "\(updated) · \(formatted) away"
    }

    /// `date` is when the station measured, not when the app fetched.
    private static func updatedText(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        return hours == 1 ? "Updated 1 hr ago" : "Updated \(hours) hr ago"
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
