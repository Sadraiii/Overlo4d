import Foundation
import TallyKit

/// The content of a share image, independent of its layout.
struct ShareModel {
    struct Stat: Hashable {
        let label: String
        let value: String
        var unit = ""
    }

    struct Line: Hashable {
        let lead: String
        let text: String
        var detail: String?
    }

    var eyebrow: String
    var title: String
    var hero: Stat?
    var stats: [Stat]
    var lines: [Line]
    /// Seven flags for a week strip (week recap only).
    var days: [Bool]?
    var todayIndex: Int?
    var footer: String
    var fileName: String
}

extension ShareModel {
    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "1:05" h or "48" min.
    private static func duration(_ interval: TimeInterval) -> Stat {
        let minutes = Int(interval / 60)
        return minutes >= 60
            ? Stat(label: "Time", value: String(format: "%d:%02d", minutes / 60, minutes % 60), unit: "h")
            : Stat(label: "Time", value: "\(minutes)", unit: "min")
    }

    @MainActor
    static func workout(_ workout: Workout, gym: GymStore, health: HealthManager.WorkoutHealth?) -> ShareModel {
        let records = gym.recordCount(in: workout)
        var stats: [Stat] = []
        let hero: Stat
        if workout.volume > 0 {
            hero = Stat(label: "Volume", value: Int(workout.volume.rounded()).formatted(), unit: "kg")
            stats.append(duration(workout.duration))
        } else {
            hero = duration(workout.duration)
        }
        stats.append(Stat(label: "Sets", value: "\(workout.completedSets.count)"))
        if records > 0 { stats.append(Stat(label: "Records", value: "\(records)")) }
        if let kcal = health?.activeEnergy, kcal >= 1 { stats.append(Stat(label: "Energy", value: "\(Int(kcal.rounded()))", unit: "kcal")) }
        if let bpm = health?.averageHeartRate { stats.append(Stat(label: "Avg HR", value: "\(Int(bpm.rounded()))", unit: "bpm")) }

        let lines = workout.exercises.map { exercise -> Line in
            let def = gym.exercise(exercise.exerciseID)
            let kind = def?.kind ?? .weightReps
            let best = exercise.sets.filter { $0.type != .warmup }.max {
                switch kind {
                case .weightReps, .weightedBodyweight: ($0.weight ?? 0, $0.reps ?? 0) < ($1.weight ?? 0, $1.reps ?? 0)
                case .assistedBodyweight: (-($0.assistance ?? 0), $0.reps ?? 0) < (-($1.assistance ?? 0), $1.reps ?? 0)
                case .repsOnly: ($0.reps ?? 0) < ($1.reps ?? 0)
                case .duration: ($0.seconds ?? 0) < ($1.seconds ?? 0)
                case .distanceDuration: ($0.meters ?? 0, $0.seconds ?? 0) < ($1.meters ?? 0, $1.seconds ?? 0)
                }
            }
            return Line(lead: "\(exercise.sets.count)×", text: def?.name ?? "Exercise", detail: best.map { Fmt.set($0, kind: kind) })
        }

        let end = workout.endedAt ?? workout.startedAt
        let time = "\(workout.startedAt.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
        return ShareModel(
            eyebrow: "Strength · \(shortDate(workout.startedAt))",
            title: workout.name,
            hero: hero,
            stats: stats,
            lines: lines,
            footer: "\(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) · \(time)",
            fileName: "Overload \(workout.name)"
        )
    }

    @MainActor
    static func week(containing date: Date, gym: GymStore) -> ShareModel {
        let start = gym.weekStart(date)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let workouts = gym.workouts.filter { gym.weekStart($0.startedAt) == start }
        let week = Calendar.current.component(.weekOfYear, from: start)

        var setsPerExercise: [UUID: Int] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                setsPerExercise[exercise.exerciseID, default: 0] += exercise.sets.count
            }
        }
        let lines = setsPerExercise.sorted { $0.value > $1.value }.map {
            Line(lead: "\($0.value)", text: gym.name(of: $0.key), detail: "sets")
        }

        let range = "\(start.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated)))"
        return ShareModel(
            eyebrow: "Week \(week) · \(range)",
            title: "Training week",
            hero: Stat(label: "Workouts", value: "\(workouts.count)"),
            stats: [
                Stat(label: "Volume", value: Int(workouts.reduce(0) { $0 + $1.volume }.rounded()).formatted(), unit: "kg"),
                duration(workouts.reduce(0) { $0 + $1.duration }),
                Stat(label: "Sets", value: "\(workouts.reduce(0) { $0 + $1.completedSets.count })"),
            ],
            lines: lines,
            days: gym.snapshot.trainedDays(inWeekOf: date),
            todayIndex: Calendar.current.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
                ? ActivitySnapshot.weekdayIndex() : nil,
            footer: "Week \(week), \(start.formatted(.dateTime.year()))",
            fileName: "Overload week \(week)"
        )
    }

    @MainActor
    static func reps(_ model: RepModel) -> ShareModel {
        let lines = model.exercises
            .map { (exercise: $0, reps: model.repsToday(for: $0)) }
            .filter { $0.reps > 0 }
            .sorted { $0.reps > $1.reps }
            .map { Line(lead: "\($0.reps)", text: $0.exercise.name) }
        return ShareModel(
            eyebrow: "Reps · \(shortDate(.now))",
            title: "Daily reps",
            hero: Stat(label: "Today", value: "\(model.repsToday)", unit: "reps"),
            stats: [Stat(label: "Goal", value: "\(model.dailyGoal)")],
            lines: lines,
            footer: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()),
            fileName: "Overload reps"
        )
    }
}
