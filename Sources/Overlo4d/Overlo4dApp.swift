import Overlo4dCore
import Overlo4dKit
import SwiftUI
import UIKit
import WidgetKit

enum AppTab: Hashable {
    case home, plans, start, history, progress
}

/// App-level UI state that lives outside the accent-coloured view tree.
@MainActor
@Observable
final class AppUI {
    var showingSettings = false
    /// The rep counter, pushed on Home.
    var showingReps = false
    /// The food diary, pushed on Home.
    var showingFood = false
    /// Bumped after a backup is restored, so the stores reload their files.
    var dataVersion = 0
    /// A sheet opened from anywhere: a Home shortcut, a overlo4d:// link or the Home Screen menu.
    var sheet: AppSheet?
}

enum AppSheet: String, Identifiable {
    case cardio, plates, timer, report

    var id: String { rawValue }
}

/// A link that arrived before the interface was ready (the Home Screen menu on a cold start).
@MainActor
@Observable
final class LinkInbox {
    static let shared = LinkInbox()
    var link: AppLink?
}

/// Start workout, Log cardio and Rep counter when the app icon is held on the Home Screen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem { SceneDelegate.open(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        Self.open(shortcutItem)
    }

    /// Menu items carry their overlo4d:// link as the type.
    @MainActor @discardableResult
    static func open(_ item: UIApplicationShortcutItem) -> Bool {
        guard let url = URL(string: item.type), let link = AppLink.parse(url) else { return false }
        LinkInbox.shared.link = link
        return true
    }
}

@main
struct Overlo4dApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var reps = RepModel()
    @State private var gym = GymStore()
    @State private var rest = RestTimer()
    @State private var ui = AppUI()
    @State private var health = HealthManager()
    @State private var clock = IntervalClock()
    @State private var coach = CoachStore()
    @State private var food = FoodStore()
    @State private var sleep = SleepStore()
    @State private var bodyStore = BodyStore()
    @State private var programs = ProgramStore()
    @State private var backup = BackupStore()
    @State private var cloud = CoachCloudStore()
    @AppStorage(Accent.storageKey, store: SharedStorage.defaults) private var accent = Accent.violet.rawValue
    @AppStorage(AppearanceMode.storageKey, store: SharedStorage.defaults) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(Units.key, store: SharedStorage.defaults) private var unit = WeightUnit.kg.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Typo.registerFonts()
        Self.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(reps)
                .environment(gym)
                .environment(rest)
                .environment(ui)
                .environment(health)
                .environment(clock)
                .environment(coach)
                .environment(food)
                .environment(sleep)
                .environment(bodyStore)
                .environment(programs)
                .environment(cloud)
                .tint(Theme.accent)
                // Rebuild with the new accent colour or weight unit when it changes.
                .id("\(accent).\(unit)")
                .sheet(isPresented: $ui.showingSettings) { SettingsSheet().environment(health).environment(coach).environment(gym).environment(ui).environment(backup)
                        .environment(cloud).environment(sleep).environment(food).environment(bodyStore).environment(programs).environment(reps) }
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
                .onAppear {
                    rest.requestPermission()
                    food.health = health
                    bodyStore.health = health
                    food.scheduleMealReminders()
                    Task { await ExerciseMediaStore.shared.loadCatalogue() }
                }
                .onChange(of: ui.dataVersion) { reloadData() }
                .onChange(of: accent) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: health.isConnected) {
                    Task {
                        await HealthSync.refresh(gym: gym, health: health)
                        await sleep.refresh(health: health)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Anything typed in the last moment is written before the app can be suspended.
            if phase != .active { gym.flush() }
            if phase != .inactive { TrainingReminders.reschedule(gym: gym) }
            if phase == .background {
                backup.backUpIfChanged()
                let toolbox = CoachToolbox(gym: gym, sleep: sleep, food: food, body: bodyStore, programs: programs)
                Task { await cloud.sync(toolbox: toolbox) }
                // Leave the widgets showing exactly what the app last showed.
                WidgetCenter.shared.reloadAllTimelines()
            }
            // Pick up the new day (and any widget-side changes) when returning to the app.
            guard phase == .active else { return }
            reps.reload()
            Task { await cloud.refreshInbox() }
            Task {
                // After Health's refresh, which asks for sleep access the first time.
                await HealthSync.refresh(gym: gym, health: health)
                sleep.updateContext(gym: gym, food: food)
                await sleep.refresh(health: health)
            }
        }
    }

    /// Reads every store's file again after a restore.
    private func reloadData() {
        gym.cancelPendingSave()
        gym = GymStore()
        food = FoodStore()
        sleep = SleepStore()
        bodyStore = BodyStore()
        programs = ProgramStore()
        coach = CoachStore()
        reps.reload()
        food.health = health
        bodyStore.health = health
        food.scheduleMealReminders()
        sleep.scheduleReminders()
        TrainingReminders.reschedule(gym: gym)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await HealthSync.refresh(gym: gym, health: health)
            sleep.updateContext(gym: gym, food: food)
            await sleep.refresh(health: health)
        }
    }

    /// Navigation titles in bold Schibsted Grotesk, matching the in-page headings.
    private static func styleNavigationBars() {
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: "SchibstedGrotesk-Bold", size: 32) {
            appearance.largeTitleTextAttributes = [.font: large, .kern: -0.6]
        }
        if let inline = UIFont(name: "SchibstedGrotesk-Bold", size: 17) {
            appearance.titleTextAttributes = [.font: inline]
        }
    }
}

