import Foundation

/// Reads workout history exported from Strong, Hevy or this app's own spreadsheet export.
public enum WorkoutImport {
    public enum Source: String, Sendable, Equatable {
        case strong, hevy, overlo4d

        public var label: String {
            switch self {
            case .strong: "Strong"
            case .hevy: "Hevy"
            case .overlo4d: "Overlo4d"
            }
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// Not a CSV from an app this reads.
        case unknownFormat
        case empty
    }

    public struct ImportedSet: Sendable, Equatable {
        /// "normal", "warmup", "drop" or "failure".
        public var type: String
        /// Kilograms.
        public var weight: Double?
        public var reps: Int?
        public var assistance: Double?
        public var meters: Double?
        public var seconds: Int?
        public var rpe: Double?
    }

    public struct ImportedExercise: Sendable, Equatable {
        public var name: String
        public var notes: String
        /// Exercises sharing a key in one workout were a superset.
        public var superset: String?
        public var sets: [ImportedSet]

        /// The kind of exercise its sets describe, as the app's `ExerciseKind` raw value.
        public var kind: String {
            let hasWeight = sets.contains { ($0.weight ?? 0) > 0 }
            let hasReps = sets.contains { ($0.reps ?? 0) > 0 }
            let hasDistance = sets.contains { ($0.meters ?? 0) > 0 }
            let hasTime = sets.contains { ($0.seconds ?? 0) > 0 }
            if sets.contains(where: { ($0.assistance ?? 0) > 0 }) { return "assistedBodyweight" }
            if hasWeight { return "weightReps" }
            if hasDistance { return "distanceDuration" }
            if hasReps { return "repsOnly" }
            if hasTime { return "duration" }
            return "weightReps"
        }
    }

    public struct ImportedWorkout: Sendable, Equatable {
        public var name: String
        public var start: Date
        public var end: Date?
        public var notes: String
        public var exercises: [ImportedExercise]

        public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    }

    public struct Result: Sendable, Equatable {
        public var source: Source
        /// Oldest first.
        public var workouts: [ImportedWorkout]
        /// Rows that couldn't be read (no date or no exercise) or held nothing (rest timers).
        public var skippedRows: Int
    }

    /// - Parameters:
    ///   - weightUnit: the unit of weights when the file doesn't say (older Strong exports).
    ///   - timeZone: the time zone the file's dates were written in.
    public static func parse(_ text: String, weightUnit: WeightUnit = .kg, timeZone: TimeZone = .current) throws -> Result {
        let rows = CSVReader.rows(text)
        guard let header = rows.first, rows.count > 1 else { throw Failure.empty }
        let columns = Columns(header)
        let body = Array(rows.dropFirst())
        if columns.has("exercisetitle") {
            return build(.hevy, body.map { hevy($0, columns, weightUnit: weightUnit, timeZone: timeZone) })
        }
        if columns.has("exercisename"), columns.has("setorder") {
            return build(.strong, body.map { strong($0, columns, weightUnit: weightUnit, timeZone: timeZone) })
        }
        if columns.has("exercise"), columns.has("settype"), columns.has("workout") {
            return build(.overlo4d, body.map { own($0, columns, timeZone: timeZone) })
        }
        throw Failure.unknownFormat
    }

    /// Whether the file names its weight unit, so the picker for it can be hidden.
    public static func statesWeightUnit(_ text: String) -> Bool {
        guard let header = CSVReader.rows(String(text.prefix(4000))).first else { return false }
        let columns = Columns(header)
        if columns.has("exercise"), columns.has("settype"), columns.has("workout") { return true }
        return columns.names.contains { $0.hasPrefix("weight") && ($0.contains("kg") || $0.contains("lb")) } || columns.has("weightunit")
    }

    // MARK: Rows

    /// One set with what it belongs to.
    struct Row {
        var workout: String
        var start: Date
        var end: Date?
        var workoutNotes: String
        var exercise: String
        var exerciseNotes: String
        var superset: String?
        var set: ImportedSet
    }

    /// Header names reduced to lowercase letters and digits, so "Exercise Name" and "exercise_name" match.
    struct Columns {
        let names: [String]

        init(_ header: [String]) {
            names = header.map { Self.key($0) }
        }

        static func key(_ text: String) -> String {
            String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }

        func has(_ name: String) -> Bool { names.contains(name) }

        /// The first column called `name`, or failing that starting with it.
        func index(_ name: String) -> Int? {
            names.firstIndex(of: name) ?? names.firstIndex { $0.hasPrefix(name) }
        }

