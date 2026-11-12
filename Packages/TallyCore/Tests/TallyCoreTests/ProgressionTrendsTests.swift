import Foundation
import Testing
@testable import TallyCore

@Suite struct ProgressionTests {
    private func s(_ weight: Double, _ reps: Int, rpe: Double? = nil) -> Progression.PastSet {
        Progression.PastSet(weight: weight, reps: reps, rpe: rpe)
    }

    @Test func increasesWhenEverySetHitsTheTarget() {
        let result = Progression.suggest(sessions: [[s(60, 8), s(60, 8), s(60, 9)]], targetReps: 8)
        #expect(result?.action == .increase)
        #expect(result?.weight == 62.5)
        #expect(result?.reps == 8)
    }

    @Test func usesTheEquipmentStep() {
        #expect(Progression.step(equipment: "dumbbell", weight: 8) == 1)
        #expect(Progression.step(equipment: "dumbbell", weight: 20) == 2)
        #expect(Progression.step(equipment: "machine", weight: 120) == 5)
        #expect(Progression.step(equipment: "barbell", weight: 100) == 2.5)
        #expect(Progression.step(equipment: nil, weight: 40) == 2.5)
        let result = Progression.suggest(sessions: [[s(20, 10), s(20, 10)]], targetReps: 10, step: 2)
        #expect(result?.weight == 22)
    }

    @Test func keepsTheWeightWhenASetFellShort() {
        let result = Progression.suggest(sessions: [[s(60, 8), s(60, 7), s(60, 6)]], targetReps: 8)
        #expect(result?.action == .addReps)
        #expect(result?.weight == 60)
        #expect(result?.reason.contains("2 sets") == true)
    }

    @Test func lighterSetsDoNotBlockAnIncrease() {
        // Only sets at the top weight are judged.
        let result = Progression.suggest(sessions: [[s(60, 8), s(60, 8), s(50, 6)]], targetReps: 8)
        #expect(result?.action == .increase)
    }

    @Test func holdsAfterAMaxEffortSet() {
        let result = Progression.suggest(sessions: [[s(60, 8), s(60, 8, rpe: 10)]], targetReps: 8)
        #expect(result?.action == .hold)
        #expect(result?.weight == 60)
        // Extra reps at RPE 10 on one set, but another only just made it: still a hold.
        #expect(Progression.suggest(sessions: [[s(60, 10, rpe: 10), s(60, 9)]], targetReps: 8)?.action == .increase)
    }

    @Test func fallsBackToLastTimesFirstSetWithoutATarget() {
        #expect(Progression.suggest(sessions: [[s(40, 10), s(40, 10)]], targetReps: nil)?.action == .increase)
        #expect(Progression.suggest(sessions: [[s(40, 10), s(40, 8)]], targetReps: nil)?.action == .addReps)
    }

    @Test func suggestsADeloadAfterThreeStuckSessions() {
        let stuck = [[s(80, 5), s(80, 4), s(80, 4)], [s(80, 5), s(80, 4), s(80, 4)], [s(80, 5), s(80, 5), s(80, 4)]]
        let result = Progression.suggest(sessions: stuck, targetReps: 6)
        #expect(result?.action == .deload)
        #expect(result?.weight == 72.5)
        // Reps still creeping up is progress, not a stall.
        let moving = [[s(80, 5), s(80, 5), s(80, 5)], [s(80, 5), s(80, 4), s(80, 4)], [s(80, 4), s(80, 4), s(80, 4)]]
        #expect(Progression.suggest(sessions: moving, targetReps: 6)?.action == .addReps)
    }

    @Test func nothingWithoutWeightedSets() {
        #expect(Progression.suggest(sessions: [], targetReps: 8) == nil)
        #expect(Progression.suggest(sessions: [[s(0, 10)]], targetReps: 8) == nil)
    }

    @Test func matchesPreviousSetsByKind() {
        // Last time: 2 warm-ups then 3 sets. Today: no warm-ups.
        #expect(PreviousSets.match(current: [false, false, false], previous: [true, true, false, false, false]) == [2, 3, 4])
        // Today has a warm-up, last time had none; and one more working set than last time.
        #expect(PreviousSets.match(current: [true, false, false, false], previous: [false, false]) == [nil, 0, 1, nil])
        #expect(PreviousSets.match(current: [true, false], previous: [true, false]) == [0, 1])
    }
}

