import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Any JSON value. Message content is kept as JSON so blocks the app doesn't use itself (thinking,
/// fallback markers) go back to the API exactly as they came.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        // Whole numbers as integers, so 16000 doesn't go out as 16000.0.
        case .number(let value) where value.rounded() == value && abs(value) < 1e15: try container.encode(Int64(value))
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var int: Int? {
        if case .number(let value) = self, value.isFinite { Int(value.rounded()) } else { nil }
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// One message of a chat with the coach, in the Messages API's shape.
public struct CoachChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: [JSONValue]

    public init(role: String, content: [JSONValue]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> CoachChatMessage {
        CoachChatMessage(role: "user", content: [["type": "text", "text": .string(text)]])
    }

    /// The text blocks, joined.
    public var text: String {
        content.filter { $0["type"] == "text" }.compactMap { $0["text"]?.string }.joined(separator: "\n\n")
    }

    /// The tools Claude asked to run in this message.
    public var toolCalls: [CoachToolCall] {
        content.compactMap { block in
            guard block["type"] == "tool_use", let id = block["id"]?.string, let name = block["name"]?.string else { return nil }
            return CoachToolCall(id: id, name: name, input: block["input"] ?? [:])
        }
    }

    /// True for the user messages that only carry tool results back.
    public var isToolResults: Bool {
        role == "user" && !content.isEmpty && content.allSatisfy { $0["type"] == "tool_result" }
    }
}

public struct CoachToolCall: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// What a tool returned, sent back as a `tool_result` block.
public struct CoachToolResult: Sendable, Equatable {
    public var id: String
    public var text: String
    public var isError: Bool

    public init(id: String, text: String, isError: Bool = false) {
        self.id = id
        self.text = text
        self.isError = isError
    }
}

/// The tools the chat coach can call. The app runs them on the phone's own data.
public enum CoachTool: String, CaseIterable, Sendable {
    case getWorkouts = "get_workouts"
    case getExerciseHistory = "get_exercise_history"
    case searchExercises = "search_exercises"
    case getWeeklySets = "get_weekly_sets"
    case getSleep = "get_sleep"
    case getFood = "get_food"
    case getBody = "get_body"
    case getPlans = "get_plans"
    case getPrograms = "get_programs"
    case proposePlanChange = "propose_plan_change"

    /// Shown while the tool runs, e.g. "Reading your workouts…".
    public var status: String {
        switch self {
        case .getWorkouts: "Reading your workouts…"
        case .getExerciseHistory: "Looking at your progress…"
        case .searchExercises: "Searching exercises…"
        case .getWeeklySets: "Counting sets per muscle…"
        case .getSleep: "Reading your sleep…"
        case .getFood: "Reading your food log…"
        case .getBody: "Reading your measurements…"
        case .getPlans: "Reading your plans…"
        case .getPrograms: "Reading your strength programs…"
        case .proposePlanChange: "Writing a plan change…"
        }
    }

    private static func object(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
        ]
    }

    private var toolDescription: String {
        switch self {
        case .getWorkouts:
            "Workouts logged in the last `days` days (1-365), newest first, with every set (W warm-up, D drop, F failure), notes, and cardio from Apple Health. Use it for questions about recent training."
        case .getExerciseHistory:
            "Every logged session of one exercise, oldest first, with its sets, best set and estimated one-rep max. Use it to judge progress on a lift. Pass the exercise name as the app shows it; if you're unsure of the name, call search_exercises first."
        case .searchExercises:
            "Exercises in the app's library and the user's own exercises whose name or muscles match `query`, with muscles and equipment. Use it to find exact names before proposing plan changes."
        case .getWeeklySets:
            "Hard sets per muscle for each of the last `weeks` weeks (1-12), newest first. Warm-ups don't count; secondary muscles count half."
        case .getSleep:
            "The last two weeks of sleep: times, hours, stages, scores, tags and the sleep goal. Empty if the user doesn't track sleep."
        case .getFood:
            "The last week of the food diary: calories and macros per day against the goals, and body weight. Empty if the user doesn't log food."
        case .getBody:
            "Body measurements (waist, chest, arms, thighs, body fat and so on) with the change over the last month and since the first reading, plus how many progress-photo days there are. Weight is in get_food. Empty if the user doesn't measure."
        case .getPlans:
            "The user's saved workout plans with each exercise and its target sets."
        case .getPrograms:
            "The user's multi-week strength programs (e.g. Juggernaut or a coach-written block): where they are in each, current training maxes, every week's main-lift percentages, the days with accessories, rep-out results and the progression rules. Main-lift weights are a percentage of the training max. Use it for questions about their program or what to do this week."
        case .proposePlanChange:
            "Proposes changes to one of the user's saved plans. Nothing changes until the user taps Apply under your message, so explain the change in your reply too. Use exact plan and exercise names from get_plans and search_exercises. Actions: add (append `exercise` with `sets` sets of `reps`), remove (`exercise`), replace (`exercise` with `new_exercise`, keeping its sets), set_sets (set `exercise` to `sets` sets of `reps`). Use 0 for sets or reps you don't set and an empty string for an unused new_exercise."
        }
    }

    private var inputSchema: JSONValue {
        switch self {
        case .getWorkouts:
            Self.object(["days": ["type": "integer", "description": "How many days back, 1-365."]], required: ["days"])
        case .getExerciseHistory:
            Self.object(["exercise": ["type": "string", "description": "The exercise name, e.g. Bench Press (Barbell)."]], required: ["exercise"])
        case .searchExercises:
            Self.object(["query": ["type": "string", "description": "Part of a name or a muscle, e.g. row or hamstrings."]], required: ["query"])
        case .getWeeklySets:
            Self.object(["weeks": ["type": "integer", "description": "How many weeks back, 1-12."]], required: ["weeks"])
        case .getSleep, .getFood, .getBody, .getPlans, .getPrograms:
            Self.object([:], required: [])
        case .proposePlanChange:
            Self.object([
                "plan": ["type": "string", "description": "The plan's name."],
                "summary": ["type": "string", "description": "What the change does and why, in one or two sentences."],
                "changes": [
                    "type": "array",
                    "items": Self.object([
                        "action": ["type": "string", "enum": ["add", "remove", "replace", "set_sets"]],
                        "exercise": ["type": "string"],
                        "new_exercise": ["type": "string"],
                        "sets": ["type": "integer"],
                        "reps": ["type": "integer"],
                    ], required: ["action", "exercise", "new_exercise", "sets", "reps"]),
                ],
            ], required: ["plan", "summary", "changes"])
        }
    }

    /// The tool's definition for the request.
    public var definition: JSONValue {
        ["name": .string(rawValue), "description": .string(toolDescription), "input_schema": inputSchema, "strict": true]
    }
}

