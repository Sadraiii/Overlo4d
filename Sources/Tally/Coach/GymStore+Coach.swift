import Foundation
import TallyCore

extension Muscle {
    /// Muscles the load check expects some direct work for.
    static let coachWatch: [Muscle] = [.chest, .lats, .upperBack, .sideDelts, .rearDelts, .biceps, .triceps, .quads, .hamstrings, .glutes]

    /// The label for a muscle key from TallyCore.
    static func label(_ key: String) -> String {
        Muscle(rawValue: key)?.label ?? key
    }
}

extension GymStore {
    static let balancePairs = [
        BalancePair(
            name: "Push and pull",
            first: .init("Push", [Muscle.chest, .frontDelts, .triceps].map(\.rawValue)),
            second: .init("Pull", [Muscle.lats, .upperBack, .rearDelts, .biceps].map(\.rawValue))
        ),
        BalancePair(
            name: "Front and back of the thighs",
            first: .init("Quads", [Muscle.quads.rawValue]),
            second: .init("Hamstrings", [Muscle.hamstrings.rawValue])
        ),
    ]

    /// Every exercise in history with its muscles and working sets.
    var muscleWork: [MuscleWork] {
        workouts.flatMap { workout in
            workout.exercises.compactMap { item -> MuscleWork? in
                guard let def = exercise(item.exerciseID) else { return nil }
                return MuscleWork(
                    date: workout.startedAt,
                    primary: def.primary.map(\.rawValue),
                    secondary: def.secondary.map(\.rawValue),
                    sets: item.sets.filter { $0.type != .warmup }.count
                )
            }
        }
    }

    func loadReport(now: Date = .now) -> LoadReport {
        TrainingLoad.report(
            muscleWork,
            now: now,
            watch: Muscle.coachWatch.map(\.rawValue),
            pairs: Self.balancePairs
        )
    }

    /// The text sent to Claude: the last 4 weeks of workouts and other activity, the weekly sets
    /// per muscle and the load check. `focus` is included and marked even when it is older.
    func coachPrompt(focus: Workout?, goal: String, now: Date = .now) -> String {
        let since = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now
        var recent = Array(workouts.filter { $0.startedAt >= since && $0.startedAt <= now }.prefix(40))
        if let focus, !recent.contains(where: { $0.id == focus.id }) { recent.append(focus) }

        var digest = recent.map { workout in
            DigestWorkout(
                name: workout.name,
                date: workout.startedAt,
                minutes: Int(workout.duration / 60),
                exercises: workout.exercises.map { item in
                    let def = exercise(item.exerciseID)
                    return DigestWorkout.Exercise(
                        name: def?.name ?? "Deleted exercise",
                        muscles: def.map(Self.muscleText) ?? "",
                        sets: item.sets.map { set in
                            let text = Fmt.set(set, kind: def?.kind ?? .weightReps)
                            return set.type == .normal ? text : "\(set.type.badge) \(text)"
                        },
                        notes: item.notes
                    )
                },
                notes: workout.notes,
                isFocus: workout.id == focus?.id
            )
        }
        // Runs, rides and the like from Apple Health count towards recovery too.
        for activity in healthWorkouts where activity.start >= since && activity.start <= now && !activity.isStrengthLike {
            var name = "\(activity.name) (from \(activity.sourceName)"
            if let meters = activity.meters, meters > 0 { name += ", \(Pace.distance(meters))" }
            name += ")"
            digest.append(DigestWorkout(name: name, date: activity.start, minutes: Int(activity.duration / 60), exercises: []))
        }

        let report = loadReport(now: now)
        let weekly = report.lastWeek
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (muscle: Muscle.label($0.key), sets: $0.value, usual: report.usualWeek[$0.key]) }

        let focusKind: CoachFocus = focus.map { .workout(name: $0.name, date: $0.startedAt) } ?? .overall
        return CoachAPI.prompt(
            focus: focusKind,
            goal: goal,
            workouts: digest,
            load: report.flags.map { "\($0.title). \($0.detail)" },
            weekly: weekly,
            now: now
        )
    }

    /// "Chest; also Front delts, Triceps".
    nonisolated private static func muscleText(_ def: ExerciseDef) -> String {
        let primary = def.primary.isEmpty ? def.muscle.label : def.primary.map(\.label).joined(separator: ", ")
        return def.secondary.isEmpty ? primary : "\(primary); also \(def.secondary.map(\.label).joined(separator: ", "))"
    }
}

extension LoadFlag {
    var title: String {
        switch self {
        case .tooMuch(let muscle, let sets):
            "\(Muscle.label(muscle)): \(Self.format(sets)) sets in 7 days"
        case .spike(let muscle, let sets, let usual):
            "\(Muscle.label(muscle)): \(Self.format(sets)) sets, up from \(Self.format(usual))"
        case .shortRecovery(let muscle, let hours):
            "\(Muscle.label(muscle)) trained hard again after \(Int(hours.rounded())) h"
        case .imbalance(_, let more, let less, let ratio):
            ratio.isFinite
                ? "\(more) gets \(Self.format(ratio))× the work of \(less)"
                : "\(more) work but no \(less.lowercased())"
        case .neglected(let muscle, let days):
            days.map { "No \(Muscle.label(muscle).lowercased()) work in \($0) days" }
                ?? "No \(Muscle.label(muscle).lowercased()) work yet"
        }
    }

    var detail: String {
        switch self {
        case .tooMuch:
            "Past about 20 hard sets a week, a muscle usually stops recovering in time. Drop a few sets or an exercise."
        case .spike:
            "A sudden jump makes soreness and strain more likely. Add volume over a few weeks instead."
        case .shortRecovery:
            "Muscles need about 48 hours between hard sessions to recover and grow."
        case .imbalance(let pair, _, _, _):
            "Over the last 4 weeks (\(pair.lowercased())). Evening it out protects your joints and posture."
        case .neglected:
            "You've trained the rest of the body. Add an exercise for it so it keeps up."
        }
    }

    var symbol: String {
        switch severity {
        case 2: "exclamationmark.triangle.fill"
        case 1: "arrow.up.right"
        default: "lightbulb"
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
