import Foundation
import Testing
@testable import Overlo4dCore

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

@Suite struct MotionTests {
    @Test func everyExerciseInTheTableHasAMove() {
        #expect(MotionLibrary.exercises.count >= 129)
        #expect(MotionLibrary.motion(for: "Pull-ups")?.move == .pullUp)
        #expect(MotionLibrary.motion(for: "Squat (Barbell)")?.load == .barbell)
    }

    @Test func customNamesFallBackToKeywords() {
        #expect(MotionLibrary.motion(for: "Paused Box Squat", equipment: "barbell")?.move == .squat)
        #expect(MotionLibrary.motion(for: "Cable Hammer Curl", equipment: "cable")?.load == .cable)
        #expect(MotionLibrary.motion(for: "Sled Push") == nil)
    }

    @Test func limbsKeepTheirLength() {
        for move in MotionMove.allCases {
            let s = move.pattern.skeleton(at: 0.37)
            #expect(abs(s.elbow.distance(to: s.hand) - MotionBody.forearm) < 0.001)
            #expect(abs(s.knee.distance(to: s.ankle) - MotionBody.shin) < 0.001)
        }
    }

    @Test func floorAnchorKeepsFeetDown() {
        let squat = MotionMove.squat.pattern
        for phase in [0, 0.5, 1.0] {
            let s = squat.skeleton(at: phase)
            #expect(abs(min(s.ankle.y, s.toe.y)) < 0.001)
            #expect(abs(s.ankle.x) < 0.001)
        }
    }

    @Test func barsTravelInAStraightLine() {
        // Measured from the hips, which stay put in these lifts.
        for move in [MotionMove.benchPress, .overheadPress, .row] {
            let pattern = move.pattern
            func bar(_ phase: Double) -> MotionPoint {
                let s = pattern.skeleton(at: phase)
                return MotionPoint(s.hand.x - s.hip.x, s.hand.y - s.hip.y)
            }
            let start = bar(0), middle = bar(0.5), end = bar(1)
            #expect(abs(middle.x - (start.x + end.x) / 2) < 0.01)
            #expect(abs(middle.y - (start.y + end.y) / 2) < 0.01)
        }
    }

    @Test func flaredElbowsShortenTheUpperArmFromTheSide() {
        let s = MotionMove.benchPress.pattern.skeleton(at: 1)
        #expect(s.shoulder.distance(to: s.elbow) < MotionBody.upperArm * 0.7)
        #expect(abs(s.elbow.distance(to: s.hand) - MotionBody.forearm) < 0.001)
    }

    @Test func bigLiftsFollowTheFormGuides() {
        // Squat: the hip crease ends below the knee.
        let squat = MotionMove.squat.pattern.skeleton(at: 1)
        #expect(squat.hip.y < squat.knee.y)
        // Deadlift: bar over the foot, hips between knees and shoulders, shoulders just in front of the bar.
        let pull = MotionMove.deadlift.pattern.skeleton(at: 0)
        #expect(pull.hand.x > pull.ankle.x && pull.hand.x < pull.toe.x)
        #expect(pull.hip.y > pull.knee.y && pull.hip.y < pull.shoulder.y)
        #expect(pull.shoulder.x > pull.hand.x)
        // Bench press: the bar comes down from over the shoulders to the chest, forearms upright.
        let bench = MotionMove.benchPress.pattern
        let top = bench.skeleton(at: 0), bottom = bench.skeleton(at: 1)
        #expect(abs(top.hand.x - top.shoulder.x) < 1)
        #expect(bottom.hand.x < bottom.shoulder.x - 5)
        #expect(abs(bottom.hand.x - bottom.elbow.x) < 1)
    }

    @Test func anglesBlendTheShortWay() {
        let pose = MotionPose(torso: 350).blended(to: MotionPose(torso: 20), 0.5)
        #expect(abs((pose.torso - 5).truncatingRemainder(dividingBy: 360)) < 0.001)
    }

    @Test func phaseGoesThereAndBack() {
        #expect(MotionPattern.phase(at: 0, duration: 2) == 0)
        #expect(abs(MotionPattern.phase(at: 1, duration: 2) - 1) < 0.001)
        #expect(abs(MotionPattern.phase(at: 2, duration: 2)) < 0.001)
    }

    @Test func aRepRestsAtBothEndsAndNeverJumps() {
        // Still for a moment in the start position and again in the end position.
        #expect(MotionPattern.phase(at: 0.05, duration: 2) == 0)
        #expect(MotionPattern.phase(at: 1.03, duration: 2) == 1)
        // Halfway through the way there it is halfway, and the way back mirrors the way there.
        #expect(abs(MotionPattern.phase(at: 0.5, duration: 2) - 0.5) < 0.001)
        #expect(abs(MotionPattern.phase(at: 0.3, duration: 2) - MotionPattern.phase(at: 1.7, duration: 2)) < 0.001)
        // Two frames a sixtieth of a second apart are never far apart, across the loop's seam as well.
        var last = MotionPattern.phase(at: -1.0 / 60, duration: 2)
        for frame in 0...130 {
            let next = MotionPattern.phase(at: Double(frame) / 60, duration: 2)
            #expect(abs(next - last) < 0.04)
            last = next
        }
    }

