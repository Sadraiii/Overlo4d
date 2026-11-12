import Foundation

/// How long a stretch the Progress trends look at.
public enum TrendRange: String, CaseIterable, Sendable, Identifiable {
    case month, quarter, half, year

    public var id: String { rawValue }

    public var days: Int {
        switch self {
        case .month: 28
        case .quarter: 84
        case .half: 182
        case .year: 364
        }
    }

    /// Short label for the range picker.
    public var label: String {
        switch self {
        case .month: "4 wk"
        case .quarter: "12 wk"
        case .half: "6 mo"
        case .year: "1 yr"
        }
    }

    /// "the last 4 weeks"
    public var phrase: String {
        switch self {
        case .month: "the last 4 weeks"
        case .quarter: "the last 12 weeks"
        case .half: "the last 6 months"
        case .year: "the last year"
        }
    }
}

public struct PeriodTotals: Sendable, Equatable {
    public var workouts = 0
    public var duration: TimeInterval = 0
    public var volume: Double = 0
    public var sets = 0
    public var records = 0

    public init() {}

    public var averageDuration: TimeInterval { workouts > 0 ? duration / Double(workouts) : 0 }
}

/// A period next to the equally long one before it.
public struct PeriodComparison: Sendable, Equatable {
    public let current: DateInterval
    public let previous: DateInterval
    public let totals: PeriodTotals
    public let before: PeriodTotals
    /// Whether any workout is older than the current period, so the comparison means something.
    public let hasEarlier: Bool

    public var workoutsPerWeek: Double { Double(totals.workouts) / max(current.duration / (7 * 86_400), 1) }
}

/// How one lift's estimated one-rep max moved over a period.
public struct LiftTrend: Sendable, Equatable, Identifiable {
    public let exerciseID: UUID
    /// Best estimated 1RM of each session in the period, oldest first.
    public let points: [Double]

    public var id: UUID { exerciseID }
    public var first: Double { points.first ?? 0 }
    public var last: Double { points.last ?? 0 }
    public var best: Double { points.max() ?? 0 }
    public var change: Double { last - first }
    /// Change as a fraction of the starting value (0.05 = up 5 %).
    public var fraction: Double { first > 0 ? change / first : 0 }
}

public struct MonthStat: Sendable, Equatable, Identifiable {
    public let month: Date
    public let workouts: Int
    public let volume: Double
    public let duration: TimeInterval

    public var id: Date { month }
}

public enum Trends {
    /// Totals for the `days` up to `now`, and for the same number of days before that.
    public static func compare(sessions: [SessionSummary], days: Int, now: Date) -> PeriodComparison {
        let length = TimeInterval(max(days, 1)) * 86_400
        let current = DateInterval(start: now.addingTimeInterval(-length), end: now)
        let previous = DateInterval(start: current.start.addingTimeInterval(-length), end: current.start)
        return PeriodComparison(
            current: current,
            previous: previous,
            totals: totals(sessions, in: current, includeEnd: true),
            before: totals(sessions, in: previous, includeEnd: false),
            hasEarlier: sessions.contains { $0.start < current.start }
        )
    }

    static func totals(_ sessions: [SessionSummary], in interval: DateInterval, includeEnd: Bool) -> PeriodTotals {
        var totals = PeriodTotals()
        for session in sessions where session.start >= interval.start && (includeEnd ? session.start <= interval.end : session.start < interval.end) {
            totals.workouts += 1
            totals.duration += session.duration
            totals.volume += session.volume
            totals.sets += session.sets
            totals.records += session.records
        }
        return totals
    }

    /// Change from `before` to `now` as a fraction (0.2 = up 20 %), nil when there is nothing to compare with.
    public static func change(_ now: Double, from before: Double) -> Double? {
        before > 0 ? (now - before) / before : nil
    }

    /// "+20%", "−8%", "same", or nil when there is nothing to compare with.
    public static func changeText(_ now: Double, from before: Double) -> String? {
        guard let change = change(now, from: before) else { return nil }
        let percent = Int((change * 100).rounded())
        if percent == 0 { return "same" }
        return percent > 0 ? "+\(percent)%" : "−\(-percent)%"
    }

    /// The lifts trained most often in `interval` (at least `minSessions` times), each with its
    /// estimated 1RM per session. Most sessions first; ties by the bigger lift.
    public static func lifts(sessions: [SessionSummary], in interval: DateInterval, minSessions: Int = 2, limit: Int = 6) -> [LiftTrend] {
        var points: [UUID: [Double]] = [:]
        for session in sessions.sorted(by: { $0.start < $1.start }) where session.start >= interval.start && session.start <= interval.end {
            for (id, value) in session.bestOneRepMax where value > 0 {
                points[id, default: []].append(value)
            }
        }
        return points
            .filter { $0.value.count >= max(minSessions, 1) }
            .map { LiftTrend(exerciseID: $0.key, points: $0.value) }
            .sorted { a, b in
                if a.points.count != b.points.count { return a.points.count > b.points.count }
                if a.best != b.best { return a.best > b.best }
                return a.exerciseID.uuidString < b.exerciseID.uuidString
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    /// The last `count` calendar months, oldest first, including months without workouts.
    public static func months(sessions: [SessionSummary], count: Int = 12, now: Date, calendar: Calendar = .current) -> [MonthStat] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<max(count, 0)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let interval = calendar.dateInterval(of: .month, for: start) else { return nil }
            let inMonth = sessions.filter { $0.start >= interval.start && $0.start < interval.end }
            return MonthStat(
                month: interval.start,
                workouts: inMonth.count,
                volume: inMonth.reduce(0) { $0 + $1.volume },
                duration: inMonth.reduce(0) { $0 + $1.duration }
            )
        }
    }
}

