import CoreTransferable
import Foundation
import TallyCore
import UniformTypeIdentifiers

/// Workouts turned into a spreadsheet, a text log or a full backup.
@MainActor
enum WorkoutExport {
    /// Every set of the workouts, oldest first, for `WorkoutCSV`.
    static func sets(_ workouts: [Workout], gym: GymStore) -> [ExportedSet] {
        workouts.sorted { $0.startedAt < $1.startedAt }.flatMap { workout in
            let supersets = WorkoutCSV.supersetLabels(workout.exercises.supersetIDs)
            return workout.exercises.enumerated().flatMap { index, exercise in
                let def = gym.exercise(exercise.exerciseID)
                let kind = def?.kind ?? .weightReps
                return exercise.sets.enumerated().map { number, set in
                    ExportedSet(
                        workoutStart: workout.startedAt,
                        workoutEnd: workout.endedAt,
                        workoutName: workout.name,
                        workoutNotes: workout.notes,
                        exercise: gym.name(of: exercise.exerciseID),
                        muscleGroup: def?.muscle.label ?? "",
                        muscles: def.map { $0.primary.map(\.label).joined(separator: ", ") } ?? "",
                        equipment: def?.equipment?.label ?? "",
                        exerciseNotes: exercise.notes,
                        superset: supersets[index],
                        setNumber: number + 1,
                        setType: set.type.label,
                        weight: set.weight,
                        reps: set.reps,
                        assistance: set.assistance,
                        meters: set.meters,
                        seconds: set.seconds,
                        volume: set.volume,
                        // Added weight on a pull-up isn't a one-rep max.
                        estimatedOneRepMax: kind == .weightReps ? set.estimatedOneRepMax : nil,
                        records: (gym.records[set.id] ?? []).map(\.label)
                    )
                }
            }
        }
    }

    static func csv(_ workouts: [Workout], gym: GymStore) -> Data {
        Data(WorkoutCSV.document(sets(workouts, gym: gym)).utf8)
    }

    /// Working sets per muscle group across the workouts, most first.
    static func muscles(_ workouts: [Workout], gym: GymStore) -> [TrainingLog.MuscleSets] {
        TrainingLog.muscleSets(workouts.flatMap { workout in
            workout.exercises.map { exercise in
                (muscle: gym.exercise(exercise.exerciseID)?.muscle.label ?? "",
                 sets: exercise.sets.filter { $0.isDone && $0.type != .warmup }.count)
            }
        })
    }

    /// One workout set by set, as on the History screen.
    static func log(_ workout: Workout, gym: GymStore) -> TrainingLog.Workout {
        let supersets = WorkoutCSV.supersetLabels(workout.exercises.supersetIDs)
        let end = workout.endedAt ?? workout.startedAt
        let sets = workout.completedSets.count
        var totals = [Fmt.duration(workout.duration), sets == 1 ? "1 set" : "\(sets) sets"]
        if workout.volume > 0 { totals.insert(Fmt.volume(workout.volume), at: 0) }
        let records = gym.recordCount(in: workout)
        if records > 0 { totals.append(records == 1 ? "1 record" : "\(records) records") }

        return TrainingLog.Workout(
            title: workout.name,
            details: [
                "\(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())) · "
                    + "\(workout.startedAt.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
                    + (workout.timesEdited == true ? " (edited)" : ""),
                totals.joined(separator: " · "),
            ],
            notes: workout.notes,
            muscles: muscles([workout], gym: gym),
            exercises: workout.exercises.enumerated().map { index, exercise in
                let def = gym.exercise(exercise.exerciseID)
                let kind = def?.kind ?? .weightReps
                return TrainingLog.Exercise(
                    name: gym.name(of: exercise.exerciseID),
                    muscle: def?.muscle.label ?? "",
                    superset: supersets[index],
                    notes: exercise.notes,
                    sets: exercise.sets.enumerated().map { number, set in
                        let label = set.type == .normal
                            ? "\(exercise.sets.prefix(number + 1).filter { $0.type != .warmup }.count)"
                            : set.type.badge
                        return TrainingLog.SetLine(label: label, value: Fmt.set(set, kind: kind), isRecord: gym.records[set.id] != nil)
                    }
                )
            }
        )
    }

    static func text(_ workout: Workout, gym: GymStore) -> String {
        TrainingLog.text(log(workout, gym: gym))
    }

    /// Several workouts, oldest first, under a heading with the period and totals.
    static func text(_ workouts: [Workout], title: String, gym: GymStore) -> String {
        let ordered = workouts.sorted { $0.startedAt < $1.startedAt }
        let sets = ordered.reduce(0) { $0 + $1.completedSets.count }
        var summary = [ordered.count == 1 ? "1 workout" : "\(ordered.count) workouts", sets == 1 ? "1 set" : "\(sets) sets"]
        let volume = ordered.reduce(0) { $0 + $1.volume }
        if volume > 0 { summary.append(Fmt.volume(volume)) }
        return TrainingLog.text(ordered.map { log($0, gym: gym) }, heading: [title, summary.joined(separator: " · ")])
    }

    /// Everything the app stores except the workout in progress, readable by any JSON tool.
    static func backup(gym: GymStore) -> Data {
        let backup = GymBackup(
            version: AppVersion.number,
            exportedAt: .now,
            data: GymData(exercises: gym.exercises, workouts: gym.workouts, plans: gym.plans)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(backup)) ?? Data()
    }
}

/// The backup file: the app's own data with when and by which version it was written.
struct GymBackup: Codable {
    var format = 1
    var version: String
    var exportedAt: Date
    var data: GymData
}

/// A spreadsheet or backup file for the share sheet.
struct ExportFile: Transferable {
    enum Kind { case csv, json }

    let data: Data
    let name: String
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
            .suggestedFileName { $0.name }
            .exportingCondition { $0.kind == .csv }
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.name }
            .exportingCondition { $0.kind == .json }
    }
}
