import SwiftUI
import TallyCore
import TallyKit

struct PlansTab: View {
    @Environment(GymStore.self) private var gym

    @State private var editingPlan: Plan?
    @State private var deletingPlan: Plan?
    @State private var openedPlan: UUID?
    @State private var openedProgram: UUID?
    @State private var newProgram = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ProgramsSection(onOpen: { openedProgram = $0 }, onNew: { newProgram = true })

                    ForEach(gym.plans) { plan in
                        PlanCard(
                            plan: plan,
                            onOpen: { openedPlan = plan.id },
                            onEdit: { editingPlan = plan },
                            onDelete: { deletingPlan = plan }
                        )
                    }

                    if gym.plans.isEmpty {
                        VStack(spacing: 14) {
                            Text("No plans yet").display(22)
                            Button("New plan", systemImage: "plus") { editingPlan = Plan(name: "", exercises: []) }
                                .buttonStyle(.smallPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Plans")
            .toolbar {
                Button("New plan", systemImage: "plus") { editingPlan = Plan(name: "", exercises: []) }
            }
            .navigationDestination(item: $openedPlan) { PlanDetailView(planID: $0) }
            .navigationDestination(item: $openedProgram) { ProgramDetailView(programID: $0) }
            .sheet(isPresented: $newProgram) {
                NewProgramSheet { openedProgram = $0.id }
            }
            .navigationDestination(for: UUID.self) { id in
                if let workout = gym.workout(id) {
                    WorkoutDetailView(workout: workout)
                }
            }
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .sheet(item: $editingPlan) { PlanEditor(plan: $0) }
            .confirmationDialog(
                "Delete \(deletingPlan?.name ?? "plan")?",
                isPresented: Binding(get: { deletingPlan != nil }, set: { if !$0 { deletingPlan = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deletingPlan { gym.deletePlan(deletingPlan) }
                }
            }
        }
    }
}

/// A plan: name, exercises, the muscles it trains and when it was last done.
struct PlanCard: View {
    @Environment(GymStore.self) private var gym
    let plan: Plan
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let defs = plan.exercises.compactMap { gym.exercise($0.exerciseID) }
        let setCount = plan.exercises.reduce(0) { $0 + $1.sets.count }
        let last = gym.sessions(of: plan).first

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name).display(27).lineLimit(2)
                    Text(defs.map(\.name).joined(separator: " · "))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                AnatomyFigure(primary: Set(defs.flatMap(\.primary)), secondary: Set(defs.flatMap(\.secondary)))
                    .frame(height: 78)
                    .accessibilityHidden(true)
            }

            Rectangle().fill(Theme.line).frame(height: 1)

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(plan.exercises.count) exercises · \(setCount) sets")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                    if let last {
                        Text(lastLine(last))
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Duplicate", systemImage: "plus.square.on.square") { gym.duplicatePlan(plan) }
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                Button {
                    gym.startWorkout(from: plan)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.smallPrimary)
                .disabled(gym.activeWorkout != nil)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
    }

    private func lastLine(_ workout: Workout) -> String {
        let date = workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month())
        return workout.volume > 0 ? "Last \(date) · \(Fmt.volume(workout.volume))" : "Last \(date)"
    }
}

struct PlanEditor: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State var plan: Plan
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $plan.name)
                        .font(Typo.display(30))
                }
                .cardRow()

                ForEach($plan.exercises) { $exercise in
                    ExerciseEditorSection(
                        exercise: $exercise,
                        isLive: false,
                        supersetPosition: plan.exercises.supersetPosition(of: exercise.id),
                        supersetCandidates: plan.exercises.supersetCandidates(for: exercise.id)
                            .map { (id: $0.id, name: gym.name(of: $0.exerciseID)) },
                        onSuperset: { plan.exercises.linkSuperset(exercise.id, with: $0) },
                        onLeaveSuperset: { plan.exercises.unlinkSuperset(exercise.id) },
                        onRemove: {
                            plan.exercises.removeAll { $0.id == exercise.id }
                            plan.exercises.normalizeSupersets()
                        },
                        onMove: {
                            plan.exercises.move(id: exercise.id, by: $0)
                            plan.exercises.normalizeSupersets()
                        }
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
            .navigationTitle(gym.plans.contains { $0.id == plan.id } ? "Edit plan" : "New plan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        if plan.name.trimmingCharacters(in: .whitespaces).isEmpty { plan.name = "Plan" }
                        gym.savePlan(plan)
                        dismiss()
                    }
                    .disabled(plan.exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePicker { exercises in
                    plan.exercises += exercises.map { def in
                        var exercise = gym.newWorkoutExercise(for: def)
                        // Prefill plan targets from last time.
                        let previous = gym.previousSets(for: def.id)
                        if !previous.isEmpty { exercise.sets = previous.map { $0.copyForNewSet() } }
                        return exercise
                    }
                }
            }
        }
    }
}
