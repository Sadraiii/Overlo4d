import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Claude models the coach can use, cheapest first. Haiku is the default; the user can pick another in Settings.
public enum CoachModel: String, CaseIterable, Identifiable, Sendable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }

    public var note: String {
        switch self {
        case .opus: "Most thorough, costs most"
        case .sonnet: "More thorough, costs more"
        case .haiku: "Fast, costs least"
        }
    }

    /// Opus and Sonnet can re-run a declined request on another model; Haiku can't.
    var supportsFallbacks: Bool { self != .haiku }
}

/// What the user wants feedback on.
public enum CoachFocus: Sendable, Equatable {
    /// One workout, read against the weeks before it.
    case workout(name: String, date: Date)
    /// The last few weeks of training as a whole.
    case overall
    /// The last two weeks of sleep and how to sleep better.
    case sleep
}

/// The coach's answer, as the JSON schema in `CoachAPI` asks for.
public struct CoachFeedback: Codable, Sendable, Equatable {
    public struct Change: Codable, Sendable, Equatable, Hashable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public struct Warning: Codable, Sendable, Equatable, Hashable {
        public enum Level: String, Codable, Sendable {
            /// Fine for now, but keep an eye on it.
            case watch
            /// Do less of this.
            case reduce
            /// Give it a few days off.
            case rest
        }

        public var area: String
        public var detail: String
        public var level: Level

        public init(area: String, detail: String, level: Level) {
            self.area = area
            self.detail = detail
            self.level = level
        }
    }

    public var summary: String
    public var goingWell: [String]
    public var changes: [Change]
    public var warnings: [Warning]
    public var nextSession: String

    public init(summary: String, goingWell: [String], changes: [Change], warnings: [Warning], nextSession: String) {
        self.summary = summary
        self.goingWell = goingWell
        self.changes = changes
        self.warnings = warnings
        self.nextSession = nextSession
    }

    enum CodingKeys: String, CodingKey {
        case summary, changes, warnings
        case goingWell = "going_well"
        case nextSession = "next_session"
    }
}

public enum CoachError: Error, Equatable, Sendable {
    case missingKey
    case invalidKey
    case noCredit(String)
    case rateLimited
    case overloaded
    case refused
    case truncated
    case badResponse
    case api(String)
    case network(String)

    /// Shown under the coach card.
    public var message: String {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings to get feedback."
        case .invalidKey: "Anthropic didn't accept the API key. Check it in Settings."
        case .noCredit(let detail): detail.isEmpty ? "The API account is out of credit." : detail
        case .rateLimited: "Too many requests right now. Try again in a minute."
        case .overloaded: "Claude is busy right now. Try again in a minute."
        case .refused: "Claude couldn't answer this one. Try again, or with another model in Settings."
        case .truncated: "The answer was cut off. Try again."
        case .badResponse: "The answer couldn't be read. Try again."
        case .api(let detail): detail
        case .network(let detail): "Couldn't reach Anthropic. \(detail)"
        }
    }
}

/// A workout, already formatted, for the text sent to the coach.
public struct DigestWorkout: Sendable, Equatable {
    public struct Exercise: Sendable, Equatable {
        public var name: String
        /// e.g. "Chest; also Front delts, Triceps".
        public var muscles: String
        /// e.g. ["W 40 kg × 10", "60 kg × 8", "F 60 kg × 6"].
        public var sets: [String]
        public var notes: String

        public init(name: String, muscles: String, sets: [String], notes: String = "") {
            self.name = name
            self.muscles = muscles
            self.sets = sets
            self.notes = notes
        }
    }

    public var name: String
    public var date: Date
    public var minutes: Int
    public var exercises: [Exercise]
    public var notes: String
    /// The workout the feedback is about.
    public var isFocus: Bool

    public init(name: String, date: Date, minutes: Int, exercises: [Exercise], notes: String = "", isFocus: Bool = false) {
        self.name = name
        self.date = date
        self.minutes = minutes
        self.exercises = exercises
        self.notes = notes
        self.isFocus = isFocus
    }
}

