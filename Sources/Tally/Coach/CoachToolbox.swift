import Foundation
import TallyCore

/// Runs the chat coach's tools on the data in the app. Nothing leaves the phone except what a tool returns.
@MainActor
struct CoachToolbox {
    let gym: GymStore
    let sleep: SleepStore
    let food: FoodStore
    let body: BodyStore
    let programs: ProgramStore
    var now: Date = .now

    func run(_ call: CoachToolCall) -> CoachToolResult {
        guard let tool = CoachTool(rawValue: call.name) else {
            return CoachToolResult(id: call.id, text: "There is no tool called \(call.name).", isError: true)
        }
        switch tool {
        case .getWorkouts:
            return CoachToolResult(id: call.id, text: workouts(days: min(max(call.input["days"]?.int ?? 28, 1), 365)))
        case .getExerciseHistory:
            return history(call)
        case .searchExercises:
            return CoachToolResult(id: call.id, text: search(call.input["query"]?.string ?? ""))
        case .getWeeklySets:
            return CoachToolResult(id: call.id, text: weeklySets(weeks: min(max(call.input["weeks"]?.int ?? 4, 1), 12)))
        case .getSleep:
            return CoachToolResult(id: call.id, text: sleep.coachLines().map { "- \($0)" }.joined(separator: "\n"))
        case .getFood:
            return CoachToolResult(id: call.id, text: food.coachLines().map { "- \($0)" }.joined(separator: "\n"))
        case .getBody:
            let lines = body.coachLines()
            return CoachToolResult(id: call.id, text: lines.isEmpty ? "No body measurements logged." : lines.map { "- \($0)" }.joined(separator: "\n"))
        case .getPlans:
            return CoachToolResult(id: call.id, text: plans())
        case .getPrograms:
            let text = programs.programs.map { $0.coachText(logs: programs.logs(for: $0, gym: gym)) }.joined(separator: "\n\n")
            return CoachToolResult(id: call.id, text: text.isEmpty ? "No strength programs yet. They can make one in Plans or on the Coach screen." : text)
        case .proposePlanChange:
            guard let proposal = PlanProposal(input: call.input) else {
                return CoachToolResult(id: call.id, text: "The proposal needs a plan and at least one complete change.", isError: true)
            }
            if case .failure(let problem) = gym.resolve(proposal) {
                return CoachToolResult(id: call.id, text: problem.message, isError: true)
            }
            return CoachToolResult(id: call.id, text: "Shown to the user with an Apply button. Nothing changes until they tap it.")
        }
    }

    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US_POSIX"))

    private func setsText(_ sets: [WorkoutSet], kind: ExerciseKind) -> String {
        sets.map { set in
            let text = Fmt.set(set, kind: kind)
            return set.type == .normal ? text : "\(set.type.badge) \(text)"
        }.joined(separator: ", ")
    }

    private func workouts(days: Int) -> String {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let entries = workoutEntries(since: since)
        return entries.isEmpty ? "No workouts in the last \(days) days." : entries.map(\.text).joined(separator: "\n")
    }

    /// Each workout and Health cardio session since `since` as text, newest first.
    private func workoutEntries(since: Date) -> [CoachSnapshot.Workout] {
        var entries: [CoachSnapshot.Workout] = []
        for workout in gym.workouts where workout.startedAt >= since {
            var lines = ["## \(workout.name), \(workout.startedAt.formatted(Self.dateFormat)), \(Int(workout.duration / 60)) min"]
            if !workout.notes.isEmpty { lines.append("Notes: \(workout.notes)") }
            for item in workout.exercises {
                let def = gym.exercise(item.exerciseID)
                lines.append("- \(def?.name ?? "Deleted exercise"): \(setsText(item.sets, kind: def?.kind ?? .weightReps))")
                if !item.notes.isEmpty { lines.append("  Notes: \(item.notes)") }
            }
            entries.append(CoachSnapshot.Workout(date: workout.startedAt, text: lines.joined(separator: "\n")))
        }
        for activity in gym.healthWorkouts where activity.start >= since && !activity.isStrengthLike {
            var line = "## \(activity.name) from \(activity.sourceName), \(activity.start.formatted(Self.dateFormat)), \(Int(activity.duration / 60)) min"
            if let meters = activity.meters, meters > 0 { line += ", \(Pace.distance(meters))" }
            entries.append(CoachSnapshot.Workout(date: activity.start, text: line))
        }
        return entries.sorted { $0.date > $1.date }
    }

    private func history(_ call: CoachToolCall) -> CoachToolResult {
        let name = call.input["exercise"]?.string ?? ""
        guard let def = gym.exercise(named: name) else {
            return CoachToolResult(id: call.id, text: "No exercise called \(name). Try search_exercises.", isError: true)
        }
        return CoachToolResult(id: call.id, text: historyText(def) ?? "\(def.name) hasn't been logged yet.")
    }

