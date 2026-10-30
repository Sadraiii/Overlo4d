import Foundation
import Observation
import TallyCore
import TallyKit
import UIKit

/// Backs up every data file to a folder the user picks, usually in iCloud Drive, and restores from it.
/// A folder bookmark works with any Apple ID, unlike an iCloud container, which needs a paid developer account.
@MainActor
@Observable
final class BackupStore {
    /// A backup found in the folder.
    struct Entry: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let date: Date
        /// Still only in iCloud, not downloaded to this phone yet. Restoring downloads it.
        let inCloud: Bool
    }

    /// Where backups go, nil until a folder is chosen.
    private(set) var folderName: String?
    private(set) var lastBackup: Date?
    private(set) var backups: [Entry] = []
    /// The last thing that went wrong, shown under the backup controls.
    private(set) var problem: String?

    var autoBackup: Bool = UserDefaults.standard.object(forKey: Keys.auto) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoBackup, forKey: Keys.auto) }
    }

    private enum Keys {
        static let bookmark = "backup.folderBookmark"
        static let auto = "backup.auto"
        static let last = "backup.last"
        static let fingerprint = "backup.fingerprint"
    }

    /// Data files kept in Documents.
    private static let documentFiles = ["gym.json", "food.json", "sleep.json", "programs.json", "coach.json", "coach-chat.json"]
    /// Data files kept in the App Group, shared with the widgets.
    private static let sharedFiles = [SharedStorage.repsFile]
    private static let settingsFile = "settings.json"

    /// Settings that belong to the user rather than this phone. Health access and API keys are set up again on a new phone.
    private static let settingsKeys = [
        "defaultRestSeconds", "rest.autoStart", "recap.dismissedWeek", "changelog.seenVersion",
        "coach.goal", "coach.model",
        "sleep.goalHours", "sleep.wakeMinutes", "sleep.reminders", "sleep.windDownMinutes", "sleep.morningCheckIn", "sleep.caffeineCutoff",
        "clock.mode", "clock.work", "clock.rest", "clock.rounds", "clock.countdown", "clock.minutes",
    ]
    private static let sharedSettingsKeys = [Accent.storageKey, AppearanceMode.storageKey]

    private static var knownFiles: Set<String> { Set(documentFiles + sharedFiles + [settingsFile]) }

    private static func location(of file: String) -> URL {
        sharedFiles.contains(file) ? SharedStorage.url(for: file) : URL.documentsDirectory.appending(path: file)
    }

    init() {
        lastBackup = UserDefaults.standard.object(forKey: Keys.last) as? Date
        if let folder = resolveFolder() {
            folderName = folder.lastPathComponent
            refreshList()
        }
    }

    var isSetUp: Bool { folderName != nil }

    // MARK: Folder

    func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Keys.bookmark)
            folderName = url.lastPathComponent
            problem = nil
        } catch {
            problem = "Couldn't use that folder. Pick a folder in iCloud Drive or On My iPhone."
            return
        }
        refreshList()
        if backups.isEmpty {
            backUpNow()
        } else {
            // A new phone picking the old phone's folder: don't add a backup of the still-empty app on the way out.
            UserDefaults.standard.set(snapshot().fingerprint, forKey: Keys.fingerprint)
        }
    }

    func forgetFolder() {
        UserDefaults.standard.removeObject(forKey: Keys.bookmark)
        UserDefaults.standard.removeObject(forKey: Keys.fingerprint)
        folderName = nil
        backups = []
        problem = nil
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.bookmark) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Keys.bookmark)
        }
        return url
    }

    /// Runs `body` with access to the backup folder.
    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let folder = resolveFolder() else { throw Failure("Choose a backup folder first.") }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    func refreshList() {
        do {
            backups = try withFolder { folder in
                let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                return names.compactMap { name in
                    BackupName.date(of: name).map {
                        Entry(name: BackupName.logicalName(name), date: $0, inCloud: name != BackupName.logicalName(name))
                    }
                }
                .sorted { $0.date > $1.date }
            }
        } catch {
            backups = []
            problem = "Couldn't open the backup folder. Choose it again."
        }
    }

    // MARK: Backing up

    /// Collects the data files and settings as they are on disk now. The stores save on every change.
    private func snapshot() -> Backup {
        var files: [String: Data] = [:]
        for file in Self.documentFiles + Self.sharedFiles {
            if let data = try? Data(contentsOf: Self.location(of: file)) { files[file] = data }
        }
        var settings: [String: Any] = [:]
        for key in Self.settingsKeys {
            if let value = UserDefaults.standard.object(forKey: key) { settings[key] = value }
        }
        for key in Self.sharedSettingsKeys {
            if let value = SharedStorage.defaults.object(forKey: key) { settings[key] = value }
        }
        if JSONSerialization.isValidJSONObject(settings),
           let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]) {
            files[Self.settingsFile] = data
        }
        return Backup(createdAt: .now, appVersion: AppVersion.number, device: UIDevice.current.name, files: files)
    }

    /// Called when the app goes to the background. Skips it when nothing changed since the last backup.
    func backUpIfChanged() {
        guard autoBackup, isSetUp else { return }
        let backup = snapshot()
        guard backup.fingerprint != UserDefaults.standard.string(forKey: Keys.fingerprint) else { return }
        // Finish writing even if the app is suspended right after.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Backup")
        write(backup)
        UIApplication.shared.endBackgroundTask(task)
    }

    func backUpNow() {
        write(snapshot())
    }

    private func write(_ backup: Backup) {
        do {
            let data = try backup.encoded()
            try withFolder { folder in
                try coordinatedWrite(data, to: folder.appending(path: BackupName.fileName(for: backup.createdAt)))
                prune(in: folder)
            }
            lastBackup = backup.createdAt
            UserDefaults.standard.set(backup.createdAt, forKey: Keys.last)
            UserDefaults.standard.set(backup.fingerprint, forKey: Keys.fingerprint)
            problem = nil
        } catch let failure as Failure {
            problem = failure.message
        } catch {
            problem = "Couldn't save the backup. Check there's space in iCloud Drive, or choose the folder again."
        }
        refreshList()
    }

    private func prune(in folder: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        var dated: [String: Date] = [:]
        for name in names {
            if let date = BackupName.date(of: name) { dated[name] = date }
        }
        for name in BackupRetention.toDelete(dated, now: .now) {
            let url = folder.appending(path: name)
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Restoring

    /// Reads a backup from the folder, downloading it from iCloud first if needed.
    func load(_ entry: Entry) throws -> Backup {
        try withFolder { folder in
            let url = folder.appending(path: entry.name)
            if entry.inCloud { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            return try Backup.decode(coordinatedRead(url))
        }
    }

    /// Reads a backup file picked in Files.
    func load(fileAt url: URL) throws -> Backup {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Backup.decode(coordinatedRead(url))
    }

    /// Replaces the data on this phone with the backup. What's here now is kept in Documents as
    /// "before-restore.json", so a mistaken restore can be undone. The stores have to be reloaded afterwards.
    func restore(_ backup: Backup) throws {
        if let data = try? snapshot().encoded() {
            try? data.write(to: Self.beforeRestoreURL, options: .atomic)
        }

        for (file, data) in backup.restorable(Self.knownFiles) where file != Self.settingsFile {
            try data.write(to: Self.location(of: file), options: .atomic)
        }
        // Files the backup doesn't have go back to empty, so the result matches the backup.
        for file in Self.documentFiles + Self.sharedFiles where backup.files[file] == nil {
            try? FileManager.default.removeItem(at: Self.location(of: file))
        }
        if let data = backup.files[Self.settingsFile],
           let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in Self.settingsKeys { if let value = settings[key] { UserDefaults.standard.set(value, forKey: key) } }
            for key in Self.sharedSettingsKeys { if let value = settings[key] { SharedStorage.defaults.set(value, forKey: key) } }
        }
        // The restored data came from a backup: only back up again once something changes.
        UserDefaults.standard.set(snapshot().fingerprint, forKey: Keys.fingerprint)
        problem = nil
    }

    private static let beforeRestoreURL = URL.documentsDirectory.appending(path: "before-restore.json")

    /// The data from before the last restore, if there was one.
    func beforeRestore() -> Backup? {
        (try? Data(contentsOf: Self.beforeRestoreURL)).flatMap { try? Backup.decode($0) }
    }

    // MARK: Files

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinatorError ?? writeError { throw error }
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(Failure("Couldn't read the backup."))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}
