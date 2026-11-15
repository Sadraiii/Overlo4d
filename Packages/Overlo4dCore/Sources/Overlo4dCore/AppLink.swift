import Foundation

/// Things the app does when opened with a overlo4d:// link, from a widget, the Home Screen menu or a
/// shortcut in the Shortcuts app.
public enum AppLink: Equatable, Sendable {
    case reps
    case food
    case train
    /// Start a workout: empty, or from the plan with this name.
    case start(plan: String?)
    case cardio
    case plates
    case timer
    case report
    case history

    public static let scheme = "overlo4d"
    /// The scheme from when the app was called Tally. Still opens the app, so old shortcuts keep working.
    public static let legacyScheme = "tally"

    public static func parse(_ url: URL) -> AppLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme || scheme == legacyScheme,
              let host = url.host()?.lowercased() else { return nil }
        switch host {
        case "reps": return .reps
        case "food": return .food
        case "train": return .train
        case "start", "workout":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let plan = items.first { $0.name.lowercased() == "plan" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .start(plan: (plan ?? "").isEmpty ? nil : plan)
        case "cardio": return .cardio
        case "plates": return .plates
        case "timer": return .timer
        case "report": return .report
        case "history": return .history
        default: return nil
        }
    }

    public var url: URL? {
        switch self {
        case .reps: return URL(string: "overlo4d://reps")
        case .food: return URL(string: "overlo4d://food")
        case .train: return URL(string: "overlo4d://train")
        case .start(let plan):
            guard let plan, !plan.isEmpty else { return URL(string: "overlo4d://start") }
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "start"
            components.queryItems = [URLQueryItem(name: "plan", value: plan)]
            return components.url
        case .cardio: return URL(string: "overlo4d://cardio")
        case .plates: return URL(string: "overlo4d://plates")
        case .timer: return URL(string: "overlo4d://timer")
        case .report: return URL(string: "overlo4d://report")
        case .history: return URL(string: "overlo4d://history")
        }
    }

    /// The plan a link means: an exact name first, then one that starts with or contains the text.
    public static func match(plan query: String, in names: [String]) -> Int? {
        let wanted = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let lowered = names.map { $0.lowercased() }
        return lowered.firstIndex(of: wanted)
            ?? lowered.firstIndex { $0.hasPrefix(wanted) }
            ?? lowered.firstIndex { $0.contains(wanted) }
    }
}