/// What a link did, for the note at the top and for a shortcut waiting on an x-callback.
private enum LinkOutcome {
    /// Opened a screen.
    case shown
    /// Did something; the text says what ("Water: 3 of 8 glasses").
    case done(String)
    case failed(String)
}

struct RootView: View {
    @Environment(GymStore.self) private var gym
    @Environment(AppUI.self) private var ui
    @Environment(FoodStore.self) private var food
    @Environment(RepModel.self) private var reps
    @Environment(RestTimer.self) private var rest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = AppTab.home
    /// A short note after a link logged something, so it's clear it worked.
    @State private var linkNote: LinkNote?
    @State private var showingStart = false
    /// Chosen on the start sheet; begun once the sheet has closed so the two presentations don't clash.
    @State private var pendingStart: StartRequest?

    var body: some View {
        @Bindable var gym = gym
        @Bindable var ui = ui
        let inbox = LinkInbox.shared

        TabView(selection: Binding(get: { tab }, set: select)) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeTab(onStart: { select(.start) })
            }
            Tab("Plans", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.plans) {
                PlansTab()
            }
            Tab("Start", systemImage: gym.activeWorkout == nil ? "plus.circle.fill" : "play.circle.fill", value: AppTab.start) {
                Color.clear
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: AppTab.progress) {
                ProgressTabView()
            }
        }
        // Scrolling down shrinks the tab bar, as in Apple's own apps, so lists get the room.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: gym.activeWorkout != nil && !gym.isPresentingWorkout) {
            WorkoutAccessory()
        }
        .sheet(isPresented: $showingStart, onDismiss: {
            guard let request = pendingStart else { return }
            pendingStart = nil
            gym.start(name: request.name, exercises: request.exercises, restSeconds: request.restSeconds, planID: request.planID)
        }) {
            StartWorkoutSheet { request in
                pendingStart = request
                showingStart = false
            }
        }
        .fullScreenCover(isPresented: $gym.isPresentingWorkout) {
            WorkoutFlowView()
        }
        .sheet(item: $ui.sheet) { sheet in
            switch sheet {
            case .cardio: CardioLogSheet()
            case .plates: PlateCalculatorSheet()
            case .timer: TimerSheet()
            case .report:
                NavigationStack {
                    RecapView(weekStart: Calendar.current.date(byAdding: .day, value: -1, to: gym.weekStart(.now)) ?? .now)
                }
            }
        }
        .onOpenURL { url in
            // Widgets, the Home Screen menu and shortcuts in the Shortcuts app all open overlo4d:// links.
            handle(url)
        }
        .overlay(alignment: .top) {
            if let linkNote {
                LinkNoteView(note: linkNote)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(linkNote.id)
            }
        }
        .sensoryFeedback(trigger: linkNote) { _, note in
            guard let note else { return nil }
            return note.failed ? .error : .success
        }
        .onChange(of: inbox.link) { takeLink() }
        .onAppear { takeLink() }
    }

    /// Acts on a link that came in through the Home Screen menu.
    private func takeLink() {
        guard let link = LinkInbox.shared.link else { return }
        LinkInbox.shared.link = nil
        note(open(link))
    }

    /// Runs a link. With Shortcuts' "Open X-Callback URL", the shortcut waits for this and then
    /// carries on: x-success gets what was done as `result`, x-error gets the reason.
    private func handle(_ url: URL) {
        let parsed = AppLinkRequest.parse(url)
        guard let request = parsed.request else {
            if let failure = parsed.failure,
               let back = AppLinkRequest.errorURL(failure, message: "Overlo4d can't open this link. Check it in Settings › Siri and Shortcuts.") {
                UIApplication.shared.open(back)
            }
            return
        }
        let outcome = open(request.link)
        let back: URL?
        switch outcome {
        case .shown: back = request.successURL(result: nil)
        case .done(let message): back = request.successURL(result: message)
        case .failed(let message): back = request.failureURL(message: message)
        }
        if let back {
            UIApplication.shared.open(back)
        } else {
            note(outcome)
        }
    }

    private func note(_ outcome: LinkOutcome) {
        let note: LinkNote
        switch outcome {
        case .shown: return
        case .done(let message): note = LinkNote(text: message, failed: false)
        case .failed(let message): note = LinkNote(text: message, failed: true)
        }
        Motion.animate(Motion.arrive) { linkNote = note }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if linkNote?.id == note.id { Motion.animate { linkNote = nil } }
        }
    }

    @discardableResult
    private func open(_ link: AppLink) -> LinkOutcome {
        switch link {
        case .reps:
            tab = .home
            ui.showingReps = true
        case .addReps(let count, let name):
            let names = reps.exercises.map(\.name)
            let index = name.map { AppLink.match(plan: $0, in: names) } ?? (names.isEmpty ? nil : 0)
            guard let index else {
                return .failed(name.map { "No rep counter exercise called \($0)" } ?? "Add an exercise to the rep counter first")
            }
            let exercise = reps.exercises[index]
            reps.add(count, to: exercise)
            return .done("+\(count) \(exercise.name) · \(reps.repsToday(for: exercise)) today")
        case .water(let glasses):
            let day = food.today
            let total = min(food.water(day) + glasses, 30)
            food.setWater(total, on: day)
            return .done("Water: \(total) of \(food.waterGoal) glasses")
        case .weight(let kg):
            food.logWeight(kg, on: food.today)
            return .done("Weight logged: \(kg.formatted(.number.precision(.fractionLength(0...1)))) kg")
        case .rest(let seconds):
            let length = seconds ?? gym.defaultRestSeconds
            rest.start(seconds: length)
            // The Lock Screen and Dynamic Island follow, even if the workout screen isn't open.
            if let workout = gym.activeWorkout {
                gym.updateActive(workout, rest: rest.interval)
            }
            return .done("Rest: \(Duration.seconds(length).formatted(.time(pattern: .minuteSecond)))")
        case .food:
            tab = .home
            ui.showingFood = true
        case .train:
            tab = .home
        case .activeWorkout:
            if gym.activeWorkout != nil { gym.isPresentingWorkout = true } else { tab = .home }
        case .history:
            tab = .history
        case .start(let plan):
            if gym.activeWorkout != nil {
                gym.isPresentingWorkout = true
            } else if let plan {
                // A plan named in the link starts straight away; an unknown name opens the start sheet.
                if let index = AppLink.match(plan: plan, in: gym.plans.map(\.name)) {
                    gym.startWorkout(from: gym.plans[index])
                    return .done("Started \(gym.plans[index].name)")
                } else {
                    showingStart = true
                    return .failed("No plan called \(plan)")
                }
            } else {
                gym.startEmptyWorkout()
            }
        case .cardio: ui.sheet = .cardio
        case .plates: ui.sheet = .plates
        case .timer: ui.sheet = .timer
        case .report: ui.sheet = .report
        }
        return .shown
    }

    /// The centre tab opens the start sheet (or the running workout) instead of switching tabs.
    private func select(_ newTab: AppTab) {
        guard newTab == .start else { tab = newTab; return }
        if gym.activeWorkout != nil {
            gym.isPresentingWorkout = true
        } else {
            showingStart = true
        }
    }
}

