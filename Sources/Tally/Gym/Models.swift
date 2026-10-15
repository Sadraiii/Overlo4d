import Foundation
import TallyCore

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
    /// Added weight × reps, e.g. weighted pull-ups.
    case weightedBodyweight
    /// Assistance × reps, e.g. machine-assisted pull-ups. Less assistance is better.
    case assistedBodyweight
    /// Distance and time, e.g. running.
    case distanceDuration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weightReps: "Weight & Reps"
        case .repsOnly: "Reps Only"
        case .duration: "Duration"
        case .weightedBodyweight: "Weighted Bodyweight"
        case .assistedBodyweight: "Assisted Bodyweight"
        case .distanceDuration: "Distance & Time"
        }
    }
}

struct ExerciseDef: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var muscle: MuscleGroup
    var kind: ExerciseKind
    var isCustom = false
    // Optional so data saved before these existed still decodes; filled from the library on load.
    var equipment: Equipment?
    var primaryMuscles: [Muscle]?
    var secondaryMuscles: [Muscle]?

    var primary: [Muscle] { primaryMuscles ?? muscle.defaultMuscles }
    var secondary: [Muscle] { secondaryMuscles ?? [] }

    /// Primary muscles, e.g. "Quads, Glutes", or the group when none are set.
    var muscleSummary: String {
        primary.isEmpty ? muscle.label : primary.map(\.label).joined(separator: ", ")
    }
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
    /// Assistance in kg for assisted exercises. Kept apart from `weight` so it never counts as volume.
    var assistance: Double?
    var meters: Double?
    var isDone = false

    /// A fresh, not-done copy (new ID) used when adding sets or starting from a plan.
    func copyForNewSet() -> WorkoutSet {
        WorkoutSet(type: type, weight: weight, reps: reps, seconds: seconds, assistance: assistance, meters: meters)
    }

    var volume: Double { (weight ?? 0) * Double(reps ?? 0) }

    /// Estimated one-rep max (Epley formula).
    var estimatedOneRepMax: Double {
        guard let weight, let reps, reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    var hasValues: Bool { weight != nil || reps != nil || seconds != nil || assistance != nil || meters != nil }
}

struct WorkoutExercise: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var exerciseID: UUID
    var sets: [WorkoutSet]
    /// Rest timer after completing a set; 0 = off.
    var restSeconds = 90
    var notes = ""
    /// Neighbouring exercises with the same ID form a superset.
    var supersetID: UUID?
}

struct Workout: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [WorkoutExercise]
    var notes = ""
    /// The plan this workout was started from, if any.
    var planID: UUID?
    /// The Apple Health workout (e.g. from Apple Watch) this session was merged with.
    var linkedHealthID: UUID?
    /// The workout Tally itself saved to Apple Health for this session.
    var savedHealthID: UUID?

    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }
    var allSets: [WorkoutSet] { exercises.flatMap(\.sets) }
    var completedSets: [WorkoutSet] { allSets.filter(\.isDone) }
    var volume: Double { completedSets.reduce(0) { $0 + $1.volume } }
}

struct Plan: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Template exercises; set weights/reps are the targets.
    var exercises: [WorkoutExercise]
}

struct GymData: Codable, Sendable {
    var exercises: [ExerciseDef] = ExerciseLibrary.defaults
    var workouts: [Workout] = []
    var plans: [Plan] = []
    /// The workout currently in progress, kept on disk so it survives the app being closed.
    var activeWorkout: Workout?

    // Plans were called routines in earlier versions; keep the stored key.
    enum CodingKeys: String, CodingKey {
        case exercises, workouts, activeWorkout
        case plans = "routines"
    }
}

enum RecordKind: String, CaseIterable, Sendable {
    case heaviestWeight, bestOneRepMax, bestSetVolume, mostReps, longestDuration
    case leastAssistance, longestDistance, bestPace

    var label: String {
        switch self {
        case .heaviestWeight: "Heaviest Weight"
        case .bestOneRepMax: "Best 1RM"
        case .bestSetVolume: "Best Set Volume"
        case .mostReps: "Most Reps"
        case .longestDuration: "Longest Time"
        case .leastAssistance: "Least Assistance"
        case .longestDistance: "Longest Distance"
        case .bestPace: "Best Pace"
        }
    }

    /// Less assistance and a lower pace (seconds per km) are better.
    var lowerIsBetter: Bool { self == .leastAssistance || self == .bestPace }

    static func kinds(for kind: ExerciseKind) -> [RecordKind] {
        switch kind {
        case .weightReps: [.heaviestWeight, .bestOneRepMax, .bestSetVolume, .mostReps]
        case .repsOnly: [.mostReps]
        case .duration: [.longestDuration]
        case .weightedBodyweight: [.heaviestWeight, .mostReps]
        case .assistedBodyweight: [.leastAssistance, .mostReps]
        case .distanceDuration: [.longestDistance, .longestDuration, .bestPace]
        }
    }

    /// The set's value for this record, or nil when the set doesn't count for it.
    func value(of set: WorkoutSet) -> Double? {
        let value: Double? = switch self {
        case .heaviestWeight: set.weight
        case .bestOneRepMax: set.estimatedOneRepMax
        case .bestSetVolume: set.volume
        case .mostReps: set.reps.map(Double.init)
        case .longestDuration: set.seconds.map(Double.init)
        case .longestDistance: set.meters
        case .leastAssistance: (set.reps ?? 0) > 0 ? set.assistance : nil
        case .bestPace: (set.meters ?? 0) >= 1000 ? Pace.secondsPerKm(meters: set.meters, seconds: set.seconds) : nil
        }
        guard let value else { return nil }
        // No assistance at all (0 kg) is the best possible; every other record needs a positive value.
        return self == .leastAssistance ? (value >= 0 ? value : nil) : (value > 0 ? value : nil)
    }

    func isBetter(_ value: Double, than other: Double) -> Bool {
        lowerIsBetter ? value < other : value > other
    }
}
