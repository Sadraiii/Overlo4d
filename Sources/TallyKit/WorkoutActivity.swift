import ActivityKit
import Foundation

/// Live Activity shown on the lock screen and Dynamic Island while a workout is running.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// The next exercise with sets left to do.
        public var exerciseName: String?
        public var setsDone: Int
        public var setsTotal: Int
        public var restEndsAt: Date?

        public init(exerciseName: String?, setsDone: Int, setsTotal: Int, restEndsAt: Date?) {
            self.exerciseName = exerciseName
            self.setsDone = setsDone
            self.setsTotal = setsTotal
            self.restEndsAt = restEndsAt
        }
    }

    public var workoutName: String
    public var startedAt: Date

    public init(workoutName: String, startedAt: Date) {
        self.workoutName = workoutName
        self.startedAt = startedAt
    }
}
