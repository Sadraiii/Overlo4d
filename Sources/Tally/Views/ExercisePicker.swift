import TallyKit
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
                ExerciseEditor { exercise in selected.append(exercise.id) }
            }
        }
    }
}

/// Exercise list grouped by muscle, filtered by search text, muscle group and equipment.
/// Shared by the picker and the Exercises page.
struct ExerciseList<Row: View>: View {
    @Environment(GymStore.self) private var gym
    let search: String
    @ViewBuilder let row: (ExerciseDef) -> Row

    @State private var group: MuscleGroup?
    @State private var equipment: Equipment?

    private var filtered: [ExerciseDef] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return gym.exercises
            .filter { exercise in
                (group == nil || exercise.muscle == group)
                    && (equipment == nil || exercise.equipment == equipment)
                    && (query.isEmpty
                        || exercise.name.localizedCaseInsensitiveContains(query)
                        || exercise.muscle.label.localizedCaseInsensitiveContains(query)
                        || exercise.primary.contains { $0.label.localizedCaseInsensitiveContains(query) })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let filtered = filtered
        List {
            Section {
                HStack(spacing: 8) {
                    FilterMenu(title: "Muscle", selection: $group, options: MuscleGroup.allCases) { $0.label }
                    FilterMenu(title: "Equipment", selection: $equipment, options: Equipment.allCases) { $0.label }
                    Spacer(minLength: 0)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))

            ForEach(MuscleGroup.allCases) { muscle in
                let exercises = filtered.filter { $0.muscle == muscle }
                if !exercises.isEmpty {
                    Section {
                        ForEach(exercises) { row($0) }
                    } header: {
                        HStack(spacing: 6) {
                            Text(muscle.label).eyebrow(11)
                            Text("\(exercises.count)").font(Typo.body(11, .semibold)).foregroundStyle(Theme.ink3)
                        }
                    }
                }
            }
        }
        .screenBackground()
        .overlay {
            if filtered.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No exercises", systemImage: "line.3.horizontal.decrease")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}
