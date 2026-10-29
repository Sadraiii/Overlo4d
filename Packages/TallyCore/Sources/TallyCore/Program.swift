import Foundation

/// A multi-week strength program: the main lifts run off a percentage of a training max, which
/// goes up after the weeks with a rep-out (AMRAP) set. Accessories are fixed sets × reps.
///
/// Every week uses the same days; a week only says which percentages and reps the main lifts get,
/// so a 16-week program stays small enough for the coach to write in one answer.
public struct StrengthProgram: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case juggernaut, block, coach
    }

    public struct Lift: Codable, Sendable, Equatable, Hashable {
        /// The exercise name as the app shows it, e.g. "Squat (Barbell)".
        public var exercise: String
        /// Kilograms. Usually 90 % of the one-rep max.
        public var trainingMax: Double
        /// Kilograms added to the training max per rep beaten on a rep-out set.
        public var increment: Double

        public init(exercise: String, trainingMax: Double, increment: Double) {
            self.exercise = exercise
            self.trainingMax = trainingMax
            self.increment = increment
        }
    }

    public struct Accessory: Codable, Sendable, Equatable, Hashable {
        public var exercise: String
        public var sets: Int
        public var reps: Int
        public var notes: String

        public init(exercise: String, sets: Int, reps: Int, notes: String = "") {
            self.exercise = exercise
            self.sets = sets
            self.reps = reps
            self.notes = notes
        }
    }

    public struct Day: Codable, Sendable, Equatable, Hashable {
        public var name: String
        /// Exercise names of `lifts` trained this day, in order.
        public var lifts: [String]
        public var accessories: [Accessory]

        public init(name: String, lifts: [String], accessories: [Accessory]) {
            self.name = name
            self.lifts = lifts
            self.accessories = accessories
        }
    }

    public struct MainSet: Codable, Sendable, Equatable, Hashable {
        /// Of the training max.
        public var percent: Double
        public var reps: Int
        /// As many reps as possible, with `reps` as the minimum.
        public var amrap: Bool
        /// A lighter ramp-up set before the work sets.
        public var warmup: Bool

        public init(_ percent: Double, _ reps: Int, amrap: Bool = false, warmup: Bool = false) {
            self.percent = percent
            self.reps = reps
            self.amrap = amrap
            self.warmup = warmup
        }
    }

    public struct Week: Codable, Sendable, Equatable, Hashable {
        /// e.g. "10s wave · Accumulation".
        public var phase: String
        /// What the week is for, in a sentence.
        public var note: String
        public var sets: [MainSet]
        /// Accessories get half their sets.
        public var isDeload: Bool
        /// Reps to beat on the rep-out set; each extra rep raises the training max by the lift's increment.
        public var amrapTarget: Int?

        public init(phase: String, note: String, sets: [MainSet], isDeload: Bool = false, amrapTarget: Int? = nil) {
            self.phase = phase
            self.note = note
            self.sets = sets
            self.isDeload = isDeload
            self.amrapTarget = amrapTarget
        }
    }

    public var id: UUID
    public var name: String
    public var summary: String
    public var source: Source
    public var startDate: Date
    public var lifts: [Lift]
    public var days: [Day]
    public var weeks: [Week]
    /// How to progress, in plain sentences.
    public var rules: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        source: Source,
        startDate: Date,
        lifts: [Lift],
        days: [Day],
        weeks: [Week],
        rules: [String]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.source = source
        self.startDate = startDate
        self.lifts = lifts
        self.days = days
        self.weeks = weeks
        self.rules = rules
    }

    public func lift(_ exercise: String) -> Lift? {
        lifts.first { $0.exercise == exercise }
    }
}

/// A finished program day, read from the logged workout.
public struct ProgramLog: Sendable, Equatable {
    public var week: Int
    public var day: Int
    /// Reps of the heaviest working set for each lift, e.g. the rep-out set.
    public var topReps: [String: Int]

