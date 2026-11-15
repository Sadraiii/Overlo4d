import Foundation

/// One copy of all the app's data in a single file, written to a folder in iCloud Drive
/// so a new phone can restore it.
public struct Backup: Codable, Equatable, Sendable {
    /// Bumped when a backup can no longer be read by older versions.
    public static let currentFormat = 1

    public var format: Int
    public var createdAt: Date
    public var appVersion: String
    public var device: String
    /// Data file name ("gym.json") → its contents.
    public var files: [String: Data]

    public init(createdAt: Date, appVersion: String, device: String, files: [String: Data]) {
        format = Self.currentFormat
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.device = device
        self.files = files
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data) else { throw BackupError.unreadable }
        guard backup.format <= currentFormat else { throw BackupError.newerFormat }
        return backup
    }

    /// The files that may be restored: only names the app knows, so a file can't write anywhere else.
    public func restorable(_ known: Set<String>) -> [String: Data] {
        files.filter { known.contains($0.key) }
    }

    /// Changes when any file's contents change, not with the time. Used to skip backups when nothing changed.
    public var fingerprint: String {
        Self.fingerprint(files)
    }

    /// 64-bit FNV-1a over the sorted names and contents.
    public static func fingerprint(_ files: [String: Data]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ bytes: some Sequence<UInt8>) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
        }
        for name in files.keys.sorted() {
            mix(name.utf8)
            mix([0])
            mix(files[name]!)
            mix([0])
        }
        return String(hash, radix: 16)
    }
}

public enum BackupError: Error, Equatable {
    case unreadable
    case newerFormat

    public var message: String {
        switch self {
        case .unreadable: "This file isn't an Overlo4d backup."
        case .newerFormat: "This backup is from a newer version of Overlo4d. Update the app first."
        }
    }
}

/// Backup file names carry the time they were made: "Overlo4d Backup 2026-10-30 112305.json".
public enum BackupName {
    public static let prefix = "Overlo4d Backup "
    /// Names used by earlier versions of the app, still recognised so old backups show up.
    static let legacyPrefixes = ["Overload Backup "]

    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)\(formatter(timeZone).string(from: date)).json"
    }

    /// The time in a backup's name, or nil for other files. Accepts iCloud placeholders
    /// (".Overlo4d Backup ….json.icloud") for backups not downloaded to this phone yet.
    public static func date(of fileName: String, timeZone: TimeZone = .current) -> Date? {
        let name = logicalName(fileName)
        guard let match = ([prefix] + legacyPrefixes).first(where: { name.hasPrefix($0) }), name.hasSuffix(".json") else { return nil }
        let stamp = name.dropFirst(match.count).dropLast(".json".count)
        return formatter(timeZone).date(from: String(stamp))
    }

    /// The real name of a file, without the dot and ".icloud" iCloud adds to files not downloaded yet.
    public static func logicalName(_ fileName: String) -> String {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return fileName }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter
    }
}

/// Which old backups to delete so the folder doesn't grow forever.
public enum BackupRetention {
    /// Keeps the newest `recent` backups, plus the newest one of each day for the last `days` days.
    /// Returns the names of the others.
    public static func toDelete(_ backups: [String: Date], now: Date, recent: Int = 5, days: Int = 30,
                                calendar: Calendar = .current) -> [String] {
        let newestFirst = backups.sorted { $0.value > $1.value }
        var keep = Set(newestFirst.prefix(recent).map(\.key))
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        var seenDays = Set<Date>()
        for (name, date) in newestFirst where date >= cutoff {
            if seenDays.insert(calendar.startOfDay(for: date)).inserted { keep.insert(name) }
        }
        return newestFirst.map(\.key).filter { !keep.contains($0) }
    }
}
