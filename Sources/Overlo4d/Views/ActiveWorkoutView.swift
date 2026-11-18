import Overlo4dCore
import Overlo4dKit
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(GymStore.self) private var gym
    @Environment(RestTimer.self) private var rest
    @Environment(HealthManager.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Local copy of the workout. Edits are pushed to the store, so this view never binds to the store's
    /// optional `activeWorkout` (which becomes nil when the workout is finished or discarded).
    @State private var draft: Workout
    @State private var showingPicker = false
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var showingNothingDone = false
    @State private var showingTimer = false
    /// The exercise the next set belongs to, with a line for the rest dock.
    @State private var nextUp: NextUp?
    /// Set to scroll the list to an exercise.
    @State private var jumpTarget: UUID?
    @FocusedValue(\.fieldStepper) private var stepper

    struct NextUp: Equatable {
        var exerciseID: UUID?
        var text: String
    }

    init(initial: Workout) {
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        groupLabel: draft.exercises.groupLabel(of: exercise.id),
                        isNext: nextUp?.exerciseID == exercise.id,
                        supersetCandidates: draft.exercises.supersetCandidates(for: exercise.id)
                            .map { (id: $0.id, name: gym.name(of: $0.exerciseID)) },
                        onSuperset: { draft.exercises.linkSuperset(exercise.id, with: $0) },
                        onLeaveSuperset: { draft.exercises.unlinkSuperset(exercise.id) },
                        onRemove: {
                            Motion.animate {
                                draft.exercises.removeAll { $0.id == exercise.id }
                                draft.exercises.normalizeSupersets()
                            }
                        },
                        onMove: { offset in
                            Motion.animate {
                                draft.exercises.move(id: exercise.id, by: offset)
                                draft.exercises.normalizeSupersets()
                            }
                        },
                        onSetCompleted: { setCompleted(in: $0) }
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
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                Motion.animate { proxy.scrollTo(target, anchor: .top) }
                jumpTarget = nil
            }
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if rest.isRunning || rest.justFinished {
                    RestDock(nextUp: nextUp?.text)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
            .animation(reduceMotion ? Motion.reduced : Motion.arrive, value: rest.isRunning || rest.justFinished)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Minimize", systemImage: "chevron.down") {
                        pushToStore()
                        gym.isPresentingWorkout = false
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if draft.exercises.count > 1 {
                        // Jump straight to an exercise; each line shows how many sets are ticked off.
                        Menu("Exercises", systemImage: "list.bullet") {
                            ForEach(draft.exercises) { exercise in
                                let done = exercise.sets.filter(\.isDone).count
                                Button {
                                    jumpTarget = exercise.id
                                } label: {
                                    Label("\(gym.name(of: exercise.exerciseID)) · \(done)/\(exercise.sets.count)", systemImage: done >= exercise.sets.count && !exercise.sets.isEmpty ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }
                    Button("Timer", systemImage: "stopwatch") { showingTimer = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        // Nothing left unticked: no need to ask.
                        if !draft.allSets.isEmpty && draft.allSets.allSatisfy(\.isDone) { finish() } else { confirmingFinish = true }
                    }
                        .font(Typo.body(15, .bold))
                        .buttonStyle(.glassProminent)
                        .tint(Theme.good)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let stepper {
                        Button { stepper.adjust(-1) } label: {
                            Label("Minus \(stepper.label)", systemImage: "minus").labelStyle(.iconOnly).frame(minWidth: 44)
                        }
                        Text(stepper.label)
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink3)
                            .monospacedDigit()
                        Button { stepper.adjust(1) } label: {
                            Label("Plus \(stepper.label)", systemImage: "plus").labelStyle(.iconOnly).frame(minWidth: 44)
                        }
                    }
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePicker { exercises in
                    Motion.animate { draft.exercises += exercises.map(gym.newWorkoutExercise) }
                }
            }
            .sheet(isPresented: $showingTimer) { TimerSheet() }
            .confirmationDialog("Finish workout?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Finish") { finish() }
            } message: {
                let open = draft.allSets.filter { !$0.isDone }.count
                Text(open == 1 ? "1 set isn't ticked off and won't be saved." : "\(open) sets aren't ticked off and won't be saved.")
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
            .onChange(of: draft) { pushToStore() }
            .onChange(of: rest.endDate) { pushToStore() }
            .onChange(of: rest.pausedRemaining) { pushToStore() }
        }
    }

    /// Saves the draft and refreshes the Live Activity with the rest countdown (running or paused).
    private func pushToStore() {
        gym.updateActive(draft, rest: rest.interval, restPaused: rest.pausedRemaining)
    }

    private func finish() {
        rest.stop()
        if gym.finishWorkout(draft), let saved = gym.summaryWorkout {
            Task { await HealthSync.finished(saved, gym: gym, health: health) }
        } else {
            showingNothingDone = true
        }
    }

    /// After a set is ticked off: works out what comes next (the next exercise of a superset, the
    /// next set, or the next exercise), and starts the rest timer except inside a superset round.
    private func setCompleted(in exercise: WorkoutExercise) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let ids = draft.exercises.supersetIDs
        let remaining = draft.exercises.map { $0.sets.filter { !$0.isDone }.count }
        // "Up next" moves to its new exercise rather than jumping.
        if let next = Supersets.next(after: index, in: ids, remaining: remaining) {
            let target = draft.exercises[next]
            let number = target.sets.count - remaining[next] + 1
            Motion.animate { nextUp = NextUp(exerciseID: target.id, text: "\(gym.name(of: target.exerciseID)) · set \(number) of \(target.sets.count)") }
            // Bring the next exercise into view when it isn't the one just done.
            if next != index { jumpTarget = target.id }
        } else {
            Motion.animate { nextUp = NextUp(exerciseID: nil, text: "All sets done") }
        }
        guard rest.autoStart, Supersets.restsAfter(index: index, in: ids) else { return }
        rest.start(seconds: draft.exercises[index].restSeconds)
    }
}

