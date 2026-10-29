import Foundation
import Testing
@testable import TallyCore

@Suite struct WorkoutTimesTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func movingTheDayKeepsTimesAndDuration() {
        let times = WorkoutTimes(start: date(20, 18, 5), end: date(20, 19, 20))
        let moved = times.movedToDay(date(14, 9, 0), calendar: calendar)
        #expect(moved.start == date(14, 18, 5))
        #expect(moved.end == date(14, 19, 20))
    }

    @Test func movingTheDayAcrossDaylightSavingKeepsWallClockStart() {
        // Daylight saving ended on 25 October 2026 in Copenhagen.
        let times = WorkoutTimes(start: date(27, 18, 0), end: date(27, 19, 0))
        let moved = times.movedToDay(date(20, 12, 0), calendar: calendar)
        #expect(moved.start == date(20, 18, 0))
        #expect(moved.duration == 3600)
    }

    @Test func changingTheStartKeepsTheDuration() {
        let times = WorkoutTimes(start: date(20, 18, 5), end: date(20, 19, 20))
        let changed = times.withStartTime(date(1, 17, 30), calendar: calendar)
        #expect(changed.start == date(20, 17, 30))
        #expect(changed.end == date(20, 18, 45))
    }

    @Test func changingTheStartOfALiveWorkoutLeavesNoEnd() {
        let changed = WorkoutTimes(start: date(20, 18, 5), end: nil).withStartTime(date(20, 17, 45), calendar: calendar)
        #expect(changed.start == date(20, 17, 45))
        #expect(changed.end == nil)
    }

    @Test func endTimeAfterStartIsTheSameDay() {
        let times = WorkoutTimes(start: date(20, 18, 0), end: date(20, 19, 0))
        #expect(times.withEndTime(date(3, 19, 45), calendar: calendar).end == date(20, 19, 45))
    }

    @Test func endTimeBeforeStartRunsPastMidnight() {
        let times = WorkoutTimes(start: date(20, 23, 15), end: nil)
        let changed = times.withEndTime(date(20, 0, 30), calendar: calendar)
        #expect(changed.end == date(21, 0, 30))
        #expect(changed.duration.map { $0.rounded() } == 4500)
    }

    @Test func durationSetsTheEndWithAMinimumOfOneMinute() {
        let times = WorkoutTimes(start: date(20, 18, 0), end: nil)
        #expect(times.withDuration(5400).end == date(20, 19, 30))
        #expect(times.withDuration(0).duration == 60)
    }

    @Test func liveWorkoutCannotStartInTheFuture() {
        let now = date(20, 18, 0)
        let future = WorkoutTimes(start: date(20, 18, 30), end: nil).clampedForLiveWorkout(now: now)
        #expect(future.start == now)
        let past = WorkoutTimes(start: date(20, 17, 0), end: nil)
        #expect(past.clampedForLiveWorkout(now: now) == past)
    }
}
