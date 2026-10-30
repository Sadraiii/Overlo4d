import Foundation
import Observation
import TallyCore
import UIKit

/// Keeps the user's coach server (cloudflare/coach-mcp) up to date, so Claude can coach through the
/// Overlo4d connector with a normal Claude plan, and fetches the plan changes and programs Claude sends back.
@MainActor
@Observable
final class CoachCloudStore {
    private enum Keys {
        static let server = "coachCloud.server"
        static let last = "coachCloud.lastSync"
        static let fingerprint = "coachCloud.fingerprint"
        static let tokenAccount = "coach-cloud-token"
    }

    private(set) var cloud: CoachCloud?
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var problem: String?
    /// Waiting for the user to apply or dismiss, oldest first.
    private(set) var inbox: [CoachInboxItem] = []

    init() {
        lastSync = UserDefaults.standard.object(forKey: Keys.last) as? Date
        if let server = UserDefaults.standard.string(forKey: Keys.server), let base = URL(string: server),
           let token = Keychain.read(Keys.tokenAccount), !token.isEmpty {
            cloud = CoachCloud(base: base, token: token)
        }
    }

    var isConnected: Bool { cloud != nil }

    // MARK: Setup

    /// Links the app to a server from its address, or from a full connector address on a second phone,
    /// then uploads straight away, which claims a new server. Returns false and sets `problem` if it fails.
    @discardableResult
    func connect(_ text: String, toolbox: CoachToolbox) async -> Bool {
        guard let parsed = CoachCloud.parse(text) else {
            problem = CoachCloudError.badAddress.message
            return false
        }
        let candidate = CoachCloud(base: parsed.base, token: parsed.token ?? Keychain.read(Keys.tokenAccount) ?? CoachCloud.newToken())
        problem = nil
        guard await upload(toolbox.snapshot(goal: CoachGoal.current.label), to: candidate) else { return false }
        Keychain.save(candidate.token, account: Keys.tokenAccount)
        UserDefaults.standard.set(candidate.base.absoluteString, forKey: Keys.server)
        cloud = candidate
        await refreshInbox()
        return true
    }

    /// Forgets the server on this phone. The token stays in the Keychain, so connecting again to the
    /// same server works; the data on the server stays until the Worker is deleted.
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Keys.server)
        UserDefaults.standard.removeObject(forKey: Keys.fingerprint)
        cloud = nil
        inbox = []
        problem = nil
    }

    // MARK: Sync

    /// Uploads when something changed since the last upload, or always with `force`.
    func sync(toolbox: CoachToolbox, force: Bool = false) async {
        guard let cloud, !isSyncing else { return }
        let snapshot = toolbox.snapshot(goal: CoachGoal.current.label)
        if !force, snapshot.fingerprint == UserDefaults.standard.string(forKey: Keys.fingerprint) { return }
        // Finish the upload when the app was just sent to the background.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Coach sync")
        defer { UIApplication.shared.endBackgroundTask(task) }
        await upload(snapshot, to: cloud)
    }

    @discardableResult
    private func upload(_ snapshot: CoachSnapshot, to cloud: CoachCloud) async -> Bool {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: try cloud.uploadRequest(snapshot))
            try CoachCloud.check(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: Keys.last)
            UserDefaults.standard.set(snapshot.fingerprint, forKey: Keys.fingerprint)
            problem = nil
            return true
        } catch {
            problem = Self.message(error)
            return false
        }
    }

    // MARK: Inbox

    func refreshInbox() async {
        guard let cloud else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: cloud.inboxRequest())
            inbox = try CoachCloud.parseInbox(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            problem = Self.message(error)
        }
    }

    /// Applies a plan change or adds a program. Returns what went wrong, or nil.
    func apply(_ item: CoachInboxItem, gym: GymStore, programs: ProgramStore) -> String? {
        switch item.kind {
        case .planChange:
            guard let proposal = item.planProposal else { return "This change couldn't be read." }
            switch gym.resolve(proposal) {
            case .success(let plan): gym.savePlan(plan)
            case .failure(let problem): return problem.message
            }
        case .program:
            guard let program = item.program(start: .now) else { return "This program couldn't be read." }
            programs.add(program)
        }
        remove(item)
        return nil
    }

    func dismiss(_ item: CoachInboxItem) {
        remove(item)
    }

    private func remove(_ item: CoachInboxItem) {
        inbox.removeAll { $0.id == item.id }
        guard let cloud else { return }
        Task {
            // If this fails the item comes back on the next refresh, and can be dismissed again.
            _ = try? await URLSession.shared.data(for: cloud.ackRequest([item.id]))
        }
    }

    private static func message(_ error: Error) -> String {
        switch error {
        case let error as CoachCloudError: error.message
        case let error as URLError: "Couldn't reach your coach server. \(error.localizedDescription)"
        default: error.localizedDescription
        }
    }
}
