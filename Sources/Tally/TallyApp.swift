import TallyCore
import TallyKit
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
    /// A sheet opened from anywhere: a Home shortcut, a tally:// link or the Home Screen menu.
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

    /// Menu items carry their tally:// link as the type.
    @MainActor @discardableResult
    static func open(_ item: UIApplicationShortcutItem) -> Bool {
        guard let url = URL(string: item.type), let link = AppLink.parse(url) else { return false }
        LinkInbox.shared.link = link
        return true
    }
}

@main
struct TallyApp: App {
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
                        .environment(cloud).environment(sleep).environment(food).environment(bodyStore).environment(programs) }
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

struct RootView: View {
    @Environment(GymStore.self) private var gym
    @Environment(AppUI.self) private var ui
    @State private var tab = AppTab.home
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
            // Widgets, the Home Screen menu and shortcuts in the Shortcuts app all open tally:// links.
            if let link = AppLink.parse(url) { open(link) }
        }
        .onChange(of: inbox.link) { takeLink() }
        .onAppear { takeLink() }
    }

    /// Acts on a link that came in through the Home Screen menu.
    private func takeLink() {
        guard let link = LinkInbox.shared.link else { return }
        LinkInbox.shared.link = nil
        open(link)
    }

    private func open(_ link: AppLink) {
        switch link {
        case .reps:
            tab = .home
            ui.showingReps = true
        case .food:
            tab = .home
            ui.showingFood = true
        case .train:
            tab = .home
        case .history:
            tab = .history
        case .start(let plan):
            if gym.activeWorkout != nil {
                gym.isPresentingWorkout = true
            } else if let plan {
                // A plan named in the link starts straight away; an unknown name opens the start sheet.
                if let index = AppLink.match(plan: plan, in: gym.plans.map(\.name)) {
                    gym.startWorkout(from: gym.plans[index])
                } else {
                    showingStart = true
                }
            } else {
                gym.startEmptyWorkout()
            }
        case .cardio: ui.sheet = .cardio
        case .plates: ui.sheet = .plates
        case .timer: ui.sheet = .timer
        case .report: ui.sheet = .report
        }
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

/// Bar above the tab bar while a workout is minimized.
struct WorkoutAccessory: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        if let workout = gym.activeWorkout {
            Button {
                gym.isPresentingWorkout = true
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(workout.name)
                            .font(Typo.title(15))
                            .lineLimit(1)
                        Text("\(workout.completedSets.count) sets")
                            .font(Typo.body(12))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Text(workout.startedAt, style: .timer)
                        .font(Typo.display(22))
                        .monospacedDigit()
                }
                .padding(.horizontal)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Content of the full-screen workout cover: the live workout, then the summary once finished.
struct WorkoutFlowView: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        if let summary = gym.summaryWorkout {
            WorkoutSummaryView(workout: summary)
        } else if let workout = gym.activeWorkout {
            ActiveWorkoutView(initial: workout)
                .id(workout.id)
        } else {
            ScreenBackground()
        }
    }
}