    public init(week: Int, day: Int, topReps: [String: Int] = [:]) {
        self.week = week
        self.day = day
        self.topReps = topReps
    }
}

/// One exercise of a day, with weights worked out.
public struct ProgramItem: Sendable, Equatable {
    public struct Set: Sendable, Equatable {
        /// Kilograms; nil for accessories, which use last time's weight.
        public var weight: Double?
        public var reps: Int
        public var amrap: Bool
        public var warmup: Bool
    }

    public var exercise: String
    public var isMainLift: Bool
    public var sets: [Set]
    public var notes: String
}

extension StrengthProgram {
    /// Weeks are 0-based. Rounded to `step` kg.
    public func trainingMax(for exercise: String, week: Int, logs: [ProgramLog]) -> Double {
        guard let lift = lift(exercise) else { return 0 }
        var max = lift.trainingMax
        for (index, plan) in weeks.enumerated() where index < week {
            guard let target = plan.amrapTarget,
                  let reps = logs.filter({ $0.week == index }).compactMap({ $0.topReps[exercise] }).max() else { continue }
            max += Self.increase(trainingMax: max, increment: lift.increment, reps: reps, target: target)
        }
        return max
    }

    /// Juggernaut's rule: the lift's increment for each rep past the target, at most 10 % of the max at once.
    /// Missing the target keeps the max where it is.
    public static func increase(trainingMax: Double, increment: Double, reps: Int, target: Int) -> Double {
        let extra = Double(max(0, reps - target)) * increment
        return min(extra, trainingMax * 0.1)
    }

    /// The exercises for `day` of `week` (both 0-based).
    public func items(week: Int, day: Int, logs: [ProgramLog], step: Double = 2.5) -> [ProgramItem] {
        guard weeks.indices.contains(week), days.indices.contains(day) else { return [] }
        let plan = weeks[week]
        let template = days[day]
        var result: [ProgramItem] = template.lifts.compactMap { exercise in
            guard lift(exercise) != nil else { return nil }
            let max = trainingMax(for: exercise, week: week, logs: logs)
            return ProgramItem(
                exercise: exercise,
                isMainLift: true,
                sets: plan.sets.map { set in
                    ProgramItem.Set(weight: Plates.round(max * set.percent / 100, to: step), reps: set.reps, amrap: set.amrap, warmup: set.warmup)
                },
                notes: plan.sets.contains(where: \.amrap) ? "Last set: as many good reps as you can." : ""
            )
        }
        result += template.accessories.map { accessory in
            let sets = plan.isDeload ? max(1, accessory.sets / 2) : accessory.sets
            return ProgramItem(
                exercise: accessory.exercise,
                isMainLift: false,
                sets: Array(repeating: ProgramItem.Set(weight: nil, reps: accessory.reps, amrap: false, warmup: false), count: sets),
                notes: accessory.notes
            )
        }
        return result
    }

    /// The first day not logged yet, in order; nil when the program is done.
    public func next(logs: [ProgramLog]) -> (week: Int, day: Int)? {
        let done = Swift.Set(logs.map { "\($0.week).\($0.day)" })
        for week in weeks.indices {
            for day in days.indices where !done.contains("\(week).\(day)") {
                return (week, day)
            }
        }
        return nil
    }

    /// Days logged out of all days.
    public func progress(logs: [ProgramLog]) -> (done: Int, total: Int) {
        let valid = Swift.Set(logs.filter { weeks.indices.contains($0.week) && days.indices.contains($0.day) }.map { "\($0.week).\($0.day)" })
        return (valid.count, weeks.count * days.count)
    }
}

/// Ready-made programs.
public enum ProgramTemplates {
    public static let squat = "Squat (Barbell)"
    public static let bench = "Bench Press (Barbell)"
    public static let deadlift = "Deadlift (Barbell)"
    public static let press = "Overhead Press (Barbell)"
    public static let bigFour = [squat, bench, deadlift, press]

    /// Training max as a share of the one-rep max.
    public static let trainingMaxShare = 0.9

