import Foundation

/// One logged set, flattened with its workout and exercise for the spreadsheet export.
public struct ExportedSet: Sendable, Equatable {
    public var workoutStart: Date
    public var workoutEnd: Date?
    public var workoutName: String
    public var workoutNotes: String
    public var exercise: String
    public var muscleGroup: String
    public var muscles: String
    public var equipment: String
    public var exerciseNotes: String
    /// "A", "B"… when the exercise is in a superset.
    public var superset: String?
    /// Position in the exercise, counting from 1.
    public var setNumber: Int
    public var setType: String
    /// Kilograms (added weight for weighted bodyweight exercises).
    public var weight: Double?
    public var reps: Int?
    /// Kilograms of assistance for assisted exercises.
    public var assistance: Double?
    public var meters: Double?
    public var seconds: Int?
    public var volume: Double?
    public var estimatedOneRepMax: Double?
    /// Labels of the records the set broke, e.g. "Heaviest Weight".
    public var records: [String]

    public init(
        workoutStart: Date, workoutEnd: Date?, workoutName: String, workoutNotes: String = "",
        exercise: String, muscleGroup: String = "", muscles: String = "", equipment: String = "", exerciseNotes: String = "",
        superset: String? = nil, setNumber: Int, setType: String = "Normal",
        weight: Double? = nil, reps: Int? = nil, assistance: Double? = nil, meters: Double? = nil, seconds: Int? = nil,
        volume: Double? = nil, estimatedOneRepMax: Double? = nil, records: [String] = []
    ) {
        self.workoutStart = workoutStart
        self.workoutEnd = workoutEnd
        self.workoutName = workoutName
        self.workoutNotes = workoutNotes
        self.exercise = exercise
        self.muscleGroup = muscleGroup
        self.muscles = muscles
        self.equipment = equipment
        self.exerciseNotes = exerciseNotes
        self.superset = superset
        self.setNumber = setNumber
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.assistance = assistance
        self.meters = meters
        self.seconds = seconds
        self.volume = volume
        self.estimatedOneRepMax = estimatedOneRepMax
        self.records = records
    }
}

/// How far back an export reaches.
public enum ExportPeriod: String, CaseIterable, Identifiable, Sendable {
    case month, threeMonths, year, all

    public var id: String { rawValue }

    /// The dates covered, ending at `now`, or nil for all time.
    public func interval(endingAt now: Date, calendar: Calendar = .current) -> DateInterval? {
        let months = switch self {
        case .month: 1
        case .threeMonths: 3
        case .year: 12
        case .all: 0
        }
        guard months > 0, let start = calendar.date(byAdding: .month, value: -months, to: now) else { return nil }
        return DateInterval(start: calendar.startOfDay(for: start), end: now)
    }
}

/// Comma-separated values that open in Numbers, Excel and Google Sheets.
public enum CSV {
    /// Quotes a field when it holds a comma, quote or line break. Text that a spreadsheet would run
    /// as a formula (starting with =, +, -, @) gets a leading apostrophe so it stays text.
    public static func field(_ text: String) -> String {
        var text = text
        if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            text = "'" + text
        }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A number with a dot and no grouping, e.g. "82.5" or "80"; empty when nil.
    public static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    public static func number(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    /// Already-escaped fields joined into one line.
    public static func line(_ fields: [String]) -> String {
        fields.joined(separator: ",")
    }
}

public enum WorkoutCSV {
    public static let columns = [
        "Date", "Workout", "Duration (min)", "Exercise", "Muscle group", "Muscles", "Equipment", "Superset",
        "Set", "Set type", "Weight (kg)", "Reps", "Assistance (kg)", "Distance (m)", "Time (s)",
        "Volume (kg)", "Est. 1RM (kg)", "Records", "Exercise notes", "Workout notes",
    ]

