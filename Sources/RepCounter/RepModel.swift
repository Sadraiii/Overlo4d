import Foundation
import Observation
import RepCore
import WidgetKit

@MainActor
@Observable
final class RepModel {
    private(set) var data: RepData

    init() {
        data = RepStorage.load()
    }

    var exercises: [Exercise] { data.exercises }

    func repsToday(for exercise: Exercise) -> Int { data.reps(for: exercise.id) }
    func totalReps(for exercise: Exercise) -> Int { data.totalReps(for: exercise.id) }
    var repsToday: Int { data.repsToday() }

    func add(_ reps: Int, to exercise: Exercise) {
        guard reps != 0 else { return }
        data.entries.append(RepEntry(exerciseID: exercise.id, reps: reps))
        persist()
    }

    func undoLast(for exercise: Exercise) {
        guard let index = data.entries.lastIndex(where: { $0.exerciseID == exercise.id }) else { return }
        data.entries.remove(at: index)
        persist()
    }

    func resetToday(for exercise: Exercise) {
        data.entries.removeAll {
            $0.exerciseID == exercise.id && Calendar.current.isDateInToday($0.date)
        }
        persist()
    }

    func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.exercises.append(Exercise(name: trimmed))
        persist()
    }

    func deleteExercises(at offsets: IndexSet) {
        let removed = Set(offsets.map { data.exercises[$0].id })
        data.exercises.remove(atOffsets: offsets)
        data.entries.removeAll { removed.contains($0.exerciseID) }
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
        WidgetCenter.shared.reloadTimelines(ofKind: RepStorage.widgetKind)
    }
}