    /// The usual four-day split: one main lift a day with matching accessories.
    public static let fourDays: [StrengthProgram.Day] = [
        .init(name: "Squat day", lifts: [squat], accessories: [
            .init(exercise: "Romanian Deadlift (Barbell)", sets: 3, reps: 8),
            .init(exercise: "Bulgarian Split Squat", sets: 3, reps: 10),
            .init(exercise: "Hanging Leg Raise", sets: 3, reps: 12),
        ]),
        .init(name: "Bench day", lifts: [bench], accessories: [
            .init(exercise: "Bent Over Row (Barbell)", sets: 4, reps: 10),
            .init(exercise: "Incline Bench Press (Dumbbell)", sets: 3, reps: 10),
            .init(exercise: "Triceps Pushdown (Cable)", sets: 3, reps: 12),
        ]),
        .init(name: "Deadlift day", lifts: [deadlift], accessories: [
            .init(exercise: "Front Squat (Barbell)", sets: 3, reps: 6),
            .init(exercise: "Leg Curl (Machine)", sets: 3, reps: 12),
            .init(exercise: "Back Extension", sets: 3, reps: 12),
        ]),
        .init(name: "Press day", lifts: [press], accessories: [
            .init(exercise: "Pull-ups", sets: 4, reps: 8),
            .init(exercise: "Lateral Raise (Dumbbell)", sets: 3, reps: 15),
            .init(exercise: "Face Pull (Cable)", sets: 3, reps: 15),
        ]),
    ]

    /// Training maxes from one-rep maxes. Squat and deadlift go up 2.5 kg per extra rep, the presses 1.25 kg.
    public static func lifts(oneRepMaxes: [String: Double]) -> [StrengthProgram.Lift] {
        bigFour.compactMap { exercise in
            guard let max = oneRepMaxes[exercise], max > 0 else { return nil }
            let lower = exercise == squat || exercise == deadlift
            return .init(exercise: exercise, trainingMax: Plates.round(max * trainingMaxShare, to: 2.5), increment: lower ? 2.5 : 1.25)
        }
    }

    private static func days(for lifts: [StrengthProgram.Lift]) -> [StrengthProgram.Day] {
        let names = Set(lifts.map(\.exercise))
        return fourDays.map { day in
            var day = day
            day.lifts = day.lifts.filter(names.contains)
            return day
        }
    }

