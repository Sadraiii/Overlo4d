import Foundation
import Testing
@testable import TallyCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    try! Date(text + "Z", strategy: .iso8601)
}

private func segment(_ start: String, _ end: String, _ stage: SleepStage) -> SleepSegment {
    SleepSegment(start: date(start), end: date(end), stage: stage)
}

private let eightHours: TimeInterval = 8 * 3600

/// `hours` asleep, in bed at 23:00 the evening before `day` (a "2026-10-dd" string).
private func night(_ day: String, hours: Double, bed: String = "23:00") -> SleepNight {
    let wakeDay = date(day + "T00:00:00")
    let parts = bed.split(separator: ":").compactMap { Double($0) }
    var bedtime = wakeDay.addingTimeInterval((parts[0] * 60 + parts[1]) * 60)
    if parts[0] >= 12 { bedtime.addTimeInterval(-86_400) }
    return SleepNight(day: wakeDay, bedtime: bedtime, wake: bedtime.addingTimeInterval(hours * 3600), asleep: hours * 3600)
}

@Suite struct SleepLinksTests {
    @Test func anEveningNapIsKeptOutOfTheNight() throws {
        let nights = SleepAnalysis.nights(from: [
            segment("2026-10-20T19:00:00", "2026-10-20T19:40:00", .asleep),
            segment("2026-10-20T23:00:00", "2026-10-21T07:00:00", .asleep),
        ], calendar: utc)
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.bedtime == date("2026-10-20T23:00:00"))
        #expect(night.asleep == eightHours)
        #expect(night.efficiency == 1)
        #expect(night.naps == [DateInterval(start: date("2026-10-20T19:00:00"), end: date("2026-10-20T19:40:00"))])
    }

    @Test func shortWakingsStayInTheNight() throws {
        let night = try #require(SleepAnalysis.nights(from: [
            segment("2026-10-20T23:00:00", "2026-10-21T02:00:00", .asleep),
            // An hour up with the baby, nothing recorded.
            segment("2026-10-21T03:00:00", "2026-10-21T07:00:00", .asleep),
        ], calendar: utc).first)
        #expect(night.naps.isEmpty)
        #expect(night.asleep == 7 * 3600)
        #expect(night.awake == 3600)
    }

    @Test func tagsLateWorkoutsMealsAndCaffeine() {
        let bed = date("2026-10-20T23:00:00")
        let tags = SleepAutoTags.tags(
            bedtime: bed,
            workouts: [DateInterval(start: date("2026-10-20T19:30:00"), end: date("2026-10-20T20:30:00"))],
            intake: [
                .init(time: date("2026-10-20T21:00:00"), kcal: 350, name: "Pasta"),
                .init(time: date("2026-10-20T22:00:00"), kcal: 200, name: "Chocolate bar"),
                .init(time: date("2026-10-20T16:00:00"), kcal: 5, name: "Flat white"),
            ]
        )
        #expect(tags == [SleepAutoTags.lateWorkout, SleepAutoTags.bigLateMeal, SleepAutoTags.lateCaffeine])

        let none = SleepAutoTags.tags(
            bedtime: bed,
            workouts: [DateInterval(start: date("2026-10-20T17:00:00"), end: date("2026-10-20T19:30:00"))],
            intake: [
                .init(time: date("2026-10-20T13:00:00"), kcal: 5, name: "Espresso"),
                .init(time: date("2026-10-20T21:00:00"), kcal: 300, name: "Decaf coffee"),
            ]
        )
        #expect(none.isEmpty)
    }

    @Test func caffeineMatchesWholeWords() {
        #expect(SleepAutoTags.hasCaffeine("Coca-Cola Zero"))
        #expect(SleepAutoTags.hasCaffeine("Monster Energy, Ultra"))
        #expect(SleepAutoTags.hasCaffeine("Iced latte (oat)"))
        #expect(!SleepAutoTags.hasCaffeine("Chocolate"))
        #expect(!SleepAutoTags.hasCaffeine("Decaf cappuccino"))
        #expect(!SleepAutoTags.hasCaffeine("Herbal tea"))
    }

    @Test func comparesWorkoutsAfterGoodAndShortNights() throws {
        var nights: [SleepNight] = []
        var sessions: [SleepTraining.Session] = []
        // Push day every other day: 5000 kg after 8 h, 4000 kg after 5.5 h.
        for day in stride(from: 1, through: 12, by: 2) {
            let rested = day % 4 == 1
            let key = String(format: "2026-10-%02d", day)
            nights.append(night(key, hours: rested ? 8 : 5.5))
            sessions.append(.init(start: date(key + "T18:00:00"), name: "Push", volume: rested ? 5000 : 4000))
        }
        // A one-off workout name has no usual volume and is ignored.
        sessions.append(.init(start: date("2026-10-03T18:00:00"), name: "Test day", volume: 9000))
        let link = try #require(SleepTraining.link(nights: nights, sessions: sessions, goal: eightHours, calendar: utc))
        #expect(link.restedCount == 3)
        #expect(link.shortCount == 3)
        #expect(abs(link.afterRested - 1.0 / 9) < 0.0001)
        #expect(abs(link.afterShort + 1.0 / 9) < 0.0001)
        #expect(link.difference > 0.2)
        #expect(SleepDigest.percent(link.afterRested) == "+11%")
        #expect(SleepDigest.percent(link.afterShort) == "-11%")
    }

    @Test func noLinkWithoutEnoughWorkouts() {
        let nights = [night("2026-10-01", hours: 8), night("2026-10-02", hours: 5)]
        let sessions = (1...2).map { SleepTraining.Session(start: date("2026-10-0\($0)T18:00:00"), name: "Legs", volume: 3000) }
        #expect(SleepTraining.link(nights: nights, sessions: sessions, goal: eightHours, calendar: utc) == nil)
    }

    @Test func flagsSleepingInAtWeekends() {
        // 2026-10-10 and 11 are a Saturday and Sunday.
        var nights = (5...9).map { night(String(format: "2026-10-%02d", $0), hours: 7.5, bed: "23:00") }
        nights += [night("2026-10-10", hours: 8, bed: "01:30"), night("2026-10-11", hours: 8, bed: "01:00")]
        let report = SleepInsights.report(nights.reversed(), goal: 7.5 * 3600, now: date("2026-10-11T10:00:00"), calendar: utc)
        let shift = report.flags.compactMap { if case .weekendShift(let minutes) = $0 { minutes } else { nil } }.first
        #expect(shift.map { $0 > 120 } == true)

        let steady = (5...11).map { night(String(format: "2026-10-%02d", $0), hours: 7.5) }
        let calm = SleepInsights.report(steady.reversed(), goal: 7.5 * 3600, now: date("2026-10-11T10:00:00"), calendar: utc)
        #expect(!calm.flags.contains { if case .weekendShift = $0 { true } else { false } })
    }

    @Test func digestMentionsNapsAndTheTrainingLink() {
        var withNap = night("2026-10-21", hours: 7)
        withNap.naps = [DateInterval(start: date("2026-10-20T19:00:00"), duration: 1800)]
        let link = SleepTrainingLink(afterRested: 0.06, afterShort: -0.09, restedCount: 5, shortCount: 4)
        let lines = SleepDigest.lines([withNap], goal: eightHours, link: link, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(lines[0].contains("+6% after nights near the goal (5 workouts), -9% after short nights (4 workouts)"))
        #expect(lines[1].contains("plus a nap of 0 h 30 m"))
    }
}
