import Foundation

enum Fmt {
    static func weight(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func volume(_ kg: Double) -> String {
        "\(Int(kg.rounded()).formatted()) kg"
    }

    static func seconds(_ total: Int) -> String {
        let minutes = total / 60, seconds = total % 60
        return minutes >= 60
            ? String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes)min"
    }

    static func rest(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : seconds < 60 ? "\(seconds)s" : seconds % 60 == 0 ? "\(seconds / 60)min" : "\(seconds / 60)min \(seconds % 60)s"
    }

    /// e.g. "60 kg × 8", "12 reps", "1:30".
    static func set(_ set: WorkoutSet, kind: ExerciseKind) -> String {
        switch kind {
        case .weightReps:
            "\(weight(set.weight ?? 0)) kg × \(set.reps ?? 0)"
        case .repsOnly:
            "\(set.reps ?? 0) reps"
        case .duration:
            seconds(set.seconds ?? 0)
        }
    }

    static func record(_ value: Double, kind: RecordKind) -> String {
        switch kind {
        case .heaviestWeight, .bestOneRepMax: "\(weight(value)) kg"
        case .bestSetVolume: volume(value)
        case .mostReps: "\(Int(value)) reps"
        case .longestDuration: seconds(Int(value))
        }
    }
}
