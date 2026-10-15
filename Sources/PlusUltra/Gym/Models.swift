import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, biceps, triceps, legs, glutes, core, cardio, fullBody, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .legs: "Legs"
        case .glutes: "Glutes"
        case .core: "Core"
        case .cardio: "Cardio"
        case .fullBody: "Full Body"
        case .other: "Other"
        }
    }
}

enum ExerciseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Weight (kg) × reps, e.g. bench press.
    case weightReps
    /// Reps only, e.g. push-ups.
    case repsOnly
    /// Time only, e.g. plank.
    case duration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weightReps: "Weight & Reps"
        case .repsOnly: "Reps Only"
        case .duration: "Duration"
        }
    }
}

struct ExerciseDef: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var muscle: MuscleGroup
    var kind: ExerciseKind
    var isCustom = false
}

enum SetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, warmup, drop, failure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warmup: "Warm-up"
        case .drop: "Drop Set"
        case .failure: "Failure"
        }
    }

    /// Short badge shown instead of the set number (empty for normal sets).
    var badge: String {
        switch self {
        case .normal: ""
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }
}

struct WorkoutSet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var type: SetType = .normal
    /// Kilograms.
    var weight: Double?
    var reps: Int?
    var seconds: Int?
    var isDone = false

    /// A fresh, not-done copy (new ID) used when adding sets or starting from a routine.
    func copyForNewSet() -> WorkoutSet {
        WorkoutSet(type: type, weight: weight, reps: reps, seconds: seconds)
    }

    var volume: Double { (weight ?? 0) * Double(reps ?? 0) }

    /// Estimated one-rep max (Epley formula).
    var estimatedOneRepMax: Double {
        guard let weight, let reps, reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    var hasValues: Bool { weight != nil || reps != nil || seconds != nil }
}

struct WorkoutExercise: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var exerciseID: UUID
    var sets: [WorkoutSet]
    /// Rest timer after completing a set; 0 = off.
    var restSeconds = 90
    var notes = ""
}

struct Workout: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [WorkoutExercise]
    var notes = ""

    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }
    var allSets: [WorkoutSet] { exercises.flatMap(\.sets) }
    var completedSets: [WorkoutSet] { allSets.filter(\.isDone) }
    var volume: Double { completedSets.reduce(0) { $0 + $1.volume } }
}

struct Routine: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Template exercises; set weights/reps are the targets.
    var exercises: [WorkoutExercise]
}

struct GymData: Codable, Sendable {
    var exercises: [ExerciseDef] = ExerciseLibrary.defaults
    var workouts: [Workout] = []
    var routines: [Routine] = []
    /// The workout currently in progress, kept on disk so it survives the app being closed.
    var activeWorkout: Workout?
}

enum RecordKind: String, CaseIterable, Sendable {
    case heaviestWeight, bestOneRepMax, bestSetVolume, mostReps, longestDuration

    var label: String {
        switch self {
        case .heaviestWeight: "Heaviest Weight"
        case .bestOneRepMax: "Best 1RM"
        case .bestSetVolume: "Best Set Volume"
        case .mostReps: "Most Reps"
        case .longestDuration: "Longest Time"
        }
    }

    static func kinds(for kind: ExerciseKind) -> [RecordKind] {
        switch kind {
        case .weightReps: [.heaviestWeight, .bestOneRepMax, .bestSetVolume, .mostReps]
        case .repsOnly: [.mostReps]
        case .duration: [.longestDuration]
        }
    }

    func value(of set: WorkoutSet) -> Double {
        switch self {
        case .heaviestWeight: set.weight ?? 0
        case .bestOneRepMax: set.estimatedOneRepMax
        case .bestSetVolume: set.volume
        case .mostReps: Double(set.reps ?? 0)
        case .longestDuration: Double(set.seconds ?? 0)
        }
    }
}