    // Standing: torso, thigh and shin in one line, the figure facing +x.
    private func standing(bends: [Double] = [MotionBody.hipBend, MotionBody.kneeBend]) -> MotionChain {
        MotionChain(joints: [MotionPoint(0, 132), MotionPoint(0, 82), MotionPoint(0, 40), MotionPoint(0, 0)],
                    lengths: [50, 42, 40], bends: bends)
    }

    // The same, sitting: the thigh points forward.
    private func sitting(flipped: Bool = false) -> MotionChain {
        MotionChain(joints: [MotionPoint(0, 132), MotionPoint(0, 82), MotionPoint(42, 82), MotionPoint(42, 42)],
                    lengths: [50, 42, 40], bends: [MotionBody.hipBend, MotionBody.kneeBend], flipped: flipped)
    }

    @Test func aStraightLimbIsDrawnAsItWas() {
        let chain = standing()
        // 5 down the thigh from the hip and 3 in front of it, well inside the part that would bend.
        for (bone, x, y, expected) in [(1, 5.0, 3.0, MotionPoint(3, 77)), (0, 45.0, -9.0, MotionPoint(-9, 87)), (2, 20.0, 4.0, MotionPoint(4, 20))] {
            let p = chain.place(bone: bone, x: x, y: y)
            #expect(p.distance(to: expected) < 1e-9)
        }
        // A bone that is longer now than it was drawn stretches what is drawn along it.
        let long = MotionChain(joints: [MotionPoint(0, 0), MotionPoint(60, 0)], lengths: [30])
        #expect(long.place(bone: 0, x: 15, y: 2).distance(to: MotionPoint(30, 2)) < 1e-9)
    }

    @Test func twoPiecesThatShareAJointMeetWithoutASeam() {
        // The thigh's drawing runs up over the hip and the torso's runs down past it. Wherever
        // they describe the same spot on the body they must land on the same spot of the screen.
        for chain in [standing(), sitting(), sitting(flipped: true)] {
            for past in stride(from: -20.0, through: 20.0, by: 0.5) {
                for across in [-17.0, -6.0, 0.0, 6.0, 12.0] {
                    let fromTorso = chain.place(bone: 0, x: 50 + past, y: across)
                    let fromThigh = chain.place(bone: 1, x: past, y: across)
                    #expect(fromTorso.distance(to: fromThigh) < 1e-9)
                }
            }
        }
    }

    @Test func aBendHasNoBreakInIt() {
        // Walking along the body in small steps, on the outside of the bend and on the inside, the
        // place never jumps: not where the curve starts, not at the joint, not at the crease. (The
        // outside of a bend is stretched, so a step there is a few times longer, but still a step.)
        let chain = sitting()
        for across in [-17.0, -8.0, 0.0, 8.0, 12.5] {
            var last = chain.place(bone: 0, x: 20, y: across)
            for step in 1...600 {
                let next = chain.place(bone: 0, x: 20 + Double(step) * 0.1, y: across)
                #expect(next.distance(to: last) < 0.5)
                last = next
            }
        }
    }

    @Test func theOutsideOfABendStaysRound() {
        // Seated, the back of the hip is the outside of the bend. A buttock drawn 17 behind the
        // hip stays about that far from the joint all the way round, neither pinched nor ballooned.
        let chain = sitting(), hip = MotionPoint(0, 82)
        for past in stride(from: -16.0, through: 16.0, by: 1) {
            let d = chain.place(bone: 1, x: past, y: -17).distance(to: hip)
            #expect(d > 12 && d < 24)
        }
    }

    @Test func theInsideOfABendCreasesInsteadOfOverlapping() {
        // Seated, the belly and the top of the thigh meet in a crease that runs from the hip
        // forward and up, halfway between the two. Neither side crosses it.
        let chain = sitting()
        func side(_ p: MotionPoint) -> Double { (p.x - 0) * 1 + (p.y - 82) * -1 }   // > 0 on the thigh's side
        for x in stride(from: 0.0, through: 60.0, by: 1) {
            #expect(side(chain.place(bone: 0, x: x, y: 13)) < 1e-6)        // the front of the torso
            #expect(side(chain.place(bone: 1, x: x - 10, y: 13)) > -1e-6 || x - 10 < 0)   // the top of the thigh
        }
        // Far from the joint the two don't touch, so nothing is trimmed there.
        #expect(chain.place(bone: 0, x: 10, y: 13).distance(to: MotionPoint(13, 122)) < 1e-9)
        #expect(chain.place(bone: 1, x: 35, y: 13).distance(to: MotionPoint(35, 95)) < 1e-9)
        // Lying face up the front of the body is on the other side, and so is the crease.
        let flipped = sitting(flipped: true).place(bone: 1, x: 30, y: -12)
        #expect(flipped.distance(to: MotionPoint(30, 94)) < 1e-9)
    }
}
