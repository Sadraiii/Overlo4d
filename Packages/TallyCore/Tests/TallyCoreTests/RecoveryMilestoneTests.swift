import Foundation
import Testing
@testable import TallyCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2  // Monday
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ text: String) -> Date {
    try! Date(text + "Z", strategy: .iso8601)
}

@Suite struct RecoveryTests {
    @Test func hoursScaleWithSetsWithinLimits() {
        #expect(Recovery.hoursNeeded(sets: 0) == 24)
        #expect(Recovery.hoursNeeded(sets: 4) == 48)
        #expect(Recovery.hoursNeeded(sets: 20) == 72)
    }

    @Test func progressAndReadyTime() throws {
        let loads = [Recovery.Load(muscle: "chest", date: day("2026-11-02T18:00:00"), sets: 4)]
        let status = try #require(Recovery.status(loads: loads, now: day("2026-11-03T18:00:00"))["chest"])
        #expect(status.readyAt == day("2026-11-04T18:00:00"))
        #expect(abs(status.progress - 0.5) < 0.0001)
        #expect(!status.isReady)
        let later = try #require(Recovery.status(loads: loads, now: day("2026-11-05T09:00:00"))["chest"])
        #expect(later.isReady)
    }

    @Test func sessionsCloseTogetherAddUp() throws {
        let loads = [
            Recovery.Load(muscle: "quads", date: day("2026-11-02T08:00:00"), sets: 3),
            Recovery.Load(muscle: "quads", date: day("2026-11-02T18:00:00"), sets: 3),
        ]
        let status = try #require(Recovery.status(loads: loads, now: day("2026-11-02T20:00:00"))["quads"])
        // 6 sets → 60 h from the evening session.
        #expect(status.readyAt == day("2026-11-05T06:00:00"))
        #expect(status.lastTrained == day("2026-11-02T18:00:00"))
    }

    @Test func oldAndFutureLoadsAreIgnored() {
        let loads = [
            Recovery.Load(muscle: "lats", date: day("2026-10-20T18:00:00"), sets: 5),
            Recovery.Load(muscle: "abs", date: day("2026-11-10T18:00:00"), sets: 5),
        ]
        #expect(Recovery.status(loads: loads, now: day("2026-11-03T12:00:00")).isEmpty)
    }
}

@Suite struct MilestoneTests {
    @Test func levelsAndProgress() {
        let m = Milestones.milestone(.workouts, MilestoneStats(workouts: 30))
        #expect(m.level == 3)
        #expect(m.reached == 25)
        #expect(m.next == 50)
        #expect(abs(m.progress - 0.2) < 0.0001)
    }

    @Test func noLevelYetAndAllLevels() {
        let none = Milestones.milestone(.records, MilestoneStats())
        #expect(none.level == 0)
        #expect(none.reached == nil)
        #expect(none.next == 1)
        let all = Milestones.milestone(.streak, MilestoneStats(bestStreak: 200))
        #expect(all.level == all.maxLevel)
        #expect(all.next == nil)
        #expect(all.progress == 1)
    }

    @Test func newlyReachedOnlyListsLevelUps() {
        let before = MilestoneStats(workouts: 9, volume: 9_000)
        let after = MilestoneStats(workouts: 10, volume: 9_500)
        #expect(Milestones.newlyReached(before: before, after: after).map(\.kind) == [.workouts])
    }

    @Test func longestWeekRun() {
        let dates = [
            "2026-09-01T10:00:00", "2026-09-09T10:00:00", "2026-09-10T10:00:00", "2026-09-16T10:00:00",  // 3 weeks
            "2026-10-05T10:00:00", "2026-10-13T10:00:00",  // 2 weeks
        ].map(day)
        #expect(Streaks.longestWeekRun(dates, calendar: calendar) == 3)
        #expect(Streaks.longestWeekRun([], calendar: calendar) == 0)
    }

    @Test func gridColumnsEndInTheWeekOfTheEndDate() throws {
        let columns = ActivityGrid.columns(ending: day("2026-11-05T12:00:00"), weeks: 3, calendar: calendar)
        #expect(columns.count == 3)
        #expect(columns.allSatisfy { $0.count == 7 })
        #expect(columns.last?.first == day("2026-11-02T00:00:00"))
        #expect(columns.first?.first == day("2026-10-19T00:00:00"))
        let counts = ActivityGrid.counts([day("2026-11-02T08:00:00"), day("2026-11-02T19:00:00")], calendar: calendar)
        #expect(counts[day("2026-11-02T00:00:00")] == 2)
    }
}
