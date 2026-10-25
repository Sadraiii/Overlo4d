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
}

@main
struct TallyApp: App {
    @State private var reps = RepModel()
    @State private var gym = GymStore()
    @State private var rest = RestTimer()
    @State private var ui = AppUI()
    @State private var health = HealthManager()
    @State private var clock = IntervalClock()
    @State private var coach = CoachStore()
    @AppStorage(Accent.storageKey, store: SharedStorage.defaults) private var accent = Accent.violet.rawValue
    @AppStorage(AppearanceMode.storageKey, store: SharedStorage.defaults) private var appearance = AppearanceMode.system.rawValue
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
                .tint(Theme.accent)
                // Rebuild with the new accent colour when it changes.
                .id(accent)
                .sheet(isPresented: $ui.showingSettings) { SettingsSheet().environment(health).environment(coach).environment(gym) }
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
                .onAppear { rest.requestPermission() }
                .onChange(of: accent) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: health.isConnected) { Task { await HealthSync.refresh(gym: gym, health: health) } }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up the new day (and any widget-side changes) when returning to the app.
            guard phase == .active else { return }
            reps.reload()
            Task { await HealthSync.refresh(gym: gym, health: health) }
        }
    }

    /// Navigation titles in the condensed display face, like Outdoor Office headings.
    private static func styleNavigationBars() {
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: "BigShouldersDisplayThin-ExtraBold", size: 44) {
            appearance.largeTitleTextAttributes = [.font: large, .kern: 0.4]
        }
        if let inline = UIFont(name: "BigShouldersDisplayThin-ExtraBold", size: 22) {
            appearance.titleTextAttributes = [.font: inline, .kern: 0.6]
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
        .onOpenURL { url in
            // Widgets deep-link with tally://reps and tally://train.
            switch url.host() {
            case "reps":
                tab = .home
                ui.showingReps = true
            case "train":
                tab = .home
            default: break
            }
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
                            .font(Typo.display(17))
                            .textCase(.uppercase)
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
