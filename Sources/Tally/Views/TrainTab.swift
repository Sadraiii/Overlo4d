import TallyKit
import SwiftUI

struct TrainTab: View {
    @Environment(GymStore.self) private var gym
    @Environment(AppUI.self) private var ui
    let onStart: () -> Void

    @State private var editingPlan: Plan?
    @State private var deletingPlan: Plan?
    @State private var openedPlan: UUID?
    @State private var showingTimer = false
    @State private var showingPlates = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Seal(size: 38)
                        Text("Tally")
                            .font(Typo.display(21))
                            .tracking(1.5)
                            .textCase(.uppercase)
                        Spacer()
                        Button("Settings", systemImage: "slider.horizontal.3") { ui.showingSettings = true }
                            .labelStyle(.iconOnly)
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.ink2)
                            .frame(width: 42, height: 42)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).eyebrow()
                        Text("Training").display(46)
                    }
                    .padding(.top, 4)

                    WeekCard(onStart: onStart)

                    HealthCard()

                    HStack(spacing: 8) {
                        ToolButton(title: "Timer", symbol: "stopwatch") { showingTimer = true }
                        ToolButton(title: "Plates", symbol: "circle.grid.2x1") { showingPlates = true }
                    }

                    SectionHead("Plans") {
                        Button("New") { editingPlan = Plan(name: "", exercises: []) }
                    }

                    if gym.plans.isEmpty {
                        VStack(spacing: 10) {
                            Text("No plans").display(20)
                            Text("Save workouts you repeat and start them in one tap.")
                                .font(Typo.body(14))
                                .foregroundStyle(Theme.ink2)
                                .multilineTextAlignment(.center)
                            Button("New plan") { editingPlan = Plan(name: "", exercises: []) }
                                .buttonStyle(.smallOutline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 18)
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }

                    ForEach(gym.plans) { plan in
                        PlanCard(
                            plan: plan,
                            onOpen: { openedPlan = plan.id },
                            onEdit: { editingPlan = plan },
                            onDelete: { deletingPlan = plan }
                        )
                    }

                    if let last = gym.workouts.first {
                        SectionHead("Last workout")
                        NavigationLink(value: last.id) {
                            WorkoutCard(workout: last)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let workout = gym.workout(id) {
                    WorkoutDetailView(workout: workout)
                }
            }
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .navigationDestination(item: $openedPlan) { PlanDetailView(planID: $0) }
            .sheet(item: $editingPlan) { PlanEditor(plan: $0) }
            .sheet(isPresented: $showingTimer) { TimerSheet() }
            .sheet(isPresented: $showingPlates) { PlateCalculatorSheet() }
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

/// This week's training as a ticket card, with the start button.
struct WeekCard: View {
    @Environment(GymStore.self) private var gym
    let onStart: () -> Void

    var body: some View {
        let snapshot = gym.snapshot
        let thisWeek = gym.workouts.filter { gym.weekStart($0.startedAt) == gym.weekStart(.now) }
        let active = gym.activeWorkout

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if active != nil {
                    StatusPill(text: "In progress", live: true)
                } else {
                    StatusPill(text: "This week")
                }
                Spacer()
                if snapshot.weekStreak > 0 {
                    StreakBadge(weeks: snapshot.weekStreak)
                }
            }

            HStack(spacing: 16) {
                Bib(date: .now)
                VStack(alignment: .leading, spacing: 5) {
                    if let active {
                        Text(active.name).display(32).lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                            Text(active.startedAt, style: .timer).monospacedDigit()
                            Text("· \(active.completedSets.count) sets")
                        }
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                    } else {
                        Text("\(thisWeek.count) \(thisWeek.count == 1 ? "workout" : "workouts")").display(36)
                        if !thisWeek.isEmpty {
                            Text("\(Fmt.volume(thisWeek.reduce(0) { $0 + $1.volume })) · \(Fmt.duration(thisWeek.reduce(0) { $0 + $1.duration }))")
                                .font(Typo.body(14))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }

            WeekStrip(days: snapshot.trainedDays(), todayIndex: ActivitySnapshot.weekdayIndex(), size: 32)

            TicketDivider()

            Button(action: onStart) {
                Label(active == nil ? "Start workout" : "Resume workout", systemImage: active == nil ? "plus" : "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .sensoryFeedback(.impact, trigger: gym.isPresentingWorkout)
        }
        .card(padding: 16, cornerRadius: 22)
        .shadow(color: .black.opacity(0.06), radius: 14, y: 10)
    }
}

/// Small square shortcut on the Train tab (Timer, Plates).
struct ToolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.line, in: .rect(cornerRadius: 10))
                Text(title).font(Typo.body(15, .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
            .foregroundStyle(Theme.ink)
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Plan card in the style of Outdoor Office's schedule slots.
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

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(plan.exercises.count) exercises · \(setCount) sets").eyebrow(11)
                    Text(plan.name).display(27).lineLimit(2)
                    if let last {
                        Text("Last \(last.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month())) · \(Fmt.volume(last.volume))")
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(defs.map(\.name).joined(separator: " · "))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
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
                SlotBar(color: defs.first?.muscle.color ?? Theme.ink3)
                    .padding(.top, 4)
            }

            Rectangle().fill(Theme.line).frame(height: 1)

            HStack(spacing: 6) {
                ForEach(Array(Set(defs.map(\.muscle))).sorted { $0.rawValue < $1.rawValue }) { muscle in
                    Circle().fill(muscle.color).frame(width: 8, height: 8)
                }
                Spacer()
                Button {
                    gym.startWorkout(from: plan)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.smallPrimary)
                .disabled(gym.activeWorkout != nil)
            }
        }
        .padding(.leading, 16)
        .padding([.trailing, .top], 14)
        .padding(.bottom, 12)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
    }
}

/// A finished workout as a ticket: date bib, title, stats and exercises.
struct WorkoutCard: View {
    @Environment(GymStore.self) private var gym
    let workout: Workout

    var body: some View {
        let prs = gym.recordCount(in: workout)
        HStack(alignment: .top, spacing: 14) {
            Bib(date: workout.startedAt)
            VStack(alignment: .leading, spacing: 7) {
                Text(workout.name).display(23).lineLimit(2)
                Text("\(Fmt.duration(workout.duration)) · \(Fmt.volume(workout.volume)) · \(workout.completedSets.count) sets")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(workout.exercises.prefix(3)) { exercise in
                        HStack(spacing: 6) {
                            Text("\(exercise.sets.count)×")
                                .font(Typo.display(16))
                                .foregroundStyle(Theme.ink)
                            Text(gym.name(of: exercise.exerciseID))
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink2)
                                .lineLimit(1)
                        }
                    }
                    if workout.exercises.count > 3 {
                        Text("+\(workout.exercises.count - 3) more")
                            .font(Typo.body(12))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                if prs > 0 {
                    Label("\(prs) \(prs == 1 ? "record" : "records")", systemImage: "trophy.fill")
                        .font(Typo.body(12, .bold))
                        .foregroundStyle(Theme.hot)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, cornerRadius: 16)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").eyebrow(11.5)
                        TextField("Push day", text: $plan.name)
                            .font(Typo.display(30))
                    }
                }
                .cardRow()

                ForEach($plan.exercises) { $exercise in
                    ExerciseEditorSection(
                        exercise: $exercise,
                        isLive: false,
                        onRemove: { plan.exercises.removeAll { $0.id == exercise.id } },
                        onMove: { plan.exercises.move(id: exercise.id, by: $0) }
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

/// Dashed "+ Exercise" button, as in Outdoor Office's workout sheet.
struct AddExerciseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add exercise", systemImage: "plus")
                .font(Typo.body(15, .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension Array where Element: Identifiable {
    /// Moves the element with `id` up (-1) or down (+1).
    mutating func move(id: Element.ID, by offset: Int) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard indices.contains(target) else { return }
        swapAt(index, target)
    }
}
