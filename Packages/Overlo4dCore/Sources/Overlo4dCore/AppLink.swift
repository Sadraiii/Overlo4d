import Foundation

/// Things the app does when opened with a overlo4d:// link, from a widget, the Home Screen menu or a
/// shortcut in the Shortcuts app. Most open a screen; `water`, `weight`, `rest` and `addReps` do the
/// thing straight away, so a shortcut can log something without touching the app.
public enum AppLink: Equatable, Sendable {
    case reps
    /// Adds reps to a rep counter exercise: the one with this name, or the first one.
    case addReps(count: Int, exercise: String?)
    /// Adds glasses of water to today.
    case water(glasses: Int)
    /// Logs today's body weight, in kg.
    case weight(kg: Double)
    /// Starts the rest timer: these seconds, or the default rest.
    case rest(seconds: Int?)
    case food
    case train
    /// The workout in progress, or Home when there is none. Never starts a workout, so a
    /// Live Activity left on the Lock Screen can't begin a new one by mistake.
    case activeWorkout
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

    /// Body weights a link may log, in kg, so a typo can't land in the log.
    public static let weightRange: ClosedRange<Double> = 20...400
    public static let restRange: ClosedRange<Int> = 5...1800

    public static func parse(_ url: URL) -> AppLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme || scheme == legacyScheme,
              var host = url.host()?.lowercased() else { return nil }
        // x-callback-url form: overlo4d://x-callback-url/water?glasses=1&x-success=…
        if host == "x-callback-url" {
            guard let action = url.pathComponents.first(where: { $0 != "/" })?.lowercased() else { return nil }
            host = action
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ names: String...) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch host {
        case "reps":
            guard let add = value("add", "count") else { return .reps }
            guard let count = number(add).map({ Int($0.rounded()) }), (1...1000).contains(count) else { return nil }
            let exercise = value("exercise", "name")
            return .addReps(count: count, exercise: (exercise ?? "").isEmpty ? nil : exercise)
        case "water":
            if let ml = value("ml").flatMap(number) {
                let glasses = Int((ml / Double(Water.glassMl)).rounded())
                return (1...20).contains(glasses) ? .water(glasses: glasses) : nil
            }
            guard let text = value("glasses", "add", "count") else { return .water(glasses: 1) }
            guard let glasses = number(text).map({ Int($0.rounded()) }), (1...20).contains(glasses) else { return nil }
            return .water(glasses: glasses)
        case "weight":
            let kg = value("kg").flatMap(number) ?? value("lb", "lbs").flatMap(number).map { $0 * 0.45359237 }
            guard let kg, weightRange.contains(kg) else { return nil }
            return .weight(kg: (kg * 10).rounded() / 10)
        case "rest":
            guard let text = value("seconds", "s") else { return .rest(seconds: nil) }
            guard let seconds = number(text).map({ Int($0.rounded()) }) else { return nil }
            return .rest(seconds: min(max(seconds, restRange.lowerBound), restRange.upperBound))
        case "food": return .food
        case "train": return .train
        case "active": return .activeWorkout
        case "start", "workout":
            let plan = value("plan")
            return .start(plan: (plan ?? "").isEmpty ? nil : plan)
        case "cardio": return .cardio
        case "plates": return .plates
        case "timer": return .timer
        case "report": return .report
        case "history": return .history
        default: return nil
        }
    }

    /// A number typed in any common way: "82.5", "82,5" (Shortcuts in many languages), " 82 ".
    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    private static func link(_ host: String, _ items: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    public var url: URL? {
        switch self {
        case .reps: return URL(string: "overlo4d://reps")
        case .addReps(let count, let exercise):
            return Self.link("reps", [URLQueryItem(name: "add", value: String(count))]
                + (exercise.map { [URLQueryItem(name: "exercise", value: $0)] } ?? []))
        case .water(let glasses): return Self.link("water", [URLQueryItem(name: "glasses", value: String(glasses))])
        case .weight(let kg): return Self.link("weight", [URLQueryItem(name: "kg", value: Self.format(kg))])
        case .rest(let seconds): return Self.link("rest", seconds.map { [URLQueryItem(name: "seconds", value: String($0))] } ?? [])
        case .food: return URL(string: "overlo4d://food")
        case .train: return URL(string: "overlo4d://train")
        case .activeWorkout: return URL(string: "overlo4d://active")
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

/// A link with the callbacks Shortcuts' "Open X-Callback URL" action adds, so a shortcut waits for
/// Overlo4d to finish the action and then carries on.
public struct AppLinkRequest: Equatable, Sendable {
    public var link: AppLink
    /// Opened once the action is done, with `result` added (x-success).
    public var success: URL?
    /// Opened when the action can't be done, with `errorMessage` added (x-error).
    public var failure: URL?

    public init(link: AppLink, success: URL? = nil, failure: URL? = nil) {
        self.link = link
        self.success = success
        self.failure = failure
    }

    /// The request in a link, or nil when it isn't an Overlo4d link. A link the app can't act on
    /// (an unknown action, a weight out of range) still comes back when it carries an x-error,
    /// with `link` nil, so the shortcut can be told why.
    public static func parse(_ url: URL) -> (request: AppLinkRequest?, failure: URL?) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func callback(_ name: String) -> URL? {
            items.first { $0.name.lowercased() == name }?.value.flatMap(URL.init(string:))
        }
        guard let link = AppLink.parse(url) else { return (nil, callback("x-error")) }
        return (AppLinkRequest(link: link, success: callback("x-success"), failure: callback("x-error")), nil)
    }

    public func successURL(result: String?) -> URL? {
        success.flatMap { Self.adding(result.map { [URLQueryItem(name: "result", value: $0)] } ?? [], to: $0) }
    }

    public func failureURL(message: String) -> URL? {
        failure.flatMap { Self.errorURL($0, message: message) }
    }

    public static func errorURL(_ url: URL, message: String) -> URL? {
        adding([URLQueryItem(name: "errorMessage", value: message)], to: url)
    }

    private static func adding(_ items: [URLQueryItem], to url: URL) -> URL? {
        guard !items.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url
    }
}
