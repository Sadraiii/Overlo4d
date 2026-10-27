import Foundation

/// A day's weight, from the app or Apple Health.
public struct WeightPoint: Hashable, Sendable {
    public let day: DayKey
    public let kg: Double

    public init(day: DayKey, kg: Double) {
        self.day = day
        self.kg = kg
    }
}

public enum WeightLog {
    /// One weight per day, oldest first. Weights logged in the app win over Health on the same day,
    /// and the last Health reading of a day wins over earlier ones.
    public static func merge(health: [(date: Date, kg: Double)], logged: [DayKey: Double], calendar: Calendar = .current) -> [WeightPoint] {
        var byDay: [DayKey: Double] = [:]
        for reading in health.sorted(by: { $0.date < $1.date }) {
            byDay[DayKey(reading.date, calendar: calendar)] = reading.kg
        }
        for (day, kg) in logged { byDay[day] = kg }
        return byDay.map { WeightPoint(day: $0.key, kg: $0.value) }.sorted { $0.day < $1.day }
    }

    /// Change in kg per week over the last `days` days, by least squares. Nil with too little data
    /// (fewer than three weights, or less than a week between the first and last).
    public static func weeklyTrend(_ points: [WeightPoint], endingOn today: DayKey, days: Int = 28, calendar: Calendar = .current) -> Double? {
        let start = today.adding(days: -days, calendar: calendar)
        let recent = points.filter { $0.day > start && $0.day <= today }
        guard recent.count >= 3, let first = recent.first else { return nil }
        let origin = first.day.date(calendar: calendar)
        let xs = recent.map { $0.day.date(calendar: calendar).timeIntervalSince(origin) / 86_400 }
        guard let span = xs.last, span >= 7 else { return nil }
        let ys = recent.map(\.kg)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return nil }
        return numerator / denominator * 7
    }
}

/// How far along the way to the goal weight you are.
public struct WeightProgress: Equatable, Sendable {
    public let start: Double
    public let current: Double
    public let target: Double
    public let weeklyRate: Double

    public init(start: Double, current: Double, target: Double, weeklyRate: Double) {
        self.start = start
        self.current = current
        self.target = target
        self.weeklyRate = weeklyRate
    }

    /// Kilograms still to lose (negative) or gain (positive).
    public var remaining: Double { target - current }

    private var losing: Bool { target < start }

    public var isReached: Bool {
        losing ? current <= target : current >= target
    }

    /// Share of the way from the start weight to the target, 0...1.
    public var fraction: Double {
        let total = start - target
        guard abs(total) > 0.05 else { return isReached ? 1 : 0 }
        return min(max((start - current) / total, 0), 1)
    }

    /// When the target is reached at the planned weekly rate. Nil once reached.
    public func projectedDate(from now: Date, calendar: Calendar = .current) -> Date? {
        guard !isReached, weeklyRate > 0 else { return nil }
        let days = Int((abs(remaining) / weeklyRate * 7).rounded(.up))
        return calendar.date(byAdding: .day, value: days, to: now)
    }
}

extension FoodDiary {
    /// What was eaten over the last `days` days, as lines for the AI coach. Empty when nothing was logged.
    public func coachLines(today: DayKey, days: Int = 7, weights: [WeightPoint] = [], calendar: Calendar = .current) -> [String] {
        let logged = (0..<days).map { today.adding(days: -$0, calendar: calendar) }.filter { !entries(on: $0).isEmpty }
        guard !logged.isEmpty else { return [] }
        let goal = self.goal
        func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }

        var plan = "Goal: \(Int(goal.kcal.rounded())) kcal a day, carbs \(grams(goal.carbs)), protein \(grams(goal.protein)), fat \(grams(goal.fat))"
        if let profile {
            switch profile.goal {
            case .lose: plan += "; aiming to lose \(profile.weeklyRateKg.formatted()) kg a week"
            case .gain: plan += "; aiming to gain \(profile.weeklyRateKg.formatted()) kg a week"
            case .maintain: plan += "; keeping weight"
            }
            if let target = profile.targetKg { plan += " to \(target.formatted()) kg" }
        }
        var lines = [plan + "."]

        if let latest = weights.last {
            var line = "Weight: \(latest.kg.formatted(.number.precision(.fractionLength(0...1)))) kg on \(latest.day)"
            if let trend = WeightLog.weeklyTrend(weights, endingOn: today, calendar: calendar) {
                line += ", trend \(trend >= 0 ? "+" : "")\(trend.formatted(.number.precision(.fractionLength(1)))) kg a week"
            }
            lines.append(line + ".")
        }

        for day in logged {
            let summary = summary(for: day)
            var line = "\(day)\(day == today ? " (today, so far)" : ""): \(Int(summary.eaten.kcal.rounded())) kcal"
            line += ", protein \(grams(summary.eaten.protein)), carbs \(grams(summary.eaten.carbs)), fat \(grams(summary.eaten.fat))"
            if summary.exercise > 0 { line += ", \(Int(summary.exercise.rounded())) kcal active energy" }
            lines.append(line)
        }
        if logged.count < days {
            lines.append("No food logged on the other \(days - logged.count) of the last \(days) days.")
        }
        return lines
    }
}