public enum CoachAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static let system = """
    You are the coach inside Tally, a gym tracker. You read someone's logged training and tell them, \
    plainly and specifically, how it is going and what to change.

    How to coach:
    - Base everything on the log you are given. Quote the actual exercises, weights, reps and set counts.
    - Judge volume per muscle in hard sets per week: about 10-20 is productive for most people, \
    more than 20 is usually more than they recover from, and the same muscle trained hard again \
    within 48 hours is short on recovery. The app's own load check is included; confirm or \
    correct it from the log rather than repeating it.
    - Look for progressive overload: are weights or reps going up over the weeks for the main lifts? \
    Point out stalls and what to try (rep ranges, deloads, swapping a variation).
    - Look at balance: push against pull, quads against hamstrings, and muscles that get no direct work.
    - Use warm-up (W), drop (D) and failure (F) set markers when judging effort. Sets with no marker are normal working sets.
    - Suggest at most four changes, the most useful first. Each must be something they can do next session.
    - Only add a warning when the log shows a real risk (too much volume, too little recovery, a sudden jump). \
    Name the muscle or area. Use "rest" only when a muscle needs a few days off.
    - You can't examine anyone. If notes mention pain or injury, say to get it checked by a professional \
    and don't prescribe around it.
    - Weights are in kilograms. Write for someone reading on a phone: short sentences, no jargon \
    without a word of explanation, no markdown.
    - If the log is too short to judge something, say so instead of guessing.
    - If food is included, use it too: protein well under about 1.6 g per kg of body weight, or \
    eating far below the calorie goal, slows muscle gain and recovery. Mention it briefly and \
    specifically (e.g. "about 90 g of protein a day, aim for 130 g"), without moralising about food. \
    Days with little logged may just be incomplete logs.
    - If sleep is included, use it for recovery: after short nights or a run of sleep debt, \
    suggest keeping the weights but cutting a set or two and staying away from failure, and say \
    when poor sleep may explain a stall.
    """

    static let sleepSystem = """
    You are the sleep coach inside Tally, a gym tracker. You read someone's sleep log (from Apple \
    Health or entered by hand) next to their training and tell them, plainly and specifically, \
    how their sleep is going and how to sleep better.

    How to coach:
    - Base everything on the log. Quote actual bedtimes, wake times and hours.
    - Most adults need 7-9 hours asleep. Judge time asleep against their goal, and look at \
    consistency: bed and wake times that move by more than about an hour unsettle the body clock, \
    and a regular wake time matters most.
    - Stage figures from a watch are estimates. Deep and REM together are usually 35-45% of a night; \
    only comment on stages when the pattern is clear over several nights.
    - Use the tags and quality ratings (e.g. late caffeine, alcohol, late workout, screens in bed) \
    to find what helps or hurts this person, and say how sure you can be from the number of nights.
    - Connect sleep and training: hard sessions late in the evening can delay sleep, and short \
    sleep slows recovery and strength gains.
    - Suggest at most four changes, the most useful first: things they can do tonight or this week, \
    such as a fixed wake time, a wind-down routine, light in the morning, caffeine cut-off, a cool \
    dark room, or moving late workouts earlier.
    - Add a warning only when the log shows a real problem, such as a large sleep debt or very short \
    nights. Use area for what it is about, e.g. Sleep debt or Bedtime. Use "rest" only when they \
    are so short on sleep that they should skip hard training.
    - You are not a doctor. If notes mention loud snoring, gasping or choking at night, being very \
    sleepy despite long nights, or trouble sleeping most nights for weeks, say to talk to a doctor. \
    Don't recommend medication or supplement doses.
    - Write for someone reading on a phone: short sentences, no jargon, no markdown.
    - If the log is too short to judge something, say so instead of guessing.
    """

    /// JSON schema for `CoachFeedback`. Sleep feedback asks for tonight's plan instead of the next workout.
    static func schema(sleep: Bool = false) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["summary", "going_well", "changes", "warnings", "next_session"],
            "properties": [
                "summary": ["type": "string", "description": sleep ? "Two or three sentences on how their sleep is going." : "Two or three sentences on how the training is going."],
                "going_well": [
                    "type": "array",
                    "description": "Up to three specific things that are working.",
                    "items": ["type": "string"],
                ],
                "changes": [
                    "type": "array",
                    "description": "Up to four changes to make, most useful first.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "detail"],
                        "properties": [
                            "title": ["type": "string", "description": "A short instruction, under eight words."],
                            "detail": ["type": "string", "description": "Why, and exactly what to do, in one to three sentences."],
                        ],
                    ],
                ],
                "warnings": [
                    "type": "array",
                    "description": sleep ? "Sleep problems the log shows. Empty when there are none." : "Overtraining or recovery risks the log shows. Empty when there are none.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["area", "detail", "level"],
                        "properties": [
                            "area": ["type": "string", "description": sleep ? "What it is about, e.g. Sleep debt or Bedtime." : "The muscle or body area, e.g. Chest or Lower back."],
                            "detail": ["type": "string"],
                            "level": ["type": "string", "enum": ["watch", "reduce", "rest"]],
                        ],
                    ],
                ],
                "next_session": ["type": "string", "description": sleep ? "The plan for tonight, in one or two sentences." : "What to do in the next workout, in one or two sentences."],
            ],
        ]
    }

    /// The training log and load check as the user message.
    public static func prompt(
        focus: CoachFocus,
        goal: String,
        workouts: [DigestWorkout],
        load: [String],
        weekly: [(muscle: String, sets: Double, usual: Double?)],
        sleep: [String] = [],
        nutrition: [String] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        var dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)
        dateFormat.calendar = calendar
        dateFormat.timeZone = calendar.timeZone
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        let count: (Double) -> String = { $0.rounded() == $0 ? String(Int($0)) : String(format: "%.1f", $0) }

        var lines: [String] = []
        switch focus {
        case .workout(let name, let date):
            lines.append("Give feedback on my workout \"\(name)\" from \(date.formatted(dateFormat)), marked FOCUS below. Compare it with the weeks before.")
        case .overall:
            lines.append("Review my training over the last few weeks.")
        case .sleep:
            lines.append("Review my sleep over the last two weeks and tell me how to sleep better. My training is below for context.")
        }
        if !goal.isEmpty { lines.append("My goal: \(goal).") }
        lines.append("Now: \(now.formatted(dateFormat)).")

        if !sleep.isEmpty {
            lines.append("")
            lines.append("Sleep, newest first:")
            lines.append(contentsOf: sleep.map { "- \($0)" })
        }

        if !nutrition.isEmpty {
            lines.append("")
            lines.append("Food log, newest first:")
            lines.append(contentsOf: nutrition.map { "- \($0)" })
        }

        lines.append("")
        lines.append("Hard sets per muscle in the last 7 days (secondary muscles count half), with the usual week before that:")
        if weekly.isEmpty {
            lines.append("- none")
        } else {
            for row in weekly {
                lines.append("- \(row.muscle): \(count(row.sets))" + (row.usual.map { " (usual \(count($0)))" } ?? ""))
            }
        }

        lines.append("")
        lines.append("The app's load check:")
        lines.append(contentsOf: load.isEmpty ? ["- nothing flagged"] : load.map { "- \($0)" })

        lines.append("")
        lines.append("Workouts, oldest first:")
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            lines.append("")
            lines.append("## \(workout.isFocus ? "FOCUS " : "")\(workout.name), \(workout.date.formatted(dateFormat)), \(workout.minutes) min")
            if !workout.notes.isEmpty { lines.append("Notes: \(workout.notes)") }
            for exercise in workout.exercises {
                lines.append("- \(exercise.name) [\(exercise.muscles)]: \(exercise.sets.joined(separator: ", "))")
                if !exercise.notes.isEmpty { lines.append("  Notes: \(exercise.notes)") }
            }
        }
        if workouts.isEmpty { lines.append("- none logged yet") }
        return lines.joined(separator: "\n")
    }

    /// The Messages API request body.
    public static func body(model: CoachModel, prompt: String, sleep: Bool = false) throws -> Data {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16_000,
            "system": sleep ? sleepSystem : system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema(sleep: sleep)],
            ],
        ]
        if model.supportsFallbacks { body["fallbacks"] = "default" }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public static func request(apiKey: String, model: CoachModel, prompt: String, sleep: Bool = false) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CoachError.missingKey }
        var request = URLRequest(url: endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        if model.supportsFallbacks { request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try body(model: model, prompt: prompt, sleep: sleep)
        return request
    }

    private struct Response: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }

        var content: [Block]
        var stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            var type: String
            var message: String
        }

        var error: Detail
    }

    /// The error to show for a failed Messages API response.
    static func error(status: Int, data: Data) -> CoachError {
        let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data).error
        switch (status, detail?.type ?? "") {
        case (401, _), (_, "authentication_error"), (403, "permission_error"): return .invalidKey
        case (402, _), (_, "billing_error"): return .noCredit(detail?.message ?? "")
        case (429, _), (_, "rate_limit_error"): return .rateLimited
        case (529, _), (_, "overloaded_error"), (500..., _): return .overloaded
        default: return .api(detail?.message ?? "Request failed (\(status)).")
        }
    }

    /// Reads a Messages API response into feedback, or the error to show.
    public static func parse(status: Int, data: Data) throws -> CoachFeedback {
        guard (200..<300).contains(status) else { throw error(status: status, data: data) }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw CoachError.badResponse }
        switch response.stop_reason {
        case "refusal": throw CoachError.refused
        case "max_tokens": throw CoachError.truncated
        default: break
        }
        // Thinking and fallback blocks come before the answer; the answer is the text.
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8),
              let feedback = try? JSONDecoder().decode(CoachFeedback.self, from: json) else { throw CoachError.badResponse }
        return feedback
    }
}
