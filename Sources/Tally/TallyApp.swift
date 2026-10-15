import TallyKit
import SwiftUI
import UIKit
import WidgetKit

enum AppTab: Hashable {
    case train, history, start, progress, reps
}

/// App-level UI state that lives outside the accent-coloured view tree.
@MainActor
@Observable
final class AppUI {
    var showingSettings = false
}

@main
struct TallyApp: App {
    @State private var reps = RepModel()
    @State private var gym = GymStore()
    @State private var rest = RestTimer()
    @State private var ui = AppUI()
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
                .tint(Theme.accent)
                // Rebuild with the new accent colour when it changes.
                .id(accent)
                .sheet(isPresented: $ui.showingSettings) { SettingsSheet() }
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
                .onAppear { rest.requestPermission() }
                .onChange(of: accent) { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up the new day (and any widget-side changes) when returning to the app.
            if phase == .active { reps.reload() }
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
    @State private var tab = AppTab.train
    @State private var showingStart = false
    /// Chosen on the start sheet; begun once the sheet has closed so the two presentations don't clash.
    @State private var pendingStart: StartRequest?

    var body: some View {
        @Bindable var gym = gym

        TabView(selection: Binding(get: { tab }, set: select)) {
            Tab("Train", systemImage: "figure.strengthtraining.traditional", value: AppTab.train) {
                TrainTab(onStart: { select(.start) })
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Start", systemImage: gym.activeWorkout == nil ? "plus.circle.fill" : "play.circle.fill", value: AppTab.start) {
                Color.clear
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: AppTab.progress) {
                ProgressTabView()
            }
            Tab("Reps", systemImage: "flame.fill", value: AppTab.reps) {
                QuickCountView()
            }
        }
        .tabViewBottomAccessory(isEnabled: gym.activeWorkout != nil && !gym.isPresentingWorkout) {
            WorkoutAccessory()
        }
        .sheet(isPresented: $showingStart, onDismiss: {
            guard let request = pendingStart else { return }
            pendingStart = nil
            gym.start(name: request.name, exercises: request.exercises, restSeconds: request.restSeconds)
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
            case "reps": tab = .reps
            case "train": tab = .train
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
