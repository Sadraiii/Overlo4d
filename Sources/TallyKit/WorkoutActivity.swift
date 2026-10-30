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

        public init(
            exerciseName: String?,
            nextSet: String? = nil,
            setsDone: Int,
            setsTotal: Int,
            restStartedAt: Date? = nil,
            restEndsAt: Date?
        ) {
            self.exerciseName = exerciseName
            self.nextSet = nextSet
            self.setsDone = setsDone
            self.setsTotal = setsTotal
            self.restStartedAt = restStartedAt
            self.restEndsAt = restEndsAt
        }

        /// The rest countdown as a range, if one is running.
        public var restInterval: ClosedRange<Date>? {
            guard let end = restEndsAt else { return nil }
            let start = min(restStartedAt ?? end, end)
            return start...end
        }
    }

    public var workoutName: String
    public var startedAt: Date

    public init(workoutName: String, startedAt: Date) {
        self.workoutName = workoutName
        self.startedAt = startedAt
    }
}
