import ActivityKit
import Foundation
import Overlo4dKit

/// Starts, updates and ends the workout Live Activity (lock screen + Dynamic Island).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Show the workout on the Lock Screen and in the Dynamic Island. Set in Settings › Training.
    nonisolated static let enabledKey = "liveActivity.enabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    /// How long a finished workout's summary stays on the Lock Screen. Apple suggests 15 to 30 minutes.
    private static let summaryLifetime: TimeInterval = 15 * 60

    private var activity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?

    func start(for workout: Workout, names: (UUID) -> String) {
        activity = nil
        lastState = nil
        guard Self.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            Task { await Self.endAll(except: nil) }
            return
        }
        let attributes = WorkoutActivityAttributes(workoutName: workout.name, startedAt: workout.startedAt)
        let state = Self.state(for: workout, rest: nil, restPaused: nil, names: names)
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        lastState = state
        // End any leftovers from earlier workouts, but not the one just started.
        let keep = activity?.id
        Task { await Self.endAll(except: keep) }
    }

    /// After a relaunch: re-attaches to this workout's Live Activity if it is still up, or starts one.
    /// Activities from other workouts are ended so nothing stale stays on the Lock Screen.
    func resume(for workout: Workout, names: (UUID) -> String) {
        let running = Activity<WorkoutActivityAttributes>.activities.first { activity in
            (activity.activityState == .active || activity.activityState == .stale)
                && activity.content.state.finishedSummary == nil
                // Within a second: the start time went through two encoders.
                && abs(activity.attributes.startedAt.timeIntervalSince(workout.startedAt)) < 1
        }
        guard Self.isEnabled, let running else {
            start(for: workout, names: names)
            return
        }
        activity = running
        lastState = running.content.state
        let keep = running.id
        Task { await Self.endAll(except: keep) }
    }

    /// `rest` is the running rest countdown, from when it started to when it ends;
    /// `restPaused` the seconds left on a paused one.
    func update(for workout: Workout, rest: ClosedRange<Date>?, restPaused: TimeInterval?, names: (UUID) -> String) {
        guard let activity else { return }
        let state = Self.state(for: workout, rest: rest, restPaused: restPaused, names: names)
        // Only real changes are sent, as Apple asks; the countdowns run on the device by themselves.
        guard state != lastState else { return }
        lastState = state
        let id = activity.id
        Task { await Self.push(state, toActivityWithID: id) }
    }

    /// Ends the activity with a summary of the saved workout, left on the Lock Screen for a while.
    func finish(_ workout: Workout, names: (UUID) -> String) {
        var state = Self.state(for: workout, rest: nil, restPaused: nil, names: names)
        state.finishedSummary = Self.summary(of: workout)
        let id = activity?.id
        activity = nil
        lastState = nil
        let dismissal = Date.now.addingTimeInterval(Self.summaryLifetime)
        Task { await Self.endAll(showing: state, onActivityWithID: id, until: dismissal) }
    }

    /// Ends every workout activity at once (workout discarded, or Live Activities switched off).
    func end() {
        lastState = nil
        activity = nil
        Task { await Self.endAll(except: nil) }
    }

    /// At launch with no workout running: clears activities left from a workout that never finished,
    /// but keeps a finished workout's summary until its own dismissal time.
    func endLeftovers() {
        lastState = nil
        activity = nil
        Task { await Self.endUnfinished() }
    }

    // `Activity` isn't Sendable, so the async calls look activities up by ID off the main actor.
    private nonisolated static func push(_ state: WorkoutActivityAttributes.ContentState, toActivityWithID id: String) async {
        // Going stale when the rest ends redraws the lock screen as "Rest over",
        // even if the app is suspended by then.
        let content = ActivityContent(state: state, staleDate: state.restEndsAt)
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    private nonisolated static func endAll(except keep: String?) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id != keep {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func endUnfinished() async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.content.state.finishedSummary == nil {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// The finished workout's activity ends showing `state` until `dismissal`; any others end at once.
    private nonisolated static func endAll(
        showing state: WorkoutActivityAttributes.ContentState,
        onActivityWithID id: String?,
        until dismissal: Date
    ) async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            if activity.id == id {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(dismissal))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func state(
        for workout: Workout,
        rest: ClosedRange<Date>?,
        restPaused: TimeInterval?,
        names: (UUID) -> String
    ) -> WorkoutActivityAttributes.ContentState {
        let next = workout.exercises.first { $0.sets.contains { !$0.isDone } }
        let nextSet = next.flatMap { exercise in
            exercise.sets.firstIndex { !$0.isDone }.map { "Set \($0 + 1) of \(exercise.sets.count)" }
        }
        let rest = rest.flatMap { $0.upperBound > .now ? $0 : nil }
        return WorkoutActivityAttributes.ContentState(
            exerciseName: next.map { names($0.exerciseID) },
            nextSet: nextSet,
            setsDone: workout.completedSets.count,
            setsTotal: workout.allSets.count,
            restStartedAt: rest?.lowerBound,
            restEndsAt: rest?.upperBound,
            // Whole seconds, as the app shows them, so the Lock Screen and the dock agree.
            restPausedRemaining: restPaused.map { $0.rounded(.up) }
        )
    }

    /// "52min · 8,450 kg · 18 sets"; the volume is left out for bodyweight-only workouts.
    private static func summary(of workout: Workout) -> String {
        let sets = workout.completedSets.count
        return [
            Fmt.duration(workout.duration),
            workout.volume > 0 ? Fmt.volume(workout.volume) : nil,
            sets == 1 ? "1 set" : "\(sets) sets",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