@Suite struct UpNextTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ count: Double) -> Date { now.addingTimeInterval(-count * 86_400) }

    @Test func picksThePlanThatWaitedLongest() {
        let push = UpNext.Candidate(id: UUID(), lastDone: days(1), muscles: ["chest"])
        let legs = UpNext.Candidate(id: UUID(), lastDone: days(5), muscles: ["quads"])
        let pick = UpNext.pick(candidates: [push, legs], recovery: [:], now: now)
        #expect(pick?.id == legs.id)
        #expect(pick?.daysSince == 5)
        #expect(pick?.readiness == 1)
    }

    @Test func tiredMusclesPushAPlanBack() {
        let push = UpNext.Candidate(id: UUID(), lastDone: days(4), muscles: ["chest", "triceps"])
        let pull = UpNext.Candidate(id: UUID(), lastDone: days(3), muscles: ["lats", "biceps"])
        let pick = UpNext.pick(candidates: [push, pull], recovery: ["chest": 0.2, "triceps": 0.3], now: now)
        #expect(pick?.id == pull.id)
        let tired = UpNext.pick(candidates: [push], recovery: ["chest": 0.2, "triceps": 0.5], now: now)
        #expect(tired?.tired == ["chest", "triceps"])
    }

    @Test func neverDoneCountsAsLongAgoAndTiesKeepOrder() {
        let first = UpNext.Candidate(id: UUID(), lastDone: nil, muscles: [])
        let second = UpNext.Candidate(id: UUID(), lastDone: nil, muscles: [])
        let pick = UpNext.pick(candidates: [first, second], recovery: [:], now: now)
        #expect(pick?.id == first.id)
        #expect(pick?.daysSince == nil)
        #expect(UpNext.pick(candidates: [], recovery: [:], now: now) == nil)
        #expect(UpNext.waitText(daysSince: nil) == "Not done yet")
        #expect(UpNext.waitText(daysSince: 1) == "Last done yesterday")
        #expect(UpNext.waitText(daysSince: 4) == "Last done 4 days ago")
    }
}

@Suite struct TrendsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lift = UUID()
    private func session(daysAgo: Double, volume: Double = 1000, sets: Int = 10, records: Int = 0, max: Double? = nil) -> SessionSummary {
        SessionSummary(start: now.addingTimeInterval(-daysAgo * 86_400), duration: 3600, volume: volume, sets: sets, records: records, bestOneRepMax: max.map { [lift: $0] } ?? [:])
    }

    @Test func comparesWithThePeriodBefore() {
        let sessions = [session(daysAgo: 1), session(daysAgo: 10, records: 2), session(daysAgo: 30), session(daysAgo: 70)]
        let result = Trends.compare(sessions: sessions, days: 28, now: now)
        #expect(result.totals.workouts == 2)
        #expect(result.totals.records == 2)
        #expect(result.before.workouts == 1)
        #expect(result.hasEarlier)
        #expect(result.workoutsPerWeek == 0.5)
        #expect(result.totals.averageDuration == 3600)
        #expect(Trends.compare(sessions: [session(daysAgo: 2)], days: 28, now: now).hasEarlier == false)
    }

    @Test func changeText() {
        #expect(Trends.changeText(120, from: 100) == "+20%")
        #expect(Trends.changeText(92, from: 100) == "−8%")
        #expect(Trends.changeText(100, from: 100) == "same")
        #expect(Trends.changeText(5, from: 0) == nil)
    }

    @Test func liftTrendsNeedTwoSessions() {
        let other = UUID()
        var sessions = [session(daysAgo: 20, max: 100), session(daysAgo: 10, max: 104), session(daysAgo: 2, max: 110), session(daysAgo: 200, max: 80)]
        sessions.append(SessionSummary(start: now.addingTimeInterval(-86_400), duration: 10, volume: 0, sets: 1, records: 0, bestOneRepMax: [other: 50]))
        let interval = DateInterval(start: now.addingTimeInterval(-84 * 86_400), end: now)
        let trends = Trends.lifts(sessions: sessions, in: interval)
        #expect(trends.count == 1)
        #expect(trends.first?.points == [100, 104, 110])
        #expect(trends.first?.change == 10)
        #expect(trends.first?.fraction == 0.1)
    }

    @Test func monthsIncludeEmptyOnes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let months = Trends.months(sessions: [session(daysAgo: 0), session(daysAgo: 65)], count: 4, now: now, calendar: calendar)
        #expect(months.count == 4)
        #expect(months.last?.workouts == 1)
        #expect(months.map(\.workouts).reduce(0, +) == 2)
        #expect(months.first!.month < months.last!.month)
    }

    @Test func balanceSharesAndNotes() {
        let shares = TrainingBalance.shares(muscleSets: ["chest": 12, "triceps": 6, "lats": 6, "quads": 6, "unknown": 9])
        #expect(shares.map(\.group) == [.push, .pull, .legs, .core])
        #expect(shares[0].sets == 18)
        #expect(shares[0].fraction == 0.6)
        #expect(TrainingBalance.note(shares)?.contains("three times") == true)
        #expect(TrainingBalance.note(TrainingBalance.shares(muscleSets: ["chest": 10, "lats": 10, "quads": 10])) == nil)
        #expect(TrainingBalance.note(TrainingBalance.shares(muscleSets: ["chest": 10, "lats": 9])) == "No leg work in this period.")
        #expect(TrainingBalance.shares(muscleSets: [:]).isEmpty)
    }
}

