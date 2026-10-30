import TallyKit
import SwiftUI

struct HomeTab: View {
    @Environment(GymStore.self) private var gym
    @Environment(AppUI.self) private var ui
    let onStart: () -> Void

    @State private var showingTimer = false
    @State private var showingPlates = false
    @State private var showingOneRepMax = false
    @State private var showingRecords = false
    @State private var showingChangelog = false
    @AppStorage("changelog.seenVersion") private var seenVersion = ""

    var body: some View {
        @Bindable var ui = ui

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Seal(size: 38)
                        Text("Overload")
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

                    if seenVersion != AppVersion.number {
                        UpdateBanner(
                            onOpen: {
                                seenVersion = AppVersion.number
                                showingChangelog = true
                            },
                            onClose: { withAnimation(.snappy) { seenVersion = AppVersion.number } }
                        )
                        .transition(.opacity)
                    }

                    WeekCard(onStart: onStart)

                    LastWeekCard()

                    FoodCard { ui.showingFood = true }

                    SleepCard()

                    BodyCard()

                    CoachCard()

                    RepsCard { ui.showingReps = true }

                    HealthCard()

                    HStack(spacing: 8) {
                        ToolButton(title: "Timer", symbol: "stopwatch") { showingTimer = true }
                        ToolButton(title: "Plates", symbol: "circle.grid.2x1") { showingPlates = true }
                    }
                    HStack(spacing: 8) {
                        ToolButton(title: "1RM", symbol: "percent") { showingOneRepMax = true }
                        ToolButton(title: "Records", symbol: "trophy") { showingRecords = true }
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
            .navigationDestination(isPresented: $ui.showingReps) { QuickCountView() }
            .navigationDestination(isPresented: $ui.showingFood) { FoodDiaryView() }
            .navigationDestination(for: RecapRoute.self) { RecapView(weekStart: $0.weekStart) }
            .navigationDestination(for: CoachRoute.self) { _ in CoachView() }
            .navigationDestination(for: CoachChatRoute.self) { _ in CoachChatView() }
            .navigationDestination(for: SleepRoute.self) { _ in SleepView() }
            .navigationDestination(for: BodyRoute.self) { _ in BodyView() }
            .sheet(isPresented: $showingTimer) { TimerSheet() }
            .navigationDestination(isPresented: $showingRecords) { RecordsView() }
            .sheet(isPresented: $showingPlates) { PlateCalculatorSheet() }
            .sheet(isPresented: $showingOneRepMax) { OneRepMaxSheet() }
            .sheet(isPresented: $showingChangelog) { ChangelogSheet() }
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

/// Today's reps against the daily goal. Opens the rep counter.
struct RepsCard: View {
    @Environment(RepModel.self) private var model
    let onOpen: () -> Void

    var body: some View {
        let progress = model.progress
        Button(action: onOpen) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reps today").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(model.repsToday)")
                            .font(Typo.display(40))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("/ \(model.dailyGoal)")
                            .font(Typo.display(22))
                            .foregroundStyle(Theme.ink3)
                    }
                    Tally(marks: Int(min(progress, 1) * 20), groups: 4, done: progress >= 1, height: 20)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Shown once after the app is updated; opens the changelog.
struct UpdateBanner: View {
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(AppVersion.number)
                        .font(Typo.display(19))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 42, minHeight: 34)
                        .background(Theme.accent, in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Updated to \(AppVersion.display)")
                            .font(Typo.body(15, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("See what changed")
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Dismiss", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink3)
                .frame(width: 34, height: 34)
                .contentShape(.rect)
                .buttonStyle(.plain)
        }
        .card(padding: 12, cornerRadius: 16)
    }
}

/// Small shortcut on Home (Timer, Plates, 1RM, Records).
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
