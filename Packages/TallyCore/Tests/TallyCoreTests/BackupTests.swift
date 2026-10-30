import Foundation
import Testing
@testable import TallyCore

private let utc = TimeZone(identifier: "UTC")!

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}

private func day(_ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

@Suite struct BackupTests {
    private let sample = Backup(createdAt: Date(timeIntervalSince1970: 1_793_000_000), appVersion: "0.9", device: "iPhone",
                                files: ["gym.json": Data(#"{"workouts":[]}"#.utf8), "food.json": Data("{}".utf8)])

    @Test func roundTrips() throws {
        let decoded = try Backup.decode(sample.encoded())
        #expect(decoded == sample)
        #expect(decoded.format == Backup.currentFormat)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: BackupError.unreadable) { try Backup.decode(Data(#"{"workouts":[]}"#.utf8)) }
        #expect(throws: BackupError.unreadable) { try Backup.decode(Data("not json".utf8)) }
    }

    @Test func rejectsNewerFormat() throws {
        var newer = sample
        newer.format = Backup.currentFormat + 1
        #expect(throws: BackupError.newerFormat) { try Backup.decode(newer.encoded()) }
    }

    @Test func restoresOnlyKnownFiles() {
        var backup = sample
        backup.files["../../evil.json"] = Data("x".utf8)
        #expect(Set(backup.restorable(["gym.json", "food.json", "sleep.json"]).keys) == ["gym.json", "food.json"])
    }

    @Test func fingerprintFollowsContentsNotTime() {
        var later = sample
        later.createdAt = later.createdAt.addingTimeInterval(3600)
        later.device = "Other"
        #expect(later.fingerprint == sample.fingerprint)

        var changed = sample
        changed.files["food.json"] = Data(#"{"water":1}"#.utf8)
        #expect(changed.fingerprint != sample.fingerprint)

        // Moving bytes between files changes it too.
        let a = Backup.fingerprint(["a": Data("xy".utf8), "b": Data()])
        let b = Backup.fingerprint(["a": Data("x".utf8), "b": Data("y".utf8)])
        #expect(a != b)
    }

    @Test func namesCarryTheTime() {
        let date = day(30, 11).addingTimeInterval(23 * 60 + 5)
        let name = BackupName.fileName(for: date, timeZone: utc)
        #expect(name == "Overload Backup 2026-10-30 112305.json")
        #expect(BackupName.date(of: name, timeZone: utc) == date)
        #expect(BackupName.date(of: ".\(name).icloud", timeZone: utc) == date)
        #expect(BackupName.date(of: "gym.json", timeZone: utc) == nil)
        #expect(BackupName.date(of: "Overload Backup notes.json", timeZone: utc) == nil)
        #expect(BackupName.logicalName(".\(name).icloud") == name)
    }

    @Test func retentionKeepsRecentAndOnePerDay() {
        let backups = [
            "a": day(30, 18), "b": day(30, 14), "c": day(30, 9), "d": day(30, 8), "e": day(30, 7),
            "f": day(30, 6), // sixth newest, same day as the five above
            "g": day(29, 20), "h": day(29, 10), // newest of the 29th is kept
            "i": day(1, 12), "j": day(1, 9),
            "old": calendar.date(byAdding: .day, value: -40, to: day(30))!,
        ]
        let deleted = Set(BackupRetention.toDelete(backups, now: day(30, 19), calendar: calendar))
        #expect(deleted == ["f", "h", "j", "old"])
    }

    @Test func retentionKeepsTheNewestEvenWhenOld() {
        let backups = ["a": day(1), "b": day(2)]
        let now = calendar.date(byAdding: .day, value: 90, to: day(2))!
        #expect(BackupRetention.toDelete(backups, now: now, calendar: calendar).isEmpty)
    }
}
