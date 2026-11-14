import Foundation
import Testing
@testable import TallyCore

@Suite struct WeightUnitTests {
    @Test func kilogramsPassThrough() {
        #expect(WeightUnit.kg.fromKg(82.5) == 82.5)
        #expect(WeightUnit.kg.toKg(82.5) == 82.5)
        #expect(WeightUnit.kg.text(82.5) == "82.5 kg")
        #expect(WeightUnit.kg.plain(100) == "100")
    }

    @Test func typedPoundsSurviveTheRoundTrip() {
        for pounds in [45.0, 135, 225, 315, 2.5, 17.5, 132.25, 405] {
            #expect(WeightUnit.lb.fromKg(WeightUnit.lb.toKg(pounds)) == pounds)
        }
    }

    @Test func poundsText() {
        #expect(WeightUnit.lb.text(WeightUnit.lb.toKg(135)) == "135 lb")
        #expect(WeightUnit.lb.plain(100) == "220.46")
        #expect(WeightUnit.lb.plain(WeightUnit.lb.toKg(12.5)) == "12.5")
    }

    @Test func roundsToLoadableWeights() {
        #expect(WeightUnit.kg.round(61.2) == 60)
        #expect(WeightUnit.kg.round(61.3) == 62.5)
        // 100 kg is 220.46 lb, which loads as 220 lb.
        #expect(WeightUnit.lb.fromKg(WeightUnit.lb.round(100)) == 220)
        #expect(WeightUnit.lb.fromKg(WeightUnit.lb.round(100, toStep: 2.5)) == 220)
    }

    @Test func poundPlatesLoadABar() {
        let load = Plates.load(target: 225, bar: 45, plates: WeightUnit.lb.plates)
        #expect(load.perSide == [45, 45])
        #expect(load.leftover == 0)
        #expect(Plates.load(target: 135, bar: 45, plates: WeightUnit.lb.plates).perSide == [45])
        #expect(Plates.load(target: 187.5, bar: 45, plates: WeightUnit.lb.plates).perSide == [45, 25])
    }

    @Test func progressionStepInPounds() {
        let lb = WeightUnit.lb
        #expect(lb.fromKg(Progression.step(equipment: "barbell", weight: lb.toKg(135), unit: .lb)) == 5)
        #expect(lb.fromKg(Progression.step(equipment: "dumbbell", weight: lb.toKg(15), unit: .lb)) == 2.5)
        #expect(lb.fromKg(Progression.step(equipment: "machine", weight: lb.toKg(250), unit: .lb)) == 10)
        #expect(Progression.step(equipment: "barbell", weight: 60, unit: .kg) == 2.5)
    }

    @Test func suggestionsLandOnPoundPlates() throws {
        let lb = WeightUnit.lb
        let set = Progression.PastSet(weight: lb.toKg(135), reps: 8)
        let step = Progression.step(equipment: "barbell", weight: set.weight, unit: .lb)
        let suggestion = try #require(Progression.suggest(sessions: [[set, set, set]], targetReps: 8, step: step, unit: .lb))
        #expect(suggestion.action == .increase)
        #expect(lb.fromKg(suggestion.weight) == 140)
    }

    @Test func plateauReasonUsesTheUnit() throws {
        let lb = WeightUnit.lb
        let stuck = [Progression.PastSet(weight: lb.toKg(200), reps: 8), Progression.PastSet(weight: lb.toKg(200), reps: 6)]
        let suggestion = try #require(Progression.suggest(sessions: [stuck, stuck, stuck], targetReps: 8, step: lb.toKg(5), unit: .lb))
        #expect(suggestion.action == .deload)
        #expect(lb.fromKg(suggestion.weight) == 180)
        #expect(suggestion.reason.contains("200 lb"))
    }
}

