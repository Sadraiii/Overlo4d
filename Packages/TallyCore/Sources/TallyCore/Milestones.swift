import Foundation

/// Lifetime totals that milestones are earned from.
public struct MilestoneStats: Sendable, Equatable {
    public var workouts: Int
    /// Kilograms lifted, all time.
    public var volume: Double
    /// Hours trained, all time.
    public var hours: Double
    /// Longest run of weeks in a row with a workout.
    public var bestStreak: Int
    public var records: Int
    /// Working sets, all time.
    public var sets: Int

    public init(workouts: Int = 0, volume: Double = 0, hours: Double = 0, bestStreak: Int = 0, records: Int = 0, sets: Int = 0) {
        self.sets = sets
        self.workouts = workouts
        self.volume = volume
        self.hours = hours
        self.bestStreak = bestStreak
        self.records = records
    }
}

public enum MilestoneKind: String, CaseIterable, Sendable {
    case workouts, sets, volume, hours, streak, records

    /// The values each level is reached at.
    public var tiers: [Double] {
        switch self {
        case .workouts: [1, 10, 25, 50, 100, 250, 500, 1000]
        case .sets: [100, 500, 1000, 2500, 5000, 10_000, 25_000]
        case .volume: [1_000, 10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000]
        case .hours: [1, 10, 25, 50, 100, 250, 500, 1000]
        case .streak: [2, 4, 8, 12, 26, 52, 104]
        case .records: [1, 10, 25, 50, 100, 250, 500]
        }
    }

    public func value(in stats: MilestoneStats) -> Double {
        switch self {
        case .workouts: Double(stats.workouts)
        case .sets: Double(stats.sets)
        case .volume: stats.volume
        case .hours: stats.hours
        case .streak: Double(stats.bestStreak)
        case .records: Double(stats.records)
        }
    }
}

public struct Milestone: Sendable, Equatable {
    public let kind: MilestoneKind
    /// Levels reached, 0 when none yet.
    public let level: Int
    public let value: Double
    /// The last level's value, nil when none reached.
    public let reached: Double?
    /// The next level's value, nil once every level is reached.
    public let next: Double?
    /// 0–1 of the way from the last level to the next.
    public let progress: Double

    public var maxLevel: Int { kind.tiers.count }
}

public enum Milestones {
    public static func all(_ stats: MilestoneStats) -> [Milestone] {
        MilestoneKind.allCases.map { milestone($0, stats) }
    }

    public static func milestone(_ kind: MilestoneKind, _ stats: MilestoneStats) -> Milestone {
        let value = kind.value(in: stats)
        let tiers = kind.tiers
        let level = tiers.filter { value >= $0 }.count
        let reached = level > 0 ? tiers[level - 1] : nil
        let next = level < tiers.count ? tiers[level] : nil
        let progress: Double
        if let next {
            let from = reached ?? 0
            progress = min(1, max(0, (value - from) / (next - from)))
        } else {
            progress = 1
        }
        return Milestone(kind: kind, level: level, value: value, reached: reached, next: next, progress: progress)
    }

    /// Milestone levels reached by `after` that weren't by `before`, e.g. to celebrate after a workout.
    public static func newlyReached(before: MilestoneStats, after: MilestoneStats) -> [Milestone] {
        MilestoneKind.allCases.compactMap { kind in
            let old = milestone(kind, before)
            let new = milestone(kind, after)
            return new.level > old.level ? new : nil
        }
    }
}

public enum Streaks {
    /// The longest run of consecutive weeks containing at least one of `dates`.
    public static func longestWeekRun(_ dates: [Date], calendar: Calendar = .current) -> Int {
        let weeks = Set(dates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        var best = 0
        for week in weeks {
            // Only count from the start of a run.
            guard let before = calendar.date(byAdding: .weekOfYear, value: -1, to: week),
                  !weeks.contains(where: { calendar.isDate($0, inSameDayAs: before) }) else { continue }
            var length = 1
            var current = week
            while let following = calendar.date(byAdding: .weekOfYear, value: 1, to: current),
                  weeks.contains(where: { calendar.isDate($0, inSameDayAs: following) }) {
                length += 1
                current = following
            }
            best = max(best, length)
        }
        return best
    }
}

/// Days laid out in week columns, like a contribution graph.
public enum ActivityGrid {
    /// `weeks` columns of 7 days (Monday first with a Monday calendar), the last column holding `end`.
    public static func columns(ending end: Date, weeks: Int, calendar: Calendar = .current) -> [[Date]] {
        guard weeks > 0, let lastWeek = calendar.dateInterval(of: .weekOfYear, for: end)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { offset -> [Date]? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: lastWeek) else { return nil }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
    }

    /// How many of `dates` fall on each day, keyed by the start of the day.
    public static func counts(_ dates: [Date], calendar: Calendar = .current) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for date in dates { result[calendar.startOfDay(for: date), default: 0] += 1 }
        return result
    }
}
