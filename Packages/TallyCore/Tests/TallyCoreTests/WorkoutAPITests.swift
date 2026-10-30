import Foundation
import Testing
@testable import TallyCore

private let catalogue = [
    "Barbell Bench Press", "Incline Barbell Bench Press", "Dumbbell Bench Press", "Seated Chest Press",
    "Pronated Grip Pull Ups", "Supinated Grip Pull Ups", "Deadlift", "Romanian Deadlift", "Lunges", "Dips",
    "Ab Wheel", "Barbell Curl", "Dumbbell Curl", "Unilateral Bent Over Row", "Barbell Bent Over Row",
    "Incline Dumbbell Reverse Fly", "Barbell Back Squat",
].enumerated().map { index, name in
    WorkoutAPI.Exercise(id: "\(index)", code: name.uppercased().replacingOccurrences(of: " ", with: "_"), name: name)
}

@Suite struct WorkoutAPITests {
    @Test func parsesTheExerciseList() {
        let json = """
        [{"id":"a1","code":"BARBELL_BENCH_PRESS","name":"Barbell Bench Press","description":"…","primaryMuscles":[{"id":"m","code":"CHEST","name":"Chest","color":"#f00"}]},
         {"id":"a2","code":"DIPS","name":"Dips"}]
        """
        let exercises = WorkoutAPI.parseExercises(Data(json.utf8))
        #expect(exercises.map(\.code) == ["BARBELL_BENCH_PRESS", "DIPS"])
        #expect(WorkoutAPI.parseExercises(Data("{\"error\":\"nope\"}".utf8)).isEmpty)
    }

    @Test func animationURLUsesTheCodeAndVariant() {
        #expect(WorkoutAPI.animationURL(code: "DIPS").absoluteString == "https://api.workoutapi.com/exercises/code/DIPS/animation?variant=basic")
        #expect(WorkoutAPI.animationURL(code: "DIPS", variant: .muscles).absoluteString.hasSuffix("variant=muscles"))
    }

    @Test func tokensIgnoreOrderPunctuationAndPlurals() {
        #expect(Set(WorkoutAPIMatcher.tokens("Bench Press (Barbell)")) == Set(WorkoutAPIMatcher.tokens("Barbell Bench Press")))
        #expect(WorkoutAPIMatcher.tokens("Pull-ups") == ["pull", "up"])
        #expect(WorkoutAPIMatcher.tokens("Overhand grip rows") == ["pronated", "row"])
    }

    private func match(_ name: String, hints: Set<String> = []) -> String? {
        WorkoutAPIMatcher.bestMatch(for: name, hints: hints, in: catalogue)?.name
    }

    @Test func matchesTheAppsNamesToTheCatalogue() {
        #expect(match("Bench Press (Barbell)") == "Barbell Bench Press")
        #expect(match("Incline Bench Press (Barbell)") == "Incline Barbell Bench Press")
        #expect(match("Bench Press (Dumbbell)") == "Dumbbell Bench Press")
        #expect(match("Dips") == "Dips")
        #expect(match("Deadlift (Barbell)") == "Deadlift")
        #expect(match("Bicep Curl (Barbell)") == "Barbell Curl")
        #expect(match("Bicep Curl (Dumbbell)") == "Dumbbell Curl")
    }

    @Test func gripHintPicksTheRightPullUp() {
        #expect(match("Pull-ups", hints: ["pronated"]) == "Pronated Grip Pull Ups")
        #expect(match("Chin-ups", hints: ["supinated"]) == "Supinated Grip Pull Ups")
    }

    @Test func differentEquipmentNeverMatches() {
        #expect(WorkoutAPIMatcher.score("Bench Press (Dumbbell)", candidate: "Barbell Bench Press") == nil)
        #expect(match("Chest Fly (Cable)") == nil)
        #expect(match("Leg Press (Machine)") == nil)
    }

    @Test func searchNeedsEveryWord() {
        #expect(WorkoutAPIMatcher.search("pull up", in: catalogue).map(\.name) == ["Pronated Grip Pull Ups", "Supinated Grip Pull Ups"])
        #expect(WorkoutAPIMatcher.search("bench db", in: catalogue).map(\.name) == ["Dumbbell Bench Press"])
        #expect(WorkoutAPIMatcher.search("", in: catalogue).count == catalogue.count)
    }
}

@Suite struct WorkoutAPISuggestionTests {
    @Test func suggestionsPutTheClosestNameFirst() {
        let names = WorkoutAPIMatcher.suggestions(for: "Bent Over Row (Barbell)", in: catalogue).map(\.name)
        #expect(names.first == "Barbell Bent Over Row")
        #expect(names.contains("Unilateral Bent Over Row"))
        #expect(!names.contains("Dumbbell Curl"))
    }
}

@Suite struct FreeExerciseDBTests {
    @Test func photoURLsPointAtTheRepo() {
        #expect(FreeExerciseDB.imageURL(id: "Pullups", frame: 1).absoluteString
            == "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Pullups/1.jpg")
    }

    @Test func builtInExercisesHavePhotos() {
        #expect(FreeExerciseDB.ids["Pull-ups"] == "Pullups")
        #expect(FreeExerciseDB.ids.count >= 128)
        #expect(FreeExerciseDB.ids.values.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
    }
}

@Suite struct MachineNameTests {
    @Test func leverMeansMachine() {
        let list = ["Lever Seated Row", "Cable Seated Row", "Barbell Bench Press", "Pull-Up", "Dumbbell Biceps Curl"]
            .enumerated().map { WorkoutAPI.Exercise(id: "\($0)", code: "\($0)", name: $1) }
        #expect(WorkoutAPIMatcher.bestMatch(for: "Seated Row (Machine)", in: list)?.name == "Lever Seated Row")
        #expect(WorkoutAPIMatcher.bestMatch(for: "Pull-ups", hints: ["pronated"], in: list)?.name == "Pull-Up")
        #expect(WorkoutAPIMatcher.bestMatch(for: "Bicep Curl (Dumbbell)", in: list)?.name == "Dumbbell Biceps Curl")
    }
}
