import SwiftUI
import Charts
import AirTodayCore

/// Swift Charts area graph with AQI threshold lines and a pollutant pill strip.
public struct ForecastGraphCard: View {
    let forecasts: [DailyForecast]
    /// The pollutant driving today's AQI, if WAQI names one.
    let dominantPollutant: Pollutant.Kind?
    let currentAQI: Int
    /// Today's level colour, threaded quietly through the chart.
    let accent: Color
    /// Values and threshold lines are drawn on this scale.
    let scale: AQIScale
    @State private var selectedPollutant: Pollutant.Kind

    private let analyzer = ForecastAnalyzer()

    public init(
        forecasts: [DailyForecast],
        dominantPollutant: Pollutant.Kind?,
        currentAQI: Int,
        accent: Color,
        scale: AQIScale = .usEPA
    ) {
        self.forecasts = forecasts
        self.dominantPollutant = dominantPollutant
        self.currentAQI = currentAQI
        self.accent = accent
        self.scale = scale
        _selectedPollutant = State(initialValue: Self.defaultSelection(forecasts: forecasts, dominant: dominantPollutant))
    }

    /// The dominant pollutant when it has a forecast. WAQI only forecasts PM2.5,
    /// PM10 and O₃, so when NO₂/SO₂/CO drives today's AQI this falls back to the
    /// first forecast pollutant instead of an empty chart.
    private static func defaultSelection(forecasts: [DailyForecast], dominant: Pollutant.Kind?) -> Pollutant.Kind {
        let forecastKinds = Set(forecasts.map(\.pollutant))
        return dominant.flatMap { forecastKinds.contains($0) ? $0 : nil }
            ?? Pollutant.Kind.allCases.first { forecastKinds.contains($0) }
            ?? .pm25
    }

    private var availablePollutants: [Pollutant.Kind] {
        let kinds = Set(forecasts.map(\.pollutant))
        return Pollutant.Kind.allCases.filter { kinds.contains($0) }
    }

    /// The selected pollutant's forecast, converted to the chosen scale.
    private var chartPoints: [ForecastPoint] {
        analyzer.forecastPoints(from: forecasts)
            .filter { $0.pollutant == selectedPollutant }
            .sorted { $0.date < $1.date }
            .map { point in
                let convert = { (aqi: Int) in
                    Int((scale.subIndex(for: point.pollutant, epaAQI: Double(aqi)) ?? Double(aqi)).rounded())
                }
                return ForecastPoint(
                    pollutant: point.pollutant,
                    date: point.date,
                    avg: convert(point.avg),
                    min: convert(point.min),
                    max: convert(point.max)
                )
            }
    }

    private var improvement: String? {
        analyzer.improvementSummary(
            forecasts: forecasts,
            currentAQI: currentAQI,
            pollutant: selectedPollutant
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            chartSection
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .background { DS.cardBackground }
        // New data (a refresh, or GPS replacing the IP lookup) can change what
        // drives the AQI; the chart should open on that pollutant again.
        .onChange(of: dominantPollutant) {
            selectedPollutant = Self.defaultSelection(forecasts: forecasts, dominant: dominantPollutant)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            HStack {
                Text("Forecast")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if let improvement {
                    Text(improvement)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, DS.spacingSM)
                        .padding(.vertical, DS.spacingXS)
                        .background(.green.opacity(0.15), in: Capsule())
                }
            }

            pollutantStrip
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.cardHeaderTop)
        .padding(.bottom, DS.cardHeaderBottom)
    }

    // MARK: - Pollutant Strip

    private var pollutantStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.spacingSM) {
                ForEach(availablePollutants) { kind in
                    pollutantPill(kind)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func pollutantPill(_ kind: Pollutant.Kind) -> some View {
        let isSelected = kind == selectedPollutant
        let isDominant = kind == dominantPollutant

        return Button {
            withAnimation(DS.Motion.quick) { selectedPollutant = kind }
        } label: {
            HStack(spacing: 6) {
                if isDominant {
                    // Marks the pollutant driving today's AQI.
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                }
                Text(kind.displayName)
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 1 : DS.opacitySecondary))
            .padding(.horizontal, DS.spacingMD)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.2 : 0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(isSelected ? 0.35 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected) { _, new in new }
        .accessibilityLabel(isDominant ? "\(kind.description), driving today's AQI" : kind.description)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Chart

    private var chartSection: some View {
        Chart {
            ForEach(chartPoints) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    yStart: .value("Min", point.min),
                    yEnd: .value("Max", point.max)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.32), accent.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Each day's PointMark carries the spoken summary.
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("AQI", point.avg)
                )
                .foregroundStyle(accent.mix(with: .white, by: 0.6).opacity(DS.opacityPrimary))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .accessibilityHidden(true)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("AQI", point.avg)
                )
                .foregroundStyle(scale.band(forValue: Double(point.avg)).color)
                .symbolSize(24)
                .accessibilityLabel(Self.fullDayFormatter.string(from: point.date))
                .accessibilityValue("\(scale.shortName) \(point.avg), \(scale.band(forValue: Double(point.avg)).longName). Range \(point.min) to \(point.max).")
            }

            // Band boundaries for the chosen scale
            ForEach(scale.chartThresholds, id: \.label) { threshold in
                thresholdRule(at: threshold.value, label: threshold.label, color: threshold.color)
            }
        }
        .chartYScale(domain: 0...chartYMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(Self.shortDayFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(DS.opacityDivider))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let intVal = value.as(Int.self) {
                        Text("\(intVal)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    }
                }
            }
        }
        .frame(height: 180)
        .padding(.leading, DS.spacingLG)
        .padding(.trailing, DS.spacingLG + 8)
        .padding(.bottom, DS.spacingLG)
    }

    @ChartContentBuilder
    private func thresholdRule(at value: Double, label: String, color: Color) -> some ChartContent {
        RuleMark(y: .value(label, value))
            .accessibilityHidden(true)
            .foregroundStyle(color.opacity(DS.opacityTertiary))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color.opacity(DS.opacitySecondary))
                    .padding(.leading, 4)
            }
    }

    /// Room above the highest forecast, never lower than the scale's top threshold line.
    private var chartYMax: Double {
        let highest = Double(chartPoints.map(\.max).max() ?? 0)
        switch scale {
        case .usEPA: return max(highest + 20, scale.chartMinimumTop)
        case .euCAQI: return max(highest + 10, scale.chartMinimumTop)
        case .ukDAQI: return max(highest, scale.chartMinimumTop)
        }
    }

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEEE"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()
}
