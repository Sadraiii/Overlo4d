import Foundation
import Testing
@testable import TallyCore

@Suite struct ProgramTests {
    let maxes = [
        ProgramTemplates.squat: 150.0,
        ProgramTemplates.bench: 100.0,
        ProgramTemplates.deadlift: 180.0,
        ProgramTemplates.press: 60.0,
    ]
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func juggernautHasFourWavesOfFourWeeks() {
        let program = ProgramTemplates.juggernaut(oneRepMaxes: maxes, start: start)
        #expect(program.weeks.count == 16)
        #expect(program.days.count == 4)
        #expect(program.weeks.filter(\.isDeload).count == 4)
        #expect(program.weeks.compactMap(\.amrapTarget) == [10, 8, 5, 3])
        // Training max is 90 % of the one-rep max, rounded to 2.5 kg.
        #expect(program.lift(ProgramTemplates.squat)?.trainingMax == 135)
        #expect(program.lift(ProgramTemplates.bench)?.trainingMax == 90)
        #expect(program.lift(ProgramTemplates.press)?.increment == 1.25)
    }

    @Test func itemsWorkOutWeights() {
        let program = ProgramTemplates.juggernaut(oneRepMaxes: maxes, start: start)
        let items = program.items(week: 0, day: 0, logs: [])
        let squat = items[0]
        #expect(squat.exercise == ProgramTemplates.squat)
        #expect(squat.isMainLift)
        #expect(squat.sets.count == 5)
        // 60 % of 135 = 81 → 80.
        #expect(squat.sets.allSatisfy { $0.weight == 80 && $0.reps == 10 })
        #expect(items.count == 4)
        #expect(items[1].sets.count == 3 && items[1].sets[0].weight == nil)
    }

    @Test func deloadHalvesAccessories() {
        let program = ProgramTemplates.juggernaut(oneRepMaxes: maxes, start: start)
        let items = program.items(week: 3, day: 1, logs: [])
        #expect(items[1].sets.count == 2)
        #expect(items[0].sets.map(\.weight) == [35, 45, 55])
    }

    @Test func repOutRaisesTrainingMaxForLaterWeeks() {
        let program = ProgramTemplates.juggernaut(oneRepMaxes: maxes, start: start)
        let squat = ProgramTemplates.squat
        // 13 reps on the 10s realization week (week 3, index 2): 3 extra × 2.5 kg.
        let logs = [ProgramLog(week: 2, day: 0, topReps: [squat: 13])]
        #expect(program.trainingMax(for: squat, week: 2, logs: logs) == 135)
        #expect(program.trainingMax(for: squat, week: 4, logs: logs) == 142.5)
        // Missing the target keeps the max.
        let missed = [ProgramLog(week: 2, day: 0, topReps: [squat: 8])]
        #expect(program.trainingMax(for: squat, week: 4, logs: missed) == 135)
        // Logs from non-rep-out weeks don't count.
        let normal = [ProgramLog(week: 0, day: 0, topReps: [squat: 20])]
        #expect(program.trainingMax(for: squat, week: 4, logs: normal) == 135)
    }

    @Test func increaseIsCapped() {
        #expect(StrengthProgram.increase(trainingMax: 100, increment: 2.5, reps: 30, target: 10) == 10)
        #expect(StrengthProgram.increase(trainingMax: 100, increment: 2.5, reps: 5, target: 10) == 0)
    }

    @Test func blockBuildsAndDeloads() {
        for count in 4...8 {
            let program = ProgramTemplates.block(weeks: count, oneRepMaxes: maxes, start: start)
            #expect(program.weeks.count == count)
            #expect(program.weeks.last?.isDeload == true)
            #expect(program.weeks[count - 2].amrapTarget == 3)
            let tops = program.weeks.dropLast().map { $0.sets.filter { !$0.warmup }.map(\.percent).max() ?? 0 }
            #expect(tops.first == 70)
            #expect(tops.last == 87.5)
            #expect(tops == tops.sorted())
        }
        #expect(ProgramTemplates.block(weeks: 20, oneRepMaxes: maxes, start: start).weeks.count == 8)
    }

    @Test func missingMaxesDropTheLift() {
        let program = ProgramTemplates.block(weeks: 6, oneRepMaxes: [ProgramTemplates.squat: 100], start: start)
        #expect(program.lifts.map(\.exercise) == [ProgramTemplates.squat])
        #expect(program.days[1].lifts.isEmpty)
        #expect(program.items(week: 0, day: 1, logs: []).allSatisfy { !$0.isMainLift })
    }

