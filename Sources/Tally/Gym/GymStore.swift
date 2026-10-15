import Foundation
import Observation
import TallyKit
import WidgetKit

/// One logged session of an exercise, used for history and charts.
struct ExerciseSession: Identifiable, Hashable {
    var id: UUID { workoutID }
    let workoutID: UUID
    let workoutName: String
    let date: Date
    let sets: [WorkoutSet]
}

@MainActor
@Observable
final class GymStore {
    private(set) var exercises: [ExerciseDef]
    /// Finished workouts, newest first.
    private(set) var workouts: [Workout]
    private(set) var plans: [Plan]
    /// The workout in progress. The workout screen edits its own copy and pushes changes via `updateActive`.
    private(set) var activeWorkout: Workout?
    /// Whether the workout screen is shown (vs. minimized to the bottom bar).
    var isPresentingWorkout = false
    /// The workout that was just finished, shown on the summary screen.
    private(set) var summaryWorkout: Workout?
    /// Set IDs that were personal records at the time, with the record kinds they set.
    private(set) var records: [UUID: [RecordKind]] = [:]

    private let fileURL = URL.documentsDirectory.appending(path: "gym.json")

    init() {
        let data = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(GymData.self, from: $0) } ?? GymData()
        exercises = ExerciseLibrary.merge(into: data.exercises)
        workouts = data.workouts.sorted { $0.startedAt > $1.startedAt }
        plans = data.plans
        activeWorkout = data.activeWorkout
        if exercises != data.exercises { save() }
        recomputeRecords()
        writeSnapshot()
        if let activeWorkout {
            LiveActivityManager.shared.resume(for: activeWorkout, names: name(of:))
        } else {
            LiveActivityManager.shared.end()
        }
    }

    func save() {
        let data = GymData(exercises: exercises, workouts: workouts, plans: plans, activeWorkout: activeWorkout)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    // MARK: Exercises

    func exercise(_ id: UUID) -> ExerciseDef? {
        exercises.first { $0.id == id }
    }

    func name(of id: UUID) -> String {
        exercise(id)?.name ?? "Deleted Exercise"
    }

    func addExercise(_ exercise: ExerciseDef) {
        exercises.append(exercise)
        save()
    }

    func updateExercise(_ exercise: ExerciseDef) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[index] = exercise
        recomputeRecords()
        save()
    }

    func isUsed(_ exercise: ExerciseDef) -> Bool {
        workouts.contains { $0.exercises.contains { $0.exerciseID == exercise.id } }
            || plans.contains { $0.exercises.contains { $0.exerciseID == exercise.id } }
    }

    func deleteExercise(_ exercise: ExerciseDef) {
        exercises.removeAll { $0.id == exercise.id }
        save()
    }

    // MARK: Active workout

    func startEmptyWorkout() {
        guard activeWorkout == nil else { isPresentingWorkout = true; return }
        begin(Workout(name: defaultWorkoutName(), startedAt: .now, exercises: []))
    }

    func startWorkout(from plan: Plan) {
        start(name: plan.name, exercises: plan.exercises, planID: plan.id)
    }

    /// Starts a workout from template exercises (an empty list, a plan or a past workout).
    func start(name: String, exercises templates: [WorkoutExercise], restSeconds: Int? = nil, planID: UUID? = nil) {
        guard activeWorkout == nil else { isPresentingWorkout = true; return }
        let exercises = templates.map { template in
            WorkoutExercise(
                exerciseID: template.exerciseID,
                sets: template.sets.map { $0.copyForNewSet() },
                restSeconds: restSeconds ?? template.restSeconds,
                notes: template.notes
            )
        }
        begin(Workout(name: name, startedAt: .now, exercises: exercises, planID: planID))
    }

    /// Rest timer used for exercises added to a workout (set on the start sheet).
    var defaultRestSeconds: Int {
        get { UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Int ?? 90 }
        set { UserDefaults.standard.set(newValue, forKey: "defaultRestSeconds") }
    }

    private func begin(_ workout: Workout) {
        summaryWorkout = nil
        activeWorkout = workout
        isPresentingWorkout = true
        save()
        LiveActivityManager.shared.start(for: workout, names: name(of:))
    }

    func updateActive(_ workout: Workout, restEndsAt: Date?) {
        guard activeWorkout != nil else { return }
        if activeWorkout != workout {
            activeWorkout = workout
            save()
        }
        LiveActivityManager.shared.update(for: workout, restEndsAt: restEndsAt, names: name(of:))
    }

    func newWorkoutExercise(for exercise: ExerciseDef) -> WorkoutExercise {
        // Same number of sets as last time (values come from the "Previous" column).
        let previousCount = previousSets(for: exercise.id).count
        let sets = (0..<max(previousCount, 1)).map { _ in WorkoutSet() }
        return WorkoutExercise(exerciseID: exercise.id, sets: sets, restSeconds: exercise.kind == .duration ? 60 : defaultRestSeconds)
    }

    /// Saves the workout to history, keeping only completed sets. Returns false if nothing was completed.
    func finishWorkout(_ draft: Workout) -> Bool {
        var workout = draft
        workout.endedAt = .now
        workout.exercises = workout.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.sets = exercise.sets.filter { $0.isDone && $0.hasValues }
            return exercise.sets.isEmpty ? nil : exercise
        }
        guard !workout.exercises.isEmpty else { return false }
        workouts.insert(workout, at: 0)
        activeWorkout = nil
        summaryWorkout = workout
        recomputeRecords()
        save()
        writeSnapshot()
        LiveActivityManager.shared.end()
        return true
    }

    func discardActiveWorkout() {
        activeWorkout = nil
        isPresentingWorkout = false
        save()
        LiveActivityManager.shared.end()
    }

    func closeSummary() {
        isPresentingWorkout = false
        summaryWorkout = nil
    }

    func defaultWorkoutName() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Morning Workout"
        case 12..<17: "Afternoon Workout"
        case 17..<22: "Evening Workout"
        default: "Night Workout"
        }
    }

    // MARK: History

    func workout(_ id: UUID) -> Workout? {
        workouts.first { $0.id == id }
    }

    func deleteWorkout(_ workout: Workout) {
        workouts.removeAll { $0.id == workout.id }
        recomputeRecords()
        save()
        writeSnapshot()
    }

    func updateWorkout(_ workout: Workout) {
        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        workouts[index] = workout
        workouts.sort { $0.startedAt > $1.startedAt }
        recomputeRecords()
        save()
        writeSnapshot()
    }

    /// Finished workouts done from a plan, newest first. Workouts from before plans were linked are matched by name.
    func sessions(of plan: Plan) -> [Workout] {
        workouts.filter { $0.planID == plan.id || ($0.planID == nil && $0.name == plan.name) }
    }

    /// When the exercise was last done, with its sets.
    func lastSession(for exerciseID: UUID) -> ExerciseSession? {
        sessions(for: exerciseID).first
    }

    /// Weight to try next time: 2.5 kg more when every working set at last time's top weight reached
    /// `targetReps` (or the reps of the first working set, if no target), otherwise the same weight.
    func suggestedWeight(for exerciseID: UUID, targetReps: Int?) -> (weight: Double, increase: Bool)? {
        let working = previousSets(for: exerciseID).filter { $0.type == .normal && ($0.weight ?? 0) > 0 }
        guard let top = working.compactMap(\.weight).max() else { return nil }
        let atTop = working.filter { $0.weight == top }
        let target = targetReps ?? working.first?.reps ?? 0
        let hitAll = target > 0 && atTop.allSatisfy { ($0.reps ?? 0) >= target }
        return hitAll ? (top + 2.5, true) : (top, false)
    }

    /// Completed sets from the most recent finished workout containing the exercise.
    func previousSets(for exerciseID: UUID) -> [WorkoutSet] {
        for workout in workouts {
            if let exercise = workout.exercises.first(where: { $0.exerciseID == exerciseID }) {
                return exercise.sets
            }
        }
        return []
    }

    /// All sessions of an exercise, newest first.
    func sessions(for exerciseID: UUID) -> [ExerciseSession] {
        workouts.compactMap { workout in
            let sets = workout.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
            guard !sets.isEmpty else { return nil }
            return ExerciseSession(workoutID: workout.id, workoutName: workout.name, date: workout.startedAt, sets: sets)
        }
    }

    /// Best value ever for each record kind of an exercise, with the date it was set.
    func bests(for exercise: ExerciseDef) -> [(kind: RecordKind, value: Double, date: Date)] {
        let sessions = sessions(for: exercise.id)
        return RecordKind.kinds(for: exercise.kind).compactMap { kind in
            var best: (value: Double, date: Date)?
            for session in sessions {
                for set in session.sets where set.type != .warmup {
                    let value = kind.value(of: set)
                    if value > 0, value > (best?.value ?? 0) { best = (value, session.date) }
                }
            }
            return best.map { (kind, $0.value, $0.date) }
        }
    }

    func recordCount(in workout: Workout) -> Int {
        workout.allSets.reduce(0) { $0 + (records[$1.id] == nil ? 0 : 1) }
    }

    /// Walks history oldest → newest and marks the best set of each session that beats all earlier sessions.
    /// The very first session of an exercise doesn't count as a record.
    private func recomputeRecords() {
        var bests: [UUID: [RecordKind: Double]] = [:]
        var result: [UUID: [RecordKind]] = [:]
        for workout in workouts.reversed() {
            for exercise in workout.exercises {
                guard let def = self.exercise(exercise.exerciseID) else { continue }
                let previous = bests[exercise.exerciseID]
                let workingSets = exercise.sets.filter { $0.type != .warmup }
                for kind in RecordKind.kinds(for: def.kind) {
                    guard let best = workingSets.max(by: { kind.value(of: $0) < kind.value(of: $1) }) else { continue }
                    let value = kind.value(of: best)
                    guard value > 0 else { continue }
                    if let previous, value > (previous[kind] ?? 0) {
                        result[best.id, default: []].append(kind)
                    }
                    bests[exercise.exerciseID, default: [:]][kind] = max(value, previous?[kind] ?? 0)
                }
            }
        }
        records = result
    }

    // MARK: Plans

    func savePlan(_ plan: Plan) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        save()
    }

    func deletePlan(_ plan: Plan) {
        plans.removeAll { $0.id == plan.id }
        save()
    }

    func duplicatePlan(_ plan: Plan) {
        var copy = plan
        copy.id = UUID()
        copy.name += " Copy"
        savePlan(copy)
    }

    func plan(from workout: Workout) -> Plan {
        Plan(
            name: workout.name,
            exercises: workout.exercises.map { exercise in
                var copy = exercise
                copy.id = UUID()
                copy.sets = exercise.sets.map { $0.copyForNewSet() }
                return copy
            }
        )
    }

    // MARK: Stats

    /// Start of the week containing `date`.
    func weekStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Consecutive weeks (ending this week or last week) with at least one workout.
    var weekStreak: Int {
        let weeks = Set(workouts.map { weekStart($0.startedAt) })
        var week = weekStart(.now)
        if !weeks.contains(week) {
            week = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            week = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        return streak
    }

    var snapshot: ActivitySnapshot {
        let since = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
        let last = workouts.first.map {
            ActivitySnapshot.LastWorkout(
                name: $0.name,
                date: $0.startedAt,
                duration: $0.duration,
                volume: $0.volume,
                sets: $0.completedSets.count,
                records: recordCount(in: $0)
            )
        }
        return ActivitySnapshot(
            workoutDates: workouts.map(\.startedAt).filter { $0 >= since },
            weekStreak: weekStreak,
            lastWorkout: last
        )
    }

    /// Shares a summary with the Training widget.
    private func writeSnapshot() {
        SharedStorage.save(snapshot, to: SharedStorage.activityFile)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.training)
    }
}
