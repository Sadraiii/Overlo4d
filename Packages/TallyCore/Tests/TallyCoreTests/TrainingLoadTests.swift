import Foundation
import Testing
@testable import TallyCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

private func work(_ days: Double, _ primary: [String], _ secondary: [String] = [], sets: Int) -> MuscleWork {
    MuscleWork(date: daysAgo(days), primary: primary, secondary: secondary, sets: sets)
}

@Suite struct TrainingLoadTests {
    @Test func countsSecondaryMusclesHalfAndOnlyTheLastSevenDays() {
        let report = TrainingLoad.report([
            work(1, ["chest"], ["triceps"], sets: 4),
            work(3, ["triceps"], sets: 3),
            work(8, ["chest"], sets: 10),
        ], now: now)
        #expect(report.lastWeek == ["chest": 4, "triceps": 5])
        // Not enough history for a usual week.
        #expect(report.usualWeek.isEmpty)
    }

    @Test func flagsMoreThanTwentySets() {
        let report = TrainingLoad.report([
            work(1, ["chest"], sets: 8),
            work(3, ["chest"], sets: 8),
            work(5, ["chest"], sets: 6),
            work(5, ["quads"], sets: 20),
        ], now: now)
        #expect(report.flags.contains(.tooMuch(muscle: "chest", sets: 22)))
        // Exactly 20 is still fine.
        #expect(!report.flags.contains { if case .tooMuch("quads", _) = $0 { true } else { false } })
    }

    @Test func flagsAJumpOverTheUsualWeek() {
        var log = [work(40, ["lats"], sets: 1)]
        // Four weeks of 6 sets, then 12 this week.
        for week in 1...4 { log.append(work(Double(week * 7) + 1, ["lats"], sets: 6)) }
        log.append(work(2, ["lats"], sets: 6))
        log.append(work(5, ["lats"], sets: 6))
        let report = TrainingLoad.report(log, now: now)
        #expect(report.usualWeek["lats"] == 6)
        #expect(report.flags.contains(.spike(muscle: "lats", sets: 12, usual: 6)))
    }

    @Test func noSpikeBelowProductiveVolume() {
        var log = [work(40, ["calves"], sets: 1)]
        for week in 1...4 { log.append(work(Double(week * 7) + 1, ["calves"], sets: 3)) }
        log.append(work(2, ["calves"], sets: 9))
        #expect(TrainingLoad.report(log, now: now).flags.isEmpty)
    }

    @Test func flagsHardSessionsLessThanTwoDaysApart() {
        let report = TrainingLoad.report([
            work(1, ["quads"], sets: 5),
            work(2, ["quads"], sets: 4),
            // Light work doesn't count as a hard session.
            work(1, ["biceps"], sets: 2),
            work(1.5, ["biceps"], sets: 6),
            // Far enough apart.
            work(1, ["chest"], sets: 5),
            work(4, ["chest"], sets: 5),
        ], now: now)
        #expect(report.flags == [.shortRecovery(muscle: "quads", hours: 24)])
    }

    @Test func comparesBothSidesOfAPair() {
        let pair = BalancePair(name: "Push and pull", first: .init("Push", ["chest", "frontDelts"]), second: .init("Pull", ["lats", "upperBack"]))
        let pushHeavy = TrainingLoad.report([
            work(2, ["chest"], sets: 10),
            work(9, ["chest", "frontDelts"], sets: 5),
            work(9, ["lats"], sets: 5),
        ], now: now, pairs: [pair])
        #expect(pushHeavy.flags == [.imbalance(pair: "Push and pull", more: "Push", less: "Pull", ratio: 4)])

        let even = TrainingLoad.report([work(2, ["chest"], sets: 8), work(4, ["lats"], sets: 6)], now: now, pairs: [pair])
        #expect(even.flags.isEmpty)

        // Too little work to judge.
        let little = TrainingLoad.report([work(2, ["chest"], sets: 9)], now: now, pairs: [pair])
        #expect(little.flags.isEmpty)
    }

    @Test func flagsWatchedMusclesSkippedForThreeWeeks() {
        let log = [
            work(30, ["hamstrings"], sets: 3),
            work(2, ["chest"], sets: 3),
            work(6, ["lats"], sets: 3),
            work(10, ["chest"], sets: 3),
            work(14, ["quads"], sets: 3),
        ]
        let report = TrainingLoad.report(log, now: now, watch: ["chest", "hamstrings", "calves"])
        #expect(report.flags == [.neglected(muscle: "hamstrings", days: 30), .neglected(muscle: "calves", days: nil)])

        // Too few workouts to call anything neglected.
        #expect(TrainingLoad.report(Array(log.prefix(3)), now: now, watch: ["calves"]).flags.isEmpty)
    }

    @Test func mostSeriousFlagsComeFirst() {
        let log = [
            work(2, ["chest"], sets: 12),
            work(3, ["chest"], sets: 12),
            work(5, ["lats"], sets: 1),
            work(6, ["quads"], sets: 1),
        ]
        let report = TrainingLoad.report(log, now: now, watch: ["hamstrings"])
        #expect(report.flags.map(\.severity) == [2, 2, 0])
        #expect(report.flags.first == .tooMuch(muscle: "chest", sets: 24))
    }
}