/// A short note at the top after a link did something, such as a shortcut logging water.
struct LinkNote: Equatable {
    let id = UUID()
    let text: String
    let failed: Bool
}

struct LinkNoteView: View {
    let note: LinkNote

    var body: some View {
        Label(note.text, systemImage: note.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(Typo.body(14, .semibold))
            .foregroundStyle(note.failed ? Theme.danger : Theme.good)
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 6)
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Bar above the tab bar while a workout is minimized. Between sets it becomes the rest timer:
/// a draining ring, the next exercise and the countdown, then a short green "Go" when it's up.
/// When the tab bar shrinks on scroll, it sits inline beside it with just the time.
struct WorkoutAccessory: View {
    @Environment(GymStore.self) private var gym
    @Environment(RestTimer.self) private var rest
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let workout = gym.activeWorkout {
            Button {
                gym.isPresentingWorkout = true
            } label: {
                HStack(spacing: 12) {
                    indicator
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(workout.name)
                            .font(Typo.title(15))
                            .lineLimit(1)
                        if placement != .inline {
                            Text(subtitle(workout))
                                .font(Typo.body(12))
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 8)
                    time(workout)
                        .font(Typo.display(placement == .inline ? 19 : 22))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal)
                .contentShape(.rect)
                .animation(Motion.standard, value: rest.isRunning)
                .animation(Motion.standard, value: rest.justFinished)
                .animation(Motion.standard, value: workout.completedSets.count)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the workout")
        }
    }

    @ViewBuilder private var indicator: some View {
        if rest.justFinished {
            Image(systemName: "bell.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.good)
                .symbolEffect(.bounce, value: rest.justFinished)
                .transition(.scale.combined(with: .opacity))
        } else if let interval = rest.interval {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(Theme.accent)
            .transition(.scale.combined(with: .opacity))
        } else if rest.isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink3)
        } else {
            Circle().fill(Theme.good).frame(width: 8, height: 8)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func subtitle(_ workout: Workout) -> String {
        let done = workout.completedSets.count
        let total = workout.allSets.count
        guard rest.isRunning || rest.justFinished else { return "\(done) of \(total) sets" }
        let next = workout.exercises.first { $0.sets.contains { !$0.isDone } }
            .flatMap { gym.exercise($0.exerciseID)?.name }
        let state = rest.justFinished ? "Rest over" : rest.isPaused ? "Rest paused" : "Rest"
        return next.map { "\(state) · Next: \($0)" } ?? state
    }

    @ViewBuilder private func time(_ workout: Workout) -> some View {
        if rest.justFinished {
            Text("Go").foregroundStyle(Theme.good)
        } else if let interval = rest.interval {
            Text(timerInterval: interval, countsDown: true)
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.trailing)
                .frame(width: 56, alignment: .trailing)
        } else if let remaining = rest.pausedRemaining {
            Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                .foregroundStyle(Theme.ink3)
        } else {
            Text(workout.startedAt, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Content of the full-screen workout cover: the live workout, then the summary once finished.
/// Finishing cross-fades into the summary instead of cutting to it.
struct WorkoutFlowView: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        Group {
            if let summary = gym.summaryWorkout {
                WorkoutSummaryView(workout: summary)
            } else if let workout = gym.activeWorkout {
                ActiveWorkoutView(initial: workout)
                    .id(workout.id)
            } else {
                ScreenBackground()
            }
        }
        .transition(.opacity)
        .animation(Motion.standard, value: gym.summaryWorkout?.id)
    }
}
