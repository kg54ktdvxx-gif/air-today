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
    @State private var selectedPollutant: Pollutant.Kind

    private let analyzer = ForecastAnalyzer()

    public init(forecasts: [DailyForecast], dominantPollutant: Pollutant.Kind?, currentAQI: Int, accent: Color) {
        self.forecasts = forecasts
        self.dominantPollutant = dominantPollutant
        self.currentAQI = currentAQI
        self.accent = accent
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

    private var chartPoints: [ForecastPoint] {
        analyzer.forecastPoints(from: forecasts)
            .filter { $0.pollutant == selectedPollutant }
            .sorted { $0.date < $1.date }
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

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("AQI", point.avg)
                )
                .foregroundStyle(accent.mix(with: .white, by: 0.6).opacity(DS.opacityPrimary))
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("AQI", point.avg)
                )
                .foregroundStyle(point.level.color)
                .symbolSize(24)
            }

            // Threshold lines
            thresholdRule(at: 50, label: "Good", color: .green)
            thresholdRule(at: 100, label: "Moderate", color: .yellow)
            thresholdRule(at: 150, label: "Sensitive", color: .orange)
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
    private func thresholdRule(at value: Int, label: String, color: Color) -> some ChartContent {
        RuleMark(y: .value(label, value))
            .foregroundStyle(color.opacity(DS.opacityTertiary))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color.opacity(DS.opacitySecondary))
                    .padding(.leading, 4)
            }
    }

    private var chartYMax: Int {
        let maxAQI = chartPoints.map(\.max).max() ?? 100
        return max(maxAQI + 20, 160)
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()
}
