import TallyCore
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
    @State private var editingLayout = false
    @AppStorage("changelog.seenVersion") private var seenVersion = ""
    /// Which cards show and in what order (see `HomeLayout`).
    @AppStorage("home.layout") private var layoutRaw = ""

    var body: some View {
        @Bindable var ui = ui

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(Typo.body(14, .medium))
                                .foregroundStyle(Theme.ink3)
                            Text(Self.greeting())
                                .font(Typo.title(30))
                                .tracking(-0.6)
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        Button("Settings", systemImage: "gearshape") { ui.showingSettings = true }
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 42, height: 42)
                            .background(Theme.card, in: .circle)
                            .shadow(color: Theme.shadow, radius: 8, y: 2)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)

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

                    HStack(spacing: 8) {
                        ToolButton(title: "Timer", symbol: "stopwatch") { showingTimer = true }
                        ToolButton(title: "Plates", symbol: "circle.grid.2x1") { showingPlates = true }
                        ToolButton(title: "1RM", symbol: "percent") { showingOneRepMax = true }
                        ToolButton(title: "Records", symbol: "trophy") { showingRecords = true }
                    }

                    let layout = HomeLayout.decode(layoutRaw)
                    let today = layout.visible(layout.today)
                    let training = layout.visible(layout.training)

                    if !today.isEmpty {
                        SectionHead("Today")
                        ForEach(today, id: \.self) { homeCard($0) }
                    }

                    if !training.isEmpty {
                        SectionHead("Training")
                        ForEach(training, id: \.self) { homeCard($0) }
                    }

                    if let last = gym.workouts.first {
                        SectionHead("Last workout")
                        NavigationLink(value: last.id) {
                            WorkoutCard(workout: last)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Edit Home", systemImage: "slider.horizontal.3") { editingLayout = true }
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.plain)
                        .padding(.top, 10)
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
            .navigationDestination(for: RecoveryRoute.self) { _ in RecoveryView() }
            .sheet(isPresented: $showingTimer) { TimerSheet() }
            .navigationDestination(isPresented: $showingRecords) { RecordsView() }
            .sheet(isPresented: $showingPlates) { PlateCalculatorSheet() }
            .sheet(isPresented: $showingOneRepMax) { OneRepMaxSheet() }
            .sheet(isPresented: $showingChangelog) { ChangelogSheet() }
            .sheet(isPresented: $editingLayout) { HomeLayoutSheet(layoutRaw: $layoutRaw) }
        }
    }

    /// One Home card by its `HomeLayout` name.
    @ViewBuilder private func homeCard(_ name: String) -> some View {
        switch name {
        case "food": FoodCard { ui.showingFood = true }
        case "sleep": SleepCard()
        case "activity": HealthCard()
        case "reps": RepsCard { ui.showingReps = true }
        case "upNext": UpNextCard()
        case "recovery": RecoveryCard()
        case "lastWeek": LastWeekCard()
        case "coach": CoachCard()
        case "body": BodyCard()
        default: EmptyView()
        }
    }

    /// "Good morning" / "Good afternoon" / "Good evening" for the current hour.
    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// This week's training: workout count, the week's days and the start button.
struct WeekCard: View {
    @Environment(GymStore.self) private var gym
    @AppStorage("training.weeklyGoal") private var weeklyGoal = 0
    let onStart: () -> Void

    var body: some View {
        let snapshot = gym.snapshot
        let thisWeek = gym.workouts.filter { gym.weekStart($0.startedAt) == gym.weekStart(.now) }
        let active = gym.activeWorkout

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                if active != nil {
                    StatusPill(text: "In progress", live: true)
                } else {
                    Text("This week").eyebrow()
                }
                Spacer()
                if snapshot.weekStreak > 0 {
                    StreakBadge(weeks: snapshot.weekStreak)
                }
            }

            if let active {
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.name).display(32).lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                        Text(active.startedAt, style: .timer).monospacedDigit()
                        Text("· \(active.completedSets.count) sets")
                    }
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(thisWeek.count)")
                        .font(Typo.display(56))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if weeklyGoal > 0 {
                        Text("/ \(weeklyGoal)")
                            .font(Typo.display(30))
                            .foregroundStyle(Theme.ink3)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        if weeklyGoal > 0 && thisWeek.count >= weeklyGoal {
                            Label("Weekly goal reached", systemImage: "checkmark.circle.fill")
                                .font(Typo.body(15, .semibold))
                                .foregroundStyle(Theme.good)
                        } else if weeklyGoal > 0 {
                            Text("\(weeklyGoal - thisWeek.count) to go this week")
                                .font(Typo.body(16, .semibold))
                        } else {
                            Text(thisWeek.count == 1 ? "workout" : "workouts")
                                .font(Typo.body(16, .semibold))
                        }
                        if !thisWeek.isEmpty {
                            Text("\(Fmt.duration(thisWeek.reduce(0) { $0 + $1.duration })) · \(Fmt.volume(thisWeek.reduce(0) { $0 + $1.volume }))")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .foregroundStyle(Theme.ink)
            }

            WeekStrip(days: snapshot.trainedDays(), todayIndex: ActivitySnapshot.weekdayIndex(), size: 34)

            Button(action: onStart) {
                Label(active == nil ? "Start workout" : "Resume workout", systemImage: active == nil ? "plus" : "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .sensoryFeedback(.impact, trigger: gym.isPresentingWorkout)
        }
        .card(padding: 18, cornerRadius: 26)
    }
}

