import Foundation
import Observation
import TallyCore
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
    /// Workouts from Apple Health not recorded by Tally and not merged into a Tally workout, newest first.
    private(set) var healthWorkouts: [HealthWorkout] = []
    /// Notes pinned to exercises, by exercise ID.
    private(set) var exerciseNotes: [UUID: String]

    private let fileURL = URL.documentsDirectory.appending(path: "gym.json")
    /// A write waiting for typing to settle (see `saveSoon`).
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init() {
        var data = GymData()
        if let raw = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(GymData.self, from: raw) {
                data = decoded
            } else {
                // Keep what couldn't be read instead of overwriting it with an empty store.
                StoreFile.setAside(fileURL, stamp: String(Int(Date.now.timeIntervalSince1970)))
            }
        }
        // One copy from before 0.6 rewrites the file, in case the update has to be undone.
        StoreFile.backUpOnce(fileURL, to: URL.documentsDirectory.appending(path: "gym-before-0.6.json"))
        exercises = ExerciseLibrary.merge(into: data.exercises)
        workouts = data.workouts.sorted { $0.startedAt > $1.startedAt }
        plans = data.plans
        activeWorkout = data.activeWorkout
        exerciseNotes = Dictionary(uniqueKeysWithValues: (data.exerciseNotes ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        let migrated = migrateAssistedSets()
        if exercises != data.exercises || migrated { save() }
        recomputeRecords()
        writeSnapshot()
        if let activeWorkout {
            LiveActivityManager.shared.resume(for: activeWorkout, names: name(of:))
        } else {
            LiveActivityManager.shared.end()
        }
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        let data = GymData(exercises: exercises, workouts: workouts, plans: plans, activeWorkout: activeWorkout, exerciseNotes: exerciseNotes.isEmpty ? nil : Dictionary(uniqueKeysWithValues: exerciseNotes.map { ($0.key.uuidString, $0.value) }))
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    /// Saves shortly, so typing in a workout doesn't rewrite the whole log on every keystroke.
    /// `flush()` writes at once when the app leaves the foreground.
    func saveSoon() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes a waiting save now.
    func flush() {
        if pendingSave != nil { save() }
    }

    /// Drops a waiting save, for when the file on disk has just been replaced by a restore.
    func cancelPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
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

    /// Sets of assisted exercises saved before 0.6 hold the assistance in `weight`. Moves it to
    /// `assistance` so it isn't counted as volume. Does nothing once moved. Returns whether anything changed.
    private func migrateAssistedSets() -> Bool {
        let assisted = Set(exercises.filter { $0.kind == .assistedBodyweight }.map(\.id))
        guard !assisted.isEmpty else { return false }
        var changed = false
        func fix(_ list: inout [WorkoutExercise]) {
            for e in list.indices where assisted.contains(list[e].exerciseID) {
                for s in list[e].sets.indices where list[e].sets[s].weight != nil && list[e].sets[s].assistance == nil {
                    list[e].sets[s].assistance = list[e].sets[s].weight
                    list[e].sets[s].weight = nil
                    changed = true
                }
            }
        }
        for w in workouts.indices { fix(&workouts[w].exercises) }
        for p in plans.indices { fix(&plans[p].exercises) }
        if activeWorkout != nil { fix(&activeWorkout!.exercises) }
        return changed
    }

    func updateExercise(_ exercise: ExerciseDef) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[index] = exercise
        recomputeRecords()
        save()
    }

    /// The note pinned to an exercise, or "" when there is none.
    func pinnedNote(for exerciseID: UUID) -> String {
        exerciseNotes[exerciseID] ?? ""
    }

    func setPinnedNote(_ note: String, for exerciseID: UUID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != pinnedNote(for: exerciseID) else { return }
        exerciseNotes[exerciseID] = trimmed.isEmpty ? nil : trimmed
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
    func start(name: String, exercises templates: [WorkoutExercise], restSeconds: Int? = nil, planID: UUID? = nil, programDay: ProgramDayRef? = nil) {
        guard activeWorkout == nil else { isPresentingWorkout = true; return }
        let exercises = templates.map { template in
            WorkoutExercise(
                exerciseID: template.exerciseID,
                sets: template.sets.map { $0.copyForNewSet() },
                restSeconds: restSeconds ?? template.restSeconds,
                notes: template.notes,
                supersetID: template.supersetID
            )
        }
        .withRenewedSupersets()
        begin(Workout(name: name, startedAt: .now, exercises: exercises, planID: planID, programDay: programDay))
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

    func updateActive(_ workout: Workout, rest: ClosedRange<Date>?) {
        guard let previous = activeWorkout else { return }
        if previous != workout {
            activeWorkout = workout
            // Ticking a set off is saved at once; typing waits a moment.
            if previous.completedSets.count != workout.completedSets.count || previous.exercises.count != workout.exercises.count {
                save()
            } else {
                saveSoon()
            }
        }
        if previous.startedAt != workout.startedAt {
            // The lock screen timer counts from the start, which a Live Activity can't change.
            LiveActivityManager.shared.start(for: workout, names: name(of:))
        }
        LiveActivityManager.shared.update(for: workout, rest: rest, names: name(of:))
    }

    func newWorkoutExercise(for exercise: ExerciseDef) -> WorkoutExercise {
        // Same number of sets as last time (values come from the "Previous" column).
        let previousCount = previousSets(for: exercise.id).count
        let sets = (0..<max(previousCount, 1)).map { _ in WorkoutSet() }
        let timed = exercise.kind == .duration || exercise.kind == .distanceDuration
        return WorkoutExercise(exerciseID: exercise.id, sets: sets, restSeconds: timed ? 60 : defaultRestSeconds)
    }

    /// Saves the workout to history, keeping only completed sets. Returns false if nothing was completed.
    func finishWorkout(_ draft: Workout) -> Bool {
        var workout = draft
        // An end time set during the workout is kept, unless it is still to come.
        workout.endedAt = max(workout.startedAt, min(draft.endedAt ?? .now, .now))
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

    /// Whether the workout screen suggests what to load next (Settings › Progression).
    var showsProgression: Bool { UserDefaults.standard.object(forKey: "progression.enabled") as? Bool ?? true }

    /// The jump used when a suggestion goes heavier: the Settings choice, or by equipment when automatic (0).
    func progressionStep(for exerciseID: UUID, weight: Double) -> Double {
        let chosen = UserDefaults.standard.double(forKey: "progression.step")
        if chosen > 0 { return chosen }
        return Progression.step(equipment: exercise(exerciseID)?.equipment?.rawValue, weight: weight)
    }

    /// What to load next time, from the last sessions of the exercise: more weight once every set
    /// reached `targetReps`, the same weight while reps are missing, lighter after a plateau.
    func progression(for exerciseID: UUID, targetReps: Int?) -> Progression.Suggestion? {
        var history: [[Progression.PastSet]] = []
        for workout in workouts {
            let sets = workout.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
                .filter { $0.type == .normal && ($0.weight ?? 0) > 0 && ($0.reps ?? 0) > 0 }
                .map { Progression.PastSet(weight: $0.weight ?? 0, reps: $0.reps ?? 0, rpe: $0.rpe) }
            if !sets.isEmpty { history.append(sets) }
            if history.count == 3 { break }
        }
        guard let top = history.first?.map(\.weight).max() else { return nil }
        return Progression.suggest(sessions: history, targetReps: targetReps, step: progressionStep(for: exerciseID, weight: top))
    }

    /// Weight to try next time, for callers that only need the number.
    func suggestedWeight(for exerciseID: UUID, targetReps: Int?) -> (weight: Double, increase: Bool)? {
        progression(for: exerciseID, targetReps: targetReps).map { ($0.weight, $0.action == .increase) }
    }

    /// Last time's set to show beside each of today's sets: warm-ups pair with warm-ups and working
    /// sets with working sets, so an extra warm-up doesn't shift the whole column.
    func previousMatches(for exercise: WorkoutExercise) -> [WorkoutSet?] {
        let previous = previousSets(for: exercise.exerciseID)
        guard !previous.isEmpty else { return exercise.sets.map { _ in nil } }
        return PreviousSets.match(current: exercise.sets.map { $0.type == .warmup }, previous: previous.map { $0.type == .warmup })
            .map { $0.map { previous[$0] } }
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
                    guard let value = kind.value(of: set) else { continue }
                    if best.map({ kind.isBetter(value, than: $0.value) }) ?? true { best = (value, session.date) }
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
                    let scored = workingSets.compactMap { set in kind.value(of: set).map { (set: set, value: $0) } }
                    guard let best = scored.max(by: { kind.isBetter($1.value, than: $0.value) }) else { continue }
                    let earlier = previous?[kind]
                    let beatsEarlier = earlier.map { kind.isBetter(best.value, than: $0) } ?? true
                    // The first session of an exercise doesn't count as a record.
                    if previous != nil && beatsEarlier {
                        result[best.set.id, default: []].append(kind)
                    }
                    if beatsEarlier {
                        bests[exercise.exerciseID, default: [:]][kind] = best.value
                    }
                }
            }
        }
        records = result
    }

    // MARK: Apple Health

    /// Start dates of Tally and Health workouts, for the calendar, week streak and widget.
    var activityDates: [Date] { workouts.map(\.startedAt) + healthWorkouts.map(\.start) }

    /// Takes the latest workouts from Health. Links Tally workouts to the strength sessions that
    /// overlap them, and keeps the rest to show in History. Returns the IDs of Tally's own Health
    /// copies that are now duplicates (recent linked workouts that still have a saved copy).
    func applyHealthWorkouts(_ all: [HealthWorkout]) -> [UUID] {
        let plan = HealthLinking.plan(
            sessions: workouts.map { workout in
                LinkableSession(
                    id: workout.id,
                    interval: DateInterval(start: workout.startedAt, end: max(workout.endedAt ?? workout.startedAt, workout.startedAt)),
                    linkedHealthID: workout.linkedHealthID,
                    savedHealthID: workout.savedHealthID
                )
            },
            candidates: all.filter(\.isStrengthLike).map { (id: $0.id, interval: $0.interval) },
            now: .now
        )
        for index in workouts.indices {
            if let link = plan.links[workouts[index].id] { workouts[index].linkedHealthID = link }
        }
        let linked = Set(workouts.compactMap(\.linkedHealthID))
        healthWorkouts = all.filter { !linked.contains($0.id) }
        if !plan.links.isEmpty { save() }
        writeSnapshot()
        return plan.deletions
    }

    /// Tally's own copy in Health was deleted because a Watch session covers the workout.
    func healthCopyDeleted(_ healthID: UUID) {
        guard let index = workouts.firstIndex(where: { $0.savedHealthID == healthID }) else { return }
        workouts[index].savedHealthID = nil
        save()
    }

    /// Records how a finished workout reached Health: merged with a Watch session, or saved by Tally.
    func setHealthLink(for workoutID: UUID, linked: UUID?, saved: UUID?) {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        if let linked {
            workouts[index].linkedHealthID = linked
            healthWorkouts.removeAll { $0.id == linked }
        }
        if let saved { workouts[index].savedHealthID = saved }
        save()
        writeSnapshot()
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
            .withRenewedSupersets()
        )
    }

    /// Adds one plan per day of a ready-made routine. Returns how many were added.
    @discardableResult
    func addPlans(from template: PlanTemplate) -> Int {
        var added = 0
        for day in template.days {
            let exercises: [WorkoutExercise] = day.items.compactMap { item in
                guard let def = exercises.first(where: { !$0.isCustom && $0.name == item.exercise })
                    ?? exercises.first(where: { $0.name.caseInsensitiveCompare(item.exercise) == .orderedSame }) else { return nil }
                let timed = def.kind == .duration || def.kind == .distanceDuration
                // Start from last time's weight when the exercise has been done before.
                let lastWeight = previousSets(for: def.id).filter { $0.type == .normal }.compactMap(\.weight).max()
                let sets = (0..<item.sets).map { _ in
                    timed ? WorkoutSet(seconds: 45) : WorkoutSet(weight: def.kind == .weightReps ? lastWeight : nil, reps: item.reps)
                }
                return WorkoutExercise(exerciseID: def.id, sets: sets, restSeconds: item.rest)
            }
            guard !exercises.isEmpty else { continue }
            var name = day.name
            var copy = 2
            while plans.contains(where: { $0.name == name }) {
                name = "\(day.name) \(copy)"
                copy += 1
            }
            plans.append(Plan(name: name, exercises: exercises))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    /// The plan to train next: the one that has waited longest and whose muscles are rested.
    func upNext(now: Date = .now) -> (plan: Plan, pick: UpNext.Pick)? {
        guard !plans.isEmpty else { return nil }
        let candidates = plans.map { plan in
            UpNext.Candidate(
                id: plan.id,
                lastDone: sessions(of: plan).first?.startedAt,
                muscles: plan.exercises.compactMap { exercise($0.exerciseID) }.flatMap(\.primary).map(\.rawValue)
            )
        }
        var levels: [String: Double] = [:]
        for (muscle, status) in recovery(now: now) { levels[muscle.rawValue] = status.progress }
        guard let pick = UpNext.pick(candidates: candidates, recovery: levels, now: now),
              let plan = plans.first(where: { $0.id == pick.id }) else { return nil }
        return (plan, pick)
    }

    /// Workouts aimed for each week (Settings › Training); 0 when no goal is set.
    var weeklyGoal: Int { UserDefaults.standard.integer(forKey: "training.weeklyGoal") }

    /// The session before `workout` of the same plan (or with the same name), to compare against.
    func previousSession(like workout: Workout) -> Workout? {
        workouts.first { other in
            other.id != workout.id && other.startedAt < workout.startedAt
                && (workout.planID != nil ? other.planID == workout.planID : other.name == workout.name)
        }
    }

    // MARK: Recap

    /// Finished workouts reduced for the weekly recap.
    var sessionSummaries: [SessionSummary] {
        workouts.map { workout in
            var best: [UUID: Double] = [:]
            for exercise in workout.exercises where self.exercise(exercise.exerciseID)?.kind == .weightReps {
                let value = exercise.sets.filter { $0.type != .warmup }.map(\.estimatedOneRepMax).max() ?? 0
                if value > 0 { best[exercise.exerciseID] = max(best[exercise.exerciseID] ?? 0, value) }
            }
            return SessionSummary(
                start: workout.startedAt,
                duration: workout.duration,
                volume: workout.volume,
                sets: workout.completedSets.count,
                records: recordCount(in: workout),
                bestOneRepMax: best
            )
        }
    }

    func recap(weekOf date: Date) -> WeeklyRecap? {
        Recaps.recap(
            weekOf: date,
            sessions: sessionSummaries,
            activities: healthWorkouts.map { ActivitySummary(start: $0.start, duration: $0.duration, energy: $0.energy) }
        )
    }

    /// Working sets per muscle in `interval`, scaled to 0–1. Secondary muscles count half.
    /// Working sets per muscle per week in `interval`. A set counts fully for its exercise's primary
    /// muscles and half for its secondary muscles. Intervals shorter than a week aren't scaled up.
    func weeklyMuscleSets(in interval: DateInterval) -> [Muscle: Double] {
        var counts: [Muscle: Double] = [:]
        for workout in workouts where workout.startedAt >= interval.start && workout.startedAt < interval.end {
            for exercise in workout.exercises {
                guard let def = self.exercise(exercise.exerciseID) else { continue }
                let sets = Double(exercise.sets.filter { $0.type != .warmup }.count)
                for muscle in def.primary { counts[muscle, default: 0] += sets }
                for muscle in def.secondary { counts[muscle, default: 0] += sets / 2 }
            }
        }
        let weeks = max(interval.duration / (7 * 24 * 60 * 60), 1)
        return counts.filter { $0.value > 0 }.mapValues { $0 / weeks }
    }

    // MARK: Recovery and milestones

    /// How rested each muscle trained in the last week is. Primary sets count fully, secondary half,
    /// warm-ups not at all.
    func recovery(now: Date = .now) -> [Muscle: Recovery.Status] {
        let since = now.addingTimeInterval(-7 * 24 * 3600)
        var loads: [Recovery.Load] = []
        for workout in workouts where workout.startedAt >= since {
            var sets: [Muscle: Double] = [:]
            for exercise in workout.exercises {
                guard let def = self.exercise(exercise.exerciseID) else { continue }
                let count = Double(exercise.sets.filter { $0.type != .warmup }.count)
                for muscle in def.primary { sets[muscle, default: 0] += count }
                for muscle in def.secondary { sets[muscle, default: 0] += count / 2 }
            }
            let end = workout.endedAt ?? workout.startedAt
            loads += sets.map { Recovery.Load(muscle: $0.key.rawValue, date: end, sets: $0.value) }
        }
        var result: [Muscle: Recovery.Status] = [:]
        for (key, status) in Recovery.status(loads: loads, now: now) {
            if let muscle = Muscle(rawValue: key) { result[muscle] = status }
        }
        return result
    }

    /// Lifetime totals for milestones.
    var milestoneStats: MilestoneStats {
        MilestoneStats(
            workouts: workouts.count,
            volume: workouts.reduce(0) { $0 + $1.volume },
            hours: workouts.reduce(0) { $0 + $1.duration } / 3600,
            bestStreak: Streaks.longestWeekRun(activityDates),
            records: records.count,
            sets: workouts.reduce(0) { $0 + $1.completedSets.filter { $0.type != .warmup }.count }
        )
    }

    /// Milestone levels the workout just reached, by comparing totals with and without it.
    func milestonesReached(by workout: Workout) -> [Milestone] {
        guard workouts.contains(where: { $0.id == workout.id }) else { return [] }
        let after = milestoneStats
        var before = after
        before.workouts -= 1
        before.volume -= workout.volume
        before.hours -= workout.duration / 3600
        before.records -= recordCount(in: workout)
        before.sets -= workout.completedSets.filter { $0.type != .warmup }.count
        var dates = activityDates
        if let index = dates.firstIndex(of: workout.startedAt) { dates.remove(at: index) }
        before.bestStreak = Streaks.longestWeekRun(dates)
        return Milestones.newlyReached(before: before, after: after)
    }

    // MARK: Stats

    /// Start of the week containing `date`.
    func weekStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Consecutive weeks (ending this week or last week) with at least one workout.
    var weekStreak: Int {
        let weeks = Set(activityDates.map { weekStart($0) })
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
            workoutDates: activityDates.filter { $0 >= since },
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
