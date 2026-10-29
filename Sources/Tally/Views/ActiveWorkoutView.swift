import TallyCore
import TallyKit
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(GymStore.self) private var gym
    @Environment(RestTimer.self) private var rest
    @Environment(HealthManager.self) private var health

    /// Local copy of the workout. Edits are pushed to the store, so this view never binds to the store's
    /// optional `activeWorkout` (which becomes nil when the workout is finished or discarded).
    @State private var draft: Workout
    @State private var showingPicker = false
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var showingNothingDone = false
    @State private var showingTimer = false

    init(initial: Workout) {
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkoutHeader(draft: $draft)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                ForEach($draft.exercises) { $exercise in
                    ExerciseEditorSection(
                        exercise: $exercise,
                        isLive: true,
                        supersetPosition: draft.exercises.supersetPosition(of: exercise.id),
                        supersetCandidates: draft.exercises.supersetCandidates(for: exercise.id)
                            .map { (id: $0.id, name: gym.name(of: $0.exerciseID)) },
                        onSuperset: { draft.exercises.linkSuperset(exercise.id, with: $0) },
                        onLeaveSuperset: { draft.exercises.unlinkSuperset(exercise.id) },
                        onRemove: {
                            draft.exercises.removeAll { $0.id == exercise.id }
                            draft.exercises.normalizeSupersets()
                        },
                        onMove: {
                            draft.exercises.move(id: exercise.id, by: $0)
                            draft.exercises.normalizeSupersets()
                        },
                        onSetCompleted: { startRestIfNeeded(after: $0) }
                    )
                }

                if !WorkoutMuscles(draft, gym: gym).entries.isEmpty {
                    Section {
                        WorkoutMusclesCard(workout: draft)
                            .padding(.vertical, 6)
                    }
                    .cardRow()
                }

                Section {
                    VStack(spacing: 14) {
                        AddExerciseButton { showingPicker = true }
                        Button("Discard workout", role: .destructive) { confirmingDiscard = true }
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(14)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if rest.isRunning {
                    RestDock()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: rest.isRunning)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Minimize", systemImage: "chevron.down") {
                        gym.updateActive(draft, restEndsAt: rest.endDate)
                        gym.isPresentingWorkout = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Timer", systemImage: "stopwatch") { showingTimer = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { confirmingFinish = true }
                        .font(Typo.body(15, .bold))
                        .buttonStyle(.glassProminent)
                        .tint(Theme.good)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePicker { exercises in
                    draft.exercises += exercises.map(gym.newWorkoutExercise)
                }
            }
            .sheet(isPresented: $showingTimer) { TimerSheet() }
            .confirmationDialog("Finish workout?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Finish") {
                    rest.stop()
                    if gym.finishWorkout(draft), let saved = gym.summaryWorkout {
                        Task { await HealthSync.finished(saved, gym: gym, health: health) }
                    } else {
                        showingNothingDone = true
                    }
                }
            } message: {
                Text("Sets that aren't ticked off won't be saved.")
            }
            .confirmationDialog("Discard workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    rest.stop()
                    gym.discardActiveWorkout()
                }
            } message: {
                Text("This workout won't be saved.")
            }
            .alert("No completed sets", isPresented: $showingNothingDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Tick off at least one set, or discard the workout.")
            }
            .onChange(of: draft) { gym.updateActive(draft, restEndsAt: rest.endDate) }
            .onChange(of: rest.endDate) { gym.updateActive(draft, restEndsAt: rest.endDate) }
        }
    }

    /// Starts the rest timer after a set, except between exercises of the same superset.
    private func startRestIfNeeded(after exercise: WorkoutExercise) {
        guard rest.autoStart,
              let index = draft.exercises.firstIndex(where: { $0.id == exercise.id }),
              Supersets.restsAfter(index: index, in: draft.exercises.supersetIDs) else { return }
        rest.start(seconds: exercise.restSeconds)
    }
}

/// Status, editable name, big elapsed timer and running totals.
struct WorkoutHeader: View {
    @Binding var draft: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(text: "In progress", live: true)
                Spacer()
                Text("Started \(draft.startedAt.formatted(date: .omitted, time: .shortened))").eyebrow(11)
            }
            TextField("Workout", text: $draft.name)
                .font(Typo.display(34))
                .foregroundStyle(Theme.ink)
            Text(draft.startedAt, style: .timer)
                .font(Typo.display(72))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.vertical, -6)
            HStack(spacing: 12) {
                StatBlock(label: "Volume", value: Fmt.volume(draft.volume))
                StatBlock(label: "Sets", value: "\(draft.completedSets.count)/\(draft.allSets.count)")
                StatBlock(label: "Exercises", value: "\(draft.exercises.count)")
            }
            .animation(.snappy, value: draft.completedSets.count)
        }
        .padding(.horizontal, 4)
    }
}

/// Floating rest countdown, styled like Outdoor Office's sign-up dock.
struct RestDock: View {
    @Environment(RestTimer.self) private var rest

    var body: some View {
        if let end = rest.endDate {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let remaining = max(0, end.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest").eyebrow(11)
                        Text(Fmt.seconds(Int(remaining.rounded(.up))))
                            .font(Typo.display(30))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("−15") { rest.adjust(by: -15) }
                    .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 44))
                Button("+15") { rest.adjust(by: 15) }
                    .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 44))
                Button("Skip") { rest.stop() }
                    .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 44))
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.line2, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            .task(id: end) {
                // Hide the dock when the countdown reaches zero.
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                if !Task.isCancelled, rest.endDate == end { rest.finish() }
            }
        }
    }
}

/// Duration · Volume · Sets for a finished workout.
struct WorkoutStatsRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            StatBlock(label: "Duration", value: Fmt.duration(workout.duration))
            StatBlock(label: "Volume", value: Fmt.volume(workout.volume))
            StatBlock(label: "Sets", value: "\(workout.completedSets.count)")
        }
    }
}
