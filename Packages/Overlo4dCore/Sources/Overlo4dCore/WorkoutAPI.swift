import Foundation

/// Workout API (workoutapi.com): an exercise catalogue with animated GIFs of each movement.
/// Every request needs the user's own key in the `x-api-key` header.
public enum WorkoutAPI {
    public static let baseURL = URL(string: "https://api.workoutapi.com")!
    public static let signUpURL = URL(string: "https://workoutapi.com/signup")!
    public static let keyHeader = "x-api-key"

    /// One exercise from the catalogue. The API sends more (description, muscles); only these are kept.
    public struct Exercise: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var code: String
        public var name: String

        public init(id: String, code: String, name: String) {
            self.id = id
            self.code = code
            self.name = name
        }
    }

    /// The plain illustration, or the same one with the worked muscles highlighted.
    public enum Variant: String, CaseIterable, Identifiable, Sendable {
        case basic, muscles

        public var id: String { rawValue }
    }

    /// All exercises in one list.
    public static var exercisesURL: URL { baseURL.appending(path: "exercises") }

    /// The animated GIF for an exercise code, e.g. BARBELL_BENCH_PRESS.
    public static func animationURL(code: String, variant: Variant = .basic) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "exercises/code/\(code)/animation"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "variant", value: variant.rawValue)]
        return components.url!
    }

    public static func parseExercises(_ data: Data) -> [Exercise] {
        (try? JSONDecoder().decode([Exercise].self, from: data)) ?? []
    }

    /// A short reason for a failed request, from the HTTP status.
    public static func failure(status: Int) -> String {
        switch status {
        case 401: "The Workout API key wasn't accepted."
        case 403: "This Workout API key can't load exercise animations."
        case 404: "No animation for this exercise."
        case 429: "Workout API limit reached. Try again later."
        default: "Workout API didn't answer (\(status))."
        }
    }
}

/// Finds the Workout API exercise that best matches one of the app's exercise names,
/// e.g. "Bench Press (Barbell)" → "Barbell Bench Press", "Pull-ups" + overhand → "Pronated Grip Pull Ups".
public enum WorkoutAPIMatcher {
    static let equipment: Set<String> = ["barbell", "dumbbell", "cable", "machine", "smith", "kettlebell", "band", "ez", "trap", "landmine", "plate"]
    static let grips: Set<String> = ["pronated", "supinated", "neutral"]
    static let ignored: Set<String> = ["grip", "with", "the", "on", "a", "of", "and", "to", "exercise", "bodyweight"]
    static let synonyms: [String: String] = [
        "overhand": "pronated", "underhand": "supinated",
        "db": "dumbbell", "bb": "barbell", "kb": "kettlebell", "bw": "bodyweight",
        "pullup": "pull up", "chinup": "chin up", "pushup": "push up", "situp": "sit up",
        "bentover": "bent over", "rdl": "romanian deadlift", "ohp": "overhead press",
        "single": "unilateral", "ups": "up",
        // Machines are often named "lever" or "leverage".
        "lever": "machine", "leverage": "machine", "sled": "machine", 
    ]

    /// Lower-case word stems with equipment and grip words normalised.
    public static func tokens(_ name: String) -> [String] {
        let cleaned = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        var words: [String] = []
        for raw in String(cleaned).split(separator: " ").map(String.init) {
            let mapped = synonyms[raw] ?? raw
            words += mapped.split(separator: " ").map { stem(String($0)) }
        }
        return words.filter { !ignored.contains($0) && !$0.isEmpty }
    }

    static func stem(_ word: String) -> String {
        if word.count > 4 && word.hasSuffix("sses") { return String(word.dropLast(2)) }
        if word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// 0...1, or nil when the two clearly name different movements (different equipment).
    /// `hints` are words the app knows but doesn't put in the name, such as the grip; they count
    /// only when the candidate mentions them.
    public static func score(_ name: String, hints: Set<String> = [], candidate: String) -> Double? {
        let a = tokens(name), b = tokens(candidate)
        let aEquipment = Set(a).intersection(equipment), bEquipment = Set(b).intersection(equipment)
        if !aEquipment.isEmpty && !bEquipment.isEmpty && aEquipment.isDisjoint(with: bEquipment) { return nil }
        let aCore = Set(a).subtracting(equipment), bCore = Set(b).subtracting(equipment)
        let hinted = hints.intersection(bCore).subtracting(aCore)
        // A grip in the candidate that contradicts the hint is a different exercise.
        if !hints.isEmpty, let hintGrip = hints.intersection(grips).first,
           let candidateGrip = bCore.intersection(grips).first, hintGrip != candidateGrip, !aCore.contains(candidateGrip) {
            return nil
        }
        let shared = aCore.intersection(bCore).count + hinted.count
        let total = aCore.count + hinted.count + bCore.count
        guard total > 0, shared > 0 else { return 0 }
        var score = 2 * Double(shared) / Double(total)
        if aEquipment.isEmpty != bEquipment.isEmpty { score -= 0.12 }
        if aEquipment == bEquipment && !aEquipment.isEmpty { score += 0.05 }
        return score
    }

    /// The best candidate scoring at least `threshold`, or nil.
    public static func bestMatch(for name: String, hints: Set<String> = [], in catalogue: [WorkoutAPI.Exercise], threshold: Double = 0.62) -> WorkoutAPI.Exercise? {
        var best: (exercise: WorkoutAPI.Exercise, score: Double)?
        for candidate in catalogue {
            guard let score = score(name, hints: hints, candidate: candidate.name), score >= threshold else { continue }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        return best?.exercise
    }

    /// The closest names for an exercise, for picking one by hand, best first.
    public static func suggestions(for name: String, in catalogue: [WorkoutAPI.Exercise], limit: Int = 12) -> [WorkoutAPI.Exercise] {
        var scored: [(exercise: WorkoutAPI.Exercise, score: Double)] = []
        for candidate in catalogue {
            if let value = score(name, candidate: candidate.name), value > 0.25 { scored.append((candidate, value)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.exercise.name < $1.exercise.name }
        return scored.prefix(limit).map(\.exercise)
    }

    /// Catalogue entries for a search box, in name order.
    public static func search(_ query: String, in catalogue: [WorkoutAPI.Exercise]) -> [WorkoutAPI.Exercise] {
        let words = tokens(query)
        guard !words.isEmpty else { return catalogue.sorted { $0.name < $1.name } }
        return catalogue
            .map { ($0, Set(tokens($0.name))) }
            .filter { _, candidate in words.allSatisfy { word in candidate.contains { $0.hasPrefix(word) } } }
            .map(\.0)
            .sorted { $0.name < $1.name }
    }
}