/// A plan change the coach proposed, read from a `propose_plan_change` call.
public struct PlanProposal: Sendable, Equatable {
    public enum Action: String, Sendable {
        case add, remove, replace
        case setSets = "set_sets"
    }

    public struct Change: Sendable, Equatable {
        public var action: Action
        public var exercise: String
        /// Only for `replace`.
        public var newExercise: String?
        /// Nil when not set.
        public var sets: Int?
        public var reps: Int?

        public init(action: Action, exercise: String, newExercise: String? = nil, sets: Int? = nil, reps: Int? = nil) {
            self.action = action
            self.exercise = exercise
            self.newExercise = newExercise
            self.sets = sets
            self.reps = reps
        }

        /// "Add Face Pull (Cable): 3 × 15".
        public var label: String {
            let target = sets.map { sets in reps.map { "\(sets) × \($0)" } ?? "\(sets) sets" }
            switch action {
            case .add: return "Add \(exercise)" + (target.map { ": \($0)" } ?? "")
            case .remove: return "Remove \(exercise)"
            case .replace: return "Swap \(exercise) for \(newExercise ?? "?")"
            case .setSets: return "\(exercise): " + (target ?? "unchanged")
            }
        }
    }

    public var plan: String
    public var summary: String
    public var changes: [Change]

    public init(plan: String, summary: String, changes: [Change]) {
        self.plan = plan
        self.summary = summary
        self.changes = changes
    }

    /// Reads the tool input; nil if it is missing what a change needs.
    public init?(input: JSONValue) {
        guard let plan = input["plan"]?.string, !plan.isEmpty, let items = input["changes"]?.array, !items.isEmpty else { return nil }
        var changes: [Change] = []
        for item in items {
            guard let action = item["action"]?.string.flatMap(Action.init(rawValue:)),
                  let exercise = item["exercise"]?.string, !exercise.isEmpty else { return nil }
            let newExercise = item["new_exercise"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            let sets = item["sets"]?.int.flatMap { $0 > 0 ? min($0, 20) : nil }
            let reps = item["reps"]?.int.flatMap { $0 > 0 ? min($0, 100) : nil }
            switch action {
            case .replace where newExercise == nil: return nil
            case .setSets where sets == nil && reps == nil: return nil
            default: break
            }
            changes.append(Change(action: action, exercise: exercise, newExercise: newExercise, sets: sets, reps: reps))
        }
        self.init(plan: plan, summary: input["summary"]?.string ?? "", changes: changes)
    }
}

/// A chat with the coach: Claude answers questions and calls `CoachTool`s to read the log.
public enum CoachChat {
    /// Tool rounds allowed for one question before giving up.
    public static let maxRounds = 8

