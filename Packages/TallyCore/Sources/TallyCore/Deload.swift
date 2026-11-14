import Foundation

/// Whether it is time for an easier week, and what an easier week looks like.
public enum Deload {
    /// One calendar week of training.
    public struct Week: Sendable, Equatable {
        public let start: Date
        public let sessions: Int
        /// Sets that aren't warm-ups.
        public let hardSets: Int

        public init(start: Date, sessions: Int, hardSets: Int) {
            self.start = start
            self.sessions = sessions
            self.hardSets = hardSets
        }
    }

    /// A lift's best estimated one-rep max per session, oldest first.
    public struct Lift: Sendable, Equatable {
        public let name: String
        public let recent: [Double]

        public init(name: String, recent: [Double]) {
            self.name = name
            self.recent = recent
        }
    }

    public enum Level: String, Sendable, Equatable {
        /// Worth thinking about.
        case consider
        /// Take one now.
        case due
    }

    public struct Advice: Sendable, Equatable {
        public let level: Level
        /// Hard weeks in a row, counting back from the newest.
        public let hardWeeks: Int
        public let reasons: [String]
        /// Lifts that have slipped back.
        public let slipping: [String]
    }

    /// A week counts as hard with at least two sessions and at least this share of a usual week's sets.
    static let hardShare = 0.7
    static let considerWeeks = 5
    static let dueWeeks = 8

    /// - Parameters:
    ///   - weeks: consecutive calendar weeks, oldest first, ending with the current one.
    ///   - lifts: the most trained lifts with their last sessions.
    ///   - averageRPE: mean effort of rated sets over the last two weeks, if any were rated.
    ///   - lastDeload: when a deload week was last started in the app.
    public static func assess(weeks: [Week], lifts: [Lift], averageRPE: Double?, lastDeload: Date? = nil) -> Advice? {
        let hard = hardWeeks(weeks, lastDeload: lastDeload)
        // Fatigue takes weeks to build; early on a bad session is just a bad session.
        guard hard >= 3 else { return nil }

        let slipping = lifts.filter(isSlipping).map(\.name)
        var score = 0
        var reasons: [String] = []
        if hard >= dueWeeks {
            score += 3
            reasons.append("\(hard) hard weeks in a row without an easier one.")
        } else if hard >= considerWeeks {
            score += 1
            reasons.append("\(hard) hard weeks in a row.")
        }
        if slipping.count >= 2 {
            score += 2
            reasons.append("\(list(slipping)) have slipped back over the last sessions.")
        } else if let lift = slipping.first {
            score += 1
            reasons.append("\(lift) has slipped back over the last sessions.")
        }
        if let averageRPE, averageRPE >= 9 {
            score += 1
            reasons.append("Your sets have averaged RPE \((averageRPE * 10).rounded() / 10): close to the limit every time.")
        }
        guard score >= 2 else { return nil }
        return Advice(level: score >= 3 ? .due : .consider, hardWeeks: hard, reasons: reasons, slipping: slipping)
    }

    /// Hard weeks in a row, newest first. The current week is skipped while it is still light (it
    /// may just have started). A light or empty week, or a deload started in the app, ends the run.
    static func hardWeeks(_ weeks: [Week], lastDeload: Date?) -> Int {
        let trained = weeks.filter { $0.sessions > 0 }.map(\.hardSets).sorted()
        guard !trained.isEmpty else { return 0 }
        let usual = Double(trained[trained.count / 2])
        var count = 0
        for (offset, week) in weeks.reversed().enumerated() {
            if let lastDeload, week.start <= lastDeload { break }
            let isHard = week.sessions >= 2 && Double(week.hardSets) >= usual * hardShare
            if isHard {
                count += 1
            } else if offset == 0 {
                continue
            } else {
                break
            }
        }
        return count
    }

    /// The last two sessions were both at least 3% under the best of the ones before.
    static func isSlipping(_ lift: Lift) -> Bool {
        let values = lift.recent.filter { $0 > 0 }
        guard values.count >= 4, let peak = values.dropLast(2).max() else { return false }
        return values.suffix(2).allSatisfy { $0 < peak * 0.97 }
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    // MARK: The easier week itself

    /// How long a deload lasts once started.
    public static let days = 7

    /// Working sets to do instead of `sets`: about 60%, never fewer than two (or what was planned).
    public static func sets(_ sets: Int) -> Int {
        sets <= 2 ? sets : Int((Double(sets) * 0.6).rounded(.up))
    }

    /// About 10% lighter, on a weight that can be loaded.
    public static func weight(_ weight: Double, step: Double) -> Double {
        guard weight > 0, step > 0 else { return weight }
        let lighter = ((weight * 0.9) / step).rounded() * step
        return lighter >= weight ? max(weight - step, step) : max(lighter, step)
    }

    /// Whether a deload started at `start` is still running.
    public static func isActive(start: Date?, now: Date) -> Bool {
        guard let start else { return false }
        return now >= start && now < start.addingTimeInterval(Double(days) * 86_400)
    }

    /// Whole days left of a running deload, counting today.
    public static func daysLeft(start: Date, now: Date) -> Int {
        max(0, Int((start.addingTimeInterval(Double(days) * 86_400).timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    public static let plan = [
        "Keep your exercises and your reps.",
        "Use about 10% less weight.",
        "Do roughly 60% of your usual sets and stop well short of failure.",
    ]
}