@Suite struct CardioTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func paceAndSpeed() {
        let run = CardioSession(activity: .run, start: start, seconds: 1500, meters: 5000)
        #expect(run.secondsPerKm == 300)
        #expect(run.kmPerHour == 12)
        #expect(run.end == start.addingTimeInterval(1500))
        #expect(run.summary.hasSuffix("25:00 · 5:00 /km"))
        let ride = CardioSession(activity: .cycle, start: start, seconds: 3600, meters: 25_000)
        #expect(ride.summary.hasSuffix("25.0 km/h"))
        let stairs = CardioSession(activity: .stairs, start: start, seconds: 600)
        #expect(stairs.summary == "10:00")
        #expect(stairs.secondsPerKm == nil)
    }

    @Test func energyIsTypedOrEstimated() {
        var run = CardioSession(activity: .run, start: start, seconds: 1800, meters: 5000)
        // MET 9.8 × 80 kg × 0.5 h.
        #expect(abs((run.energy(bodyMass: 80) ?? 0) - 392) < 0.001)
        #expect(run.energy(bodyMass: nil) == nil)
        run.effort = .easy
        #expect(abs((run.energy(bodyMass: 80) ?? 0) - 280) < 0.001)
        run.kcal = 410
        #expect(run.energy(bodyMass: nil) == 410)
    }

    @Test func harderEffortBurnsMore() {
        for activity in CardioActivity.allCases {
            #expect(activity.met(.easy) < activity.met(.steady))
            #expect(activity.met(.steady) < activity.met(.hard))
        }
    }

    @Test func decodesWhatItEncodes() throws {
        let session = CardioSession(activity: .row, start: start, seconds: 1200, meters: 5000, effort: .hard, kcal: 300, averageHeartRate: 150, notes: "2k pieces")
        let decoded = try JSONDecoder().decode(CardioSession.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }

    @Test func weekTotalsAndBests() {
        let day = 86_400.0
        let sessions = [
            CardioSession(activity: .run, start: start, seconds: 1500, meters: 5000),
            CardioSession(activity: .run, start: start.addingTimeInterval(2 * day), seconds: 3300, meters: 10_000),
            CardioSession(activity: .run, start: start.addingTimeInterval(3 * day), seconds: 200, meters: 800),
            CardioSession(activity: .cycle, start: start.addingTimeInterval(9 * day), seconds: 3600, meters: 30_000),
        ]
        let week = CardioTotals.totals(sessions, in: DateInterval(start: start, duration: 7 * day))
        #expect(week == CardioTotals.Week(sessions: 3, seconds: 5000, meters: 15_800))
        // The 800 m sprint is faster but too short to count as a best pace.
        #expect(CardioTotals.bestPace(sessions, activity: .run)?.meters == 5000)
        #expect(CardioTotals.longest(sessions, activity: .run)?.meters == 10_000)
        #expect(CardioTotals.bestPace(sessions, activity: .swim) == nil)
    }
}

@Suite struct AppLinkTests {
    @Test func parsesKnownLinks() throws {
        #expect(AppLink.parse(try #require(URL(string: "tally://reps"))) == .reps)
        #expect(AppLink.parse(try #require(URL(string: "tally://start"))) == .start(plan: nil))
        #expect(AppLink.parse(try #require(URL(string: "tally://start?plan=Push%20Day"))) == .start(plan: "Push Day"))
        #expect(AppLink.parse(try #require(URL(string: "TALLY://Cardio"))) == .cardio)
        #expect(AppLink.parse(try #require(URL(string: "tally://nope"))) == nil)
        #expect(AppLink.parse(try #require(URL(string: "https://start"))) == nil)
    }

    @Test func linksRoundTrip() throws {
        for link in [AppLink.reps, .food, .train, .start(plan: nil), .start(plan: "Legs & Core"), .cardio, .plates, .timer, .report, .history] {
            #expect(AppLink.parse(try #require(link.url)) == link)
        }
    }

    @Test func matchesPlansLoosely() {
        let plans = ["Push Day", "Pull Day", "Legs", "Upper Body A"]
        #expect(AppLink.match(plan: "pull day", in: plans) == 1)
        #expect(AppLink.match(plan: "upper", in: plans) == 3)
        #expect(AppLink.match(plan: "body", in: plans) == 3)
        #expect(AppLink.match(plan: "arms", in: plans) == nil)
        #expect(AppLink.match(plan: " ", in: plans) == nil)
    }
}
