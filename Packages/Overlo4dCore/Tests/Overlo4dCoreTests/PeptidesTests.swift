import Foundation
import Testing
@testable import Overlo4dCore

@Suite struct PeptidesTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    // MARK: Calculator

    @Test func concentrationAndPerUnit() {
        // 5 mg in 2 mL: 2.5 mg/mL, 2500 mcg/mL, 25 mcg per unit.
        let math = Reconstitution(vialMg: 5, waterMl: 2, doseMcg: 250)
        #expect(close(math.mgPerMl, 2.5))
        #expect(close(math.mcgPerMl, 2500))
        #expect(close(math.mcgPerUnit, 25))
        #expect(close(math.mcgPerTick, 25))
        #expect(close(math.units, 10))
        #expect(close(math.milliliters, 0.1))
        #expect(!math.isRounded)
        #expect(math.dosesPerVial == 20)
    }

    @Test func unitsMatchTheShortFormula() {
        // units = dose mcg × water mL ÷ (vial mg × 10)
        let math = Reconstitution(vialMg: 10, waterMl: 3, doseMcg: 500)
        #expect(close(math.exactUnits, 500 * 3 / (10 * 10)))
        #expect(close(math.units, 15))
    }

    @Test func roundsToTheNearestMark() {
        // 10 mg in 3 mL: 33.33 mcg per unit; 250 mcg is 7.5 units.
        let whole = Reconstitution(vialMg: 10, waterMl: 3, doseMcg: 250, syringe: .u100)
        #expect(close(whole.exactUnits, 7.5))
        #expect(close(whole.units, 8))
        #expect(whole.isRounded)
        #expect(close(whole.drawnMcg, 8 * 10_000 / 300))

        let half = Reconstitution(vialMg: 10, waterMl: 3, doseMcg: 250, syringe: .u30, halfUnits: true)
        #expect(close(half.tickUnits, 0.5))
        #expect(close(half.units, 7.5))
        #expect(!half.isRounded)
        #expect(close(half.mcgPerTick, half.mcgPerUnit / 2))
    }

    @Test func halfUnitsOnlyOnSmallSyringes() {
        let math = Reconstitution(vialMg: 5, waterMl: 2, doseMcg: 250, syringe: .u100, halfUnits: true)
        #expect(!math.halfUnits)
        #expect(close(math.tickUnits, 1))
        #expect(SyringeSize.u50.allowsHalfUnits && SyringeSize.u30.allowsHalfUnits)
        #expect(close(SyringeSize.u30.milliliters, 0.3))
    }

    @Test func syringeCapacity() {
        // 2 mg in 2 mL: 10 mcg per unit; 400 mcg is 40 units.
        #expect(Reconstitution(vialMg: 2, waterMl: 2, doseMcg: 400, syringe: .u50).fitsSyringe)
        let over = Reconstitution(vialMg: 2, waterMl: 2, doseMcg: 400, syringe: .u30)
        #expect(!over.fitsSyringe)
        #expect(over.syringesNeeded == 2)
        #expect(Reconstitution(vialMg: 2, waterMl: 2, doseMcg: 300, syringe: .u30).fitsSyringe)
    }

    @Test func tinyAndMissingNumbers() {
        // 10 mg in 1 mL: 100 mcg per unit, so 20 mcg is under the first mark.
        let tiny = Reconstitution(vialMg: 10, waterMl: 1, doseMcg: 20)
        #expect(tiny.belowFirstMark)
        #expect(close(tiny.units, 0))

        let empty = Reconstitution(vialMg: 0, waterMl: 2, doseMcg: 250)
        #expect(!empty.hasConcentration && !empty.hasDose)
        #expect(empty.mgPerMl == 0 && empty.units == 0 && empty.dosesPerVial == 0)
        #expect(Reconstitution(vialMg: 5, waterMl: 0, doseMcg: 250).mcgPerUnit == 0)

        let noDose = Reconstitution(vialMg: 5, waterMl: 2, doseMcg: 0)
        #expect(noDose.hasConcentration && !noDose.hasDose)
        #expect(close(noDose.mcgPerUnit, 25))
        #expect(noDose.units == 0 && noDose.dosesPerVial == 0)
    }

    @Test func wholeDosesAreFloored() {
        #expect(Reconstitution(vialMg: 5, waterMl: 2, doseMcg: 300).dosesPerVial == 16)
        // 3 × 0.1 mg must count as 3 despite floating point.
        #expect(Reconstitution.wholeDoses(inMcg: 0.1 * 3 * 1000, doseMcg: 100) == 3)
        #expect(Reconstitution(vialMg: 5, waterMl: 2, doseMcg: 6000).dosesPerVial == 0)
    }

    @Test func milligramTargets() {
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 0.25, doseUnit: .mg)
        #expect(close(profile.doseMcg, 250))
        #expect(close(profile.reconstitution.units, 10))
    }

    // MARK: Schedule

    @Test func scheduleDueToday() {
        let today = DayKey(date(12), calendar: utc) // a Thursday
        let yesterday = today.adding(days: -1, calendar: utc)
        #expect(PeptideSchedule.daily.dueToday(logDays: [], today: today, calendar: utc) == 1)
        #expect(PeptideSchedule.daily.dueToday(logDays: [today], today: today, calendar: utc) == 0)
        #expect(PeptideSchedule.twiceDaily.dueToday(logDays: [today], today: today, calendar: utc) == 1)
        #expect(PeptideSchedule.twiceDaily.dueToday(logDays: [today, today, today], today: today, calendar: utc) == 0)

        #expect(PeptideSchedule.everyOtherDay.dueToday(logDays: [], today: today, calendar: utc) == 1)
        #expect(PeptideSchedule.everyOtherDay.dueToday(logDays: [yesterday], today: today, calendar: utc) == 0)
        #expect(PeptideSchedule.everyOtherDay.dueToday(logDays: [today.adding(days: -2, calendar: utc)], today: today, calendar: utc) == 1)

        #expect(PeptideSchedule.weekly.dueToday(logDays: [today.adding(days: -6, calendar: utc)], today: today, calendar: utc) == 0)
        #expect(PeptideSchedule.weekly.dueToday(logDays: [today.adding(days: -7, calendar: utc)], today: today, calendar: utc) == 1)
        #expect(PeptideSchedule.twiceWeekly.dueToday(logDays: [today.adding(days: -3, calendar: utc)], today: today, calendar: utc) == 1)
        #expect(PeptideSchedule.asNeeded.dueToday(logDays: [], today: today, calendar: utc) == 0)
    }

    @Test func fiveOnTwoOffRestsAtTheWeekend() {
        let friday = DayKey(date(13), calendar: utc)
        let saturday = DayKey(date(14), calendar: utc)
        let monday = DayKey(date(16), calendar: utc)
        #expect(PeptideSchedule.fiveOnTwoOff.dueToday(logDays: [], today: friday, calendar: utc) == 1)
        #expect(PeptideSchedule.fiveOnTwoOff.dueToday(logDays: [], today: saturday, calendar: utc) == 0)
        #expect(PeptideSchedule.fiveOnTwoOff.dueToday(logDays: [], today: monday, calendar: utc) == 1)
    }

    // MARK: Sites

    @Test func siteRotation() {
        let id = UUID()
        func entry(_ site: InjectionSite?, day: Int) -> PeptideLogEntry {
            PeptideLogEntry(date: date(day), peptideID: id, peptideName: "A", amountMcg: 100, units: 4, site: site)
        }
        #expect(InjectionSite.next(after: []) == .abdomenLeft)
        #expect(InjectionSite.next(after: [entry(.abdomenLeft, day: 1), entry(nil, day: 2)]) == .abdomenRight)

        // Everything used once, abdomen right longest ago.
        var logs = InjectionSite.allCases.enumerated().map { entry($1, day: $0 + 2) }
        logs.append(entry(.abdomenLeft, day: 12))
        #expect(InjectionSite.next(after: logs) == .abdomenRight)
        #expect(InjectionSite.next(after: logs, among: []) == nil)
    }

    // MARK: Log and inventory

    @Test func loggingCountsTheVialDown() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "  BPC-157 ", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        #expect(data.profiles[0].name == "BPC-157")
        #expect(data.profiles[0].remainingMg == 5)
        #expect(data.profiles[0].dosesLeft == 20)
        #expect(data.profiles[0].daysLeft == 20)

        let entry = data.log(profile.id, at: date(2), site: .thighLeft, notes: " evening ")
        #expect(entry?.units == 10)
        #expect(entry?.amountMcg == 250)
        #expect(entry?.peptideName == "BPC-157")
        #expect(entry?.notes == "evening")
        #expect(close(data.profiles[0].leftMg, 4.75))
        #expect(data.profiles[0].dosesLeft == 19)
        #expect(data.nextSite() == .abdomenLeft)

        data.log(profile.id, at: date(3), site: .abdomenLeft)
        #expect(data.logs.map(\.date) == [date(3), date(2)])
        #expect(data.dueToday(data.profiles[0], now: date(3, hour: 20), calendar: utc) == 0)
        #expect(data.dueToday(data.profiles[0], now: date(4), calendar: utc) == 1)

        data.deleteLog(entry!.id)
        #expect(close(data.profiles[0].leftMg, 4.75))
        #expect(data.logs.count == 1)
    }

    @Test func roundedDrawIsWhatGetsLogged() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 10, waterMl: 3, dose: 250)
        data.save(profile, now: date(1))
        let entry = data.log(profile.id, at: date(2), site: nil)
        #expect(entry?.units == 8)
        #expect(close(entry?.amountMcg ?? 0, 8 * 10_000 / 300))
        #expect(close(data.profiles[0].leftMg, 10 - 8.0 / 30))
    }

    @Test func vialNeverGoesBelowEmptyAndNewVialRefills() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 1, waterMl: 1, dose: 0.6, doseUnit: .mg)
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(2), site: nil)
        let second = data.log(profile.id, at: date(3), site: nil)
        #expect(data.profiles[0].leftMg == 0)
        #expect(data.profiles[0].dosesLeft == 0)

        data.startNewVial(profile.id, now: date(4))
        #expect(data.profiles[0].leftMg == 1)
        // An entry from the old vial is not given back to the new one.
        data.deleteLog(second!.id)
        #expect(data.profiles[0].leftMg == 1)
    }

    @Test func untrackedProfilesStayFull() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250, tracksVial: false)
        data.save(profile, now: date(1))
        let entry = data.log(profile.id, at: date(2), site: nil)
        #expect(entry?.countedInVial == false)
        #expect(data.profiles[0].leftMg == 5)
    }

    @Test func nothingIsLoggedWithoutNumbers() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 0, dose: 250)
        data.save(profile, now: date(1))
        #expect(data.log(profile.id, at: date(2), site: nil) == nil)
        #expect(data.log(UUID(), at: date(2), site: nil) == nil)
        #expect(data.logs.isEmpty)
    }

    @Test func editingKeepsTheVialUnlessItsSizeChanges() {
        var data = PeptideData()
        var profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(2), site: nil)

        profile = data.profiles[0]
        profile.dose = 500
        data.save(profile, now: date(3))
        #expect(close(data.profiles[0].leftMg, 4.75))
        #expect(data.profiles[0].dosesLeft == 9)

        profile = data.profiles[0]
        profile.vialMg = 10
        data.save(profile, now: date(4))
        #expect(data.profiles[0].leftMg == 10)
        #expect(data.profiles[0].vialOpened == date(4))
    }

    @Test func deletingAProfileKeepsItsHistory() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        let entry = data.log(profile.id, at: date(2), site: nil)
        data.deleteProfile(profile.id)
        #expect(data.profiles.isEmpty)
        #expect(data.logs.first?.peptideName == "A")
        data.deleteLog(entry!.id)
        #expect(data.isEmpty)
    }

    // MARK: Export and import

    @Test func exportRoundTrips() throws {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 0.25, doseUnit: .mg, schedule: .fiveOnTwoOff,
                                     syringe: .u30, halfUnits: true, notes: "fridge")
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(2), site: .gluteRight, notes: "ok")
        let decoded = try PeptideData.decode(try data.encoded())
        #expect(decoded == data)
        #expect(String(decoding: try data.encoded(), as: UTF8.self).contains("2026-11-02T09:00:00Z"))
    }

    @Test func importToleratesMissingAndUnknownFields() throws {
        let json = """
        {"profiles":[{"name":"X","vialMg":5,"waterMl":2,"dose":250,"schedule":"somethingNew","syringe":7}],
         "logs":[{"date":"2026-11-02T09:00:00Z","peptideName":"X","amountMcg":250,"units":10,"site":"elbow"}]}
        """
        let data = try PeptideData.decode(Data(json.utf8))
        #expect(data.version == 1)
        #expect(data.profiles[0].schedule == .daily)
        #expect(data.profiles[0].syringe == .u100)
        #expect(data.profiles[0].tracksVial)
        #expect(data.logs[0].site == nil)
        #expect(throws: (any Error).self) { try PeptideData.decode(Data("[1,2]".utf8)) }
    }

    @Test func mergeMatchesByID() {
        var mine = PeptideData()
        let shared = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        mine.save(shared, now: date(1))
        mine.save(PeptideProfile(name: "Mine", vialMg: 2, waterMl: 1, dose: 100), now: date(1))
        mine.log(shared.id, at: date(2), site: nil)

        var theirs = PeptideData(profiles: [mine.profiles[0]], logs: mine.logs)
        theirs.profiles[0].name = "A renamed"
        theirs.save(PeptideProfile(name: "Theirs", vialMg: 2, waterMl: 1, dose: 100), now: date(1))
        theirs.log(shared.id, at: date(5), site: .armLeft)

        mine.merge(theirs)
        #expect(mine.profiles.map(\.name) == ["A renamed", "Mine", "Theirs"])
        #expect(mine.logs.count == 2)
        #expect(mine.logs.first?.date == date(5))
    }

    // MARK: Formatting

    @Test func formatting() {
        #expect(PeptideFormat.number(2.5) == "2.5")
        #expect(PeptideFormat.number(10) == "10")
        #expect(PeptideFormat.number(33.3333) == "33.33")
        #expect(PeptideFormat.number(0.3333, places: 3) == "0.333")
        #expect(PeptideFormat.number(-0.001) == "0")
        #expect(PeptideFormat.number(.infinity) == "–")
        #expect(PeptideFormat.amount(mcg: 250, unit: .mcg) == "250 mcg")
        #expect(PeptideFormat.amount(mcg: 250, unit: .mg) == "0.25 mg")
        #expect(PeptideFormat.units(1) == "1 unit")
        #expect(PeptideFormat.units(7.5) == "7.5 units")
    }
}

