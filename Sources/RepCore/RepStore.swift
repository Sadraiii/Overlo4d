import Foundation

public struct Exercise: Codable, Identifiable, Hashable, Sendable {
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
    public var exercises: [Exercise]
    public var entries: [RepEntry]

    public init(exercises: [Exercise] = RepData.defaultExercises, entries: [RepEntry] = []) {
        self.exercises = exercises
        self.entries = entries
    }

    public static let defaultExercises: [Exercise] = [
        Exercise(name: "Push-ups", symbol: "figure.strengthtraining.functional"),
        Exercise(name: "Pull-ups", symbol: "figure.climbing"),
        Exercise(name: "Chin-ups", symbol: "figure.play"),
        Exercise(name: "Squats", symbol: "figure.cross.training"),
        Exercise(name: "Sit-ups", symbol: "figure.core.training"),
        Exercise(name: "Dips", symbol: "figure.strengthtraining.traditional"),
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
}

/// Reads and writes `RepData` to a JSON file shared between the app and the widget.
public enum RepStorage {
    public static let widgetKind = "RepCounterWidget"

    /// xtool rewrites App Group IDs at signing time (e.g. `group.XTL-ABCD1234.com.mahmud.RepCounter`),
    /// so the real ID is read from the bundle's provisioning profile rather than hardcoded.
    public static let appGroupID: String? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        return groups.first
    }()

    static var fileURL: URL {
        let directory: URL
        if let appGroupID,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = container
        } else {
            directory = URL.applicationSupportDirectory
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "reps.json")
    }

    public static func load() -> RepData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(RepData.self, from: data)
        else { return RepData() }
        return decoded
    }

    public static func save(_ repData: RepData) {
        guard let data = try? JSONEncoder().encode(repData) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
