import Foundation
import Testing
@testable import TallyCore

@Suite struct WeeklyReportTests {
    func totals(workouts: Int, volume: Double = 0, records: Int = 0, sets: Int = 0) -> WeekTotals {
        var totals = WeekTotals()
        totals.workouts = workouts
        totals.volume = volume
        totals.records = records
        totals.sets = sets
        return totals
    }

    @Test func strongWeek() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 4, volume: 22_000, records: 3),
            previous: totals(workouts: 4, volume: 20_000),
            weeklyGoal: 4,
            mostImproved: (name: "Squat (Barbell)", percent: 2.4),
            cardioSessions: 1, cardioMinutes: 30,
            streakWeeks: 6
        ))
        #expect(report.headline == "Strong week")
        #expect(report.score == 100)
        #expect(report.wins.contains("Weekly goal reached: 4 of 4 workouts."))
        #expect(report.wins.contains("3 personal records."))
        #expect(report.wins.contains("Volume up 10% to 22 t."))
        #expect(report.wins.contains("Squat (Barbell) is up 2% on its estimated max."))
        #expect(report.wins.contains("6 weeks in a row with training."))
        #expect(report.watch.isEmpty)
        #expect(report.next == ["Keep the plan as it is. Add a little weight where every set reached its reps."])
    }

    @Test func missedGoalAndTooMuchChest() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 2, volume: 9000),
            previous: totals(workouts: 4, volume: 20_000),
            weeklyGoal: 4,
            flags: [.tooMuch(muscle: "chest", sets: 24), .neglected(muscle: "hamstrings", days: 25)],
            muscleNames: ["chest": "Chest", "hamstrings": "Hamstrings"]
        ))
        #expect(report.headline == "Mixed week")
        // 25 for half the goal, nothing for progress, 25 − 8 − 2 for balance.
        #expect(report.score == 40)
        #expect(report.watch.first == "2 of 4 planned workouts: 2 short.")
        #expect(report.watch.contains("Volume fell 55% against the week before."))
        #expect(report.watch.contains("Chest got 24 hard sets. Past about 20 a week, recovery suffers."))
        #expect(report.watch.contains("No direct hamstrings work in 25 days."))
        #expect(report.next == [
            "Book 4 sessions in your calendar before the week starts.",
            "Cut chest back to 14–18 sets.",
            "Add 6 or more sets for hamstrings.",
        ])
    }

    @Test func noGoalUsesLastWeekAsTheYardstick() {
        let report = WeeklyReport.build(.init(totals: totals(workouts: 3, volume: 100), previous: totals(workouts: 2, volume: 100)))
        #expect(report.wins.first == "3 workouts, 1 more than the week before.")
        #expect(report.score == 85)
    }

    @Test func emptyWeek() {
        let report = WeeklyReport.build(.init(totals: totals(workouts: 0), previous: totals(workouts: 3), weeklyGoal: 3, cardioSessions: 2, cardioMinutes: 50))
        #expect(report.headline == "No lifting logged")
        #expect(report.score == 20)
        #expect(report.wins == ["2 cardio sessions kept you moving."])
        #expect(report.next.first == "Plan 3 sessions and put the first one in your calendar.")
    }

    @Test func deloadDueLeadsTheToDoList() {
        let advice = Deload.Advice(level: .due, hardWeeks: 9, reasons: ["9 hard weeks in a row without an easier one."], slipping: [])
        let report = WeeklyReport.build(.init(totals: totals(workouts: 4, volume: 100), previous: totals(workouts: 4, volume: 100), weeklyGoal: 4, deload: advice))
        #expect(report.next.first == "Take a deload week: same exercises, about 10% lighter and fewer sets.")
        #expect(report.watch.contains { $0.hasPrefix("A deload week is due") })
    }

    @Test func deloadWeekIsNotMarkedDownForLowVolume() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 3, volume: 8000), previous: totals(workouts: 3, volume: 20_000), weeklyGoal: 3, wasDeload: true
        ))
        #expect(report.watch.isEmpty)
        #expect(report.wins.contains("Deload week done. Expect to feel fresher next week."))
        #expect(report.score == 85)
    }

    @Test func shortSleepIsFlagged() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 3, volume: 100), previous: totals(workouts: 3, volume: 100), weeklyGoal: 3, sleepHours: 6.2, sleepGoalHours: 8
        ))
        #expect(report.watch == ["Sleep averaged 6.2 h against a goal of 8 h. Strength is built while you sleep."])
        #expect(report.next.contains("Go to bed 30 minutes earlier on training days."))
    }

    @Test func poundsInTheVolumeLine() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 3, volume: 11_000), previous: totals(workouts: 3, volume: 10_000), unit: .lb
        ))
        #expect(report.wins.contains("Volume up 10% to 24251 lb."))
    }

    @Test func neverMoreThanThreeActions() {
        let report = WeeklyReport.build(.init(
            totals: totals(workouts: 1), previous: totals(workouts: 4, volume: 100), weeklyGoal: 4,
            flags: [.tooMuch(muscle: "chest", sets: 30), .shortRecovery(muscle: "quads", hours: 20), .imbalance(pair: "Push and pull", more: "Push", less: "Pull", ratio: 3), .neglected(muscle: "glutes", days: nil)]
        ))
        #expect(report.next.count == 3)
        #expect(report.watch.count == 6)
    }
}

