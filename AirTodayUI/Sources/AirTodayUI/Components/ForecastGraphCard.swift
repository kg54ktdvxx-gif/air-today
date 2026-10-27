import SwiftUI
import Charts
import AirTodayCore

/// Each pollutant's index now, and the hourly forecast for today and tomorrow, then
/// each later day's worst, on the chosen scale — overall or for one pollutant.
public struct ForecastGraphCard: View {
    let quality: AirQuality
    let scale: AQIScale
    /// Today's band colour, threaded quietly through the chart.
    let accent: Color
    let now: Date
    /// Whether the chart draws itself in, left to right, when it first comes into view.
    let drawsIn: Bool
    /// Nil is the overall index.
    @State private var selectedPollutant: Pollutant.Kind?
    /// How much of the plot is drawn, 0 to 1.
    @State private var drawn: CGFloat = 0

    public init(quality: AirQuality, scale: AQIScale, accent: Color, now: Date = Date(), drawsIn: Bool = false) {
        self.quality = quality
        self.scale = scale
        self.accent = accent
        self.now = now
        self.drawsIn = drawsIn
    }

    private var model: ModelAirData? { quality.model }
    private var calendar: Calendar { model?.calendar ?? .current }

    /// The end of tomorrow in the place's time.
    private var hourlyEnd: Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now
    }

    private var series: [(time: Date, value: Int)] {
        scale.hourlySeries(for: quality, pollutant: selectedPollutant, now: now)
    }

    private var hourlyPoints: [(time: Date, value: Int)] {
        series.filter { $0.time < hourlyEnd }
    }

    /// Each later day's worst hour, for days with most of their hours forecast.
    private var laterDays: [(day: Date, value: Int)] {
        let later = series.filter { $0.time >= hourlyEnd }
        let byDay = Dictionary(grouping: later) { calendar.startOfDay(for: $0.time) }
        return byDay
            .filter { $0.value.count >= 12 }
            .map { (day: $0.key, value: $0.value.map(\.value).max() ?? 0) }
            .sorted { $0.day < $1.day }
    }

    /// Every 6 hours on the place's clock (midnight, 6, noon, 18) across the hourly range.
    private var axisDates: [Date] {
        let start = calendar.startOfDay(for: now)
        return (0...8).compactMap { calendar.date(byAdding: .hour, value: $0 * 6, to: start) }
            .filter { $0 >= (hourlyPoints.first?.time ?? now) && $0 <= hourlyEnd }
    }

    /// When the headline is a station's measurement and the model's estimate for the
    /// hour falls in another band, says so — otherwise the chart seems to contradict
    /// the number above it.
    private var sourceNote: String? {
        guard selectedPollutant == nil,
              quality.source == .station,
              scale == .usEPA,
              let modelNow = hourlyPoints.first?.value,
              scale.band(forValue: modelNow).name != scale.band(forValue: quality.aqi).name
        else { return nil }
        return "The forecast is an estimate for the wider area: \(modelNow) now, where the station measures \(quality.aqi)."
    }

    /// The scale's pollutants with a reading now or a forecast, in display order.
    private var availablePollutants: [Pollutant.Kind] {
        let upcoming = model?.upcoming(from: now) ?? []
        let forecast: Set<Pollutant.Kind> = switch scale {
        case .usEPA: Set(upcoming.flatMap(\.usSubIndices.keys))
        case .euEAQI: Set(upcoming.flatMap(\.europeanSubIndices.keys))
        case .ukDAQI: Set(upcoming.flatMap(\.concentrations.keys))
        }
        return Pollutant.Kind.allCases.filter {
            scale.pollutants.contains($0) && (forecast.contains($0) || scale.subIndex(for: $0, in: quality) != nil)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            if model == nil {
                Text("The forecast isn't available right now.")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    .padding(.horizontal, DS.spacingLG)
                    .padding(.bottom, DS.spacingLG)
            } else {
                chartSection
                if !laterDays.isEmpty {
                    laterDaysRow
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .background { DS.cardBackground }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            Text("Forecast")
                .font(DS.Typeface.cardTitle)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                HStack(spacing: DS.spacingSM) {
                    pill("Overall", value: scale.reading(for: quality)?.value, selected: selectedPollutant == nil, accessibility: "Overall \(scale.shortName)") {
                        selectedPollutant = nil
                    }
                    ForEach(availablePollutants) { kind in
                        pill(kind.displayName, value: scale.subIndex(for: kind, in: quality), selected: selectedPollutant == kind, accessibility: kind.description) {
                            selectedPollutant = kind
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if let sourceNote {
                Text(sourceNote)
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.top, DS.cardHeaderTop)
        .padding(.bottom, DS.cardHeaderBottom)
    }

    /// A pollutant (or the overall index) with its value now, so the pills double as
    /// the list of pollutants.
    private func pill(_ title: String, value: Int?, selected: Bool, accessibility: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.quick) { action() }
        } label: {
            HStack(spacing: DS.spacingSM) {
                if let value {
                    DS.colorDot(scale.band(forValue: value).color, size: 6)
                }
                Text(title)
                if let value {
                    Text("\(value)")
                        .monospacedDigit()
                }
            }
            .font(DS.Typeface.captionStrong)
            .foregroundStyle(.white.opacity(selected ? 1 : DS.opacitySecondary))
            .padding(.horizontal, DS.spacingMD)
            .padding(.vertical, DS.spacingSM)
            .background(Capsule().fill(selected ? DS.selectedFill : DS.chipFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new }
        .accessibilityLabel(value.map { "\(accessibility), \($0), \(scale.band(forValue: $0).longName)" } ?? accessibility)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Chart

    private var chartSection: some View {
        let points = hourlyPoints
        return Chart {
            ForEach(points, id: \.time) { point in
                AreaMark(
                    x: .value("Hour", point.time),
                    yStart: .value("Base", 0),
                    yEnd: .value(scale.compactName, point.value)
                )
                .interpolationMethod(.monotone)
                // A flat tint: backgrounds carry no gradients; the line carries the shape.
                .foregroundStyle(accent.opacity(0.16))

                LineMark(
                    x: .value("Hour", point.time),
                    y: .value(scale.compactName, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent.mix(with: .white, by: 0.6).opacity(DS.opacityPrimary))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Only two points are labelled: now, and the worst hour if it's later. "Now"
            // carries no number: the chart is the area forecast, and the headline above
            // may be a station's measurement.
            if let first = points.first {
                PointMark(x: .value("Hour", first.time), y: .value(scale.compactName, first.value))
                    .foregroundStyle(scale.band(forValue: first.value).color)
                    .symbolSize(40)
                    .annotation(position: .top, spacing: DS.spacingXS, overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        chartLabel("Now")
                    }
            }
            if let peak = points.max(by: { $0.value < $1.value }), peak.time != points.first?.time {
                PointMark(x: .value("Hour", peak.time), y: .value(scale.compactName, peak.value))
                    .foregroundStyle(scale.band(forValue: peak.value).color)
                    .symbolSize(30)
                    .annotation(position: .top, spacing: DS.spacingXS, overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        chartLabel("\(peak.value) at \(ActivityGuidanceService.hourText(peak.time, calendar: calendar))")
                    }
            }

            // Band boundaries for the chosen scale. Their names sit outside the plot (the
            // y-axis below), so they can't collide with the "Now" and peak labels.
            ForEach(scale.chartThresholds, id: \.label) { threshold in
                RuleMark(y: .value(threshold.label, threshold.value))
                    .foregroundStyle(threshold.color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .chartYScale(domain: 0...chartYMax(points))
        // The plot (line, fill, band lines) wipes in left to right like a progress bar.
        .chartPlotStyle { plot in
            plot.mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * (drawsIn ? drawn : 1))
                }
            }
        }
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            guard visible, drawn == 0 else { return }
            withAnimation(DS.Motion.draw.delay(0.25)) { drawn = 1 }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(axisLabel(date))
                            .font(DS.Typeface.fine)
                            .foregroundStyle(.white.opacity(calendar.component(.hour, from: date) == 0 ? DS.opacityPrimary : DS.opacityTertiary))
                    }
                }
            }
        }
        // No numbers or gridlines: only the band names, beside their lines.
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.chartThresholds.map(\.value)) { value in
                AxisValueLabel {
                    if let threshold = scale.chartThresholds.first(where: { $0.value == value.as(Double.self) }) {
                        Text(threshold.label)
                            .font(DS.Typeface.fine)
                            .foregroundStyle(threshold.color.opacity(DS.opacitySecondary))
                    }
                }
            }
        }
        // Hours and day boundaries in the place's own time.
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .frame(height: 180)
        .padding(.horizontal, DS.spacingLG)
        .padding(.bottom, DS.spacingLG)
        // A chart's labels have fixed room; past this size they'd overlap. The values
        // are all in the accessibility summary, and in the pills and later days.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hourly forecast, today and tomorrow")
        .accessibilityValue(Self.summary(points, scale: scale, calendar: calendar))
    }

    private func chartLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typeface.fine.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(DS.opacityPrimary))
    }

    /// "6 AM", "12 PM", and the weekday at midnight.
    private func axisLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        style = calendar.component(.hour, from: date) == 0 ? style.weekday(.abbreviated) : style.hour()
        return date.formatted(style)
    }

    /// Room above the highest forecast, never lower than the scale's top threshold line.
    private func chartYMax(_ points: [(time: Date, value: Int)]) -> Double {
        let highest = Double(points.map(\.value).max() ?? 0)
        switch scale {
        case .usEPA: return max(highest + 20, scale.chartMinimumTop)
        case .euEAQI: return max(highest + 10, scale.chartMinimumTop)
        case .ukDAQI: return max(highest, scale.chartMinimumTop)
        }
    }

    /// The spoken version: the range and when the worst and best hours are.
    static func summary(_ points: [(time: Date, value: Int)], scale: AQIScale, calendar: Calendar) -> String {
        guard let worst = points.max(by: { $0.value < $1.value }),
              let best = points.min(by: { $0.value < $1.value })
        else { return "No forecast" }
        func when(_ date: Date) -> String {
            let day = calendar.isDate(date, inSameDayAs: points[0].time) ? "today" : "tomorrow"
            return "\(ActivityGuidanceService.hourText(date, calendar: calendar)) \(day)"
        }
        return "Highest \(worst.value), \(scale.band(forValue: worst.value).longName), at \(when(worst.time)). Lowest \(best.value) at \(when(best.time))."
    }

    // MARK: - Later days

    private var laterDaysRow: some View {
        VStack(spacing: 0) {
            DS.divider
            HStack(spacing: 0) {
                ForEach(laterDays, id: \.day) { day in
                    let band = scale.band(forValue: day.value)
                    VStack(spacing: DS.spacingXS) {
                        Text(day.day.formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)))
                            .font(DS.Typeface.fine.weight(.semibold))
                            .foregroundStyle(.white.opacity(DS.opacitySecondary))
                        HStack(spacing: DS.spacingXS) {
                            DS.colorDot(band.color)
                            Text("\(day.value)")
                                .font(DS.Typeface.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        Text(band.name)
                            .font(DS.Typeface.fine)
                            .foregroundStyle(.white.opacity(DS.opacityTertiary))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.day.formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)))
                    .accessibilityValue("At worst \(day.value), \(band.longName)")
                }
            }
            .padding(.vertical, DS.spacingMD)
            .padding(.horizontal, DS.spacingSM)
            // Three columns share the card's width; past this, band names break mid-word.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            Text("Later days show each day's worst hour.")
                .font(DS.Typeface.fine)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))
                .padding(.bottom, DS.spacingMD)
        }
    }
}
