import SwiftUI
import Charts
import AirTodayCore

/// Swift Charts area graph with AQI threshold lines and pollutant picker.
public struct ForecastGraphCard: View {
    let forecasts: [DailyForecast]
    let dominantPollutant: Pollutant.Kind
    let currentAQI: Int
    @State private var selectedPollutant: Pollutant.Kind

    private let analyzer = ForecastAnalyzer()

    public init(forecasts: [DailyForecast], dominantPollutant: Pollutant.Kind, currentAQI: Int) {
        self.forecasts = forecasts
        self.dominantPollutant = dominantPollutant
        self.currentAQI = currentAQI
        _selectedPollutant = State(initialValue: dominantPollutant)
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

            if availablePollutants.count > 1 {
                Picker("Pollutant", selection: $selectedPollutant) {
                    ForEach(availablePollutants) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.cardHeaderTop)
        .padding(.bottom, DS.cardHeaderBottom)
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
                .foregroundStyle(.white.opacity(0.15))

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("AQI", point.avg)
                )
                .foregroundStyle(.white.opacity(DS.opacityPrimary))
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
