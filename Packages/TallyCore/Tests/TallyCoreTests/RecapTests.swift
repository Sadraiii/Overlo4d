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

private func session(_ start: String, minutes: Double = 60, volume: Double = 1000, sets: Int = 10, records: Int = 0, best: [UUID: Double] = [:]) -> SessionSummary {
    SessionSummary(start: day(start), duration: minutes * 60, volume: volume, sets: sets, records: records, bestOneRepMax: best)
}

@Suite struct RecapTests {
    @Test func totalsUseStartDateAndExcludeNextMonday() throws {
        let sessions = [
            session("2026-10-12T18:00:00", records: 1),    // Monday, this week
            session("2026-10-18T23:30:00", minutes: 90),  // Sunday late, this week
            session("2026-10-19T00:00:00"),               // next Monday 00:00, next week
            session("2026-10-06T18:00:00", volume: 500),  // previous week
        ]
        let activities = [ActivitySummary(start: day("2026-10-15T07:00:00"), duration: 1800, energy: 300)]
        let recap = try #require(Recaps.recap(weekOf: day("2026-10-14T12:00:00"), sessions: sessions, activities: activities, calendar: calendar))
        #expect(recap.week.start == day("2026-10-12T00:00:00"))
        #expect(recap.totals.workouts == 2)
        #expect(recap.totals.duration == 150 * 60)
        #expect(recap.totals.volume == 2000)
        #expect(recap.totals.sets == 20)
        #expect(recap.totals.records == 1)
        #expect(recap.totals.activities == 1)
        #expect(recap.totals.activityEnergy == 300)
        #expect(recap.previous.workouts == 1)
        #expect(recap.previous.volume == 500)
    }

    @Test func mostImprovedIsLargestGainOverLastEarlierSession() throws {
        let bench = UUID(), squat = UUID(), curl = UUID(), newOne = UUID()
        let sessions = [
            session("2026-10-01T18:00:00", best: [bench: 90, squat: 70]),
            session("2026-10-06T18:00:00", best: [bench: 100, squat: 80, curl: 40]),
            session("2026-10-13T18:00:00", best: [bench: 103, squat: 90, curl: 38, newOne: 60]),
            session("2026-10-15T18:00:00", best: [bench: 105]),
        ]
        let recap = try #require(Recaps.recap(weekOf: day("2026-10-13T12:00:00"), sessions: sessions, activities: [], calendar: calendar))
        // Squat +10 beats bench +5; curl went down; the new exercise has nothing to compare with.
        #expect(recap.mostImproved == Improvement(exerciseID: squat, before: 80, after: 90))
    }

    @Test func noImprovementWithoutEarlierSessions() throws {
        let only = session("2026-10-13T18:00:00", best: [UUID(): 100])
        let recap = try #require(Recaps.recap(weekOf: day("2026-10-13T12:00:00"), sessions: [only], activities: [], calendar: calendar))
        #expect(recap.mostImproved == nil)
    }

    @Test func weeksAreDistinctAndNewestFirst() {
        let sessions = [session("2026-10-06T18:00:00"), session("2026-10-13T18:00:00"), session("2026-10-14T18:00:00")]
        #expect(Recaps.weeks(with: sessions, calendar: calendar) == [day("2026-10-12T00:00:00"), day("2026-10-05T00:00:00")])
    }
}