@Suite struct CSVReaderTests {
    @Test func quotedFields() {
        let rows = CSVReader.rows("a,b,c\r\n\"1,5\",\"say \"\"hi\"\"\",\"two\nlines\"\r\n")
        #expect(rows == [["a", "b", "c"], ["1,5", "say \"hi\"", "two\nlines"]])
    }

    @Test func semicolonsAndByteOrderMark() {
        let rows = CSVReader.rows("\u{FEFF}Date;Workout Name;Weight\n2024-01-01;Legs;82,5\n\n")
        #expect(rows == [["Date", "Workout Name", "Weight"], ["2024-01-01", "Legs", "82,5"]])
    }

    @Test func emptyFieldsAndNoFinalNewline() {
        #expect(CSVReader.rows("a,,c\n,,") == [["a", "", "c"], ["", "", ""]])
    }
}

@Suite struct WorkoutImportTests {
    let utc = TimeZone(identifier: "UTC")!

    static let strong = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2023-11-15 18:00:00,"Push Day",1h 5m,"Bench Press (Barbell)",1,60,5,0,0,"Paused",Felt good,
    2023-11-15 18:00:00,"Push Day",1h 5m,"Bench Press (Barbell)",2,100,5,0,0,,Felt good,8.5
    2023-11-15 18:00:00,"Push Day",1h 5m,"Bench Press (Barbell)",Rest Timer,0,0,0,120,,Felt good,
    2023-11-15 18:00:00,"Push Day",1h 5m,"Plank",1,0,0,0,60,,Felt good,
    2023-11-13 07:30:00,"Morning Run",30m,"Running",1,0,0,5,1500,,,
    """

    @Test func readsStrong() throws {
        let result = try WorkoutImport.parse(Self.strong, timeZone: utc)
        #expect(result.source == .strong)
        #expect(result.skippedRows == 1)
        #expect(result.workouts.map(\.name) == ["Morning Run", "Push Day"])
        let push = result.workouts[1]
        #expect(push.start == Date(timeIntervalSince1970: 1_700_071_200))
        #expect(push.end == push.start.addingTimeInterval(3900))
        #expect(push.notes == "Felt good")
        #expect(push.exercises.map(\.name) == ["Bench Press (Barbell)", "Plank"])
        #expect(push.exercises[0].notes == "Paused")
        #expect(push.exercises[0].sets.map(\.weight) == [60, 100])
        #expect(push.exercises[0].sets[1].rpe == 8.5)
        #expect(push.exercises[0].kind == "weightReps")
        #expect(push.exercises[1].sets == [.init(type: "normal", weight: nil, reps: nil, assistance: nil, meters: nil, seconds: 60, rpe: nil)])
        #expect(push.exercises[1].kind == "duration")
        let run = result.workouts[0].exercises[0]
        #expect(run.sets[0].meters == 5000)
        #expect(run.sets[0].seconds == 1500)
        #expect(run.kind == "distanceDuration")
        #expect(push.setCount == 3)
    }

    @Test func strongInPounds() throws {
        let result = try WorkoutImport.parse(Self.strong, weightUnit: .lb, timeZone: utc)
        let weight = try #require(result.workouts[1].exercises[0].sets[1].weight)
        #expect(abs(weight - 45.359237) < 0.0001)
        #expect(!WorkoutImport.statesWeightUnit(Self.strong))
    }

    @Test func newerStrongStatesItsUnits() throws {
        let csv = """
        Workout #;Date;Workout Name;Duration (sec);Exercise Name;Set Order;Weight (kg);Reps;RPE;Distance (meters);Seconds;Notes;Workout Notes
        1;2023-11-15 18:00:00;Legs;3000;Squat (Barbell);W;60;5;;;;;
        1;2023-11-15 18:00:00;Legs;3000;Squat (Barbell);1;120,5;5;9;;;;
        1;2023-11-15 18:00:00;Legs;3000;Rowing Machine;1;;;;2000;480;;
        """
        #expect(WorkoutImport.statesWeightUnit(csv))
        let result = try WorkoutImport.parse(csv, weightUnit: .lb, timeZone: utc)
        let legs = try #require(result.workouts.first)
        #expect(legs.end == legs.start.addingTimeInterval(3000))
        #expect(legs.exercises[0].sets.map(\.type) == ["warmup", "normal"])
        #expect(legs.exercises[0].sets[1].weight == 120.5)
        #expect(legs.exercises[0].sets[1].rpe == 9)
        #expect(legs.exercises[1].sets[0].meters == 2000)
    }

    @Test func readsHevy() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Pull Up",,"Strict",0,"normal",,8,,,
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Pull Up",,"Strict",1,"failure",,6,,,10
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Bent Over Row (Barbell)",0,"",0,"warmup",40,10,,,
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Bent Over Row (Barbell)",0,"",1,"dropset",70,8,,,
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Face Pull",0,"",0,"normal",25,15,,,
        "Pull","14 Mar 2024, 18:05","14 Mar 2024, 19:10","Quick one","Treadmill",,"",0,"normal",,,2.5,900,
        """
        let result = try WorkoutImport.parse(csv, timeZone: utc)
        #expect(result.source == .hevy)
        let pull = try #require(result.workouts.first)
        #expect(result.workouts.count == 1)
        #expect(pull.end?.timeIntervalSince(pull.start) == 3900)
        #expect(pull.notes == "Quick one")
        #expect(pull.exercises.map(\.name) == ["Pull Up", "Bent Over Row (Barbell)", "Face Pull", "Treadmill"])
        #expect(pull.exercises[0].kind == "repsOnly")
        #expect(pull.exercises[0].notes == "Strict")
        #expect(pull.exercises[0].sets.map(\.type) == ["normal", "failure"])
        #expect(pull.exercises[1].sets.map(\.type) == ["warmup", "drop"])
        #expect(pull.exercises[1].superset == "0")
        #expect(pull.exercises[2].superset == "0")
        #expect(pull.exercises[3].superset == nil)
        #expect(pull.exercises[3].sets[0].meters == 2500)
        #expect(WorkoutImport.statesWeightUnit(csv))
    }

    @Test func hevyInPounds() throws {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_miles,duration_seconds,rpe
        Legs,"1 Jan 2024, 09:00","1 Jan 2024, 10:00",,Squat (Barbell),,,0,normal,225,5,,,
        Legs,"1 Jan 2024, 09:00","1 Jan 2024, 10:00",,Running,,,0,normal,,,1,600,
        """
        let result = try WorkoutImport.parse(csv, timeZone: utc)
        let legs = try #require(result.workouts.first)
        #expect(abs((legs.exercises[0].sets[0].weight ?? 0) - 102.058) < 0.001)
        #expect(abs((legs.exercises[1].sets[0].meters ?? 0) - 1609.344) < 0.001)
    }

    @Test func readsItsOwnExport() throws {
        let start = Date(timeIntervalSince1970: 1_700_071_200)
        let sets = [
            ExportedSet(workoutStart: start, workoutEnd: start.addingTimeInterval(3600), workoutName: "Upper, heavy", workoutNotes: "-5 kg today",
                        exercise: "Bench Press (Barbell)", superset: "A", setNumber: 1, setType: "Warm-up", weight: 60, reps: 5),
            ExportedSet(workoutStart: start, workoutEnd: start.addingTimeInterval(3600), workoutName: "Upper, heavy", workoutNotes: "-5 kg today",
                        exercise: "Bench Press (Barbell)", superset: "A", setNumber: 2, setType: "Normal", weight: 82.5, reps: 5),
            ExportedSet(workoutStart: start, workoutEnd: start.addingTimeInterval(3600), workoutName: "Upper, heavy", workoutNotes: "-5 kg today",
                        exercise: "Pull Up (Assisted)", superset: "A", setNumber: 1, setType: "Normal", reps: 8, assistance: 20),
            ExportedSet(workoutStart: start, workoutEnd: start.addingTimeInterval(3600), workoutName: "Upper, heavy", workoutNotes: "-5 kg today",
                        exercise: "Plank", setNumber: 1, setType: "Normal", seconds: 90),
        ]
        let result = try WorkoutImport.parse(WorkoutCSV.document(sets, timeZone: utc), timeZone: utc)
        #expect(result.source == .overlo4d)
        #expect(result.skippedRows == 0)
        let workout = try #require(result.workouts.first)
        #expect(workout.name == "Upper, heavy")
        #expect(workout.notes == "-5 kg today")
        #expect(workout.start == start)
        #expect(workout.end == start.addingTimeInterval(3600))
        #expect(workout.exercises.map(\.name) == ["Bench Press (Barbell)", "Pull Up (Assisted)", "Plank"])
        #expect(workout.exercises[0].sets.map(\.type) == ["warmup", "normal"])
        #expect(workout.exercises[0].sets[1].weight == 82.5)
        #expect(workout.exercises[0].superset == "A")
        #expect(workout.exercises[1].kind == "assistedBodyweight")
        #expect(workout.exercises[1].sets[0].assistance == 20)
        #expect(workout.exercises[2].sets[0].seconds == 90)
        #expect(workout.exercises[2].superset == nil)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: WorkoutImport.Failure.unknownFormat) { try WorkoutImport.parse("name,age\nSam,30\n") }
        #expect(throws: WorkoutImport.Failure.empty) { try WorkoutImport.parse("Date,Workout Name\n") }
        #expect(throws: WorkoutImport.Failure.empty) { try WorkoutImport.parse("") }
    }

    @Test func durations() {
        #expect(WorkoutImport.duration("1h 5m") == 3900)
        #expect(WorkoutImport.duration("45m") == 2700)
        #expect(WorkoutImport.duration("50s") == 50)
        #expect(WorkoutImport.duration("3000") == 3000)
        #expect(WorkoutImport.duration("1:05:00") == 3900)
        #expect(WorkoutImport.duration("") == nil)
        #expect(WorkoutImport.duration("soon") == nil)
    }

    @Test func matchesExerciseNames() {
        let library = ["Bench Press (Barbell)", "Bench Press (Dumbbell)", "Pull-ups", "Squat (Barbell)", "Lat Pulldown"]
        #expect(WorkoutImport.match("Bench Press (Barbell)", in: library) == 0)
        #expect(WorkoutImport.match("barbell bench press", in: library) == 0)
        #expect(WorkoutImport.match("Bench Press - Dumbbell", in: library) == 1)
        #expect(WorkoutImport.match("Pull Up", in: library) == 2)
        #expect(WorkoutImport.match("Lat Pulldowns", in: library) == 4)
        #expect(WorkoutImport.match("Bench Press", in: library) == nil)
        #expect(WorkoutImport.match("Zercher Squat", in: library) == nil)
    }

    @Test func spotsDuplicates() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(WorkoutImport.isDuplicate(start.addingTimeInterval(30), of: [start]))
        #expect(!WorkoutImport.isDuplicate(start.addingTimeInterval(120), of: [start]))
    }
}
