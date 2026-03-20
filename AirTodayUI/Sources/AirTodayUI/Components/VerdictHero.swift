import SwiftUI
import AirTodayCore

/// Hero section: verdict as primary readout, AQI number secondary.
public struct VerdictHero: View {
    let quality: AirQuality?
    let state: LoadingState
    let lastRefreshed: Date?
    let heroOpacity: Double
    let hasScrolled: Bool
    let onRetry: () async -> Void

    private static let guidanceService = ActivityGuidanceService()

    public init(
        quality: AirQuality?,
        state: LoadingState,
        lastRefreshed: Date?,
        heroOpacity: Double,
        hasScrolled: Bool,
        onRetry: @escaping () async -> Void
    ) {
        self.quality = quality
        self.state = state
        self.lastRefreshed = lastRefreshed
        self.heroOpacity = heroOpacity
        self.hasScrolled = hasScrolled
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

        // === ZONE 1: Air Quality (top) ===
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quality.level.verdict). Air Quality Index \(quality.aqi), \(quality.level.label)")

        Spacer()

        // === ZONE 2: Conditions (middle) ===
        conditionsRow(quality.weather)

        Spacer()

        // === ZONE 3: Location + swipe hint (bottom) ===
        VStack(spacing: 8) {
            Text(quality.station.name)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            if let lastRefreshed {
                Text(Self.updatedText(lastRefreshed))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }

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
        Spacer().frame(maxHeight: 20)
    }

    @ViewBuilder
    private func conditionsRow(_ weather: Weather) -> some View {
        let items = Self.conditionItems(
            weather,
            uviForecast: quality?.uviForecast ?? [],
            quality: quality
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
        uviForecast: [UVIForecastPoint],
        quality: AirQuality?
    ) -> [(icon: String, value: String, label: String)] {
        var items: [(icon: String, value: String, label: String)] = []

        // 1. Local city time
        if let tzOffset = quality?.timeZoneOffset {
            let localTime = SunCalculator.localTime(timeZoneOffset: tzOffset)
            items.append(("clock.fill", localTime, "Local"))
        }

        // 2. Temperature
        if let temp = weather.temperature {
            items.append(("thermometer.medium", "\(Int(temp))°", "Temp"))
        }

        // 3. UV Index (peak for today, 0 after sunset)
        if let todayUVI = uviForecast.first(where: { guard let d = $0.date else { return false }; return Calendar.current.isDateInToday(d) }) {
            let isNight: Bool = {
                guard let quality, let tzOffset = quality.timeZoneOffset else { return false }
                let lat = quality.station.coordinate.latitude
                let lng = quality.station.coordinate.longitude
                guard let sunset = SunCalculator.sunset(latitude: lat, longitude: lng, timeZoneOffset: tzOffset),
                      let sunrise = SunCalculator.sunrise(latitude: lat, longitude: lng, timeZoneOffset: tzOffset)
                else { return false }
                let now = Date()
                return now > sunset || now < sunrise
            }()
            let uvValue = isNight ? 0 : todayUVI.max
            items.append(("sun.max.fill", "\(uvValue)", "UV"))
        }

        // 4. Weather summary (derived from conditions)
        let (weatherIcon, weatherLabel) = Self.weatherSummary(weather, quality: quality)
        items.append((weatherIcon, weatherLabel, "Weather"))

        return items
    }

    /// Derive a simple weather summary from available data.
    private static func weatherSummary(_ weather: Weather, quality: AirQuality?) -> (icon: String, label: String) {
        // Check if it's currently nighttime at the station
        let isNight: Bool = {
            guard let quality, let tzOffset = quality.timeZoneOffset else { return false }
            let lat = quality.station.coordinate.latitude
            let lng = quality.station.coordinate.longitude
            guard let sunset = SunCalculator.sunset(latitude: lat, longitude: lng, timeZoneOffset: tzOffset),
                  let sunrise = SunCalculator.sunrise(latitude: lat, longitude: lng, timeZoneOffset: tzOffset)
            else { return false }
            let now = Date()
            return now > sunset || now < sunrise
        }()

        let humidity = weather.humidity ?? 0
        let wind = weather.windSpeed ?? 0

        if humidity > 85 {
            return ("humidity.fill", "Humid")
        } else if humidity > 70 {
            return ("cloud.fill", "Overcast")
        } else if wind > 10 {
            return ("wind", "Windy")
        } else if isNight {
            return ("moon.stars.fill", "Clear Night")
        } else {
            return ("sun.max.fill", "Clear")
        }
    }

    private static func updatedText(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes == 1 { return "Updated 1 min ago" }
        return "Updated \(minutes) min ago"
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
