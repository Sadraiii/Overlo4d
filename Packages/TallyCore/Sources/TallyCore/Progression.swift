import Foundation

/// What to load next time on a weight-and-reps exercise, from the last few sessions.
public enum Progression {
    /// One working set (not a warm-up) with weight on it.
    public struct PastSet: Sendable, Equatable {
        public let weight: Double
        public let reps: Int
        public let rpe: Double?

        public init(weight: Double, reps: Int, rpe: Double? = nil) {
            self.weight = weight
            self.reps = reps
            self.rpe = rpe
        }
    }

    public enum Action: String, Sendable, Equatable {
        /// Every set reached the target: go heavier.
        case increase
        /// Same weight, more reps.
        case addReps
        /// Same weight and reps once more (it was a maximal effort).
        case hold
        /// Stuck for several sessions: go lighter and build back up.
        case deload
    }

    public struct Suggestion: Sendable, Equatable {
        public let weight: Double
        /// Reps to aim for on each set.
        public let reps: Int
        public let action: Action
        /// One short sentence saying why.
        public let reason: String
    }

    /// The smallest sensible jump for the equipment: 2.5 kg on bars and stacks (5 kg on heavy
    /// machines), 2 kg on dumbbells and kettlebells (1 kg while they are light).
    public static func step(equipment: String?, weight: Double) -> Double {
        switch equipment {
        case "dumbbell", "kettlebell": weight < 10 ? 1 : 2
        case "machine": weight >= 100 ? 5 : 2.5
        case "band", "bodyweight": 1
        default: 2.5
        }
    }

    /// - Parameters:
    ///   - sessions: working sets of each past session, newest first.
    ///   - targetReps: the reps planned today, or nil to use last time's first set.
    ///   - step: the jump to add when going heavier.
    public static func suggest(sessions: [[PastSet]], targetReps: Int?, step: Double = 2.5) -> Suggestion? {
        let history = sessions.map { $0.filter { $0.weight > 0 && $0.reps > 0 } }.filter { !$0.isEmpty }
        guard let last = history.first, let top = last.map(\.weight).max() else { return nil }
        let atTop = last.filter { $0.weight == top }
        let target = max(targetReps ?? last.first?.reps ?? 0, 0)
        guard target > 0 else { return nil }
        let hitAll = atTop.allSatisfy { $0.reps >= target }

        if hitAll {
            // A grinder that only just made it is repeated before weight goes on.
            let maximal = atTop.contains { ($0.rpe ?? 0) >= 10 } && atTop.contains { $0.reps == target }
            if maximal {
                return Suggestion(weight: top, reps: target, action: .hold, reason: "You hit \(target) reps at max effort. Own it once more before adding weight.")
            }
            return Suggestion(weight: top + step, reps: target, action: .increase, reason: "Every set reached \(target) reps last time.")
        }

        if isStalled(history, target: target) {
            let lighter = max(step, ((top * 0.9) / step).rounded() * step)
            if lighter < top {
                return Suggestion(weight: lighter, reps: target, action: .deload, reason: "Three sessions at \(format(top)) kg without progress. Drop 10% and build back up.")
            }
        }

        let short = atTop.filter { $0.reps < target }.count
        let reason = short == 1 ? "One set fell short of \(target) reps. Same weight, get them all." : "\(short) sets fell short of \(target) reps. Same weight, get them all."
        return Suggestion(weight: top, reps: target, action: .addReps, reason: reason)
    }

    /// Three sessions in a row at the same top weight, none reaching the target on every set, and no
    /// more total reps at that weight in the newest than in the oldest of the three.
    static func isStalled(_ history: [[PastSet]], target: Int) -> Bool {
        guard history.count >= 3 else { return false }
        let recent = Array(history.prefix(3))
        let tops = recent.compactMap { $0.map(\.weight).max() }
        guard tops.count == 3, Set(tops).count == 1, let top = tops.first else { return false }
        let reps = recent.map { session in session.filter { $0.weight == top }.reduce(0) { $0 + $1.reps } }
        let missed = recent.allSatisfy { session in session.filter { $0.weight == top }.contains { $0.reps < target } }
        return missed && reps[0] <= reps[2]
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Lines up today's sets with last time's, so set 1 is compared with last time's first working set
/// even when the number of warm-ups differs.
public enum PreviousSets {
    /// For each of today's sets, the index of the matching set from last time: the n-th warm-up
    /// pairs with the n-th warm-up, and the n-th other set with the n-th other set.
    public static func match(current: [Bool], previous: [Bool]) -> [Int?] {
        let warm = previous.indices.filter { previous[$0] }
        let work = previous.indices.filter { !previous[$0] }
        var warmSeen = 0, workSeen = 0
        return current.map { isWarmUp in
            if isWarmUp {
                defer { warmSeen += 1 }
                return warmSeen < warm.count ? warm[warmSeen] : nil
            }
            defer { workSeen += 1 }
            return workSeen < work.count ? work[workSeen] : nil
        }
    }
}
