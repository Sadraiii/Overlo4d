import Foundation
import Overlo4dCore

/// Cardio, deload weeks, strength forecasts, the weekly report and importing from other apps.
extension GymStore {
    // MARK: Deload

    var isDeloading: Bool { Deload.isActive(start: deloadStart, now: .now) }

    /// Fewer working sets while a deload week runs; warm-ups and everything else stay.
    func deloaded(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        guard isDeloading else { return sets }
        let keep = Deload.sets(sets.filter { $0.type == .normal }.count)
        var seen = 0
        return sets.filter { set in
            guard set.type == .normal else { return true }
            seen += 1
            return seen <= keep
        }
    }

    /// Whether an easier week is due, from the last twelve weeks of training.
    func deloadAdvice(now: Date = .now) -> Deload.Advice? {
        guard !isDeloading else { return nil }
        let calendar = Calendar.current
        let thisWeek = weekStart(now)
        let weeks: [Deload.Week] = (0..<12).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = workouts.filter { $0.startedAt >= start && $0.startedAt < end }
            let sets = inWeek.reduce(0) { $0 + $1.completedSets.filter { $0.type != .warmup }.count }
            return Deload.Week(start: start, sessions: inWeek.count, hardSets: sets)
        }

        // The five lifts trained most in the last eight weeks, with their last five sessions.
        let since = now.addingTimeInterval(-56 * 86_400)
        var counts: [UUID: Int] = [:]
        for workout in workouts where workout.startedAt >= since {
            for item in workout.exercises where exercise(item.exerciseID)?.kind == .weightReps {
                counts[item.exerciseID, default: 0] += 1
            }
        }
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.uuidString < $1.key.uuidString }.prefix(5)
        let lifts = top.map { id, _ in
            let recent = sessions(for: id).prefix(5).reversed().map { session in
                session.sets.filter { $0.type != .warmup }.map(\.estimatedOneRepMax).max() ?? 0
            }
            return Deload.Lift(name: name(of: id), recent: Array(recent))
        }

        let rated = workouts.filter { $0.startedAt >= now.addingTimeInterval(-14 * 86_400) }
            .flatMap(\.completedSets).filter { $0.type != .warmup }.compactMap(\.rpe)
        let effort = rated.count >= 6 ? rated.reduce(0, +) / Double(rated.count) : nil
        return Deload.assess(weeks: weeks, lifts: lifts, averageRPE: effort, lastDeload: deloadStart)
    }

    func startDeload() {
        deloadStart = .now
    }

    /// Ends a running deload early. The start date is kept so the hard-week count restarts from it.
    func endDeload() {
        guard isDeloading else { return }
        deloadStart = Date.now.addingTimeInterval(-Double(Deload.days) * 86_400)
    }

    // MARK: Forecast

    /// Where the lift's estimated max is heading. Nil for other kinds of exercise or too little history.
    func forecast(for exercise: ExerciseDef, now: Date = .now) -> StrengthForecast.Result? {
        guard exercise.kind == .weightReps else { return nil }
        let points = sessions(for: exercise.id).compactMap { session -> StrengthForecast.Point? in
            let best = session.sets.filter { $0.type != .warmup }.map(\.estimatedOneRepMax).max() ?? 0
            return best > 0 ? StrengthForecast.Point(date: session.date, oneRepMax: best) : nil
        }
        return StrengthForecast.forecast(points, now: now, unit: Units.weight)
    }

    // MARK: Cardio

    func saveCardio(_ session: CardioSession) {
        if let index = cardio.firstIndex(where: { $0.id == session.id }) {
            cardio[index] = session
        } else {
            cardio.append(session)
        }
        cardio.sort { $0.start > $1.start }
        save()
        refreshWidgets()
    }

    func deleteCardio(_ session: CardioSession) {
        cardio.removeAll { $0.id == session.id }
        save()
        refreshWidgets()
    }

    func setCardioHealthID(_ healthID: UUID?, for id: UUID) {
        guard let index = cardio.firstIndex(where: { $0.id == id }) else { return }
        cardio[index].savedHealthID = healthID
        save()
    }

    // MARK: Weekly report

    /// Weeks in a row with a workout or cardio, ending with the week of `date`.
    func weekStreak(endingAt date: Date) -> Int {
        let weeks = Set(activityDates.map { weekStart($0) })
        var week = weekStart(date)
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            week = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: week) ?? week.addingTimeInterval(-7 * 86_400)
        }
        return streak
    }

    /// The written review of the week containing `date`.
    func weeklyReport(weekOf date: Date, sleepHours: Double? = nil, sleepGoalHours: Double? = nil, now: Date = .now) -> WeeklyReport.Report? {
        guard let recap = recap(weekOf: date) else { return nil }
        let week = recap.week
        let end = min(week.end, now)
        var improved: (name: String, percent: Double)?
        if let best = recap.mostImproved, best.before > 0 {
            improved = (name(of: best.exerciseID), best.change / best.before * 100)
        }
        let totals = CardioTotals.totals(cardio, in: week)
        let other = healthWorkouts.filter { !$0.isStrengthLike && $0.start >= week.start && $0.start < week.end }
        let isRecent = week.end > now.addingTimeInterval(-8 * 86_400)
        let wasDeload = deloadStart.map { $0 >= week.start.addingTimeInterval(-3 * 86_400) && $0 < week.end.addingTimeInterval(-2 * 86_400) } ?? false
        var names: [String: String] = [:]
        for muscle in Muscle.allCases { names[muscle.rawValue] = muscle.label }
        return WeeklyReport.build(.init(
            totals: recap.totals,
            previous: recap.previous,
            weeklyGoal: weeklyGoal,
            mostImproved: improved,
            flags: recap.totals.workouts > 0 ? loadReport(now: end).flags : [],
            muscleNames: names,
            cardioSessions: totals.sessions + other.count,
            cardioMinutes: totals.seconds / 60 + Int(other.reduce(0) { $0 + $1.duration } / 60),
            streakWeeks: weekStreak(endingAt: week.start),
            deload: isRecent ? deloadAdvice(now: now) : nil,
            wasDeload: wasDeload,
            sleepHours: sleepHours,
            sleepGoalHours: sleepGoalHours,
            unit: Units.weight
        ))
    }

    // MARK: Import

    struct ImportSummary: Equatable {
        var workouts = 0
        var sets = 0
        var duplicates = 0
        /// Names of exercises that aren't in the library and will be added as custom ones.
        var newExercises: [String] = []
    }

    /// What importing would add, without changing anything.
    func importSummary(_ imported: [WorkoutImport.ImportedWorkout]) -> ImportSummary {
        var summary = ImportSummary()
        let starts = workouts.map(\.startedAt)
        let names = exercises.map(\.name)
        var unknown: [String] = []
        for workout in imported {
            if WorkoutImport.isDuplicate(workout.start, of: starts) {
                summary.duplicates += 1
                continue
            }
            summary.workouts += 1
            summary.sets += workout.setCount
            for item in workout.exercises where WorkoutImport.match(item.name, in: names) == nil {
                if !unknown.contains(where: { WorkoutImport.nameKey($0) == WorkoutImport.nameKey(item.name) }) { unknown.append(item.name) }
            }
        }
        summary.newExercises = unknown
        return summary
    }

    /// Adds imported workouts to history. Workouts already in the log (same start time) are skipped,
    /// and exercises the library doesn't know are added as custom exercises.
    @discardableResult
    func importWorkouts(_ imported: [WorkoutImport.ImportedWorkout]) -> ImportSummary {
        let summary = importSummary(imported)
        let starts = workouts.map(\.startedAt)
        var added: [Workout] = []
        var newDefs: [ExerciseDef] = []

        func definition(for item: WorkoutImport.ImportedExercise) -> ExerciseDef {
            let known = exercises + newDefs
            if let index = WorkoutImport.match(item.name, in: known.map(\.name)) { return known[index] }
            let def = ExerciseDef(name: item.name, muscle: .other, kind: ExerciseKind(rawValue: item.kind) ?? .weightReps, isCustom: true)
            newDefs.append(def)
            return def
        }

        for workout in imported where !WorkoutImport.isDuplicate(workout.start, of: starts) {
            var supersets: [String: UUID] = [:]
            var items: [WorkoutExercise] = workout.exercises.map { item in
                let def = definition(for: item)
                let sets = item.sets.map { set in
                    // An assisted exercise keeps its help apart from weight, so it never counts as volume.
                    let assisted = def.kind == .assistedBodyweight
                    return WorkoutSet(
                        type: SetType(rawValue: set.type) ?? .normal,
                        weight: assisted ? nil : set.weight,
                        reps: set.reps,
                        seconds: set.seconds,
                        assistance: assisted ? (set.assistance ?? set.weight) : set.assistance,
                        meters: set.meters,
                        isDone: true,
                        rpe: set.rpe.flatMap { (1...10).contains($0) ? $0 : nil }
                    )
                }
                var supersetID: UUID?
                if let key = item.superset {
                    supersetID = supersets[key] ?? UUID()
                    supersets[key] = supersetID
                }
                return WorkoutExercise(exerciseID: def.id, sets: sets, restSeconds: defaultRestSeconds, notes: item.notes, supersetID: supersetID)
            }
            items.normalizeSupersets()
            let end = workout.end.map { max($0, workout.start) } ?? workout.start.addingTimeInterval(3600)
            added.append(Workout(name: workout.name, startedAt: workout.start, endedAt: end, exercises: items, notes: workout.notes))
        }
        guard !added.isEmpty else { return summary }
        addImported(workouts: added, exercises: newDefs)
        return summary
    }
}
