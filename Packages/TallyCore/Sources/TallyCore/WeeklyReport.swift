import Foundation

/// A written review of one training week: what went well, what to watch and what to do next.
/// Built from the numbers alone, so it works offline and without an AI key.
public enum WeeklyReport {
    public struct Input: Sendable {
        public var totals: WeekTotals
        public var previous: WeekTotals
        /// Workouts aimed for each week; 0 when no goal is set.
        public var weeklyGoal: Int
        /// The lift whose estimated max rose the most, with the rise in percent.
        public var mostImproved: (name: String, percent: Double)?
        public var flags: [LoadFlag]
        /// Labels for the muscle keys in `flags`.
        public var muscleNames: [String: String]
        public var cardioSessions: Int
        public var cardioMinutes: Int
        /// Weeks in a row with a workout, including this one.
        public var streakWeeks: Int
        public var deload: Deload.Advice?
        /// Whether a deload week was running during the week.
        public var wasDeload: Bool
        /// Average hours slept, when sleep is tracked.
        public var sleepHours: Double?
        public var sleepGoalHours: Double?
        public var unit: WeightUnit

        public init(
            totals: WeekTotals, previous: WeekTotals, weeklyGoal: Int = 0, mostImproved: (name: String, percent: Double)? = nil,
            flags: [LoadFlag] = [], muscleNames: [String: String] = [:], cardioSessions: Int = 0, cardioMinutes: Int = 0,
            streakWeeks: Int = 0, deload: Deload.Advice? = nil, wasDeload: Bool = false,
            sleepHours: Double? = nil, sleepGoalHours: Double? = nil, unit: WeightUnit = .kg
        ) {
            self.totals = totals
            self.previous = previous
            self.weeklyGoal = weeklyGoal
            self.mostImproved = mostImproved
            self.flags = flags
            self.muscleNames = muscleNames
            self.cardioSessions = cardioSessions
            self.cardioMinutes = cardioMinutes
            self.streakWeeks = streakWeeks
            self.deload = deload
            self.wasDeload = wasDeload
            self.sleepHours = sleepHours
            self.sleepGoalHours = sleepGoalHours
            self.unit = unit
        }
    }

    public struct Report: Sendable, Equatable {
        /// "Strong week", "Solid week"…
        public let headline: String
        /// One sentence under the headline.
        public let summary: String
        /// 0–100.
        public let score: Int
        public let wins: [String]
        public let watch: [String]
        /// At most three things to do next week.
        public let next: [String]
    }