    /// Juggernaut Method: four 4-week waves (10s, 8s, 5s, 3s), each with accumulation, intensification,
    /// realization and deload weeks. The realization rep-out sets set the next wave's training max.
    public static func juggernaut(oneRepMaxes: [String: Double], start: Date) -> StrengthProgram {
        typealias S = StrengthProgram.MainSet
        let deload = [S(40, 5), S(50, 5), S(60, 5)]
        let waves: [(reps: Int, acc: [S], int: [S], real: [S])] = [
            (10,
             Array(repeating: S(60, 10), count: 5),
             [S(55, 5, warmup: true), S(62.5, 5, warmup: true)] + Array(repeating: S(67.5, 10), count: 3),
             [S(50, 5, warmup: true), S(60, 3, warmup: true), S(70, 1, warmup: true), S(75, 10, amrap: true)]),
            (8,
             Array(repeating: S(65, 8), count: 5),
             [S(60, 3, warmup: true), S(67.5, 3, warmup: true)] + Array(repeating: S(72.5, 8), count: 3),
             [S(50, 5, warmup: true), S(60, 3, warmup: true), S(70, 2, warmup: true), S(75, 1, warmup: true), S(80, 8, amrap: true)]),
            (5,
             Array(repeating: S(70, 5), count: 5),
             [S(65, 2, warmup: true), S(72.5, 2, warmup: true)] + Array(repeating: S(77.5, 5), count: 3),
             [S(50, 5, warmup: true), S(60, 3, warmup: true), S(70, 2, warmup: true), S(75, 1, warmup: true), S(80, 1, warmup: true), S(85, 5, amrap: true)]),
            (3,
             Array(repeating: S(75, 3), count: 6),
             [S(70, 1, warmup: true), S(75, 1, warmup: true)] + Array(repeating: S(80, 3), count: 4),
             [S(50, 5, warmup: true), S(60, 3, warmup: true), S(70, 2, warmup: true), S(75, 1, warmup: true), S(80, 1, warmup: true), S(85, 1, warmup: true), S(90, 3, amrap: true)]),
        ]
        var weeks: [StrengthProgram.Week] = []
        for wave in waves {
            let name = "\(wave.reps)s wave"
            weeks.append(.init(phase: "\(name) · Accumulation", note: "Lots of sets of \(wave.reps) at a moderate weight. Stop each set with a rep or two left.", sets: wave.acc))
            weeks.append(.init(phase: "\(name) · Intensification", note: "Heavier, slightly fewer total reps. Keep every rep clean.", sets: wave.int))
            weeks.append(.init(phase: "\(name) · Realization", note: "Ramp up, then one all-out set. Beat \(wave.reps) reps to raise your training max.", sets: wave.real, amrapTarget: wave.reps))
            weeks.append(.init(phase: "\(name) · Deload", note: "Light week so you come back fresh. Accessories are halved.", sets: deload, isDeload: true))
        }
        let lifts = lifts(oneRepMaxes: oneRepMaxes)
        return StrengthProgram(
            name: "Juggernaut 16 weeks",
            summary: "Four waves of 4 weeks for squat, bench, deadlift and overhead press. Reps drop from 10 to 3 while the weights climb, and each wave ends with a rep-out set and a deload.",
            source: .juggernaut,
            startDate: start,
            lifts: lifts,
            days: days(for: lifts),
            weeks: weeks,
            rules: [
                "Training max is 90 % of your one-rep max. All main-lift weights are a percentage of it.",
                "On realization weeks, the last set is as many good reps as you can. Squat and deadlift go up 2.5 kg for every rep past the target, bench and press 1.25 kg. The app does this for you.",
                "Miss the target and the training max stays the same for the next wave.",
                "Accessories: when you hit all the reps on every set, add the smallest weight step next time.",
                "Deload weeks are part of the plan. Don't skip them.",
            ]
        )
    }

    /// A linear strength block: build weeks from 70 % × 8 to about 87.5 % × 3, a rep-out set at the end
    /// of the last build week, and a deload. `weeks` is 4 to 8.
    public static func block(weeks count: Int, oneRepMaxes: [String: Double], start: Date) -> StrengthProgram {
        typealias S = StrengthProgram.MainSet
        let total = min(max(count, 4), 8)
        let build = total - 1
        var weeks: [StrengthProgram.Week] = []
        for index in 0..<build {
            let t = build == 1 ? 1 : Double(index) / Double(build - 1)
            let percent = Plates.round(70 + 17.5 * t, to: 2.5)
            let reps = Int((8 - 5 * t).rounded())
            let setCount = reps >= 6 ? 4 : 5
            let last = index == build - 1
            var sets = [S(Plates.round(percent * 0.6, to: 2.5), 5, warmup: true), S(Plates.round(percent * 0.8, to: 2.5), 3, warmup: true)]
            sets += Array(repeating: S(percent, reps), count: last ? setCount - 1 : setCount)
            if last { sets.append(S(percent, reps, amrap: true)) }
            let phase = t < 0.34 ? "Volume" : (last ? "Peak" : "Strength")
            weeks.append(.init(
                phase: "Week \(index + 1) · \(phase)",
                note: last
                    ? "Heaviest week. Last set is a rep-out: beat \(reps) reps to raise your training max."
                    : "\(setCount) sets of \(reps) at \(Int(percent)) %. Leave a rep or two in the tank.",
                sets: sets,
                amrapTarget: last ? reps : nil
            ))
        }
        weeks.append(.init(phase: "Week \(total) · Deload", note: "Light week to recover before the next block.", sets: [S(50, 5), S(60, 5), S(60, 5)], isDeload: true))
        let lifts = lifts(oneRepMaxes: oneRepMaxes)
        return StrengthProgram(
            name: "\(total)-week strength block",
            summary: "Weights climb every week while reps drop, ending with a rep-out set and a deload. Run another block after with the new training maxes.",
            source: .block,
            startDate: start,
            lifts: lifts,
            days: days(for: lifts),
            weeks: weeks,
            rules: [
                "Training max is 90 % of your one-rep max. All main-lift weights are a percentage of it.",
                "Every week is heavier than the last. If a week's sets felt grinding, repeat it once before moving on.",
                "The rep-out set in the peak week raises the training max: 2.5 kg per extra rep for squat and deadlift, 1.25 kg for bench and press.",
                "Accessories: when you hit all the reps on every set, add the smallest weight step next time.",
            ]
        )
    }
}

