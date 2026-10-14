import SwiftUI
import RepCore

struct ContentView: View {
    @Environment(RepModel.self) private var model
    @State private var showingAddExercise = false
    @State private var newExerciseName = ""
    @State private var customTarget: Exercise?
    @State private var customAmount = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(model.repsToday) reps")
                                .font(.largeTitle.bold())
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }

                Section("Exercises") {
                    ForEach(model.exercises) { exercise in
                        ExerciseRow(exercise: exercise) {
                            customAmount = ""
                            customTarget = exercise
                        }
                    }
                    .onDelete(perform: model.deleteExercises)
                    .onMove(perform: model.moveExercises)
                }
            }
            .navigationTitle("Reps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Exercise", systemImage: "plus") {
                        newExerciseName = ""
                        showingAddExercise = true
                    }
                }
            }
            .alert("New Exercise", isPresented: $showingAddExercise) {
                TextField("e.g. Burpees", text: $newExerciseName)
                Button("Add") { model.addExercise(named: newExerciseName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Add reps to \(customTarget?.name ?? "")",
                isPresented: Binding(
                    get: { customTarget != nil },
                    set: { if !$0 { customTarget = nil } }
                )
            ) {
                TextField("Reps", text: $customAmount)
                    .keyboardType(.numberPad)
                Button("Add") {
                    if let exercise = customTarget, let reps = Int(customAmount) {
                        withAnimation { model.add(reps, to: exercise) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ExerciseRow: View {
    @Environment(RepModel.self) private var model
    let exercise: Exercise
    let onCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(exercise.name, systemImage: exercise.symbol)
                    .font(.headline)
                Spacer()
                Text("\(model.repsToday(for: exercise))")
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
            }
            HStack(spacing: 8) {
                RepButton(title: "+10") { withAnimation { model.add(10, to: exercise) } }
                RepButton(title: "+20") { withAnimation { model.add(20, to: exercise) } }
                RepButton(title: "+…", prominent: false, action: onCustom)
                Spacer()
                Text("All time: \(model.totalReps(for: exercise))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Undo Last", systemImage: "arrow.uturn.backward") {
                withAnimation { model.undoLast(for: exercise) }
            }
            Button("Reset Today", systemImage: "arrow.counterclockwise", role: .destructive) {
                withAnimation { model.resetToday(for: exercise) }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                withAnimation { model.undoLast(for: exercise) }
            }
            .tint(.orange)
        }
    }
}

struct RepButton: View {
    let title: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.bold())
            .buttonStyle(.bordered)
            .tint(prominent ? .accentColor : .gray)
            .buttonBorderShape(.capsule)
    }
}
