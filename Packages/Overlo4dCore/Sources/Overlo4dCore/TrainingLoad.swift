import Foundation

/// One exercise in a finished workout, reduced to the muscles it trained and how many working sets.
/// Muscles are keys such as "chest" or "quads", so this works without the app's types.
public struct MuscleWork: Sendable, Equatable {
    public var date: Date
    public var primary: [String]
    public var secondary: [String]
    /// Sets that aren't warm-ups.
    public var sets: Int

    public init(date: Date, primary: [String], secondary: [String] = [], sets: Int) {
        self.date = date
        self.primary = primary
        self.secondary = secondary
        self.sets = sets
    }
}

/// Two sides of the body that should get roughly the same work, e.g. push and pull.
public struct BalancePair: Sendable, Equatable {
    public struct Side: Sendable, Equatable {
        public var label: String
        public var muscles: [String]

        public init(_ label: String, _ muscles: [String]) {
            self.label = label
            self.muscles = muscles
        }
    }

    public var name: String
    public var first: Side
    public var second: Side

    public init(name: String, first: Side, second: Side) {
        self.name = name
        self.first = first
        self.second = second
    }
}

/// Something about recent training worth pointing out, most serious first.
public enum LoadFlag: Sendable, Equatable {
    /// More hard sets for a muscle in the last 7 days than most people recover from.
    case tooMuch(muscle: String, sets: Double)
    /// The last 7 days were far above the muscle's usual week.
    case spike(muscle: String, sets: Double, usual: Double)
    /// The muscle was trained hard again before it had two days to recover.
    case shortRecovery(muscle: String, hours: Double)
    /// One side of a pair got much more work than the other over the last 4 weeks.
    case imbalance(pair: String, more: String, less: String, ratio: Double)
    /// A muscle that hasn't been trained lately while the rest of the body has.
    case neglected(muscle: String, days: Int?)

    /// 2 = cut back, 1 = keep an eye on it, 0 = an idea.
    public var severity: Int {
        switch self {
        case .tooMuch, .shortRecovery: 2
        case .spike, .imbalance: 1
        case .neglected: 0
        }
    }
}

public struct LoadReport: Sendable, Equatable {
    /// Hard sets per muscle in the last 7 days. Secondary muscles count half.
    public var lastWeek: [String: Double]
    /// Average hard sets per muscle per week over the 4 weeks before that; empty without enough history.
    public var usualWeek: [String: Double]
    public var flags: [LoadFlag]
}

public enum TrainingLoad {
    /// Hard sets per muscle per week. Around 10–20 is where most lifters grow; past 20 recovery
    /// usually suffers more than results improve.
    public static let productiveSets = 10.0
    public static let highSets = 20.0
    /// A week this many times the usual one is a sudden jump.
    static let spikeRatio = 1.5
    /// A session with at least this many sets for a muscle counts as training it hard.
    static let hardSessionSets = 4.0
    /// Muscles need about this long between hard sessions.
    static let recoveryHours = 48.0
    /// One side of a pair getting this many times the work of the other is an imbalance.
    static let imbalanceRatio = 2.0

