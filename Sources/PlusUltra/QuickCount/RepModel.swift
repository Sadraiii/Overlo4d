import Foundation
import Observation
import PlusUltraKit
import WidgetKit

@MainActor
@Observable
final class RepModel {
    private(set) var data: RepData

    init() {
        data = RepStorage.load()
    }

    var exercises: [QuickExercise] { data.exercises }
    var dailyGoal: Int { data.dailyGoal }
    var repsToday: Int { data.repsToday() }
    var progress: Double { data.goalProgress() }

    func repsToday(for exercise: QuickExercise) -> Int { data.reps(for: exercise.id) }
    func totalReps(for exercise: QuickExercise) -> Int { data.totalReps(for: exercise.id) }

    /// Total reps per day for the last `days` days, oldest first.
    func dailyTotals(days: Int = 7) -> [(date: Date, reps: Int)] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, data.repsToday(on: day))
        }
    }

    func add(_ reps: Int, to exercise: QuickExercise) {
        guard reps != 0 else { return }
        data.entries.append(RepEntry(exerciseID: exercise.id, reps: reps))
        persist()
    }

    func undoLast(for exercise: QuickExercise) {
        guard let index = data.entries.lastIndex(where: { $0.exerciseID == exercise.id }) else { return }
        data.entries.remove(at: index)
        persist()
    }

    func resetToday(for exercise: QuickExercise) {
        data.entries.removeAll {
            $0.exerciseID == exercise.id && Calendar.current.isDateInToday($0.date)
        }
        persist()
    }

    func setGoal(_ goal: Int) {
        data.dailyGoal = max(1, goal)
        persist()
    }

    func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.exercises.append(QuickExercise(name: trimmed))
        persist()
    }

    func deleteExercises(at offsets: IndexSet) {
        let removed = Set(offsets.map { data.exercises[$0].id })
        data.exercises.remove(atOffsets: offsets)
        data.entries.removeAll { removed.contains($0.exerciseID) }
        persist()
    }

    func move(_ exercise: QuickExercise, by offset: Int) {
        data.exercises.move(id: exercise.id, by: offset)
        persist()
    }

    func delete(_ exercise: QuickExercise) {
        data.exercises.removeAll { $0.id == exercise.id }
        data.entries.removeAll { $0.exerciseID == exercise.id }
        persist()
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        data.exercises.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func reload() {
        data = RepStorage.load()
    }

    private func persist() {
        RepStorage.save(data)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.reps)
    }
}
