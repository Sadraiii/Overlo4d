import Foundation
import Observation
import TallyCore

/// What a piece of feedback is about: one workout, training overall, or sleep.
enum CoachScope: Hashable, Codable {
    case workout(UUID)
    case overall
    case sleep

    var key: String {
        switch self {
        case .workout(let id): id.uuidString
        case .overall: "overall"
        case .sleep: "sleep"
        }
    }
}

/// The user's goal, sent with every request so feedback fits it.
enum CoachGoal: String, CaseIterable, Identifiable {
    case muscle, strength, fitness, fatLoss

    static let storageKey = "coach.goal"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .muscle: "Build muscle"
        case .strength: "Get stronger"
        case .fitness: "General fitness"
        case .fatLoss: "Lose fat, keep muscle"
        }
    }
}

/// Asks Claude for feedback with the user's own API key and keeps the latest answer per scope.
@MainActor
@Observable
final class CoachStore {
    struct Saved: Codable {
        var feedback: CoachFeedback
        var date: Date
        var model: String
    }

    private static let keyAccount = "anthropic-api-key"
    private static let modelKey = "coach.model"

    private(set) var hasKey: Bool
    private(set) var saved: [String: Saved]
    /// Scopes with a request in flight.
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: CoachError] = [:]

    private var modelID: String

    var model: CoachModel {
        get { CoachModel(rawValue: modelID) ?? .haiku }
        set {
            modelID = newValue.rawValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.modelKey)
        }
    }

    private static let fileURL = URL.documentsDirectory.appending(path: "coach.json")

    init() {
        hasKey = Keychain.read(Self.keyAccount)?.isEmpty == false
        modelID = UserDefaults.standard.string(forKey: Self.modelKey) ?? CoachModel.haiku.rawValue
        saved = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
    }

    // MARK: API key

    /// Stores the key in the Keychain. Returns false if it doesn't look like an Anthropic key.
    @discardableResult
    func setKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-"), Keychain.save(trimmed, account: Self.keyAccount) else { return false }
        hasKey = true
        errors = errors.filter { $0.value != .invalidKey && $0.value != .missingKey }
        return true
    }

    func removeKey() {
        Keychain.delete(Self.keyAccount)
        hasKey = false
    }

    // MARK: Feedback

    func feedback(for scope: CoachScope) -> Saved? { saved[scope.key] }
    func isLoading(_ scope: CoachScope) -> Bool { loading.contains(scope.key) }
    func error(for scope: CoachScope) -> CoachError? { errors[scope.key] }

    /// `sleep` is the sleep log as lines for the prompt (see `SleepStore.coachLines`); empty without sleep data.
    func ask(_ scope: CoachScope, gym: GymStore, sleep: [String] = []) async {
        let key = scope.key
        guard !loading.contains(key) else { return }
        errors[key] = nil
        guard let apiKey = Keychain.read(Self.keyAccount), !apiKey.isEmpty else {
            errors[key] = .missingKey
            return
        }
        let focus: Workout? = if case .workout(let id) = scope { gym.workout(id) } else { nil }
        let goal = (UserDefaults.standard.string(forKey: CoachGoal.storageKey).flatMap(CoachGoal.init(rawValue:)) ?? .muscle).label
        let isSleep = scope == .sleep
        let prompt = gym.coachPrompt(focus: focus, goal: goal, sleep: sleep, sleepReview: isSleep)
        let model = self.model

        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let request = try CoachAPI.request(apiKey: apiKey, model: model, prompt: prompt, sleep: isSleep)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let feedback = try CoachAPI.parse(status: status, data: data)
            saved[key] = Saved(feedback: feedback, date: .now, model: model.rawValue)
            save()
        } catch let error as CoachError {
            errors[key] = error
        } catch is CancellationError {
            // Left the screen; nothing to show.
        } catch let error as URLError where error.code == .cancelled {
            // Same, from URLSession.
        } catch {
            errors[key] = .network(error.localizedDescription)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }
}
