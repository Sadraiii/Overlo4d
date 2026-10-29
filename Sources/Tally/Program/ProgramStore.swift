import Foundation
import Observation
import TallyCore

/// Which program day a workout was started from. Weeks and days are 0-based.
struct ProgramDayRef: Codable, Hashable, Sendable {
    var programID: UUID
    var week: Int
    var day: Int
}

/// The user's strength programs. Progress comes from the workouts started from them, so nothing
/// here changes when a workout is finished or deleted.
@MainActor
@Observable
final class ProgramStore {
    private struct Saved: Codable {
        var programs: [StrengthProgram]
    }

    private(set) var programs: [StrengthProgram]
    /// The coach is writing a program.
    private(set) var isGenerating = false
    private(set) var error: CoachError?

    private static let fileURL = URL.documentsDirectory.appending(path: "programs.json")

    init() {
        programs = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }?.programs ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(programs: programs)) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func program(_ id: UUID) -> StrengthProgram? {
        programs.first { $0.id == id }
    }

    func add(_ program: StrengthProgram) {
        programs.insert(program, at: 0)
        save()
    }

    func update(_ program: StrengthProgram) {
        guard let index = programs.firstIndex(where: { $0.id == program.id }) else { return }
        programs[index] = program
        save()
    }

    func delete(_ program: StrengthProgram) {
        programs.removeAll { $0.id == program.id }
        save()
    }

    // MARK: Progress

    /// Finished program days, with the top reps of each main lift.
    func logs(for program: StrengthProgram, gym: GymStore) -> [ProgramLog] {
        gym.workouts.compactMap { workout in
            guard let ref = workout.programDay, ref.programID == program.id else { return nil }
            var top: [String: Int] = [:]
            for lift in program.lifts {
                let sets = workout.exercises
                    .filter { gym.exercise($0.exerciseID)?.name == lift.exercise }
                    .flatMap(\.sets)
                    .filter { $0.type != .warmup && ($0.weight ?? 0) > 0 }
                guard let heaviest = sets.compactMap(\.weight).max() else { continue }
                top[lift.exercise] = sets.filter { $0.weight == heaviest }.compactMap(\.reps).max()
            }
            return ProgramLog(week: ref.week, day: ref.day, topReps: top)
        }
    }

    /// The workout logged for a day, newest first if done more than once.
    func workout(for program: StrengthProgram, week: Int, day: Int, gym: GymStore) -> Workout? {
        gym.workouts.first { $0.programDay == ProgramDayRef(programID: program.id, week: week, day: day) }
    }

    // MARK: Starting a day

    /// Starts the day as a workout with the weights filled in.
    func start(_ program: StrengthProgram, week: Int, day: Int, gym: GymStore) {
        let items = program.items(week: week, day: day, logs: logs(for: program, gym: gym))
        let exercises = items.map { item in
            let def = gym.programExercise(named: item.exercise)
            let suggested = item.isMainLift ? nil : gym.suggestedWeight(for: def.id, targetReps: item.sets.first?.reps)?.weight
            return WorkoutExercise(
                exerciseID: def.id,
                sets: item.sets.map { set in
                    WorkoutSet(type: set.warmup ? .warmup : .normal, weight: set.weight ?? suggested, reps: set.reps)
                },
                restSeconds: item.isMainLift ? 180 : gym.defaultRestSeconds,
                notes: item.notes
            )
        }
        gym.start(
            name: "\(program.days[day].name) · W\(week + 1)",
            exercises: exercises,
            programDay: ProgramDayRef(programID: program.id, week: week, day: day)
        )
    }

    // MARK: One-rep maxes

    /// Best estimated one-rep max from the last 4 months, or ever if none since.
    static func estimatedMax(_ exercise: String, gym: GymStore) -> Double? {
        guard let def = gym.exercises.first(where: { $0.name == exercise }) else { return nil }
        let sessions = gym.sessions(for: def.id)
        let since = Calendar.current.date(byAdding: .month, value: -4, to: .now) ?? .now
        func best(_ list: [ExerciseSession]) -> Double? {
            let value = list.flatMap(\.sets).filter { $0.type != .warmup }.map(\.estimatedOneRepMax).max() ?? 0
            return value > 0 ? value : nil
        }
        return best(sessions.filter { $0.date >= since }) ?? best(sessions)
    }

    // MARK: Coach

    /// Asks the coach to write a program and adds it. Returns it, or nil with `error` set.
    func generate(_ request: ProgramRequest, gym: GymStore, coach: CoachStore) async -> StrengthProgram? {
        guard !isGenerating else { return nil }
        error = nil
        guard let apiKey = coach.apiKey, !apiKey.isEmpty else {
            error = .missingKey
            return nil
        }
        let prompt = ProgramCoach.prompt(request, exercises: gym.exercises.map(\.name), log: Self.trainingLog(gym))
        isGenerating = true
        defer { isGenerating = false }
        do {
            let urlRequest = try ProgramCoach.request(apiKey: apiKey, model: coach.model, prompt: prompt)
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let program = try ProgramCoach.parse(status: status, data: data, start: .now)
            add(program)
            return program
        } catch let error as CoachError {
            self.error = error
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            self.error = .network(error.localizedDescription)
        }
        return nil
    }

    /// One line per exercise done in the last 8 weeks, most frequent first:
    /// "Squat (Barbell): 7 sessions, best recent set 120 kg × 5, est. max 140 kg".
    static func trainingLog(_ gym: GymStore) -> String {
        let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now) ?? .now
        let recent = gym.workouts.filter { $0.startedAt >= since }
        var counts: [UUID: Int] = [:]
        for workout in recent {
            for id in Set(workout.exercises.map(\.exerciseID)) { counts[id, default: 0] += 1 }
        }
        let lines = counts.sorted { $0.value != $1.value ? $0.value > $1.value : gym.name(of: $0.key) < gym.name(of: $1.key) }
            .prefix(30)
            .compactMap { id, count -> String? in
                guard let def = gym.exercise(id) else { return nil }
                var line = "- \(def.name): \(count) session\(count == 1 ? "" : "s")"
                let sets = gym.sessions(for: id).filter { $0.date >= since }.flatMap(\.sets).filter { $0.type != .warmup }
                if let best = sets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }), best.estimatedOneRepMax > 0 {
                    line += ", best recent set \(Fmt.set(best, kind: def.kind)), est. max \(Int(best.estimatedOneRepMax.rounded())) kg"
                } else if let last = sets.first {
                    line += ", e.g. \(Fmt.set(last, kind: def.kind))"
                }
                return line
            }
        return lines.joined(separator: "\n")
    }
}

extension GymStore {
    /// The exercise with this name, matched without case if needed. Adds a custom one when there is none,
    /// so a program from the coach always starts.
    func programExercise(named name: String) -> ExerciseDef {
        if let def = exercises.first(where: { $0.name == name })
            ?? exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return def
        }
        let def = ExerciseDef(name: name, muscle: .other, kind: .weightReps, isCustom: true)
        addExercise(def)
        return def
    }
}