/// The plan to train next, picked from how long each has waited and how rested its muscles are.
struct UpNextCard: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        if gym.activeWorkout == nil, let next = gym.upNext() {
            let defs = next.plan.exercises.compactMap { gym.exercise($0.exerciseID) }
            HStack(alignment: .center, spacing: 12) {
                AnatomyFigure(primary: Set(defs.flatMap(\.primary)), secondary: Set(defs.flatMap(\.secondary)))
                    .frame(width: 64, height: 76)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up next").eyebrow()
                    Text(next.plan.name)
                        .font(Typo.title(18))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(Self.reason(next.pick))
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    gym.startWorkout(from: next.plan)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.smallPrimary)
            }
            .card(padding: 14, cornerRadius: 20)
        }
    }

    /// "Last done 5 days ago · muscles rested" or "… · chest still recovering".
    static func reason(_ pick: UpNext.Pick) -> String {
        let wait = UpNext.waitText(daysSince: pick.daysSince)
        let tired = pick.tired.compactMap { Muscle(rawValue: $0)?.label.lowercased() }
        guard !tired.isEmpty else { return "\(wait) · muscles rested" }
        let names = tired.prefix(2).joined(separator: " and ")
        return "\(wait) · \(names) still recovering"
    }
}

/// Choose which cards Home shows and drag them into order.
struct HomeLayoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var layoutRaw: String
    @State private var layout = HomeLayout.standard

    private static let titles: [String: (name: String, symbol: String)] = [
        "food": ("Food", "fork.knife"),
        "sleep": ("Sleep", "moon.fill"),
        "activity": ("Activity", "heart.fill"),
        "reps": ("Reps today", "number"),
        "upNext": ("Up next", "play.fill"),
        "recovery": ("Recovery", "figure.cooldown"),
        "lastWeek": ("Last week", "calendar"),
        "coach": ("Coach", "sparkles"),
        "body": ("Body", "ruler"),
    ]

    var body: some View {
        NavigationStack {
            List {
                section("Today", cards: $layout.today)
                section("Training", cards: $layout.training)
                if !layout.isStandard {
                    Section {
                        Button("Reset to standard") { withAnimation { layout = .standard } }
                            .font(Typo.body(15, .semibold))
                    }
                    .cardRow()
                }
            }
            .environment(\.editMode, .constant(.active))
            .screenBackground()
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .onAppear { layout = HomeLayout.decode(layoutRaw) }
            .onChange(of: layout) { layoutRaw = layout.isStandard ? "" : layout.encoded }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, cards: Binding<[String]>) -> some View {
        Section {
            ForEach(cards.wrappedValue, id: \.self) { card in
                let shown = !layout.hidden.contains(card)
                Toggle(isOn: Binding(
                    get: { !layout.hidden.contains(card) },
                    set: { isOn in
                        if isOn { layout.hidden.remove(card) } else { layout.hidden.insert(card) }
                    }
                )) {
                    Label(Self.titles[card]?.name ?? card, systemImage: Self.titles[card]?.symbol ?? "square")
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(shown ? Theme.ink : Theme.ink3)
                }
            }
            .onMove { cards.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
            .cardRow()
        } header: {
            Text(title)
        } footer: {
            if title == "Training" {
                Text("Switch a card off to hide it. Drag the handles to change the order.")
            }
        }
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
        .card(padding: 12, cornerRadius: 20)
    }
}

/// Small square shortcut on Home (Timer, Plates, 1RM, Records).
struct ToolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: .circle)
                Text(title)
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .card(padding: 0, cornerRadius: 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A finished workout: date badge, title, stats and exercises.
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
                                .font(Typo.body(13, .semibold))
                                .monospacedDigit()
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
        .card(padding: 14, cornerRadius: 20)
    }
}

/// Dashed "+ Exercise" button at the end of a workout.
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
