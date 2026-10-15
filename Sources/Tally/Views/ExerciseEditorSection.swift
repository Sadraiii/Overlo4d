import TallyKit
import SwiftUI

/// List section for one exercise inside a workout or routine: header menu, notes, set rows, "Add set".
struct ExerciseEditorSection: View {
    @Environment(GymStore.self) private var gym
    @Binding var exercise: WorkoutExercise
    /// true in an active workout (previous column + checkmarks); false when editing a routine or past workout.
    let isLive: Bool
    var onRemove: () -> Void
    var onMove: (Int) -> Void = { _ in }
    var onSetCompleted: (WorkoutExercise) -> Void = { _ in }

    private static let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let def = gym.exercise(exercise.exerciseID)
        let kind = def?.kind ?? .weightReps
        let previous = isLive ? gym.previousSets(for: exercise.exerciseID) : []

        Section {
            HStack(spacing: 12) {
                ExerciseBadge(exercise: def, size: 36)
                if let def {
                    NavigationLink(value: def) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.name).display(22).foregroundStyle(Theme.ink).lineLimit(2)
                            if exercise.restSeconds > 0 {
                                Label("Rest \(Fmt.rest(exercise.restSeconds))", systemImage: "timer")
                                    .font(Typo.body(12, .semibold))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                } else {
                    Text("Deleted exercise").display(22)
                }
                Menu {
                    Picker(selection: $exercise.restSeconds) {
                        ForEach(Self.restOptions, id: \.self) { Text(Fmt.rest($0)).tag($0) }
                    } label: {
                        Label("Rest timer: \(Fmt.rest(exercise.restSeconds))", systemImage: "timer")
                    }
                    .pickerStyle(.menu)
                    Button("Move up", systemImage: "arrow.up") { onMove(-1) }
                    Button("Move down", systemImage: "arrow.down") { onMove(1) }
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
            }
            .cardRow()

            TextField("Note", text: $exercise.notes, axis: .vertical)
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink2)
                .cardRow()

            SetHeader(kind: kind, showsPrevious: isLive, showsCheck: isLive)
                .cardRow()

            ForEach($exercise.sets) { $set in
                let index = exercise.sets.firstIndex { $0.id == set.id } ?? 0
                SetRow(
                    set: $set,
                    number: exercise.sets.prefix(index + 1).filter { $0.type != .warmup }.count,
                    kind: kind,
                    previous: previous.indices.contains(index) ? previous[index] : nil,
                    showsCheck: isLive,
                    isRecord: gym.records[set.id] != nil
                ) {
                    onSetCompleted(exercise)
                }
            }
            .onDelete { exercise.sets.remove(atOffsets: $0) }

            Button {
                let last = exercise.sets.last
                exercise.sets.append(WorkoutSet(type: .normal, weight: last?.weight, reps: last?.reps, seconds: last?.seconds))
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.paper, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .cardRow()
        }
    }
}
