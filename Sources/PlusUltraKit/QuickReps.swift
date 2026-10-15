import Foundation

/// An exercise in the quick rep counter (Reps tab), e.g. push-ups.
public struct QuickExercise: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String

    public init(id: UUID = UUID(), name: String, symbol: String = "figure.strengthtraining.functional") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

public struct RepEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var exerciseID: UUID
    public var reps: Int
    public var date: Date

    public init(id: UUID = UUID(), exerciseID: UUID, reps: Int, date: Date = .now) {
        self.id = id
        self.exerciseID = exerciseID
        self.reps = reps
        self.date = date
    }
}

public struct RepData: Codable, Sendable {
    public var exercises: [QuickExercise]
    public var entries: [RepEntry]
    /// Total reps per day to aim for (shown as a ring).
    public var dailyGoal: Int

    public init(exercises: [QuickExercise] = RepData.defaultExercises, entries: [RepEntry] = [], dailyGoal: Int = 100) {
        self.exercises = exercises
        self.entries = entries
        self.dailyGoal = dailyGoal
    }

    enum CodingKeys: String, CodingKey { case exercises, entries, dailyGoal }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exercises = try container.decodeIfPresent([QuickExercise].self, forKey: .exercises) ?? RepData.defaultExercises
        entries = try container.decodeIfPresent([RepEntry].self, forKey: .entries) ?? []
        dailyGoal = try container.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 100
    }

    public static let defaultExercises: [QuickExercise] = [
        QuickExercise(name: "Push-ups", symbol: "figure.strengthtraining.functional"),
        QuickExercise(name: "Pull-ups", symbol: "figure.climbing"),
        QuickExercise(name: "Chin-ups", symbol: "figure.play"),
        QuickExercise(name: "Squats", symbol: "figure.cross.training"),
        QuickExercise(name: "Sit-ups", symbol: "figure.core.training"),
        QuickExercise(name: "Dips", symbol: "figure.strengthtraining.traditional"),
    ]

    /// Reps logged for an exercise on the same calendar day as `day`.
    public func reps(for exerciseID: UUID, on day: Date = .now, calendar: Calendar = .current) -> Int {
        entries
            .filter { $0.exerciseID == exerciseID && calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.reps }
    }

    /// Reps logged for an exercise across all time.
    public func totalReps(for exerciseID: UUID) -> Int {
        entries.filter { $0.exerciseID == exerciseID }.reduce(0) { $0 + $1.reps }
    }

    /// Reps logged for all exercises on the same calendar day as `day`.
    public func repsToday(on day: Date = .now, calendar: Calendar = .current) -> Int {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.reps }
    }

    public func goalProgress(on day: Date = .now) -> Double {
        dailyGoal > 0 ? Double(repsToday(on: day)) / Double(dailyGoal) : 0
    }
}

public enum RepStorage {
    public static func load() -> RepData {
        SharedStorage.load(RepData.self, from: SharedStorage.repsFile) ?? RepData()
    }

    public static func save(_ data: RepData) {
        SharedStorage.save(data, to: SharedStorage.repsFile)
    }
}