    public static func report(
        _ work: [MuscleWork],
        now: Date,
        watch: [String] = [],
        pairs: [BalancePair] = []
    ) -> LoadReport {
        let day = 86_400.0
        let lastWeek = sets(in: work, from: now.addingTimeInterval(-7 * day), to: now)
        var usualWeek: [String: Double] = [:]
        // Only compare with a usual week once there are 5 weeks of history to average.
        if let first = work.map(\.date).min(), first <= now.addingTimeInterval(-35 * day) {
            usualWeek = sets(in: work, from: now.addingTimeInterval(-35 * day), to: now.addingTimeInterval(-7 * day))
                .mapValues { $0 / 4 }
        }

        var flags: [LoadFlag] = []
        for (muscle, value) in lastWeek.sorted(by: order) {
            if value > highSets {
                flags.append(.tooMuch(muscle: muscle, sets: value))
            } else if let usual = usualWeek[muscle], usual >= 3, value >= productiveSets, value >= usual * spikeRatio {
                flags.append(.spike(muscle: muscle, sets: value, usual: usual))
            }
        }
        flags += shortRecoveries(in: work, now: now)
        flags += imbalances(in: work, now: now, pairs: pairs)
        flags += neglected(in: work, now: now, watch: watch)
        // Stable order: severity, then the order each check added them.
        let ranked = flags.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }
        return LoadReport(lastWeek: lastWeek, usualWeek: usualWeek, flags: ranked.map(\.element))
    }

    /// Hard sets per muscle for work in [start, end). Secondary muscles count half.
    static func sets(in work: [MuscleWork], from start: Date, to end: Date) -> [String: Double] {
        var totals: [String: Double] = [:]
        for item in work where item.date >= start && item.date < end && item.sets > 0 {
            for muscle in item.primary { totals[muscle, default: 0] += Double(item.sets) }
            for muscle in item.secondary { totals[muscle, default: 0] += Double(item.sets) / 2 }
        }
        return totals
    }

    /// Most sets first, then by name, so results don't depend on dictionary order.
    private static func order(_ a: (key: String, value: Double), _ b: (key: String, value: Double)) -> Bool {
        a.value != b.value ? a.value > b.value : a.key < b.key
    }

    /// The shortest gap between hard sessions for each muscle, when a later one is in the last 7 days.
    static func shortRecoveries(in work: [MuscleWork], now: Date) -> [LoadFlag] {
        let since = now.addingTimeInterval(-9 * 86_400)
        // Sets per muscle per session (work items sharing a start date belong to one workout).
        var sessions: [String: [Date: Double]] = [:]
        for item in work where item.date >= since && item.date < now {
            for muscle in item.primary { sessions[muscle, default: [:]][item.date, default: 0] += Double(item.sets) }
        }
        var gaps: [(muscle: String, hours: Double)] = []
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        for (muscle, byDate) in sessions {
            let hard = byDate.filter { $0.value >= hardSessionSets }.keys.sorted()
            let shortest = zip(hard, hard.dropFirst())
                .filter { $0.1 >= weekAgo }
                .map { $0.1.timeIntervalSince($0.0) / 3600 }
                .filter { $0 > 0 && $0 < recoveryHours }
                .min()
            if let shortest { gaps.append((muscle, shortest)) }
        }
        return gaps
            .sorted { $0.hours != $1.hours ? $0.hours < $1.hours : $0.muscle < $1.muscle }
            .map { .shortRecovery(muscle: $0.muscle, hours: $0.hours) }
    }

    static func imbalances(in work: [MuscleWork], now: Date, pairs: [BalancePair]) -> [LoadFlag] {
        let month = sets(in: work, from: now.addingTimeInterval(-28 * 86_400), to: now)
        return pairs.compactMap { pair in
            let first = pair.first.muscles.reduce(0) { $0 + (month[$1] ?? 0) }
            let second = pair.second.muscles.reduce(0) { $0 + (month[$1] ?? 0) }
            // Too little work on both sides to say anything.
            guard first + second >= 12 else { return nil }
            let (more, less, high, low) = first >= second
                ? (pair.first.label, pair.second.label, first, second)
                : (pair.second.label, pair.first.label, second, first)
            let ratio = low > 0 ? high / low : .infinity
            return ratio >= imbalanceRatio ? .imbalance(pair: pair.name, more: more, less: less, ratio: ratio) : nil
        }
    }

    /// Watched muscles with no direct work in 3 weeks, when there were at least 4 workouts in that time.
    static func neglected(in work: [MuscleWork], now: Date, watch: [String]) -> [LoadFlag] {
        let since = now.addingTimeInterval(-21 * 86_400)
        let recent = work.filter { $0.date >= since && $0.date < now }
        guard Set(recent.map(\.date)).count >= 4 else { return [] }
        let trained = Set(recent.filter { $0.sets > 0 }.flatMap(\.primary))
        return watch.filter { !trained.contains($0) }.map { muscle in
            let last = work.filter { $0.date < now && $0.sets > 0 && $0.primary.contains(muscle) }.map(\.date).max()
            return .neglected(muscle: muscle, days: last.map { Int(now.timeIntervalSince($0) / 86_400) })
        }
    }
}
