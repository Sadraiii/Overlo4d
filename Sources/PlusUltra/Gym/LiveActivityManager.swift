import ActivityKit
import Foundation
import PlusUltraKit

/// Starts, updates and ends the workout Live Activity (lock screen + Dynamic Island).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?

    func start(for workout: Workout, names: (UUID) -> String) {
        activity = nil
        lastState = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Task { await Self.endAll(except: nil) }
            return
        }
        let attributes = WorkoutActivityAttributes(workoutName: workout.name, startedAt: workout.startedAt)
        let state = Self.state(for: workout, restEndsAt: nil, names: names)
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        lastState = state
        // End any leftovers from earlier workouts, but not the one just started.
        let keep = activity?.id
        Task { await Self.endAll(except: keep) }
    }

    /// Re-attaches to a Live Activity left running from a previous launch, or starts one.
    func resume(for workout: Workout, names: (UUID) -> String) {
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            activity = existing
        } else {
            start(for: workout, names: names)
        }
    }

    func update(for workout: Workout, restEndsAt: Date?, names: (UUID) -> String) {
        guard let activity else { return }
        let state = Self.state(for: workout, restEndsAt: restEndsAt, names: names)
        guard state != lastState else { return }
        lastState = state
        let id = activity.id
        Task { await Self.push(state, toActivityWithID: id) }
    }

    func end() {
        lastState = nil
        activity = nil
        Task { await Self.endAll(except: nil) }
    }

    // `Activity` isn't Sendable, so the async calls look activities up by ID off the main actor.
    private nonisolated static func push(_ state: WorkoutActivityAttributes.ContentState, toActivityWithID id: String) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private nonisolated static func endAll(except keep: String?) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id != keep {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func state(
        for workout: Workout,
        restEndsAt: Date?,
        names: (UUID) -> String
    ) -> WorkoutActivityAttributes.ContentState {
        let next = workout.exercises.first { $0.sets.contains { !$0.isDone } }
        return WorkoutActivityAttributes.ContentState(
            exerciseName: next.map { names($0.exerciseID) },
            setsDone: workout.completedSets.count,
            setsTotal: workout.allSets.count,
            restEndsAt: restEndsAt.flatMap { $0 > .now ? $0 : nil }
        )
    }
}