extension StrengthProgram {
    /// "(50 % × 5), 3 × 67.5 % × 10, 75 % × 10+": ramp-up sets in brackets, + for a rep-out.
    public static func setsText(_ sets: [MainSet]) -> String {
        var groups: [(set: MainSet, count: Int)] = []
        for set in sets {
            if let last = groups.last, last.set == set {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((set, 1))
            }
        }
        return groups.map { group in
            let percent = group.set.percent.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
            var text = (group.count > 1 ? "\(group.count) × " : "") + "\(percent) % × \(group.set.reps)"
            if group.set.amrap { text += "+" }
            return group.set.warmup ? "(\(text))" : text
        }
        .joined(separator: ", ")
    }

    /// The program as text for the chat coach.
    public func coachText(logs: [ProgramLog]) -> String {
        let kg: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))) + " kg" }
        let progress = progress(logs: logs)
        let next = next(logs: logs)
        var lines = ["## \(name): \(weeks.count) weeks × \(days.count) days, \(progress.done) of \(progress.total) days done"]
        if !summary.isEmpty { lines.append(summary) }
        if let next {
            lines.append("Now: week \(next.week + 1), \(weeks[next.week].phase). Next day: \(days[next.day].name).")
        } else {
            lines.append("Finished.")
        }
        let current = next?.week ?? weeks.count
        if !lifts.isEmpty {
            lines.append("Training maxes now (at the start):")
            for lift in lifts {
                let now = trainingMax(for: lift.exercise, week: current, logs: logs)
                lines.append("- \(lift.exercise): \(kg(now)) (\(kg(lift.trainingMax))), +\(kg(lift.increment)) per rep beaten on a rep-out")
            }
        }
        lines.append("Days:")
        for day in days {
            var line = "- \(day.name): main " + (day.lifts.isEmpty ? "none" : day.lifts.joined(separator: ", "))
            if !day.accessories.isEmpty {
                line += "; accessories " + day.accessories.map { "\($0.exercise) \($0.sets) × \($0.reps)" }.joined(separator: ", ")
            }
            lines.append(line)
        }
        lines.append("Weeks (main-lift sets as % of training max):")
        for (index, week) in weeks.enumerated() {
            var line = "- W\(index + 1) \(week.phase)\(week.isDeload ? " (deload)" : ""): \(Self.setsText(week.sets))"
            if let target = week.amrapTarget { line += ", beat \(target) reps" }
            if index == next?.week { line += "  ← current" }
            lines.append(line)
        }
        let repOuts = logs.filter { weeks.indices.contains($0.week) && weeks[$0.week].amrapTarget != nil }
            .sorted { ($0.week, $0.day) < ($1.week, $1.day) }
            .flatMap { log in log.topReps.sorted { $0.key < $1.key }.map { "- W\(log.week + 1) \($0.key): \($0.value) reps (target \(weeks[log.week].amrapTarget ?? 0))" } }
        if !repOuts.isEmpty {
            lines.append("Rep-out results:")
            lines += repOuts
        }
        if !rules.isEmpty {
            lines.append("Rules:")
            lines += rules.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}