    @Test func nextAndProgress() {
        let program = ProgramTemplates.block(weeks: 4, oneRepMaxes: maxes, start: start)
        #expect(program.next(logs: [])! == (0, 0))
        let logs = [ProgramLog(week: 0, day: 0), ProgramLog(week: 0, day: 1), ProgramLog(week: 0, day: 0)]
        #expect(program.next(logs: logs)! == (0, 2))
        #expect(program.progress(logs: logs) == (2, 16))
        let all = (0..<4).flatMap { w in (0..<4).map { ProgramLog(week: w, day: $0) } }
        #expect(program.next(logs: all) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let program = ProgramTemplates.juggernaut(oneRepMaxes: maxes, start: start)
        let decoded = try JSONDecoder().decode(StrengthProgram.self, from: JSONEncoder().encode(program))
        #expect(decoded == program)
    }
}

@Suite struct ProgramCoachTests {
    private func response(_ program: String, stop: String = "end_turn") -> Data {
        let text = String(data: try! JSONSerialization.data(withJSONObject: [program], options: []), encoding: .utf8)!.dropFirst().dropLast()
        return Data(#"{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":\#(text)}],"stop_reason":"\#(stop)"}"#.utf8)
    }

    private let draft = """
    {"name":"8-week bench focus","summary":"Bench twice a week.","rules":["Add weight when you beat the target."],
     "lifts":[{"exercise":"Bench Press (Barbell)","training_max_kg":91.3,"increment_kg":1.25},
              {"exercise":"Squat (Barbell)","training_max_kg":0,"increment_kg":2.5}],
     "days":[{"name":"Upper","lifts":["Bench Press (Barbell)","Squat (Barbell)"],"accessories":[{"exercise":"Dumbbell Row","sets":40,"reps":10,"notes":""}]}],
     "weeks":[{"phase":"Week 1","note":"Start","deload":false,"amrap_target":5,"sets":[{"percent":150,"reps":5,"amrap":false,"warmup":true}]},
              {"phase":"Week 2","note":"Test","deload":false,"amrap_target":5,"sets":[{"percent":85,"reps":5,"amrap":true,"warmup":true}]}]}
    """

    @Test func parsesAndCleansTheDraft() throws {
        let program = try ProgramCoach.parse(status: 200, data: response(draft), start: .distantPast)
        #expect(program.name == "8-week bench focus")
        #expect(program.source == .coach)
        // The lift without a training max is dropped, from the day too.
        #expect(program.lifts.map(\.exercise) == ["Bench Press (Barbell)"])
        #expect(program.lifts[0].trainingMax == 91.5)
        #expect(program.days[0].lifts == ["Bench Press (Barbell)"])
        #expect(program.days[0].accessories[0].sets == 10)
        #expect(program.weeks[0].sets[0].percent == 105)
        // No rep-out set, no target; a rep-out set is never a warm-up.
        #expect(program.weeks[0].amrapTarget == nil)
        #expect(program.weeks[1].amrapTarget == 5)
        #expect(program.weeks[1].sets[0].warmup == false)
    }

    @Test func errors() {
        #expect(throws: CoachError.truncated) {
            try ProgramCoach.parse(status: 200, data: response("{", stop: "max_tokens"), start: .now)
        }
        #expect(throws: CoachError.badResponse) {
            try ProgramCoach.parse(status: 200, data: response(#"{"name":"x"}"#), start: .now)
        }
        #expect(throws: CoachError.invalidKey) {
            try ProgramCoach.parse(status: 401, data: Data(), start: .now)
        }
    }

    @Test func promptListsMaxesAndNotes() {
        let prompt = ProgramCoach.prompt(
            ProgramRequest(weeks: 16, daysPerWeek: 4, goal: "Get stronger", notes: "Bigger bench", oneRepMaxes: ["Bench Press (Barbell)": 102.3]),
            exercises: ["Bench Press (Barbell)", "Dumbbell Row"],
            log: "- Bench 5x5"
        )
        #expect(prompt.contains("16-week"))
        #expect(prompt.contains("4 training days"))
        #expect(prompt.contains("Bench Press (Barbell): 102.5 kg"))
        #expect(prompt.contains("Notes from me: Bigger bench"))
        #expect(prompt.contains("Bench Press (Barbell); Dumbbell Row"))
    }

    @Test func bodyAsksForTheSchema() throws {
        let data = try ProgramCoach.body(model: .sonnet, prompt: "hi")
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(body["fallbacks"] as? String == "default")
    }
}