    /// One row per set, oldest workout first. Starts with a byte order mark so Excel reads it as UTF-8.
    public static func document(_ sets: [ExportedSet], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let rows = sets.map { set -> String in
            // Whole minutes, as the app shows them.
            let minutes = set.workoutEnd.map { Int($0.timeIntervalSince(set.workoutStart) / 60) }
            return CSV.line([
                formatter.string(from: set.workoutStart),
                CSV.field(set.workoutName),
                CSV.number(minutes),
                CSV.field(set.exercise),
                CSV.field(set.muscleGroup),
                CSV.field(set.muscles),
                CSV.field(set.equipment),
                set.superset ?? "",
                CSV.number(set.setNumber),
                CSV.field(set.setType),
                CSV.number(set.weight),
                CSV.number(set.reps),
                CSV.number(set.assistance),
                CSV.number(set.meters),
                CSV.number(set.seconds),
                CSV.number((set.volume ?? 0) > 0 ? set.volume : nil),
                CSV.number((set.estimatedOneRepMax ?? 0) > 0 ? set.estimatedOneRepMax : nil),
                CSV.field(set.records.joined(separator: "; ")),
                CSV.field(set.exerciseNotes),
                CSV.field(set.workoutNotes),
            ])
        }
        return "\u{FEFF}" + ([CSV.line(columns.map(CSV.field))] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// Letters for the supersets in an ordered list of exercises: the first group is "A", the next "B".
    public static func supersetLabels(_ ids: [UUID?]) -> [String?] {
        var letters: [UUID: String] = [:]
        return ids.indices.map { index in
            guard Supersets.position(at: index, in: ids) != .none, let id = ids[index] else { return nil }
            if let letter = letters[id] { return letter }
            let letter = label(letters.count)
            letters[id] = letter
            return letter
        }
    }

    /// "A"…"Z", then "AA", "AB"…
    private static func label(_ index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return index < 26 ? String(alphabet[index]) : label(index / 26 - 1) + String(alphabet[index % 26])
    }
}

/// A plain-text training log, for Notes, Messages or pasting into a chat with a coach.
public enum TrainingLog {
    public struct Workout: Sendable, Equatable {
        public var title: String
        /// Lines under the title: date and time, totals.
        public var details: [String]
        public var notes: String
        /// Working sets per muscle group, most first.
        public var muscles: [MuscleSets]
        public var exercises: [Exercise]

        public init(title: String, details: [String], notes: String = "", muscles: [MuscleSets] = [], exercises: [Exercise]) {
            self.title = title
            self.details = details
            self.notes = notes
            self.muscles = muscles
            self.exercises = exercises
        }
    }

    public struct MuscleSets: Sendable, Equatable {
        public var muscle: String
        public var sets: Int

        public init(muscle: String, sets: Int) {
            self.muscle = muscle
            self.sets = sets
        }
    }

    public struct Exercise: Sendable, Equatable {
        public var name: String
        /// The exercise's muscle group, e.g. "Chest"; empty when unknown.
        public var muscle: String
        public var superset: String?
        public var notes: String
        public var sets: [SetLine]

        public init(name: String, muscle: String = "", superset: String? = nil, notes: String = "", sets: [SetLine]) {
            self.name = name
            self.muscle = muscle
            self.superset = superset
            self.notes = notes
            self.sets = sets
        }
    }

    public struct SetLine: Sendable, Equatable {
        /// "1", "2"… or "W" for a warm-up.
        public var label: String
        public var value: String
        public var isRecord: Bool

        public init(label: String, value: String, isRecord: Bool = false) {
            self.label = label
            self.value = value
            self.isRecord = isRecord
        }
    }

    /// Sets added up per muscle group, most first, leaving out groups with no sets or no name.
    public static func muscleSets(_ exercises: [(muscle: String, sets: Int)]) -> [MuscleSets] {
        var totals: [String: Int] = [:]
        for exercise in exercises where !exercise.muscle.isEmpty && exercise.sets > 0 {
            totals[exercise.muscle, default: 0] += exercise.sets
        }
        return totals
            .map { MuscleSets(muscle: $0.key, sets: $0.value) }
            .sorted { ($1.sets, $0.muscle) < ($0.sets, $1.muscle) }
    }

    /// "Chest 7 · Triceps 5 · Shoulders 4"
    public static func muscleLine(_ muscles: [MuscleSets]) -> String {
        muscles.map { "\($0.muscle) \($0.sets)" }.joined(separator: " · ")
    }

    public static func text(_ workout: Workout) -> String {
        var lines = [workout.title.uppercased()]
        lines += workout.details
        if !workout.muscles.isEmpty { lines.append("Muscles: \(muscleLine(workout.muscles))") }
        let notes = workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("Note: \(notes)") }
        let width = workout.exercises.flatMap(\.sets).map(\.label.count).max() ?? 1
        for exercise in workout.exercises {
            lines.append("")
            var heading = [exercise.name]
            if !exercise.muscle.isEmpty { heading.append(exercise.muscle) }
            if let superset = exercise.superset { heading.append("superset \(superset)") }
            lines.append(heading.joined(separator: " · "))
            for set in exercise.sets {
                let label = String(repeating: " ", count: max(width - set.label.count, 0)) + set.label
                lines.append("  \(label)  \(set.value)\(set.isRecord ? "  PR" : "")")
            }
            let notes = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { lines.append("  Note: \(notes)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Several workouts under one heading, separated by a rule.
    public static func text(_ workouts: [Workout], heading: [String]) -> String {
        let body = workouts.map(text).joined(separator: "\n\n---\n\n")
        return heading.isEmpty ? body : (heading.joined(separator: "\n") + "\n\n" + body)
    }
}