    public static func build(_ input: Input) -> Report {
        let totals = input.totals
        let previous = input.previous
        // Without a goal, last week's count (or three sessions) is the yardstick.
        let aim = input.weeklyGoal > 0 ? input.weeklyGoal : max(min(previous.workouts, 5), 3)

        guard totals.workouts > 0 else {
            var next = ["Plan \(aim) sessions and put the first one in your calendar."]
            if previous.workouts > 0 { next.append("Start with the weights from your last session. They will still be there.") }
            let cardio = input.cardioSessions > 0 ? ["\(input.cardioSessions) cardio \(input.cardioSessions == 1 ? "session" : "sessions") kept you moving."] : []
            return Report(
                headline: "No lifting logged",
                summary: previous.workouts > 0 ? "A week off now and then does no harm. Pick it back up." : "Nothing in the log for this week.",
                score: input.cardioSessions > 0 ? 20 : 0,
                wins: cardio,
                watch: [],
                next: next
            )
        }

        var wins: [String] = []
        var watch: [String] = []
        var next: [String] = []

        // Consistency.
        if input.weeklyGoal > 0 {
            if totals.workouts >= input.weeklyGoal {
                wins.append("Weekly goal reached: \(totals.workouts) of \(input.weeklyGoal) workouts.")
            } else {
                let missed = input.weeklyGoal - totals.workouts
                watch.append("\(totals.workouts) of \(input.weeklyGoal) planned workouts: \(missed) short.")
                next.append("Book \(input.weeklyGoal) sessions in your calendar before the week starts.")
            }
        } else if totals.workouts > previous.workouts && previous.workouts > 0 {
            wins.append("\(totals.workouts) workouts, \(totals.workouts - previous.workouts) more than the week before.")
        }
        if input.streakWeeks >= 4 {
            wins.append("\(input.streakWeeks) weeks in a row with training.")
        }

        // Progress.
        if totals.records > 0 {
            wins.append("\(totals.records) personal \(totals.records == 1 ? "record" : "records").")
        }
        if let improved = input.mostImproved, improved.percent >= 0.5 {
            wins.append("\(improved.name) is up \(percent(improved.percent)) on its estimated max.")
        }
        let volumeChange = previous.volume > 0 ? (totals.volume - previous.volume) / previous.volume * 100 : nil
        if let volumeChange, !input.wasDeload {
            if volumeChange >= 5 && volumeChange <= 30 {
                wins.append("Volume up \(percent(volumeChange)) to \(volume(totals.volume, input.unit)).")
            } else if volumeChange > 30 && previous.workouts >= 2 {
                watch.append("Volume jumped \(percent(volumeChange)) in one week. Build up more gradually to stay healthy.")
            } else if volumeChange <= -25 {
                watch.append("Volume fell \(percent(-volumeChange)) against the week before.")
            }
        }
        if input.wasDeload {
            wins.append("Deload week done. Expect to feel fresher next week.")
        }

        // Cardio.
        if input.cardioSessions > 0 {
            wins.append("\(input.cardioSessions) cardio \(input.cardioSessions == 1 ? "session" : "sessions"), \(input.cardioMinutes) min in total.")
        }

        // Load and balance.
        var penalty = 0
        for flag in input.flags.prefix(4) {
            penalty += flag.severity == 2 ? 8 : flag.severity == 1 ? 5 : 2
            let (text, action) = describe(flag, names: input.muscleNames)
            watch.append(text)
            if let action, next.count < 3, !next.contains(action) { next.append(action) }
        }

        // Recovery.
        if let hours = input.sleepHours, let goal = input.sleepGoalHours, goal > 0, hours < goal - 0.75 {
            watch.append("Sleep averaged \(oneDecimal(hours)) h against a goal of \(oneDecimal(goal)) h. Strength is built while you sleep.")
            if next.count < 3 { next.append("Go to bed 30 minutes earlier on training days.") }
        }
        if let deload = input.deload, !input.wasDeload {
            watch.append(deload.level == .due ? "A deload week is due: \(deload.reasons.first ?? "")" : "Think about a deload week soon: \(deload.reasons.first ?? "")")
            if deload.level == .due { next.insert("Take a deload week: same exercises, about 10% lighter and fewer sets.", at: 0) }
        }
        if next.isEmpty {
            next.append(totals.records > 0
                ? "Keep the plan as it is. Add a little weight where every set reached its reps."
                : "Pick one lift per session and beat last time by one rep or the smallest plate.")
        }
        if next.count < 3 && input.cardioSessions == 0 {
            next.append("Add one easy 20-minute cardio session for your heart and recovery.")
        }

        // Score: showing up counts most, then progress, then balance.
        let consistency = min(Double(totals.workouts) / Double(max(aim, 1)), 1) * 50
        var progress = 0.0
        if totals.records > 0 || (input.mostImproved?.percent ?? 0) >= 0.5 { progress += 15 }
        if input.wasDeload || (volumeChange ?? 0) >= -10 { progress += 10 }
        let balance = Double(max(0, 25 - penalty))
        let score = Int((consistency + progress + balance).rounded())

        let headline: String
        let summary: String
        switch score {
        case 85...:
            headline = "Strong week"
            summary = "You showed up, moved forward and kept your training balanced."
        case 65..<85:
            headline = "Solid week"
            summary = "Good work in the bank, with a thing or two to tidy up."
        case 40..<65:
            headline = "Mixed week"
            summary = "Some good sessions, and clear room to do better next week."
        default:
            headline = "Quiet week"
            summary = "A light week. Next week is a clean start."
        }
        return Report(headline: headline, summary: summary, score: min(score, 100), wins: wins, watch: watch, next: Array(next.prefix(3)))
    }

    /// One line about a load flag, and what to do about it.
    static func describe(_ flag: LoadFlag, names: [String: String]) -> (text: String, action: String?) {
        func name(_ key: String) -> String { names[key] ?? key }
        switch flag {
        case .tooMuch(let muscle, let sets):
            return ("\(name(muscle)) got \(Int(sets.rounded())) hard sets. Past about 20 a week, recovery suffers.",
                    "Cut \(name(muscle).lowercased()) back to 14–18 sets.")
        case .spike(let muscle, let sets, let usual):
            return ("\(name(muscle)) jumped to \(Int(sets.rounded())) sets from a usual \(Int(usual.rounded())).",
                    "Hold \(name(muscle).lowercased()) at this week's sets before adding more.")
        case .shortRecovery(let muscle, let hours):
            return ("\(name(muscle)) was trained hard twice within \(Int(hours.rounded())) hours.",
                    "Leave two days between hard \(name(muscle).lowercased()) sessions.")
        case .imbalance(_, let more, let less, let ratio):
            let text = ratio.isFinite
                ? "\(more) got \(oneDecimal(ratio))× the work of \(less.lowercased()) over the last 4 weeks."
                : "Plenty of \(more.lowercased()) work but no \(less.lowercased()) in the last 4 weeks."
            return (text, "Add a \(less.lowercased()) exercise to even things out.")
        case .neglected(let muscle, let days):
            let text = days.map { "No direct \(name(muscle).lowercased()) work in \($0) days." } ?? "No direct \(name(muscle).lowercased()) work yet."
            return (text, "Add 6 or more sets for \(name(muscle).lowercased()).")
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// "12,400 kg" style totals without relying on the locale: "12400 kg", or tonnes past 10 000 kg.
    private static func volume(_ kg: Double, _ unit: WeightUnit) -> String {
        let value = unit.fromKg(kg)
        if unit == .kg && value >= 10_000 { return "\(oneDecimal(value / 1000)) t" }
        return "\(Int(value.rounded())) \(unit.label)"
    }
}
