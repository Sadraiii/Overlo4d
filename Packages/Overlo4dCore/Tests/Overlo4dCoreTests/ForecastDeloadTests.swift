import Foundation
import Testing
@testable import Overlo4dCore

@Suite struct StrengthForecastTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let week = 7 * 86_400.0

    /// One session a week, the newest a day before `now`.
    func points(_ values: [Double]) -> [StrengthForecast.Point] {
        values.enumerated().map { index, value in
            StrengthForecast.Point(date: now.addingTimeInterval(-86_400 - Double(values.count - 1 - index) * week), oneRepMax: value)
        }
    }

    @Test func needsEnoughHistory() {
        #expect(StrengthForecast.forecast(points([100, 101, 102]), now: now) == nil)
        // Four sessions inside one week say nothing about a trend.
        let crammed = (0..<4).map { StrengthForecast.Point(date: now.addingTimeInterval(-Double($0) * 86_400), oneRepMax: 100 + Double($0)) }
        #expect(StrengthForecast.forecast(crammed, now: now) == nil)
    }

    @Test func steadyGainIsProjected() throws {
        let result = try #require(StrengthForecast.forecast(points([100, 101, 102, 103, 104, 105, 106, 107]), now: now))
        #expect(abs(result.perWeek - 1) < 0.0001)
        #expect(result.current == 107)
        #expect(result.best == 107)
        #expect(abs(result.inFourWeeks - 111) < 0.0001)
        #expect(abs(result.inTwelveWeeks - 116) < 0.0001)
        #expect(result.trend == .rising)
        #expect(result.confidence == .high)
        #expect(result.sessions == 8)
        #expect(result.milestone.weight == 110)
        let date = try #require(result.milestone.date)
        #expect(abs(date.timeIntervalSince(now) - 3 * week) < 1)
    }

    @Test func fastGainsAreCapped() throws {
        let result = try #require(StrengthForecast.forecast(points([60, 70, 80, 90, 100]), now: now))
        #expect(abs(result.perWeek - 2.5) < 0.0001)
        #expect(abs(result.inFourWeeks - 110) < 0.0001)
    }

    @Test func fallingLiftIsNotProjectedDown() throws {
        let result = try #require(StrengthForecast.forecast(points([110, 108, 106, 104, 102]), now: now))
        #expect(result.trend == .falling)
        #expect(result.perWeek < 0)
        #expect(result.inFourWeeks == result.current)
        #expect(result.best == 110)
        #expect(result.milestone.weight == 115)
        #expect(result.milestone.date == nil)
    }

    @Test func flatLift() throws {
        let result = try #require(StrengthForecast.forecast(points([100, 100, 100, 100]), now: now))
        #expect(result.trend == .flat)
        #expect(result.milestone.weight == 105)
    }

    @Test func oldSessionsOnlyCountForTheBest() throws {
        var all = points([100, 101, 102, 103])
        all.insert(StrengthForecast.Point(date: now.addingTimeInterval(-40 * week), oneRepMax: 120), at: 0)
        let result = try #require(StrengthForecast.forecast(all, now: now))
        #expect(result.sessions == 4)
        #expect(result.best == 120)
        #expect(result.milestone.weight == 125)
    }

    @Test func milestonesInPounds() throws {
        let lb = WeightUnit.lb
        let result = try #require(StrengthForecast.forecast(points([200, 202, 204, 206].map(lb.toKg)), now: now, unit: .lb))
        #expect(abs(lb.fromKg(result.milestone.weight) - 210) < 0.01)
    }

    @Test func targetsBeatTheRecord() {
        let targets = StrengthForecast.targets(toBeat: 100)
        #expect(targets.map(\.reps) == [1, 3, 5, 8])
        #expect(targets.map(\.weight) == [102.5, 92.5, 87.5, 80])
        for target in targets {
            #expect(OneRepMax.estimate(weight: target.weight, reps: target.reps) > 100)
            #expect(OneRepMax.estimate(weight: target.weight - 2.5, reps: target.reps) <= 100.0001)
        }
        #expect(StrengthForecast.targets(toBeat: 0).isEmpty)
    }
}

