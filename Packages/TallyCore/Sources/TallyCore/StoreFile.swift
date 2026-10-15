import Foundation

/// Safety copies of the app's data file.
public enum StoreFile {
    /// Copies `file` to `backup` unless the backup already exists. Returns whether a copy was made.
    @discardableResult
    public static func backUpOnce(_ file: URL, to backup: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: file.path), !fileManager.fileExists(atPath: backup.path) else { return false }
        return (try? fileManager.copyItem(at: file, to: backup)) != nil
    }

    /// Moves a file that couldn't be read out of the way, so saving fresh data doesn't overwrite it.
    /// "gym.json" becomes "gym-unreadable-<stamp>.json". Returns the new location.
    @discardableResult
    public static func setAside(_ file: URL, stamp: String) -> URL? {
        let name = "\(file.deletingPathExtension().lastPathComponent)-unreadable-\(stamp)"
        let target = file.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(file.pathExtension)
        return (try? FileManager.default.moveItem(at: file, to: target)) != nil ? target : nil
    }
}
