import PlusUltraKit
import SwiftUI

/// Searchable, multi-select list of exercises grouped by muscle.
struct ExercisePicker: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([ExerciseDef]) -> Void

    @State private var search = ""
    @State private var selected: [UUID] = []
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            ExerciseList(search: search) { exercise in
                Button {
                    if let index = selected.firstIndex(of: exercise.id) {
                        selected.remove(at: index)
                    } else {
                        selected.append(exercise.id)
                    }
                } label: {
                    HStack {
                        ExerciseLabel(exercise: exercise)
                        Spacer()
                        if let index = selected.firstIndex(of: exercise.id) {
                            Text("\(index + 1)")
                                .font(Typo.body(13, .bold))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 26, height: 26)
                                .background(Theme.accent, in: .circle)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(selected.contains(exercise.id) ? Theme.accentSoft : Theme.card)
            }
            .animation(.snappy, value: selected)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New exercise", systemImage: "plus") { showingCreate = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button("Add \(selected.count)") {
                        onAdd(selected.compactMap(gym.exercise))
                        dismiss()
                    }
                    .buttonStyle(.bigPrimary)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateExerciseView { exercise in selected.append(exercise.id) }
            }
        }
    }
}

/// Exercise list grouped by muscle, filtered by search text. Shared by the picker and the Exercises screen.
struct ExerciseList<Row: View>: View {
    @Environment(GymStore.self) private var gym
    let search: String
    @ViewBuilder let row: (ExerciseDef) -> Row

    private var filtered: [ExerciseDef] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return gym.exercises
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.muscle.label.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases) { muscle in
                let exercises = filtered.filter { $0.muscle == muscle }
                if !exercises.isEmpty {
                    Section {
                        ForEach(exercises) { row($0) }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(muscle.color).frame(width: 8, height: 8)
                            Text(muscle.label).eyebrow(11)
                        }
                    }
                }
            }
        }
        .screenBackground()
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

struct CreateExerciseView: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    var onCreate: (ExerciseDef) -> Void = { _ in }

    @State private var name = ""
    @State private var muscle = MuscleGroup.chest
    @State private var kind = ExerciseKind.weightReps

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .cardRow()
                Picker("Muscle", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
                }
                .cardRow()
                Picker("Type", selection: $kind) {
                    ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                }
                .cardRow()
            }
            .font(Typo.body(16))
            .screenBackground()
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let exercise = ExerciseDef(
                            name: name.trimmingCharacters(in: .whitespaces),
                            muscle: muscle,
                            kind: kind,
                            isCustom: true
                        )
                        gym.addExercise(exercise)
                        onCreate(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