        func value(_ name: String, in row: [String]) -> String {
            guard let index = index(name), index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The full header key of the column `value(_:in:)` reads.
        func header(_ name: String) -> String {
            index(name).map { names[$0] } ?? ""
        }
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    static func positive(_ text: String) -> Double? {
        number(text).flatMap { $0 > 0 ? $0 : nil }
    }

    static func date(_ text: String, formats: [String], timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// "1h 5m", "45m", "50s", "1:05:00" or a number of seconds.
    static func duration(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let seconds = Double(trimmed) { return seconds > 0 ? seconds : nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        var total = 0.0
        var digits = ""
        for character in trimmed {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if let value = Double(digits) {
                switch character {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: continue
                }
                digits = ""
            }
        }
        return total > 0 ? total : nil
    }

    static func strong(_ row: [String], _ columns: Columns, weightUnit: WeightUnit, timeZone: TimeZone) -> Row? {
        let exercise = columns.value("exercisename", in: row)
        guard !exercise.isEmpty,
              let start = date(columns.value("date", in: row), formats: ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"], timeZone: timeZone)
        else { return nil }

        let order = columns.value("setorder", in: row).lowercased()
        // Strong writes rest timers and notes as rows of their own.
        guard !order.contains("rest"), !order.contains("note") else { return nil }
        let type = switch order.first {
        case "w": "warmup"
        case "d": "drop"
        case "f": "failure"
        default: "normal"
        }

        var unit = weightUnit
        let weightHeader = columns.header("weight")
        let stated = columns.value("weightunit", in: row).lowercased()
        if weightHeader.contains("kg") || stated.hasPrefix("kg") { unit = .kg }
        if weightHeader.contains("lb") || stated.hasPrefix("lb") { unit = .lb }

        var meters: Double?
        if let distance = positive(columns.value("distance", in: row)) {
            let header = columns.header("distance")
            let statedUnit = columns.value("distanceunit", in: row).lowercased()
            if header.contains("meter") || statedUnit == "m" || statedUnit.hasPrefix("meter") {
                meters = distance
            } else if statedUnit.hasPrefix("mi") {
                meters = distance * 1609.344
            } else if statedUnit.hasPrefix("km") {
                meters = distance * 1000
            } else {
                // No unit given: small numbers are kilometres, large ones metres.
                meters = distance <= 200 ? distance * 1000 : distance
            }
        }

        let set = ImportedSet(
            type: type,
            weight: positive(columns.value("weight", in: row)).map(unit.toKg),
            reps: positive(columns.value("reps", in: row)).map { Int($0.rounded()) },
            assistance: nil,
            meters: meters,
            seconds: positive(columns.value("seconds", in: row)).map { Int($0.rounded()) },
            rpe: positive(columns.value("rpe", in: row))
        )
        guard set.weight != nil || set.reps != nil || set.meters != nil || set.seconds != nil else { return nil }
        let length = duration(columns.value("duration", in: row))
        return Row(
            workout: columns.value("workoutname", in: row),
            start: start,
            end: length.map { start.addingTimeInterval($0) },
            workoutNotes: columns.value("workoutnotes", in: row),
            exercise: exercise,
            exerciseNotes: columns.value("notes", in: row),
            superset: nil,
            set: set
        )
    }

    static func hevy(_ row: [String], _ columns: Columns, weightUnit: WeightUnit, timeZone: TimeZone) -> Row? {
        let formats = ["d MMM yyyy, HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "d MMM yyyy HH:mm"]
        let exercise = columns.value("exercisetitle", in: row)
        guard !exercise.isEmpty, let start = date(columns.value("starttime", in: row), formats: formats, timeZone: timeZone) else { return nil }

        let rawType = columns.value("settype", in: row).lowercased()
        let type = rawType.hasPrefix("warm") ? "warmup" : rawType.hasPrefix("drop") ? "drop" : rawType.hasPrefix("fail") ? "failure" : "normal"

        var weight = positive(columns.value("weightkg", in: row))
        if weight == nil, let pounds = positive(columns.value("weightlbs", in: row)) { weight = WeightUnit.lb.toKg(pounds) }
        var meters = positive(columns.value("distancekm", in: row)).map { $0 * 1000 }
        if meters == nil, let miles = positive(columns.value("distancemiles", in: row)) { meters = miles * 1609.344 }

        let set = ImportedSet(
            type: type,
            weight: weight,
            reps: positive(columns.value("reps", in: row)).map { Int($0.rounded()) },
            assistance: nil,
            meters: meters,
            seconds: positive(columns.value("durationseconds", in: row)).map { Int($0.rounded()) },
            rpe: positive(columns.value("rpe", in: row))
        )
        guard set.weight != nil || set.reps != nil || set.meters != nil || set.seconds != nil else { return nil }
        let superset = columns.value("supersetid", in: row)
        return Row(
            workout: columns.value("title", in: row),
            start: start,
            end: date(columns.value("endtime", in: row), formats: formats, timeZone: timeZone),
            workoutNotes: columns.value("description", in: row),
            exercise: exercise,
            exerciseNotes: columns.value("exercisenotes", in: row),
            superset: superset.isEmpty ? nil : superset,
            set: set
        )
    }

    static func own(_ row: [String], _ columns: Columns, timeZone: TimeZone) -> Row? {
        let exercise = text(columns.value("exercise", in: row))
        guard !exercise.isEmpty, let start = date(columns.value("date", in: row), formats: ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"], timeZone: timeZone) else { return nil }
        let rawType = columns.value("settype", in: row).lowercased()
        let type = rawType.hasPrefix("warm") ? "warmup" : rawType.hasPrefix("drop") ? "drop" : rawType.hasPrefix("fail") ? "failure" : "normal"
        let set = ImportedSet(
            type: type,
            weight: positive(columns.value("weightkg", in: row)),
            reps: positive(columns.value("reps", in: row)).map { Int($0.rounded()) },
            assistance: positive(columns.value("assistancekg", in: row)),
            meters: positive(columns.value("distancem", in: row)),
            seconds: positive(columns.value("times", in: row)).map { Int($0.rounded()) },
            rpe: nil
        )
        guard set.weight != nil || set.reps != nil || set.meters != nil || set.seconds != nil || set.assistance != nil else { return nil }
        let minutes = positive(columns.value("durationmin", in: row))
        let superset = columns.value("superset", in: row)
        return Row(
            workout: text(columns.value("workout", in: row)),
            start: start,
            end: minutes.map { start.addingTimeInterval($0 * 60) },
            workoutNotes: text(columns.value("workoutnotes", in: row)),
            exercise: exercise,
            exerciseNotes: text(columns.value("exercisenotes", in: row)),
            superset: superset.isEmpty ? nil : superset,
            set: set
        )
    }

    /// Undoes the apostrophe the export puts in front of text a spreadsheet would run as a formula.
    static func text(_ field: String) -> String {
        guard field.hasPrefix("'"), let second = field.dropFirst().first, "=+-@".contains(second) else { return field }
        return String(field.dropFirst())
    }

    /// Groups rows into workouts (same name and start) and exercises (neighbouring rows with the same name).
    static func build(_ source: Source, _ rows: [Row?]) -> Result {
        struct Key: Hashable {
            let name: String
            let start: Date
        }
        var order: [Key] = []
        var workouts: [Key: ImportedWorkout] = [:]
        var skipped = 0
        for row in rows {
            guard let row else { skipped += 1; continue }
            let key = Key(name: row.workout, start: row.start)
            var workout = workouts[key] ?? ImportedWorkout(
                name: row.workout.isEmpty ? "Workout" : row.workout, start: row.start, end: row.end, notes: row.workoutNotes, exercises: []
            )
            if workouts[key] == nil { order.append(key) }
            if let last = workout.exercises.indices.last, workout.exercises[last].name == row.exercise, workout.exercises[last].superset == row.superset {
                workout.exercises[last].sets.append(row.set)
                if workout.exercises[last].notes.isEmpty { workout.exercises[last].notes = row.exerciseNotes }
            } else {
                workout.exercises.append(ImportedExercise(name: row.exercise, notes: row.exerciseNotes, superset: row.superset, sets: [row.set]))
            }
            workouts[key] = workout
        }
        let sorted = order.compactMap { workouts[$0] }.sorted { $0.start < $1.start }
        return Result(source: source, workouts: sorted, skippedRows: skipped)
    }

    // MARK: Fitting into the app

    /// A name reduced for matching: lowercase, letters and digits only, plural "s" dropped from words.
    /// "Bench Press (Barbell)" and "bench press - barbell" give the same key.
    public static func nameKey(_ name: String) -> String {
        let words = name.lowercased()
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(words).split(separator: " ").map { word in
            word.count > 2 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : String(word)
        }
        .joined(separator: " ")
    }

    /// The library exercise an imported name means: the same words in any order
    /// ("Barbell Bench Press" matches "Bench Press (Barbell)"). Returns its index in `library`.
    public static func match(_ name: String, in library: [String]) -> Int? {
        let key = nameKey(name)
        guard !key.isEmpty else { return nil }
        let keys = library.map(nameKey)
        if let exact = keys.firstIndex(of: key) { return exact }
        let words = Set(key.split(separator: " "))
        return keys.firstIndex { Set($0.split(separator: " ")) == words }
    }

    /// Whether a workout starting at `start` is already in the log (within a minute).
    public static func isDuplicate(_ start: Date, of existing: [Date]) -> Bool {
        existing.contains { abs($0.timeIntervalSince(start)) < 60 }
    }
}

/// Splits CSV text into rows of fields. Handles quoted fields with commas, quotes and line breaks,
/// a byte order mark, and semicolons as the separator.
public enum CSVReader {
    public static func rows(_ text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let separator = separator(in: scalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var index = 0
        func endRow() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }
        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\"" && field.isEmpty {
                quoted = true
            } else if scalar == separator {
                row.append(String(field))
                field = String.UnicodeScalarView()
            } else if scalar == "\r" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                endRow()
            } else if scalar == "\n" {
                endRow()
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// Semicolons when the first line has more of them than commas outside quotes.
    static func separator(in scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        var commas = 0, semicolons = 0, quoted = false
        for scalar in scalars {
            if scalar == "\"" { quoted.toggle() }
            if quoted { continue }
            if scalar == "\n" || scalar == "\r" { break }
            if scalar == "," { commas += 1 }
            if scalar == ";" { semicolons += 1 }
        }
        return semicolons > commas ? ";" : ","
    }
}
