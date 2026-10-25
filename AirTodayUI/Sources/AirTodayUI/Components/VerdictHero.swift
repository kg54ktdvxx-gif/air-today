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
        let params = AtmosphereParameters(from: quality)
        let guidance = Self.guidanceService.guidance(for: quality)

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

            Text("\(quality.aqi)")
                .font(.system(size: 96, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(quality.aqi)))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .padding(.top, 4)
                .animation(
                    .spring(response: params.springResponse, dampingFraction: params.springDamping),
                    value: quality.aqi
                )

            // Without the standard and direction, "82" means nothing to most people.
            Text("US EPA AQI · Scale 0–500 · Lower is better")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .padding(.top, -6)

            HStack(spacing: 8) {
                Text(quality.level.shortLabel)
                if let dominant = quality.dominantPollutant {
                    Text("·")
                    Text(dominant.displayName)
                }
            }
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .padding(.top, 4)

            // Conditions inline below AQI
            conditionsRow(quality.weather)
                .padding(.top, 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(guidance.verdict). US EPA Air Quality Index \(quality.aqi) out of 500, \(quality.level.label). Lower is better.")

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
                .symbolEffect(.pulse, isActive: !hasScrolled)
                .opacity(hasScrolled ? 0 : 1)
                .animation(.easeOut(duration: 0.5), value: hasScrolled)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private func conditionsRow(_ weather: Weather) -> some View {
        let items = Self.conditionItems(
            weather,
            quality: quality,
            temperatureUnit: temperatureUnit
        )
        if !items.isEmpty {
            HStack(spacing: 24) {
                ForEach(items, id: \.label) { item in
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                        Text(item.value)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text(item.label)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.75))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
    }

    private static func conditionItems(
        _ weather: Weather,
        quality: AirQuality?,
        temperatureUnit: TemperatureUnit
    ) -> [(icon: String, value: String, label: String)] {
        var items: [(icon: String, value: String, label: String)] = []

        // 1. Local city time
        if let tzOffset = quality?.timeZoneOffset {
            let localTime = SunCalculator.localTime(timeZoneOffset: tzOffset)
            items.append(("clock.fill", localTime, "Local"))
        }

        // 2. Temperature
        if let temp = weather.temperature {
            items.append(("thermometer.medium", temperatureUnit.format(celsius: temp), "Temp"))
        }

        // 3. Wind (if notable)
        if let wind = weather.windSpeed, wind >= 3.0 {
            items.append(("wind", String(format: "%.0f m/s", wind), "Wind"))
        }

        return items
    }

    /// "Updated 12 min ago · 2.4 km away" — how fresh and how local the reading is.
    private static func freshnessText(measuredAt: Date, distance: Double?) -> String {
        let updated = updatedText(measuredAt)
        guard let distance else { return updated }
        let formatted = Measurement(value: distance, unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1)))
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
            Image(systemName: "wifi.exclamationmark")
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
