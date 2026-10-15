import TallyKit
import SwiftUI

struct HistoryView: View {
    @Environment(GymStore.self) private var gym

    private var byMonth: [(month: Date, workouts: [Workout])] {
        let grouped = Dictionary(grouping: gym.workouts) {
            Calendar.current.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(byMonth, id: \.month) { group in
                    Section {
                        ForEach(group.workouts) { workout in
                            NavigationLink(value: workout.id) {
                                WorkoutCard(workout: workout)
                            }
                            .navigationLinkIndicatorVisibility(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete { offsets in offsets.map { group.workouts[$0] }.forEach(gym.deleteWorkout) }
                    } header: {
                        // Dark month band, as in Outdoor Office's schedule.
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.month.formatted(.dateTime.month(.wide).year()))
                                .font(Typo.body(14.5, .semibold))
                            Spacer()
                            Text("\(group.workouts.count) \(group.workouts.count == 1 ? "workout" : "workouts")")
                                .font(Typo.body(12.5, .medium))
                                .opacity(0.7)
                        }
                        .foregroundStyle(Theme.bandInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Theme.band)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .screenBackground()
            .overlay {
                if gym.workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "calendar",
                        description: Text("Finished workouts show up here.")
                    )
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let workout = gym.workout(id) {
                    WorkoutDetailView(workout: workout)
                }
            }
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    @State private var editing: Workout?
    @State private var confirmingDelete = false
    @State private var savedRoutine = false
    @State private var sharing = false
    @State private var workoutHealth: HealthManager.WorkoutHealth?

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Bib(date: workout.startedAt, size: .large)
                    Text(workout.name).display(40).multilineTextAlignment(.center)
                    Text(workout.startedAt.formatted(date: .complete, time: .shortened))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                    HStack(spacing: 8) {
                        Tile(value: Fmt.duration(workout.duration), label: "Duration")
                        Tile(value: Fmt.volume(workout.volume), label: "Volume")
                        Tile(value: "\(workout.completedSets.count)", label: "Sets")
                    }
                    WorkoutHealthTiles(workout: workout, stats: $workoutHealth)
                    if !workout.notes.isEmpty {
                        Text(workout.notes)
                            .font(Typo.body(15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.accentSoft, in: .rect(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            ForEach(workout.exercises) { exercise in
                let def = gym.exercise(exercise.exerciseID)
                Section {
                    HStack(spacing: 12) {
                        ExerciseBadge(exercise: def, size: 34)
                        if let def {
                            NavigationLink(value: def) {
                                Text(def.name).display(22).foregroundStyle(Theme.ink)
                            }
                        } else {
                            Text("Deleted exercise").display(22)
                        }
                    }
                    if !exercise.notes.isEmpty {
                        Text(exercise.notes).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                    }
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: 12) {
                            Text(set.type == .normal ? "\(exercise.sets.prefix(index + 1).filter { $0.type != .warmup }.count)" : set.type.badge)
                                .font(Typo.display(18))
                                .foregroundStyle(Theme.ink3)
                                .frame(width: 26)
                            Text(Fmt.set(set, kind: def?.kind ?? .weightReps))
                                .font(Typo.display(22))
                                .monospacedDigit()
                            Spacer()
                            if let kinds = gym.records[set.id] {
                                Label(kinds.map(\.label).joined(separator: ", "), systemImage: "trophy.fill")
                                    .font(Typo.body(12, .bold))
                                    .foregroundStyle(Theme.hot)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .cardRow()
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Share", systemImage: "square.and.arrow.up") { sharing = true }
            Menu {
                Button("Edit", systemImage: "pencil") { editing = workout }
                Button("Save as routine", systemImage: "square.and.arrow.down") {
                    gym.saveRoutine(gym.routine(from: workout))
                    savedRoutine = true
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        .sheet(item: $editing) { EditWorkoutView(workout: $0) }
        .sheet(isPresented: $sharing) {
            ShareSheet(model: .workout(workout, gym: gym, health: workoutHealth))
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                gym.deleteWorkout(workout)
            }
        }
        .alert("Saved as routine", isPresented: $savedRoutine) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(workout.name)\" is under Routines on the Train tab.")
        }
    }
}

/// Edit a finished workout: name, date, sets.
struct EditWorkoutView: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $workout.name)
                        .font(Typo.display(28))
                    DatePicker("Started", selection: $workout.startedAt)
                    DatePicker(
                        "Ended",
                        selection: Binding(get: { workout.endedAt ?? workout.startedAt }, set: { workout.endedAt = $0 }),
                        in: workout.startedAt...
                    )
                    TextField("Note", text: $workout.notes, axis: .vertical)
                }
                .font(Typo.body(15))
                .cardRow()

                ForEach($workout.exercises) { $exercise in
                    ExerciseEditorSection(
                        exercise: $exercise,
                        isLive: false,
                        onRemove: { workout.exercises.removeAll { $0.id == exercise.id } },
                        onMove: { workout.exercises.move(id: exercise.id, by: $0) }
                    )
                }

                Section {
                    AddExerciseButton { showingPicker = true }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        // Edited sets count as completed; drop empty ones.
                        workout.exercises = workout.exercises.compactMap { exercise in
                            var exercise = exercise
                            exercise.sets = exercise.sets
                                .filter(\.hasValues)
                                .map { var set = $0; set.isDone = true; return set }
                            return exercise.sets.isEmpty ? nil : exercise
                        }
                        gym.updateWorkout(workout)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePicker { exercises in
                    workout.exercises += exercises.map(gym.newWorkoutExercise)
                }
            }
        }
    }
}