@Suite struct DeloadTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func weeks(_ sets: [Int], sessions: Int = 3) -> [Deload.Week] {
        sets.enumerated().map { index, count in
            Deload.Week(start: start.addingTimeInterval(Double(index) * 7 * 86_400), sessions: count == 0 ? 0 : sessions, hardSets: count)
        }
    }

    @Test func countsHardWeeksBackFromNow() {
        #expect(Deload.hardWeeks(weeks([60, 60, 60, 60]), lastDeload: nil) == 4)
        // An easy week in the middle ends the run.
        #expect(Deload.hardWeeks(weeks([60, 60, 20, 60, 60]), lastDeload: nil) == 2)
        #expect(Deload.hardWeeks(weeks([60, 0, 60]), lastDeload: nil) == 1)
        // The current week has only just started.
        #expect(Deload.hardWeeks(weeks([60, 60, 60, 10]), lastDeload: nil) == 3)
        #expect(Deload.hardWeeks([], lastDeload: nil) == 0)
    }

    @Test func deloadInTheAppEndsTheRun() {
        let all = weeks([60, 60, 60, 60, 60, 60])
        #expect(Deload.hardWeeks(all, lastDeload: all[3].start.addingTimeInterval(3600)) == 2)
    }

    @Test func oneSessionWeeksAreNotHard() {
        #expect(Deload.hardWeeks(weeks([60, 60, 60], sessions: 1), lastDeload: nil) == 0)
    }

    @Test func eightHardWeeksIsDue() throws {
        let advice = try #require(Deload.assess(weeks: weeks(Array(repeating: 60, count: 8)), lifts: [], averageRPE: nil))
        #expect(advice.level == .due)
        #expect(advice.hardWeeks == 8)
        #expect(advice.reasons.count == 1)
    }

    @Test func fiveHardWeeksAloneIsFine() {
        #expect(Deload.assess(weeks: weeks(Array(repeating: 60, count: 5)), lifts: [], averageRPE: 8) == nil)
    }

    @Test func fiveWeeksAndASlippingLiftIsWorthConsidering() throws {
        let squat = Deload.Lift(name: "Squat", recent: [140, 142, 136, 135])
        let advice = try #require(Deload.assess(weeks: weeks(Array(repeating: 60, count: 5)), lifts: [squat], averageRPE: nil))
        #expect(advice.level == .consider)
        #expect(advice.slipping == ["Squat"])
    }

    @Test func slippingLiftsAndHighEffortAreDue() throws {
        let lifts = [
            Deload.Lift(name: "Squat", recent: [140, 142, 136, 135]),
            Deload.Lift(name: "Bench Press", recent: [100, 100, 96, 95]),
            Deload.Lift(name: "Row", recent: [80, 81, 82, 83]),
        ]
        let advice = try #require(Deload.assess(weeks: weeks([60, 60, 60, 60]), lifts: lifts, averageRPE: 9.4))
        #expect(advice.level == .due)
        #expect(advice.slipping == ["Squat", "Bench Press"])
        #expect(advice.reasons.count == 2)
    }

    @Test func newLiftersAreLeftAlone() {
        let lifts = [Deload.Lift(name: "Squat", recent: [140, 142, 136, 135]), Deload.Lift(name: "Bench", recent: [100, 100, 96, 95])]
        #expect(Deload.assess(weeks: weeks([60, 60]), lifts: lifts, averageRPE: 9.5) == nil)
    }

    @Test func slippingNeedsTwoLowSessions() {
        #expect(Deload.isSlipping(.init(name: "A", recent: [100, 102, 97, 98])))
        #expect(!Deload.isSlipping(.init(name: "A", recent: [100, 102, 97, 101])))
        #expect(!Deload.isSlipping(.init(name: "A", recent: [100, 97, 96])))
    }

    @Test func easierWeek() {
        #expect([1, 2, 3, 4, 5, 6].map(Deload.sets) == [1, 2, 2, 3, 3, 4])
        #expect(Deload.weight(100, step: 2.5) == 90)
        #expect(Deload.weight(62.5, step: 2.5) == 57.5)
        #expect(Deload.weight(10, step: 2) == 8)
        #expect(Deload.weight(2, step: 2) == 2)
        #expect(Deload.weight(0, step: 2.5) == 0)
    }

    @Test func runsForAWeek() {
        #expect(!Deload.isActive(start: nil, now: start))
        #expect(Deload.isActive(start: start, now: start.addingTimeInterval(6 * 86_400)))
        #expect(!Deload.isActive(start: start, now: start.addingTimeInterval(7 * 86_400)))
        #expect(Deload.daysLeft(start: start, now: start) == 7)
        #expect(Deload.daysLeft(start: start, now: start.addingTimeInterval(6.5 * 86_400)) == 1)
        #expect(Deload.daysLeft(start: start, now: start.addingTimeInterval(9 * 86_400)) == 0)
    }
}