@Suite struct HomeLayoutTests {
    @Test func roundTripsAndSurvivesOldOrBrokenData() {
        var layout = HomeLayout.standard
        layout.today = ["reps", "food", "gone", "food"]
        layout.hidden = ["sleep", "gone"]
        let restored = HomeLayout.decode(layout.encoded)
        #expect(restored.today == ["reps", "food", "sleep", "activity"])
        #expect(restored.hidden == ["sleep"])
        #expect(restored.visible(restored.today) == ["reps", "food", "activity"])
        #expect(restored.training == HomeLayout.trainingCards)
        #expect(HomeLayout.decode("") == .standard)
        #expect(HomeLayout.decode("{nonsense") == .standard)
        #expect(HomeLayout.standard.isStandard)
        #expect(!restored.isStandard)
    }
}

@Suite struct PlanTemplateTests {
    @Test func templatesAreWellFormed() {
        #expect(Set(PlanTemplates.all.map(\.id)).count == PlanTemplates.all.count)
        for template in PlanTemplates.all {
            #expect(!template.days.isEmpty)
            #expect(Set(template.days.map(\.name)).count == template.days.count)
            for day in template.days {
                #expect(day.items.count >= 4)
                #expect(day.items.allSatisfy { $0.sets > 0 && $0.rest > 0 })
            }
        }
    }
}

@Suite struct SupersetFlowTests {
    private let a = UUID(), b = UUID()

    @Test func namesAndLetters() {
        #expect(Supersets.groupName(size: 2) == "Superset")
        #expect(Supersets.groupName(size: 3) == "Giant set")
        #expect(Supersets.groupName(size: 5) == "Circuit")
        #expect(Supersets.letters([nil, a, a, nil, b, b, b]) == [nil, "A", "A", nil, "B", "B", "B"])
        #expect(Supersets.members(of: 5, in: [nil, a, a, nil, b, b, b]) == [4, 5, 6])
        #expect(Supersets.members(of: 0, in: [nil, a, a]).isEmpty)
        // A lone ID is not a group.
        #expect(Supersets.letters([a, nil, a]) == [nil, nil, nil])
    }

    @Test func nextGoesRoundTheGroupThenOn() {
        let ids: [UUID?] = [a, a, a, nil]
        #expect(Supersets.next(after: 0, in: ids, remaining: [2, 3, 3, 3]) == 1)
        #expect(Supersets.next(after: 2, in: ids, remaining: [2, 2, 2, 3]) == 0)
        // A member that is finished is skipped.
        #expect(Supersets.next(after: 0, in: ids, remaining: [1, 0, 1, 3]) == 2)
        // Group done: on to the next exercise.
        #expect(Supersets.next(after: 2, in: ids, remaining: [0, 0, 0, 3]) == 3)
    }

    @Test func nextOutsideAGroup() {
        let ids: [UUID?] = [nil, nil, nil]
        #expect(Supersets.next(after: 1, in: ids, remaining: [0, 2, 3]) == 1)
        #expect(Supersets.next(after: 1, in: ids, remaining: [0, 0, 3]) == 2)
        #expect(Supersets.next(after: 2, in: ids, remaining: [1, 0, 0]) == 0)
        #expect(Supersets.next(after: 2, in: ids, remaining: [0, 0, 0]) == nil)
    }
}
