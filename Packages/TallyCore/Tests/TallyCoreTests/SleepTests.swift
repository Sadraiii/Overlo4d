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

/// A plain night of `hours` asleep from `bed` on the evening before `day`.
private func night(_ day: String, bed: String = "23:00", hours: Double, tags: [String] = [], quality: Int? = nil) -> SleepNight {
    let wakeDay = date(day + "T00:00:00")
    let parts = bed.split(separator: ":").compactMap { Double($0) }
    var bedtime = wakeDay.addingTimeInterval((parts[0] * 60 + parts[1]) * 60)
    if parts[0] >= 12 { bedtime.addTimeInterval(-86_400) }
    let asleep = hours * 3600
    return SleepNight(
        day: wakeDay, bedtime: bedtime, wake: bedtime.addingTimeInterval(asleep + 600),
        asleep: asleep, awake: 600, quality: quality, tags: tags
    )
}

@Suite struct SleepTests {
    @Test func nightsBelongToTheDayYouWakeUp() {
        #expect(SleepAnalysis.day(for: date("2026-10-20T23:30:00"), calendar: utc) == date("2026-10-21T00:00:00"))
        #expect(SleepAnalysis.day(for: date("2026-10-21T01:30:00"), calendar: utc) == date("2026-10-21T00:00:00"))
        #expect(SleepAnalysis.day(for: date("2026-10-20T18:00:00"), calendar: utc) == date("2026-10-21T00:00:00"))
        // An afternoon nap counts towards the night that ended that morning.
        #expect(SleepAnalysis.day(for: date("2026-10-21T14:00:00"), calendar: utc) == date("2026-10-21T00:00:00"))
    }

