import ActivityKit
import Foundation

/// Live Activity shown on the lock screen and Dynamic Island while a workout is running.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// The next exercise with sets left to do.
        public var exerciseName: String?
        /// "Set 3 of 4" for the next exercise.
        public var nextSet: String?
        public var setsDone: Int
        public var setsTotal: Int
        /// When the current rest started, for the draining bar. Nil in activities from before 0.8.
        public var restStartedAt: Date?
        public var restEndsAt: Date?
        /// Whole seconds left on a paused rest. Nil while counting down or not resting.
        public var restPausedRemaining: TimeInterval?
        /// Set on the last update, when the workout is saved: "52min · 8,450 kg · 18 sets".
        /// The activity has ended by then and stays on the Lock Screen for a while.
        public var finishedSummary: String?

        // New fields are optional so states from older builds still decode.
        public init(
            exerciseName: String?,
            nextSet: String? = nil,
            setsDone: Int,
            setsTotal: Int,
            restStartedAt: Date? = nil,
            restEndsAt: Date?,
            restPausedRemaining: TimeInterval? = nil,
            finishedSummary: String? = nil
        ) {
            self.exerciseName = exerciseName
            self.nextSet = nextSet
            self.setsDone = setsDone
            self.setsTotal = setsTotal
            self.restStartedAt = restStartedAt
            self.restEndsAt = restEndsAt
            self.restPausedRemaining = restPausedRemaining
            self.finishedSummary = finishedSummary
        }

        /// The rest countdown as a range, if one is running.
        public var restInterval: ClosedRange<Date>? {
            guard let end = restEndsAt else { return nil }
            let start = min(restStartedAt ?? end, end)
            return start...end
        }

        /// What the Live Activity shows. `isStale` is the system's flag: the app makes the end of a
        /// rest the stale date, so "Rest over" appears on time even while the app is suspended.
        public func phase(isStale: Bool, now: Date = .now) -> WorkoutActivityPhase {
            if let finishedSummary { return .finished(summary: finishedSummary) }
            if let restPausedRemaining { return .restPaused(remaining: restPausedRemaining) }
            guard let rest = restInterval else { return .training }
            return isStale || rest.upperBound <= now ? .restOver : .resting(rest)
        }
    }

    public var workoutName: String
    public var startedAt: Date

    public init(workoutName: String, startedAt: Date) {
        self.workoutName = workoutName
        self.startedAt = startedAt
    }
}

/// The states of the workout Live Activity, from `ContentState.phase(isStale:now:)`.
public enum WorkoutActivityPhase: Equatable, Sendable {
    /// Between rests: elapsed time and set progress.
    case training
    /// Counting down a rest; the system animates the countdown from this range.
    case resting(ClosedRange<Date>)
    /// A rest on hold, with the seconds that were left.
    case restPaused(remaining: TimeInterval)
    /// The rest ran out and the app hasn't updated the activity since.
    case restOver
    /// The workout was saved; shown on the Lock Screen after the activity ends.
    case finished(summary: String)
}