/// Status, editable name and times, big elapsed timer and running totals.
struct WorkoutHeader: View {
    @Binding var draft: Workout
    @State private var editingTimes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(text: "In progress", live: true)
                Spacer()
                Button { editingTimes = true } label: {
                    HStack(spacing: 5) {
                        Text(timesLabel).eyebrow(11)
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit workout time")
            }
            TextField("Workout", text: $draft.name)
                .font(Typo.title(26))
                .foregroundStyle(Theme.ink)
            Text(draft.startedAt, style: .timer)
                .font(Typo.display(64))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.vertical, -6)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StatBlock(label: "Volume", value: Fmt.volume(draft.volume))
                    StatBlock(label: "Sets", value: "\(draft.completedSets.count)/\(draft.allSets.count)")
                    StatBlock(label: "Exercises", value: "\(draft.exercises.count)")
                }
                // How much of the planned work is ticked off.
                if !draft.allSets.isEmpty {
                    GeometryReader { proxy in
                        let done = Double(draft.completedSets.count) / Double(draft.allSets.count)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(done >= 1 ? Theme.good : Theme.accent)
                                .frame(width: max(done > 0 ? 6 : 0, proxy.size.width * done))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.shadow, radius: 10, y: 3)
            .animation(Motion.standard, value: draft.completedSets.count)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $editingTimes) { WorkoutTimesSheet(workout: $draft) }
    }

    private var timesLabel: String {
        let started = "Started \(draft.startedAt.formatted(date: .omitted, time: .shortened))"
        guard let end = draft.endedAt else { return started }
        return "\(started) · ends \(end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Rest countdown above the bottom edge: a ring and the time left, what comes next, and the controls.
/// When the time is up it turns green and says "Rest over" for a moment before it slides away.
struct RestDock: View {
    @Environment(RestTimer.self) private var rest
    /// e.g. "Cable Fly · set 2 of 3".
    var nextUp: String?
    /// Counts taps on −15, +15 and +30, for their haptic.
    @State private var adjustments = 0

    var body: some View {
        VStack(spacing: 12) {
            if rest.justFinished {
                restOver
                    .transition(.opacity)
            } else {
                countdown
                    .transition(.opacity)
                controls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(rest.justFinished ? Theme.good.opacity(0.5) : Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .animation(Motion.standard, value: rest.justFinished)
        .sensoryFeedback(.selection, trigger: rest.isPaused)
        .sensoryFeedback(.selection, trigger: adjustments)
    }

    /// Updates four times a second: enough for the seconds, and the ring glides between ticks.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = rest.pausedRemaining ?? max(0, (rest.endDate ?? context.date).timeIntervalSince(context.date))
            let left = rest.total > 0 ? min(1, max(0, remaining / rest.total)) : 0
            HStack(alignment: .center, spacing: 14) {
                RestRing(fraction: left, isPaused: rest.isPaused)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 0) {
                    Text(rest.isPaused ? "Paused" : "Rest").eyebrow(11)
                    Text(Fmt.seconds(Int(remaining.rounded(.up))))
                        .font(Typo.display(40))
                        .monospacedDigit()
                        .foregroundStyle(rest.isPaused ? Theme.ink3 : Theme.ink)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if let nextUp { next(nextUp, alignment: .trailing) }
            }
        }
    }

    private var restOver: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bell.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.good)
                .frame(width: 54, height: 54)
                .background(Theme.goodSoft, in: .circle)
                .accessibilityHidden(true)
            Text("Rest over")
                .font(Typo.title(24))
                .foregroundStyle(Theme.good)
            Spacer(minLength: 8)
            if let nextUp { next(nextUp, alignment: .trailing) }
        }
    }

    private func next(_ text: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("Next").eyebrow(10.5)
            Text(text)
                .font(Typo.body(13.5, .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button("−15") { adjust(by: -15) }
                .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 42, fullWidth: true))
                .accessibilityLabel("15 seconds less")
            Button("+15") { adjust(by: 15) }
                .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 42, fullWidth: true))
                .accessibilityLabel("15 seconds more")
            Button("+30") { adjust(by: 30) }
                .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 42, fullWidth: true))
                .accessibilityLabel("30 seconds more")
            Button(rest.isPaused ? "Resume" : "Pause", systemImage: rest.isPaused ? "play.fill" : "pause.fill") {
                if rest.isPaused { rest.resume() } else { rest.pause() }
            }
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 42, fullWidth: true))
            Button("Skip") { rest.stop() }
                .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 42, fullWidth: true))
        }
    }

    private func adjust(by seconds: Int) {
        rest.adjust(by: seconds)
        adjustments += 1
    }
}

/// How much rest is left, as a ring that empties clockwise. Grey while paused.
struct RestRing: View {
    let fraction: Double
    var isPaused = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isPaused ? Theme.ink3 : Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Glides between the dock's quarter-second updates instead of stepping.
                .animation(.linear(duration: 0.25), value: fraction)
            Image(systemName: isPaused ? "pause.fill" : "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isPaused ? Theme.ink3 : Theme.accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(3)
        .animation(Motion.tap, value: isPaused)
        .accessibilityHidden(true)
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
