import CryptoKit
import Foundation
import Observation
import TallyCore

/// The private peptide tracker's data. It lives in its own file (peptides.json) and is created
/// only while the tracker is open, so nothing else in the app reads it: not the widgets, the
/// coach, the iCloud backup or search. Export and import are done from inside the tracker.
@MainActor
@Observable
final class PeptideStore {
    private(set) var data: PeptideData
    /// A PIN is set. Kept here so views update when it changes.
    private(set) var hasPIN: Bool

    private static let fileURL = URL.documentsDirectory.appending(path: "peptides.json")
    private static let pinAccount = "peptides.pin"

    init() {
        var data = PeptideData()
        if let raw = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? PeptideData.decode(raw) {
                data = decoded
            } else {
                StoreFile.setAside(Self.fileURL, stamp: String(Int(Date.now.timeIntervalSince1970)))
            }
        }
        self.data = data
        hasPIN = Keychain.read(Self.pinAccount) != nil
    }

    private func save() {
        guard let encoded = try? data.encoded() else { return }
        try? encoded.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }

    private func change(_ body: (inout PeptideData) -> Void) {
        body(&data)
        save()
    }

    // MARK: Profiles and log

    func profile(_ id: UUID) -> PeptideProfile? { data.profile(id) }

    func save(_ profile: PeptideProfile) { change { $0.save(profile, now: .now) } }
    func deleteProfile(_ id: UUID) { change { $0.deleteProfile(id) } }
    func startNewVial(_ id: UUID) { change { $0.startNewVial(id, now: .now) } }

    @discardableResult
    func log(_ id: UUID, at date: Date, site: InjectionSite?, notes: String) -> Bool {
        var logged = false
        change { logged = $0.log(id, at: date, site: site, notes: notes) != nil }
        return logged
    }

    func deleteLog(_ id: UUID) { change { $0.deleteLog(id) } }

    func dueToday(_ profile: PeptideProfile) -> Int { data.dueToday(profile, now: .now) }

    // MARK: Export and import

    func exportFile() -> ExportFile? {
        guard let encoded = try? data.encoded() else { return nil }
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        return ExportFile(data: encoded, name: "Peptides \(stamp)", kind: .json)
    }

    /// Reads a file picked in Files.
    func read(fileAt url: URL) throws -> PeptideData {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try PeptideData.decode(Data(contentsOf: url))
    }

    func importData(_ imported: PeptideData, replacing: Bool) {
        change {
            if replacing {
                $0 = PeptideData(profiles: imported.profiles, logs: imported.logs)
            } else {
                $0.merge(imported)
            }
        }
    }

    /// Removes every profile and entry, and the PIN.
    func eraseEverything() {
        data = PeptideData()
        try? FileManager.default.removeItem(at: Self.fileURL)
        removePIN()
    }

    // MARK: PIN

    /// The Keychain holds "salt:hash", never the PIN itself.
    func setPIN(_ pin: String) {
        let salt = UUID().uuidString
        Keychain.save("\(salt):\(Self.hash(pin, salt: salt))", account: Self.pinAccount)
        hasPIN = true
    }

    func removePIN() {
        Keychain.delete(Self.pinAccount)
        hasPIN = false
    }

    func checkPIN(_ pin: String) -> Bool {
        guard let stored = Keychain.read(Self.pinAccount) else { return true }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        return Self.hash(pin, salt: parts[0]) == parts[1]
    }

    private static func hash(_ pin: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt)|\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
