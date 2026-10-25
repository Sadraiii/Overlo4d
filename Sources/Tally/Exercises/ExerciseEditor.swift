import SwiftUI
import TallyKit

/// Create or edit a custom exercise. Muscles are picked by tapping the body figure.
struct ExerciseEditor: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    var onSave: (ExerciseDef) -> Void

    @State private var exercise: ExerciseDef
    /// Once the group is picked by hand it no longer follows the first primary muscle.
    @State private var groupPicked: Bool
    @State private var confirmingDelete = false
    private let isNew: Bool

    init(exercise: ExerciseDef? = nil, onSave: @escaping (ExerciseDef) -> Void = { _ in }) {
        let blank = ExerciseDef(
            name: "",
            muscle: .chest,
            kind: .weightReps,
            isCustom: true,
            equipment: nil,
            primaryMuscles: [],
            secondaryMuscles: []
        )
        _exercise = State(initialValue: exercise ?? blank)
        _groupPicked = State(initialValue: exercise != nil)
        isNew = exercise == nil
        self.onSave = onSave
    }

    private var trimmedName: String { exercise.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $exercise.name)
                        .font(Typo.display(28))
                }
                .cardRow()

                Section {
                    VStack(spacing: 16) {
                        AnatomyFigure(
                            primary: Set(exercise.primary),
                            secondary: Set(exercise.secondary),
                            onTap: toggle,
                            labels: true
                        )
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        MuscleLegend(primary: exercise.primary, secondary: exercise.secondary, horizontal: true)
                    }
                    .padding(.vertical, 10)
                    .sensoryFeedback(.selection, trigger: exercise.primary + exercise.secondary)
                } header: {
                    Text("Muscles").eyebrow(11)
                } footer: {
                    Text("Tap once for primary, again for secondary.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
                .cardRow()

                Section {
                    Picker("Group", selection: Binding(get: { exercise.muscle }, set: { exercise.muscle = $0; groupPicked = true })) {
                        ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Equipment", selection: $exercise.equipment) {
                        Text("None").tag(Equipment?.none)
                        ForEach(Equipment.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Type", selection: $exercise.kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                    }
                }
                .font(Typo.body(16))
                .cardRow()

                if !isNew && !gym.isUsed(exercise) {
                    Section {
                        Button("Delete exercise", role: .destructive) { confirmingDelete = true }
                            .font(Typo.body(16, .semibold))
                    }
                    .cardRow()
                }
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(trimmedName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    gym.deleteExercise(exercise)
                    dismiss()
                }
            }
        }
    }

    /// Cycles a muscle: not worked → primary → secondary → not worked.
    private func toggle(_ muscle: Muscle) {
        var primary = exercise.primary
        var secondary = exercise.secondary
        if let index = primary.firstIndex(of: muscle) {
            primary.remove(at: index)
            secondary.append(muscle)
        } else if let index = secondary.firstIndex(of: muscle) {
            secondary.remove(at: index)
        } else {
            primary.append(muscle)
        }
        exercise.primaryMuscles = primary
        exercise.secondaryMuscles = secondary
        if !groupPicked, let first = primary.first {
            exercise.muscle = first.group
        }
    }

    private func save() {
        exercise.name = trimmedName
        if isNew {
            gym.addExercise(exercise)
        } else {
            gym.updateExercise(exercise)
        }
        onSave(exercise)
        dismiss()
    }
}