    @Test func mergesAPhoneAndAWatchWithoutCountingTwice() throws {
        let nights = SleepAnalysis.nights(from: [
            // The phone's broad record.
            segment("2026-10-20T23:00:00", "2026-10-21T07:00:00", .inBed),
            segment("2026-10-20T23:15:00", "2026-10-21T06:45:00", .asleep),
            // The Watch's stages inside it.
            segment("2026-10-20T23:20:00", "2026-10-21T01:00:00", .core),
            segment("2026-10-21T01:00:00", "2026-10-21T02:00:00", .deep),
            segment("2026-10-21T02:00:00", "2026-10-21T02:30:00", .awake),
            segment("2026-10-21T02:30:00", "2026-10-21T04:00:00", .rem),
            segment("2026-10-21T04:00:00", "2026-10-21T06:40:00", .core),
        ], calendar: utc)
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.day == date("2026-10-21T00:00:00"))
        #expect(night.bedtime == date("2026-10-20T23:00:00"))
        #expect(night.wake == date("2026-10-21T07:00:00"))
        #expect(night.deep.map { abs($0 - 3600) < 0.001 } == true)
        #expect(night.rem.map { abs($0 - 5400) < 0.001 } == true)
        // Asleep 23:15-06:45 (7.5 h) minus the Watch's 30 min awake.
        #expect(abs(night.asleep - 7 * 3600) < 0.001)
        #expect(abs(night.awake - 3600) < 0.001)
        #expect(night.efficiency.map { abs($0 - 7.0 / 8.0) < 0.0001 } == true)
        // Merged segments never overlap.
        for (a, b) in zip(night.segments, night.segments.dropFirst()) {
            #expect(a.end <= b.start)
        }
    }

    @Test func inBedAloneIsNotANight() {
        let nights = SleepAnalysis.nights(from: [segment("2026-10-20T23:00:00", "2026-10-21T07:00:00", .inBed)], calendar: utc)
        #expect(nights.isEmpty)
    }

    @Test func handLoggedNightReplacesHealthForTheSameDay() throws {
        let health = SleepAnalysis.nights(from: [segment("2026-10-20T23:00:00", "2026-10-21T06:00:00", .asleep)], calendar: utc)
        let log = ManualSleep(bedtime: date("2026-10-20T22:30:00"), wake: date("2026-10-21T06:30:00"), awakeMinutes: 20, quality: 4, tags: ["Reading"])
        let combined = SleepAnalysis.combine(health: health, manual: [log], calendar: utc)
        let night = try #require(combined.first)
        #expect(combined.count == 1)
        #expect(night.isManual)
        #expect(night.asleep == 8 * 3600 - 20 * 60)
        #expect(night.efficiency == nil)
        #expect(night.tags == ["Reading"])

        // A night recorded with the buttons gives way to Health's.
        var tapped = log
        tapped.tapped = true
        let withTapped = SleepAnalysis.combine(health: health, manual: [tapped], calendar: utc)
        #expect(withTapped.first?.isManual == false)
        #expect(SleepAnalysis.combine(health: [], manual: [tapped], calendar: utc).first?.isManual == true)
    }

    @Test func scoresAFullNightHighAndAShortOneLow() {
        let good = night("2026-10-21", hours: 8)
        let short = night("2026-10-21", hours: 4)
        let goodScore = SleepScore.score(good, goal: eightHours, calendar: utc)
        let shortScore = SleepScore.score(short, goal: eightHours, calendar: utc)
        #expect(goodScore >= 90)
        #expect(shortScore < 70)
        #expect(SleepScore.parts(good, goal: eightHours, calendar: utc).duration == 50)
    }

    @Test func lateBedtimeLosesTimingPoints() {
        let usual = SleepClock.bedtimeMinutes(date("2026-10-20T23:00:00"), calendar: utc)
        let onTime = SleepScore.parts(night("2026-10-21", bed: "23:20", hours: 8), goal: eightHours, usualBedtime: usual, calendar: utc)
        let late = SleepScore.parts(night("2026-10-21", bed: "01:30", hours: 8), goal: eightHours, usualBedtime: usual, calendar: utc)
        #expect(onTime.timing == 15)
        #expect(late.timing == 0)
    }

    @Test func clockMathAcrossMidnight() {
        #expect(SleepClock.bedtimeMinutes(date("2026-10-20T22:00:00"), calendar: utc) == 600)
        #expect(SleepClock.bedtimeMinutes(date("2026-10-21T01:30:00"), calendar: utc) == 810)
        #expect(SleepClock.timeOfDay(bedtimeMinutes: 810) == (1, 30))
        // Up at 06:30 with an 8 h goal: in bed by 22:15.
        #expect(SleepClock.bedtime(forWake: 390, goal: eightHours) == 22 * 60 + 15)
        #expect(SleepClock.bedtime(forWake: 600, goal: eightHours, latency: 0) == 120)
    }

    @Test func flagsShortSleepAndDebt() {
        let nights = (15...21).map { night("2026-10-\($0)", hours: 6) }
        let report = SleepInsights.report(nights, goal: eightHours, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(report.week.count == 7)
        #expect(report.averageAsleep.map { abs($0 - 6 * 3600) < 0.001 } == true)
        #expect(report.debtHours == 14)
        #expect(report.flags.contains(.short(average: 6 * 3600, goal: eightHours)))
        #expect(report.flags.contains(.debt(hours: 14)))
        #expect(report.readiness == .easy)
    }

    @Test func flagsIrregularAndLateBedtimes() {
        let beds = ["23:00", "01:30", "00:00", "02:30", "23:30", "01:00", "02:00"]
        let nights = beds.enumerated().map { night("2026-10-\(15 + $0.offset)", bed: $0.element, hours: 7.5) }
        let report = SleepInsights.report(nights, goal: 7.5 * 3600, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(report.flags.contains { if case .irregular = $0 { true } else { false } })
        #expect(report.flags.contains { if case .lateBedtime = $0 { true } else { false } })
        #expect(!report.flags.contains { if case .short = $0 { true } else { false } })
        #expect(report.readiness == .ready)
    }

    @Test func readinessNeedsLastNight() {
        let nights = [night("2026-10-20", hours: 4)]
        let report = SleepInsights.report(nights, goal: eightHours, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(report.readiness == nil)
        let today = SleepInsights.report([night("2026-10-21", hours: 4)], goal: eightHours, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(today.readiness == .recover)
    }

    @Test func findsTagsThatHurtSleep() throws {
        var nights: [SleepNight] = []
        for day in 1...8 {
            let caffeine = day.isMultiple(of: 2)
            nights.append(night(String(format: "2026-10-%02d", day), hours: caffeine ? 5.5 : 8, tags: caffeine ? ["Late caffeine", "Reading"] : ["Reading"]))
        }
        let report = SleepInsights.report(nights.reversed(), goal: eightHours, now: date("2026-10-08T09:00:00"), calendar: utc)
        let effect = try #require(report.tagEffects.first)
        #expect(report.tagEffects.count == 1)
        #expect(effect.tag == "Late caffeine")
        #expect(effect.scoreChange < -10)
        #expect(effect.durationChange == -2.5 * 3600)
        #expect(effect.nights == 4)
    }

    @Test func digestForTheCoach() {
        let nights = [
            night("2026-10-21", bed: "23:40", hours: 6.5, tags: ["Late workout"], quality: 3),
            night("2026-10-20", bed: "23:00", hours: 8),
        ]
        let lines = SleepDigest.lines(nights, goal: eightHours, now: date("2026-10-21T09:00:00"), calendar: utc)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Goal 8 h 00 m asleep. Last 7 nights: average 7 h 15 m, 1.5 h short"))
        #expect(lines[1].hasPrefix("Wed, Oct 21: in bed 23:40 to 06:20, asleep 6 h 30 m, score "))
        #expect(lines[1].hasSuffix("felt 3/5, tags: Late workout"))
        #expect(SleepDigest.lines([], goal: eightHours).isEmpty)
    }

    @Test func coachSleepRequestUsesTheSleepPromptAndSchema() throws {
        let data = try CoachAPI.body(model: .haiku, prompt: "x", sleep: true)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["system"] as? String)?.contains("sleep coach") == true)
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let next = try #require(properties["next_session"] as? [String: Any])
        #expect(next["description"] as? String == "The plan for tonight, in one or two sentences.")
        // The training request is unchanged.
        let training = try #require(try JSONSerialization.jsonObject(with: CoachAPI.body(model: .haiku, prompt: "x")) as? [String: Any])
        #expect((training["system"] as? String)?.contains("sleep coach") == false)
    }

    @Test func coachPromptIncludesSleep() {
        let text = CoachAPI.prompt(
            focus: .sleep, goal: "", workouts: [], load: [], weekly: [],
            sleep: ["Goal 8 h asleep.", "Tue, Oct 21: asleep 6 h"],
            now: date("2026-10-21T08:00:00"), calendar: utc
        )
        #expect(text.hasPrefix("Review my sleep over the last two weeks"))
        #expect(text.contains("Sleep, newest first:\n- Goal 8 h asleep.\n- Tue, Oct 21: asleep 6 h"))
        let without = CoachAPI.prompt(focus: .overall, goal: "", workouts: [], load: [], weekly: [], now: date("2026-10-21T08:00:00"), calendar: utc)
        #expect(!without.contains("Sleep"))
    }
}