@Suite struct PeptideInsightsTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 9, month: Int = 11) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func key(_ day: Int, month: Int = 11) -> DayKey { DayKey(date(day, month: month), calendar: utc) }

    @Test func cyclePhases() {
        let cycle = PeptideCycle(start: key(2), weeksOn: 2, weeksOff: 1)
        #expect(cycle.phase(on: key(1), calendar: utc) == .notStarted(inDays: 1))
        #expect(cycle.phase(on: key(2), calendar: utc) == .on(week: 1, of: 2, daysLeft: 14))
        #expect(cycle.phase(on: key(9), calendar: utc) == .on(week: 2, of: 2, daysLeft: 7))
        #expect(cycle.phase(on: key(16), calendar: utc) == .off(week: 1, of: 1, daysLeft: 7))
        #expect(cycle.phase(on: key(22), calendar: utc) == .off(week: 1, of: 1, daysLeft: 1))
        #expect(cycle.phase(on: key(23), calendar: utc) == .on(week: 1, of: 2, daysLeft: 14))
        #expect(cycle.phase(on: key(16), calendar: utc).label == "Off, week 1 of 1")

        let once = PeptideCycle(start: key(2), weeksOn: 1)
        #expect(once.phase(on: key(8), calendar: utc).isOn)
        #expect(once.phase(on: key(9), calendar: utc) == .finished)
        #expect(PeptideCycle(start: key(2), weeksOn: 0, weeksOff: -3).weeksOn == 1)
    }

    @Test func nothingDueInAnOffWeek() {
        var data = PeptideData()
        var profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        profile.cycle = PeptideCycle(start: key(2), weeksOn: 1, weeksOff: 1)
        data.save(profile, now: date(1))
        #expect(data.dueToday(data.profiles[0], now: date(3), calendar: utc) == 1)
        #expect(data.dueToday(data.profiles[0], now: date(10), calendar: utc) == 0)
    }

    @Test func spareVialsAndNewProfilesDate() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 1, waterMl: 1, dose: 0.5, doseUnit: .mg, spareVials: 1)
        data.save(profile, now: date(1))
        #expect(data.profiles[0].createdAt == date(1))
        data.log(profile.id, at: date(2), site: nil)
        data.log(profile.id, at: date(3), site: nil)
        #expect(!data.profiles[0].runningLow)
        data.startNewVial(profile.id, now: date(4))
        #expect(data.profiles[0].spareVials == 0)
        #expect(data.profiles[0].leftMg == 1)
        #expect(data.profiles[0].runningLow)
        data.startNewVial(profile.id, now: date(5))
        #expect(data.profiles[0].spareVials == 0)
    }

    @Test func mixedVialAge() {
        var profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250, vialOpened: date(1), keepsDays: 10)
        #expect(profile.mixedDays(now: date(5, hour: 23), calendar: utc) == 4)
        #expect(!profile.pastKeepDays(now: date(10), calendar: utc))
        #expect(profile.pastKeepDays(now: date(11), calendar: utc))
        profile.keepsDays = nil
        #expect(!profile.pastKeepDays(now: date(30), calendar: utc))
    }

    @Test func loggingACustomDraw() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        let entry = data.log(profile.id, at: date(2), site: nil, units: 12, feeling: 9)
        #expect(entry?.units == 12)
        #expect(entry?.amountMcg == 300)
        #expect(entry?.feeling == 5)
        #expect(abs(data.profiles[0].leftMg - 4.7) < 1e-9)
        #expect(data.log(profile.id, at: date(2), site: nil, units: 0) == nil)

        // A draw can be logged without a target, but not without a concentration.
        var bare = PeptideProfile(name: "B", vialMg: 5, waterMl: 2)
        data.save(bare, now: date(1))
        #expect(data.log(bare.id, at: date(2), site: nil) == nil)
        #expect(data.log(bare.id, at: date(2), site: nil, units: 4)?.amountMcg == 100)
        bare = PeptideProfile(name: "C", vialMg: 5)
        data.save(bare, now: date(1))
        #expect(data.log(bare.id, at: date(2), site: nil, units: 4) == nil)
    }

    @Test func feelingIsAveragedAndOldFilesDecode() throws {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(10), site: nil, feeling: 4)
        data.log(profile.id, at: date(11), site: nil, feeling: 2)
        data.log(profile.id, at: date(12), site: nil)
        #expect(data.averageFeeling(profile.id, now: date(13)) == 3)
        #expect(data.averageFeeling(UUID(), now: date(13)) == nil)

        let decoded = try PeptideData.decode(try data.encoded())
        #expect(decoded == data)
        let old = """
        {"profiles":[{"name":"X","vialMg":5,"waterMl":2,"dose":250,"cycle":{"start":"2026-11-02"}}],"logs":[]}
        """
        let parsed = try PeptideData.decode(Data(old.utf8))
        #expect(parsed.profiles[0].spareVials == 0)
        #expect(parsed.profiles[0].cycle?.weeksOn == 1)
        #expect(parsed.profiles[0].createdAt == nil)
    }

    @Test func adherence() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        // Logged on 6 of the 9 full days from the 1st to the 9th.
        for day in [1, 2, 3, 5, 7, 8] { data.log(profile.id, at: date(day), site: nil) }
        let result = data.adherence(data.profiles[0], now: date(10, hour: 8), calendar: utc)
        #expect(result == PeptideAdherence(planned: 9, logged: 6, days: 9))
        #expect(result?.percent == 67)

        // Every other day: planned only when two days have passed since the last entry.
        var other = PeptideProfile(name: "B", vialMg: 5, waterMl: 2, dose: 250, schedule: .everyOtherDay)
        other.createdAt = date(1)
        data.save(other, now: date(1))
        for day in [1, 3, 5] { data.log(other.id, at: date(day), site: nil) }
        #expect(data.adherence(data.profile(other.id)!, now: date(7), calendar: utc) == PeptideAdherence(planned: 3, logged: 3, days: 6))

        // Window is capped, and nothing is counted on the first day.
        #expect(data.adherence(data.profiles[0], days: 3, now: date(10), calendar: utc)?.days == 3)
        #expect(data.adherence(data.profiles[0], now: date(1, hour: 20), calendar: utc) == nil)
        let asNeeded = PeptideProfile(name: "C", schedule: .asNeeded, createdAt: date(1))
        #expect(data.adherence(asNeeded, now: date(10), calendar: utc) == nil)
    }

    @Test func reminders() {
        var data = PeptideData()
        var profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250, schedule: .everyOtherDay)
        data.save(profile, now: date(1))
        #expect(data.reminders(profile, now: date(1), calendar: utc).isEmpty)

        profile = data.profiles[0]
        profile.reminderMinutes = 8 * 60
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(10), site: nil)
        // On the 11th at 07:00: next due the 12th, then every other day.
        let times = data.reminders(data.profiles[0], days: 6, now: date(11, hour: 7), calendar: utc)
        #expect(times == [date(12, hour: 8), date(14, hour: 8), date(16, hour: 8)])

        // Today's time already passed is left out; daily within a cycle skips the off week.
        profile.schedule = .daily
        profile.cycle = PeptideCycle(start: key(9), weeksOn: 1, weeksOff: 1)
        data.save(profile, now: date(1))
        let daily = data.reminders(data.profiles[0], days: 10, now: date(14, hour: 9), calendar: utc)
        #expect(daily == [date(15, hour: 8)] + [date(23, hour: 8)])
    }

    @Test func entriesByDay() {
        var data = PeptideData()
        let profile = PeptideProfile(name: "A", vialMg: 5, waterMl: 2, dose: 250)
        data.save(profile, now: date(1))
        data.log(profile.id, at: date(2, hour: 8), site: nil)
        data.log(profile.id, at: date(2, hour: 20), site: nil)
        data.log(profile.id, at: date(9), site: nil)
        let days = data.entriesByDay(from: key(1), to: key(5), calendar: utc)
        #expect(days.count == 1)
        #expect(days[key(2)]?.count == 2)
    }

    @Test func trainingSummary() {
        let workouts = [key(20, month: 10), key(25, month: 10), key(3), key(5), key(8), key(12)]
        let weights = [WeightPoint(day: key(28, month: 10), kg: 82), WeightPoint(day: key(10), kg: 80.5), WeightPoint(day: key(16), kg: 81)]
        let summary = PeptideTrainingSummary.build(since: key(1), today: key(14), workoutDays: workouts, weights: weights, calendar: utc)
        #expect(summary.days == 14)
        #expect(summary.workouts == 4)
        #expect(summary.perWeek == 2)
        #expect(summary.previousPerWeek == 1)
        #expect(summary.weightStart == 82)
        #expect(summary.weightNow == 80.5)
        #expect(summary.weightChange == -1.5)

        let fresh = PeptideTrainingSummary.build(since: key(1), today: key(3), workoutDays: [key(2)], weights: [], calendar: utc)
        #expect(fresh.previousPerWeek == nil)
        #expect(fresh.perWeek == 1)
        #expect(fresh.weightChange == nil)
    }
}
