import Foundation
import Testing
@testable import TallyCore

private let utc = TimeZone(identifier: "UTC")!

private func day(_ text: String) -> Date {
    try! Date(text + "Z", strategy: .iso8601)
}

@Suite struct CSVTests {
    @Test func plainTextIsLeftAlone() {
        #expect(CSV.field("Bench Press") == "Bench Press")
    }

    @Test func commasQuotesAndLineBreaksAreQuoted() {
        #expect(CSV.field("Squat, low bar") == "\"Squat, low bar\"")
        #expect(CSV.field("The \"big\" one") == "\"The \"\"big\"\" one\"")
        #expect(CSV.field("felt good\nback was tight") == "\"felt good\nback was tight\"")
    }

    @Test func formulasStayText() {
        #expect(CSV.field("=SUM(A1:A9)") == "'=SUM(A1:A9)")
        #expect(CSV.field("+1 rep next time") == "'+1 rep next time")
        #expect(CSV.field("-") == "'-")
        #expect(CSV.field("@coach") == "'@coach")
        #expect(CSV.field("=HYPERLINK(\"x\",\"y\")") == "\"'=HYPERLINK(\"\"x\"\",\"\"y\"\")\"")
    }

    @Test func numbersUseADotAndNoGrouping() {
        #expect(CSV.number(82.5) == "82.5")
        #expect(CSV.number(80.0) == "80")
        #expect(CSV.number(12_500.0) == "12500")
        #expect(CSV.number(2.333) == "2.33")
        #expect(CSV.number(nil as Double?) == "")
        #expect(CSV.number(.infinity) == "")
        #expect(CSV.number(8) == "8")
        #expect(CSV.number(nil as Int?) == "")
    }
}

@Suite struct WorkoutCSVTests {
    @Test func oneRowPerSetWithHeader() {
        let start = day("2026-10-20T18:02:00")
        let sets = [
            ExportedSet(
                workoutStart: start, workoutEnd: start.addingTimeInterval(68 * 60), workoutName: "Push, heavy",
                exercise: "Bench Press", muscleGroup: "Chest", muscles: "Chest, Triceps", equipment: "Barbell",
                superset: "A", setNumber: 1, setType: "Warm-up", weight: 40, reps: 10, volume: 400, estimatedOneRepMax: 53.33
            ),
            ExportedSet(
                workoutStart: start, workoutEnd: start.addingTimeInterval(68 * 60 + 59), workoutName: "Push, heavy",
                exercise: "Bench Press", setNumber: 2, weight: 82.5, reps: 5, volume: 412.5, estimatedOneRepMax: 96.25,
                records: ["Heaviest Weight", "Best 1RM"]
            ),
            ExportedSet(
                workoutStart: start, workoutEnd: nil, workoutName: "Run", exercise: "Running", setNumber: 1,
                meters: 5000, seconds: 1500, volume: 0, estimatedOneRepMax: 0
            ),
        ]
        let document = WorkoutCSV.document(sets, timeZone: utc)
        #expect(document.hasPrefix("\u{FEFF}"))
        let lines = document.dropFirst().components(separatedBy: "\r\n")
        #expect(lines.count == 5)  // header, three sets, trailing empty line
        #expect(lines[0].hasPrefix("Date,Workout,Duration (min),Exercise,"))
        #expect(lines[0].components(separatedBy: ",").count == WorkoutCSV.columns.count)
        #expect(lines[1] == "2026-10-20 18:02,\"Push, heavy\",68,Bench Press,Chest,\"Chest, Triceps\",Barbell,A,1,Warm-up,40,10,,,,400,53.33,,,")
        #expect(lines[2] == "2026-10-20 18:02,\"Push, heavy\",68,Bench Press,,,,,2,Normal,82.5,5,,,,412.5,96.25,Heaviest Weight; Best 1RM,,")
        #expect(lines[3] == "2026-10-20 18:02,Run,,Running,,,,,1,Normal,,,,5000,1500,,,,,")
        #expect(lines[4].isEmpty)
    }

    @Test func emptyExportIsJustTheHeader() {
        let document = WorkoutCSV.document([], timeZone: utc)
        #expect(document == "\u{FEFF}" + WorkoutCSV.columns.joined(separator: ",") + "\r\n")
    }

    @Test func supersetsAreLetteredInOrder() {
        let a = UUID(), b = UUID(), lone = UUID()
        #expect(WorkoutCSV.supersetLabels([nil, a, a, nil, b, b, b, lone]) == [nil, "A", "A", nil, "B", "B", "B", nil])
        #expect(WorkoutCSV.supersetLabels([]) == [])
    }

