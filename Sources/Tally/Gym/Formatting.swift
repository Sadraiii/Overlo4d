import Foundation
import TallyCore

enum Fmt {
    static func weight(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func volume(_ kg: Double) -> String {
        "\(Int(kg.rounded()).formatted()) kg"
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
            "\(weight(set.weight ?? 0)) kg × \(set.reps ?? 0)"
        case .repsOnly:
            "\(set.reps ?? 0) reps"
        case .duration:
            seconds(set.seconds ?? 0)
        case .weightedBodyweight:
            (set.weight ?? 0) > 0 ? "+\(weight(set.weight ?? 0)) kg × \(set.reps ?? 0)" : "\(set.reps ?? 0) reps"
        case .assistedBodyweight:
            (set.assistance ?? 0) > 0 ? "−\(weight(set.assistance ?? 0)) kg × \(set.reps ?? 0)" : "\(set.reps ?? 0) reps"
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
        case .heaviestWeight: exercise == .weightedBodyweight ? "+\(weight(value)) kg" : "\(weight(value)) kg"
        case .bestOneRepMax: "\(weight(value)) kg"
        case .bestSetVolume: volume(value)
        case .mostReps: "\(Int(value)) reps"
        case .longestDuration: seconds(Int(value))
        case .leastAssistance: value > 0 ? "−\(weight(value)) kg" : "None"
        case .longestDistance: Pace.distance(value)
        case .bestPace: Pace.format(secondsPerKm: value)
        }
    }
}
