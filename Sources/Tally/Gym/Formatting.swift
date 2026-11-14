import Foundation
import TallyCore
import TallyKit

/// The weight unit chosen in Settings › Units. Weights are stored in kilograms and converted for
/// display and typing.
enum Units {
    static let key = SharedUnit.storageKey

    static var weight: WeightUnit {
        WeightUnit(rawValue: SharedStorage.defaults.string(forKey: key) ?? "") ?? .kg
    }

    /// The smallest usual jump (2.5 kg or 5 lb), in kilograms.
    static var loadStepKg: Double { weight.toKg(weight.loadStep) }
}

enum Fmt {
    /// A plain number with up to two decimals. For a weight in kilograms use `load` or `mass`.
    static func weight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "kg" or "lb".
    static var unit: String { Units.weight.label }

    /// Kilograms as a number in the chosen unit: "82.5" or "181.88".
    static func load(_ kg: Double) -> String {
        weight(Units.weight.fromKg(kg))
    }

    /// Kilograms with the chosen unit: "82.5 kg" or "181.88 lb".
    static func mass(_ kg: Double) -> String {
        "\(load(kg)) \(unit)"
    }

    static func volume(_ kg: Double) -> String {
        "\(Int(Units.weight.fromKg(kg).rounded()).formatted()) \(unit)"
    }

    static func seconds(_ total: Int) -> String {
        TimeEntry.format(total)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes)min"
    }

    static func rest(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : seconds < 60 ? "\(seconds)s" : seconds % 60 == 0 ? "\(seconds / 60)min" : "\(seconds / 60)min \(seconds % 60)s"
    }

    /// e.g. "60 kg × 8", "+10 kg × 8", "−20 kg × 8", "12 reps", "1:30", "5 km · 25:00 · 5:00 /km".
    static func set(_ set: WorkoutSet, kind: ExerciseKind) -> String {
        switch kind {
        case .weightReps:
            "\(mass(set.weight ?? 0)) × \(set.reps ?? 0)"
        case .repsOnly:
            "\(set.reps ?? 0) reps"
        case .duration:
            seconds(set.seconds ?? 0)
        case .weightedBodyweight:
            (set.weight ?? 0) > 0 ? "+\(mass(set.weight ?? 0)) × \(set.reps ?? 0)" : "\(set.reps ?? 0) reps"
        case .assistedBodyweight:
            (set.assistance ?? 0) > 0 ? "−\(mass(set.assistance ?? 0)) × \(set.reps ?? 0)" : "\(set.reps ?? 0) reps"
        case .distanceDuration:
            distanceSet(set)
        }
    }

    private static func distanceSet(_ set: WorkoutSet) -> String {
        let parts = [
            set.meters.map { Pace.distance($0) },
            set.seconds.map { seconds($0) },
            Pace.secondsPerKm(meters: set.meters, seconds: set.seconds).map { Pace.format(secondsPerKm: $0) },
        ].compactMap { $0 }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    static func record(_ value: Double, kind: RecordKind, exercise: ExerciseKind = .weightReps) -> String {
        switch kind {
        case .heaviestWeight: exercise == .weightedBodyweight ? "+\(mass(value))" : mass(value)
        case .bestOneRepMax: mass(value)
        case .bestSetVolume: volume(value)
        case .mostReps: "\(Int(value)) reps"
        case .longestDuration: seconds(Int(value))
        case .leastAssistance: value > 0 ? "−\(mass(value))" : "None"
        case .longestDistance: Pace.distance(value)
        case .bestPace: Pace.format(secondsPerKm: value)
        }
    }
}