/// How working sets are spread over pushing, pulling, legs and core.
public enum TrainingBalance {
    public enum Group: String, CaseIterable, Sendable, Identifiable {
        case push, pull, legs, core

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .push: "Push"
            case .pull: "Pull"
            case .legs: "Legs"
            case .core: "Core"
            }
        }

        public var detail: String {
            switch self {
            case .push: "Chest, shoulders, triceps"
            case .pull: "Back, biceps, forearms"
            case .legs: "Quads, hamstrings, glutes, calves"
            case .core: "Abs, obliques"
            }
        }
    }

    public static func group(of muscle: String) -> Group? {
        switch muscle {
        case "chest", "frontDelts", "sideDelts", "triceps": .push
        case "rearDelts", "biceps", "forearms", "traps", "upperBack", "lats", "lowerBack": .pull
        case "glutes", "quads", "hamstrings", "adductors", "calves": .legs
        case "abs", "obliques": .core
        default: nil
        }
    }

    public struct Share: Sendable, Equatable, Identifiable {
        public let group: Group
        public let sets: Double
        /// Part of all sets, 0–1.
        public let fraction: Double

        public var id: String { group.rawValue }
    }

    /// Sets per group from sets per muscle (raw muscle names), in push, pull, legs, core order.
    public static func shares(muscleSets: [String: Double]) -> [Share] {
        var sums: [Group: Double] = [:]
        for (muscle, sets) in muscleSets where sets > 0 {
            if let group = group(of: muscle) { sums[group, default: 0] += sets }
        }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        return Group.allCases.map { Share(group: $0, sets: sums[$0] ?? 0, fraction: (sums[$0] ?? 0) / total) }
    }

    /// One plain sentence on the biggest imbalance, or nil when the spread looks fine.
    public static func note(_ shares: [Share]) -> String? {
        func sets(_ group: Group) -> Double { shares.first { $0.group == group }?.sets ?? 0 }
        let push = sets(.push), pull = sets(.pull), legs = sets(.legs)
        let upper = push + pull
        guard upper + legs > 0 else { return nil }
        if legs == 0 && upper > 0 { return "No leg work in this period." }
        if pull == 0 && push > 0 { return "No pulling work in this period. Rows and pull-downs keep the shoulders balanced." }
        if push == 0 && pull > 0 { return "No pushing work in this period." }
        if pull > 0, push / pull >= 1.5 { return "About \(ratio(push / pull)) the pushing of pulling. Add some rows or pull-downs." }
        if push > 0, pull / push >= 1.5 { return "About \(ratio(pull / push)) the pulling of pushing. Add some pressing." }
        if legs > 0, upper / legs >= 3 { return "The upper body gets about \(ratio(upper / legs)) the sets of the legs." }
        if upper > 0, legs / upper >= 1.5 { return "Legs get about \(ratio(legs / upper)) the sets of the upper body." }
        return nil
    }

    private static func ratio(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        if rounded == 2 { return "twice" }
        if rounded == 3 { return "three times" }
        return rounded == rounded.rounded() ? "\(Int(rounded)) times" : "\(rounded) times"
    }
}

/// Which cards Home shows, and in what order.
public struct HomeLayout: Codable, Sendable, Equatable {
    /// Card names in order, per section.
    public var today: [String]
    public var training: [String]
    public var hidden: Set<String>

    public static let todayCards = ["food", "sleep", "activity", "reps"]
    public static let trainingCards = ["upNext", "recovery", "lastWeek", "coach", "body"]
    public static let standard = HomeLayout(today: todayCards, training: trainingCards, hidden: [])

    public init(today: [String], training: [String], hidden: Set<String>) {
        self.today = today
        self.training = training
        self.hidden = hidden
    }

    /// The layout with unknown cards dropped and cards added since it was saved appended, so a
    /// layout stored by an older version keeps working.
    public var normalized: HomeLayout {
        func fix(_ saved: [String], known: [String]) -> [String] {
            var seen = Set<String>()
            let kept = saved.filter { known.contains($0) && seen.insert($0).inserted }
            return kept + known.filter { !seen.contains($0) }
        }
        let all = Set(Self.todayCards + Self.trainingCards)
        return HomeLayout(
            today: fix(today, known: Self.todayCards),
            training: fix(training, known: Self.trainingCards),
            hidden: hidden.intersection(all)
        )
    }

    public func visible(_ cards: [String]) -> [String] { cards.filter { !hidden.contains($0) } }

    public var isStandard: Bool { normalized == Self.standard }

    /// Reads a stored layout; anything unreadable gives the standard one.
    public static func decode(_ string: String) -> HomeLayout {
        guard let data = string.data(using: .utf8), let layout = try? JSONDecoder().decode(HomeLayout.self, from: data) else { return .standard }
        return layout.normalized
    }

    public var encoded: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(normalized)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