    static let system = """
    You are the coach inside Overlo4d, a gym tracker, chatting with the person who uses it. \
    Answer their questions about training, recovery, sleep and food, and help them change their plans.

    How to coach:
    - Look things up with the tools before answering questions about their training; don't guess what \
    they did. Fetch only what the question needs.
    - Quote actual exercises, weights, reps, dates and set counts. Weights are in kilograms.
    - Judge volume in hard sets per muscle per week: about 10-20 is productive for most people, more \
    than 20 is usually more than they recover from, and the same muscle trained hard again within \
    48 hours is short on recovery.
    - For progress, look at whether weights or reps go up over the weeks; for stalls suggest rep \
    ranges, a deload or a different variation.
    - When they ask for a plan change, or one clearly follows from your advice, call \
    propose_plan_change; the app shows it with an Apply button. Say in your reply what you proposed.
    - If they follow a strength program, read it with get_programs before advising on their main lifts, \
    and coach within it (this week's percentages, the next rep-out set) instead of against it. \
    Programs are changed by the user in the app (Edit on the program), so tell them what to change there.
    - You can't examine anyone. If they mention pain or injury, tell them to get it checked by a \
    professional and don't prescribe around it.
    - Write for someone reading on a phone: short paragraphs, plain words, no headings or tables. \
    Keep most answers under 150 words unless they ask for more.
    """

    /// The request body: the whole conversation, the tools, and today's date and goal in the system prompt.
    public static func body(model: CoachModel, messages: [CoachChatMessage], goal: String, now: Date, calendar: Calendar = .current) throws -> Data {
        var dateFormat = Date.FormatStyle(date: .complete, time: .shortened)
        dateFormat.calendar = calendar
        dateFormat.timeZone = calendar.timeZone
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        var context = "Now: \(now.formatted(dateFormat))."
        if !goal.isEmpty { context += " Their goal: \(goal)." }

        var body: [String: JSONValue] = [
            "model": .string(model.rawValue),
            "max_tokens": 16_000,
            "system": [
                ["type": "text", "text": .string(system)],
                ["type": "text", "text": .string(context)],
            ],
            "tools": .array(CoachTool.allCases.map(\.definition)),
            "messages": .array(messages.map { ["role": .string($0.role), "content": .array($0.content)] }),
            "output_config": ["effort": "medium"],
            // Caches everything up to the last message, so each tool round only pays for what's new.
            "cache_control": ["type": "ephemeral"],
        ]
        if model.supportsFallbacks { body["fallbacks"] = "default" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(body)
    }

    public static func request(apiKey: String, model: CoachModel, messages: [CoachChatMessage], goal: String, now: Date = .now) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CoachError.missingKey }
        var request = URLRequest(url: CoachAPI.endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(CoachAPI.version, forHTTPHeaderField: "anthropic-version")
        if model.supportsFallbacks { request.setValue(CoachAPI.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try body(model: model, messages: messages, goal: goal, now: now)
        return request
    }

    /// Reads a response into the assistant message to add to the conversation. When its
    /// `toolCalls` aren't empty, run them and send `results(_:)` back.
    public static func parse(status: Int, data: Data) throws -> CoachChatMessage {
        guard (200..<300).contains(status) else { throw CoachAPI.error(status: status, data: data) }
        guard let response = try? JSONDecoder().decode(JSONValue.self, from: data),
              let content = response["content"]?.array else { throw CoachError.badResponse }
        switch response["stop_reason"]?.string {
        case "refusal": throw CoachError.refused
        case "max_tokens": throw CoachError.truncated
        default: break
        }
        let message = CoachChatMessage(role: "assistant", content: echoable(content))
        guard !message.text.isEmpty || !message.toolCalls.isEmpty else { throw CoachError.badResponse }
        return message
    }

    /// After a model switched mid-answer, the declined model's thinking and tool calls before the
    /// last `fallback` marker must not be sent back.
    static func echoable(_ content: [JSONValue]) -> [JSONValue] {
        guard let boundary = content.lastIndex(where: { $0["type"] == "fallback" }) else { return content }
        let dropped: Set<String> = ["thinking", "redacted_thinking", "tool_use"]
        return content.enumerated().compactMap { index, block in
            index < boundary && dropped.contains(block["type"]?.string ?? "") ? nil : block
        }
    }

    /// The user message that carries tool results back, in the order Claude asked for them.
    public static func results(_ results: [CoachToolResult]) -> CoachChatMessage {
        CoachChatMessage(role: "user", content: results.map { result in
            var block: [String: JSONValue] = [
                "type": "tool_result",
                "tool_use_id": .string(result.id),
                "content": .string(result.text.isEmpty ? "Nothing found." : result.text),
            ]
            if result.isError { block["is_error"] = true }
            return .object(block)
        })
    }
}