    @Test func manySupersetsGoPastZ() {
        let ids = (0..<28).flatMap { _ -> [UUID?] in let id = UUID(); return [id, id] }
        let labels = WorkoutCSV.supersetLabels(ids)
        #expect(labels[50] == "Z")
        #expect(labels[52] == "AA")
        #expect(labels[54] == "AB")
    }
}

@Suite struct ExportPeriodTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    @Test func periodsStartAtMidnightMonthsBack() throws {
        let now = day("2026-10-25T12:00:00")
        let month = try #require(ExportPeriod.month.interval(endingAt: now, calendar: calendar))
        #expect(month.start == day("2026-09-25T00:00:00"))
        #expect(month.end == now)
        #expect(ExportPeriod.threeMonths.interval(endingAt: now, calendar: calendar)?.start == day("2026-07-25T00:00:00"))
        #expect(ExportPeriod.year.interval(endingAt: now, calendar: calendar)?.start == day("2025-10-25T00:00:00"))
    }

    @Test func allTimeHasNoLimit() {
        #expect(ExportPeriod.all.interval(endingAt: .now, calendar: calendar) == nil)
    }
}

@Suite struct TrainingLogTests {
    private let push = TrainingLog.Workout(
        title: "Push Day",
        details: ["Mon 20 Oct 2026 · 18:02–19:10", "Volume 812 kg · 3 sets"],
        notes: "  Shoulder felt fine.\n",
        exercises: [
            TrainingLog.Exercise(name: "Bench Press", superset: "A", sets: [
                TrainingLog.SetLine(label: "W", value: "40 kg × 10"),
                TrainingLog.SetLine(label: "1", value: "82.5 kg × 5", isRecord: true),
            ]),
            TrainingLog.Exercise(name: "Dips", superset: "A", notes: "Slow negatives", sets: [
                TrainingLog.SetLine(label: "1", value: "12 reps"),
            ]),
        ]
    )

    @Test func workoutReadsTopToBottom() {
        #expect(TrainingLog.text(push) == """
        PUSH DAY
        Mon 20 Oct 2026 · 18:02–19:10
        Volume 812 kg · 3 sets
        Note: Shoulder felt fine.

        Bench Press · superset A
          W  40 kg × 10
          1  82.5 kg × 5  PR

        Dips · superset A
          1  12 reps
          Note: Slow negatives
        """)
    }

    @Test func musclesShowUnderTheWorkoutAndBesideEachExercise() {
        let workout = TrainingLog.Workout(
            title: "Push",
            details: ["Tue 28 Oct 2026 · 17:30–18:45 (edited)"],
            muscles: [.init(muscle: "Chest", sets: 7), .init(muscle: "Shoulders", sets: 4)],
            exercises: [
                TrainingLog.Exercise(name: "Bench Press", muscle: "Chest", superset: "A", sets: [
                    TrainingLog.SetLine(label: "1", value: "80 kg × 8"),
                ]),
            ]
        )
        #expect(TrainingLog.text(workout) == """
        PUSH
        Tue 28 Oct 2026 · 17:30–18:45 (edited)
        Muscles: Chest 7 · Shoulders 4

        Bench Press · Chest · superset A
          1  80 kg × 8
        """)
    }

    @Test func muscleSetsAddUpPerGroupMostFirst() {
        let muscles = TrainingLog.muscleSets([
            ("Chest", 4), ("Shoulders", 4), ("Chest", 3), ("Triceps", 5), ("", 2), ("Core", 0),
        ])
        #expect(muscles == [
            .init(muscle: "Chest", sets: 7), .init(muscle: "Triceps", sets: 5), .init(muscle: "Shoulders", sets: 4),
        ])
        #expect(TrainingLog.muscleLine(muscles) == "Chest 7 · Triceps 5 · Shoulders 4")
    }

    @Test func setLabelsLineUp() {
        let workout = TrainingLog.Workout(title: "Legs", details: [], exercises: [
            TrainingLog.Exercise(name: "Calf Raise", sets: (1...10).map { TrainingLog.SetLine(label: "\($0)", value: "20 reps") }),
        ])
        let lines = TrainingLog.text(workout).components(separatedBy: "\n")
        #expect(lines[3] == "   1  20 reps")
        #expect(lines[12] == "  10  20 reps")
    }

    @Test func severalWorkoutsShareAHeading() {
        let legs = TrainingLog.Workout(title: "Legs", details: ["Tue"], exercises: [])
        #expect(TrainingLog.text([push, legs], heading: ["Training log", "2 workouts"]).hasPrefix("Training log\n2 workouts\n\nPUSH DAY\n"))
        #expect(TrainingLog.text([push, legs], heading: []).hasSuffix("\n\n---\n\nLEGS\nTue"))
    }
}