@Suite struct WorkoutRemindersTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Wednesday 15 November 2023, 12:00 UTC.
    let noon = Date(timeIntervalSince1970: 1_700_049_600)

    @Test func daysEncodeAndDecode() {
        #expect(WorkoutReminders.encode([6, 2, 4]) == "2,4,6")
        #expect(WorkoutReminders.decode("2, 4,6,9,x") == [2, 4, 6])
        #expect(WorkoutReminders.decode("").isEmpty)
    }

    @Test func upcomingFallsOnTheChosenDays() {
        // Monday, Wednesday and Friday at 18:00.
        let settings = WorkoutReminders.Settings(days: [2, 4, 6], minutes: 18 * 60)
        let dates = WorkoutReminders.upcoming(settings, now: noon, trainedToday: false, horizonDays: 7, calendar: calendar)
        #expect(dates.count == 3)
        #expect(dates.map { calendar.component(.weekday, from: $0) } == [4, 6, 2])
        #expect(dates.allSatisfy { calendar.component(.hour, from: $0) == 18 && $0 > noon })
        #expect(dates.first == noon.addingTimeInterval(6 * 3600))
    }

    @Test func todayIsSkippedOnceTrainedOrPast() {
        let evening = WorkoutReminders.Settings(days: [4], minutes: 18 * 60)
        #expect(WorkoutReminders.upcoming(evening, now: noon, trainedToday: true, horizonDays: 7, calendar: calendar).isEmpty)
        let morning = WorkoutReminders.Settings(days: [4], minutes: 7 * 60)
        #expect(WorkoutReminders.upcoming(morning, now: noon, trainedToday: false, horizonDays: 7, calendar: calendar).isEmpty)
        #expect(WorkoutReminders.upcoming(morning, now: noon, trainedToday: false, horizonDays: 8, calendar: calendar).count == 1)
    }

    @Test func noDaysNoReminders() {
        #expect(WorkoutReminders.upcoming(.init(days: [], minutes: 600), now: noon, trainedToday: false, calendar: calendar).isEmpty)
    }

    @Test func nudgeComesAfterABreak() throws {
        let settings = WorkoutReminders.Settings(days: [], minutes: 18 * 60, nudgeAfterDays: 3)
        let last = noon.addingTimeInterval(-86_400)
        let nudge = try #require(WorkoutReminders.nudge(settings, lastWorkout: last, now: noon, calendar: calendar))
        // Tuesday + 3 days = Friday 18:00.
        #expect(calendar.component(.weekday, from: nudge) == 6)
        #expect(calendar.component(.hour, from: nudge) == 18)
    }

    @Test func overdueNudgeComesAtTheNextReminderTime() throws {
        let settings = WorkoutReminders.Settings(days: [], minutes: 18 * 60, nudgeAfterDays: 3)
        let longAgo = noon.addingTimeInterval(-30 * 86_400)
        #expect(WorkoutReminders.nudge(settings, lastWorkout: longAgo, now: noon, calendar: calendar) == noon.addingTimeInterval(6 * 3600))
        let late = noon.addingTimeInterval(8 * 3600)
        #expect(WorkoutReminders.nudge(settings, lastWorkout: longAgo, now: late, calendar: calendar) == noon.addingTimeInterval(30 * 3600))
        #expect(WorkoutReminders.nudge(settings, lastWorkout: nil, now: noon, calendar: calendar) == nil)
        #expect(WorkoutReminders.nudge(.init(days: [2], minutes: 600), lastWorkout: longAgo, now: noon, calendar: calendar) == nil)
    }

    @Test func summaryStartsOnTheFirstWeekday() {
        #expect(WorkoutReminders.summary([], calendar: calendar) == "Off")
        #expect(WorkoutReminders.summary([1, 2, 3, 4, 5, 6, 7], calendar: calendar) == "Every day")
        #expect(WorkoutReminders.summary([1, 2, 4], calendar: calendar) == "Mon, Wed, Sun")
    }
}
