import Foundation
import Testing
@testable import TallyCore

@Suite struct OneRepMaxTests {
    @Test func estimate() {
        #expect(OneRepMax.estimate(weight: 100, reps: 1) == 100)
        #expect(abs(OneRepMax.estimate(weight: 100, reps: 3) - 110) < 0.0001)
        #expect(OneRepMax.estimate(weight: 0, reps: 5) == 0)
        #expect(OneRepMax.estimate(weight: 100, reps: 0) == 0)
    }

    @Test func weightForRepsIsTheInverse() {
        let max = OneRepMax.estimate(weight: 80, reps: 8)
        #expect(abs(OneRepMax.weight(forReps: 8, oneRepMax: max) - 80) < 0.0001)
        #expect(OneRepMax.weight(forReps: 1, oneRepMax: 120) == 120)
    }

    @Test func repsAtPercent() {
        #expect(OneRepMax.reps(atPercent: 100) == 1)
        #expect(OneRepMax.reps(atPercent: 90) == 3)
        #expect(OneRepMax.reps(atPercent: 75) == 10)
        #expect(OneRepMax.reps(atPercent: 50) == 30)
    }

    @Test func tableIsRoundedToStep() {
        let table = OneRepMax.table(oneRepMax: 143)
        #expect(table.count == 11)
        #expect(table.first == OneRepMax.Row(percent: 100, weight: 142.5, reps: 1))
        #expect(table.last?.percent == 50)
        #expect(table.allSatisfy { $0.weight.truncatingRemainder(dividingBy: 2.5) == 0 })
    }
}

@Suite struct PlatesTests {
    @Test func loadsHeaviestFirst() {
        let load = Plates.load(target: 140, bar: 20)
        #expect(load.perSide == [25, 25, 10])
        #expect(load.total == 140)
        #expect(load.leftover == 0)
    }

    @Test func smallPlates() {
        #expect(Plates.load(target: 62.5, bar: 20).perSide == [20, 1.25])
    }

    @Test func leftoverWhenNotLoadable() {
        let load = Plates.load(target: 101, bar: 20)
        #expect(load.perSide == [25, 15])
        #expect(abs(load.leftover - 1) < 0.0001)
        #expect(abs(load.total - 100) < 0.0001)
    }

    @Test func belowTheBarIsJustTheBar() {
        let load = Plates.load(target: 10, bar: 20)
        #expect(load.perSide.isEmpty)
        #expect(load.total == 20)
    }

    @Test func customPlates() {
        #expect(Plates.load(target: 60, bar: 20, plates: [10, 5]).perSide == [10, 10])
    }

    @Test func rounding() {
        #expect(Plates.round(57.2) == 57.5)
        #expect(Plates.round(56.1) == 55)
        #expect(Plates.round(57.2, to: 1) == 57)
    }
}

@Suite struct WarmUpTests {
    @Test func barbellRamp() {
        #expect(WarmUp.sets(working: 100) == [
            .init(weight: 20, reps: 10),
            .init(weight: 40, reps: 5),
            .init(weight: 60, reps: 3),
            .init(weight: 80, reps: 2),
        ])
    }

    @Test func lightWorkDropsDuplicates() {
        // 40 % and 60 % of 40 kg round to the bar or below, so only bar and 80 % remain.
        #expect(WarmUp.sets(working: 40) == [
            .init(weight: 20, reps: 10),
            .init(weight: 25, reps: 3),
            .init(weight: 32.5, reps: 2),
        ])
    }

    @Test func noBar() {
        #expect(WarmUp.sets(working: 30, bar: 0, step: 2) == [
            .init(weight: 12, reps: 5),
            .init(weight: 18, reps: 3),
            .init(weight: 24, reps: 2),
        ])
    }

    @Test func nothingAtOrBelowTheBar() {
        #expect(WarmUp.sets(working: 20).isEmpty)
        #expect(WarmUp.sets(working: 0).isEmpty)
    }

    @Test func everyWarmUpIsLighterThanWork() {
        for working in stride(from: 22.5, through: 300, by: 2.5) {
            let sets = WarmUp.sets(working: working)
            #expect(sets.allSatisfy { $0.weight < working })
            #expect(zip(sets, sets.dropFirst()).allSatisfy { $0.weight < $1.weight })
        }
    }
}

@Suite struct RepMaxTests {
    let day1 = Date(timeIntervalSince1970: 0)
    let day2 = Date(timeIntervalSince1970: 86_400)

    @Test func atLeastThatManyReps() {
        let table = RepMax.table([
            .init(weight: 100, reps: 5, date: day1),
            .init(weight: 120, reps: 1, date: day1),
            .init(weight: 80, reps: 10, date: day2),
        ], upTo: 10)
        #expect(table.map(\.weight) == [120, 100, 100, 100, 100, 80, 80, 80, 80, 80])
        #expect(table.map(\.reps) == Array(1...10))
    }

    @Test func tiesKeepTheFirstDate() {
        let table = RepMax.table([
            .init(weight: 100, reps: 3, date: day2),
            .init(weight: 100, reps: 3, date: day1),
        ], upTo: 3)
        #expect(table.allSatisfy { $0.date == day1 })
    }

    @Test func gapsAboveTheHighestReps() {
        let table = RepMax.table([.init(weight: 60, reps: 3, date: day1)], upTo: 10)
        #expect(table.count == 3)
    }

    @Test func ignoresEmptySets() {
        #expect(RepMax.table([.init(weight: 0, reps: 5, date: day1), .init(weight: 50, reps: 0, date: day1)]).isEmpty)
    }
}