    /// Every session of the exercise, oldest first; nil if it hasn't been logged.
    private func historyText(_ def: ExerciseDef) -> String? {
        let sessions = gym.sessions(for: def.id).reversed()
        guard !sessions.isEmpty else { return nil }
        var lines = ["\(def.name), \(sessions.count) sessions, oldest first:"]
        for session in sessions {
            var line = "- \(session.date.formatted(Self.dateFormat)): \(setsText(session.sets, kind: def.kind))"
            let best = session.sets.filter { $0.type != .warmup }.map(\.estimatedOneRepMax).max() ?? 0
            if best > 0 { line += " (est. 1RM \(Fmt.weight(best)) kg)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func search(_ query: String) -> String {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = gym.exercises.filter { def in
            let text = ([def.name, def.muscle.label] + def.primary.map(\.label) + def.secondary.map(\.label)).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        guard !matches.isEmpty else { return "No exercises match \(query)." }
        return matches.prefix(40).map { "- \(searchLine($0))" }.joined(separator: "\n")
    }

    /// "Face Pull (Cable): rear delts; also traps (cable)" – name, muscles and equipment.
    private func searchLine(_ def: ExerciseDef) -> String {
        var line = "\(def.name): \(def.muscleSummary)"
        if !def.secondary.isEmpty { line += "; also \(def.secondary.map(\.label).joined(separator: ", "))" }
        if let equipment = def.equipment { line += " (\(equipment.label))" }
        return line
    }

    private func weeklySets(weeks: Int) -> String {
        weeklySetLines(weeks: weeks).map { "- \($0)" }.joined(separator: "\n")
    }

    private func weeklySetLines(weeks: Int) -> [String] {
        (0..<weeks).map { week in
            let end = Calendar.current.date(byAdding: .day, value: -7 * week, to: now) ?? now
            let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
            let sets = gym.weeklyMuscleSets(in: DateInterval(start: start, end: end))
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
                .map { "\($0.key.label) \(VolumeZone.format($0.value))" }
            let title = week == 0 ? "Last 7 days" : "\(week * 7 + 7)-\(week * 7) days ago"
            return "\(title): \(sets.isEmpty ? "nothing" : sets.joined(separator: ", "))"
        }
    }

    private func plans() -> String {
        guard !gym.plans.isEmpty else { return "No saved plans." }
        return gym.plans.map { plan in
            let exercises = plan.exercises.map { item in
                let def = gym.exercise(item.exerciseID)
                return "- \(def?.name ?? "Deleted exercise"): \(setsText(item.sets, kind: def?.kind ?? .weightReps))"
            }
            return (["## \(plan.name)"] + exercises).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// Everything the read tools return, for the Overlo4d connector in Claude.
    func snapshot(goal: String) -> CoachSnapshot {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        var histories: [String: String] = [:]
        for def in gym.exercises {
            if let text = historyText(def) { histories[def.name] = text }
        }
        let programText = programs.programs.map { $0.coachText(logs: programs.logs(for: $0, gym: gym)) }.joined(separator: "\n\n")
        return CoachSnapshot(
            generatedAt: now,
            timeZone: TimeZone.current.identifier,
            goal: goal,
            workouts: workoutEntries(since: yearAgo),
            exerciseHistory: histories,
            exerciseNames: gym.exercises.map(\.name),
            exercises: gym.exercises.map(searchLine),
            weeklySets: weeklySetLines(weeks: 12),
            sleep: sleep.coachLines(),
            food: food.coachLines(),
            body: body.coachLines(),
            plans: gym.plans.isEmpty ? "" : plans(),
            planNames: gym.plans.map(\.name),
            programs: programText,
            programNames: programs.programs.map(\.name)
        )
    }
}

extension GymStore {
    struct PlanProblem: Error {
        let message: String
    }

    /// An exercise by name, ignoring case; a unique partial match counts too.
    func exercise(named name: String) -> ExerciseDef? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let exact = exercises.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return exact }
        let partial = exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        return partial.count == 1 ? partial[0] : nil
    }

    /// The plan with the proposal applied, or what the coach got wrong.
    func resolve(_ proposal: PlanProposal) -> Result<Plan, PlanProblem> {
        guard var plan = plans.first(where: { $0.name.caseInsensitiveCompare(proposal.plan) == .orderedSame }) else {
            let names = plans.map(\.name).joined(separator: ", ")
            return .failure(PlanProblem(message: "No plan called \(proposal.plan). Plans: \(names.isEmpty ? "none" : names)."))
        }
        for change in proposal.changes {
            guard let def = exercise(named: change.exercise) else {
                return .failure(PlanProblem(message: "No exercise called \(change.exercise). Use search_exercises for exact names."))
            }
            let index = plan.exercises.firstIndex { $0.exerciseID == def.id }
            switch change.action {
            case .add:
                let count = change.sets ?? 3
                plan.exercises.append(WorkoutExercise(exerciseID: def.id, sets: (0..<count).map { _ in WorkoutSet(reps: change.reps) }))
            case .remove, .replace, .setSets:
                guard let index else {
                    return .failure(PlanProblem(message: "\(def.name) isn't in \(plan.name)."))
                }
                switch change.action {
                case .remove:
                    plan.exercises.remove(at: index)
                case .replace:
                    guard let replacement = change.newExercise.flatMap(exercise(named:)) else {
                        return .failure(PlanProblem(message: "No exercise called \(change.newExercise ?? ""). Use search_exercises for exact names."))
                    }
                    plan.exercises[index].exerciseID = replacement.id
                default:
                    var sets = plan.exercises[index].sets
                    if let count = change.sets {
                        let template = sets.last(where: { $0.type != .warmup }) ?? WorkoutSet()
                        let warmups = sets.filter { $0.type == .warmup }
                        sets = warmups + Array(repeating: template, count: count).map { $0.copyForNewSet() }
                    }
                    if let reps = change.reps {
                        for i in sets.indices where sets[i].type != .warmup { sets[i].reps = reps }
                    }
                    plan.exercises[index].sets = sets
                }
            }
        }
        return .success(plan)
    }
}
