import Foundation

/// The cleanest two hours of daylight left in a day, from the hourly model forecast
/// on the chosen scale.
public struct BestWindow: Equatable, Sendable {
    public enum Timing: Equatable, Sendable {
        /// Good the whole time — no need to plan around it.
        case anyTime
        case window(start: Date, end: Date)
    }

    public let timing: Timing
    /// Start of the place's local day the window is on.
    public let day: Date
    /// Severity during the window (or across the day, for `anyTime`).
    public let level: AQILevel
    /// The worst hour of the day's remaining daylight.
    public let dayWorstLevel: AQILevel
    /// The place's offset from GMT, for formatting times in local time.
    public let utcOffsetSeconds: Int

    /// Daylight for planning purposes, in the place's local hours.
    static let daylight = 6..<21
    static let windowHours = 2

    public var start: Date? {
        if case .window(let start, _) = timing { return start }
        return nil
    }

    /// "Any time", "7–9 AM", "11 AM–1 PM".
    public var headline: String {
        switch timing {
        case .anyTime:
            return "Any time"
        case .window(let start, let end):
            return Self.format(start, end, utcOffsetSeconds: utcOffsetSeconds)
        }
    }

    /// "today" or "tomorrow", in the place's time.
    public func dayName(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
        return calendar.isDate(day, inSameDayAs: now) ? "today" : "tomorrow"
    }

    public var detail: String {
        switch timing {
        case .anyTime:
            return "Air should stay good all day."
        case .window:
            let base = level == dayWorstLevel
                ? "Little change today — this is as clean as it gets."
                : "The cleanest air left today."
            // A better hour on a bad day is still a bad day.
            return level.rawValue >= AQILevel.unhealthy.rawValue
                ? "\(base) Even then it's \(level.label.lowercased()) — keep it brief."
                : base
        }
    }

    /// The best window in what's left of `day`'s daylight (the place's local day).
    /// Nil without model data or with under two daylight hours left.
    public static func on(_ day: Date, for quality: AirQuality, scale: AQIScale, now: Date) -> BestWindow? {
        guard let model = quality.model else { return nil }
        let calendar = model.calendar
        let shownScale = scale.reading(for: quality) == nil ? AQIScale.usEPA : scale

        let hours = shownScale.hourlySeries(for: quality, now: now).filter { point in
            calendar.isDate(point.time, inSameDayAs: day)
                && daylight.contains(calendar.component(.hour, from: point.time))
                && point.time.addingTimeInterval(3600) > now
        }
        guard hours.count >= windowHours else { return nil }

        let severities = hours.map { Severity.position(of: $0.value, on: shownScale) }
        let dayWorst = Severity.level(at: severities.max() ?? 0)
        let startOfDay = calendar.startOfDay(for: day)

        if dayWorst == .good {
            return BestWindow(timing: .anyTime, day: startOfDay, level: .good, dayWorstLevel: .good, utcOffsetSeconds: model.utcOffsetSeconds)
        }

        // The pair of consecutive hours with the lowest worse-hour; earliest on a tie.
        var best = 0
        for i in 0...(hours.count - windowHours) {
            let worst = severities[i..<(i + windowHours)].max() ?? 0
            let bestWorst = severities[best..<(best + windowHours)].max() ?? 0
            if worst < bestWorst { best = i }
        }
        let start = hours[best].time
        return BestWindow(
            timing: .window(start: start, end: start.addingTimeInterval(TimeInterval(windowHours * 3600))),
            day: startOfDay,
            level: Severity.level(at: severities[best..<(best + windowHours)].max() ?? 0),
            dayWorstLevel: dayWorst,
            utcOffsetSeconds: model.utcOffsetSeconds
        )
    }

    /// Today's window, or tomorrow's once today's daylight has run out.
    public static func next(for quality: AirQuality, scale: AQIScale, now: Date = Date()) -> BestWindow? {
        if let today = on(now, for: quality, scale: scale, now: now) { return today }
        guard let tomorrow = quality.model?.calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return on(tomorrow, for: quality, scale: scale, now: now)
    }

    static func format(_ start: Date, _ end: Date, utcOffsetSeconds: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
        let a = calendar.component(.hour, from: start)
        let b = calendar.component(.hour, from: end)
        func hour12(_ h: Int) -> Int { h % 12 == 0 ? 12 : h % 12 }
        func suffix(_ h: Int) -> String { h < 12 ? "AM" : "PM" }
        return suffix(a) == suffix(b)
            ? "\(hour12(a))–\(hour12(b)) \(suffix(b))"
            : "\(hour12(a)) \(suffix(a))–\(hour12(b)) \(suffix(b))"
    }
}
