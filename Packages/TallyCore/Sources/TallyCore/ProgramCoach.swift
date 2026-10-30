import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What the user asks the coach to build.
public struct ProgramRequest: Sendable, Equatable {
    /// 4 to 16.
    public var weeks: Int
    /// 2 to 6.
    public var daysPerWeek: Int
    /// e.g. "Get stronger".
    public var goal: String
    /// Anything else, e.g. "bad left knee, no barbell on Fridays, want a bigger bench".
    public var notes: String
    /// Best estimated one-rep max per exercise, from the log or typed in.
    public var oneRepMaxes: [String: Double]

    public init(weeks: Int, daysPerWeek: Int, goal: String, notes: String, oneRepMaxes: [String: Double]) {
        self.weeks = weeks
        self.daysPerWeek = daysPerWeek
        self.goal = goal
        self.notes = notes
        self.oneRepMaxes = oneRepMaxes
    }
}

/// Asks Claude to write a `StrengthProgram`, in the same compact shape as the templates.
public enum ProgramCoach {
    static let system = """
    You are the strength coach inside Overlo4d, a gym tracker. You write periodized strength \
    programs that the app turns into workouts, with the weights filled in.

    How to program:
    - Use proven structures. For 12-16 weeks, a Juggernaut-style plan works well: waves of 10s, \
    8s, 5s and 3s, each with accumulation, intensification, realization (ramp to one rep-out set) and \
    deload weeks. For 4-8 weeks, a linear block: weights up and reps down every week, a rep-out set \
    in the last hard week, then a deload. Adapt to the request rather than copying blindly.
    - Main lifts run off a training max of about 90 % of the one-rep max. Prescribe them as \
    percentages of the training max (usually 40-95 %). Use warmup true for ramp-up sets before the \
    work sets, and amrap true only on a week's final rep-out set, with amrap_target the reps to beat.
    - Pick 2-4 main lifts that fit the goal, usually squat, bench press, deadlift and overhead press. \
    Spread them over the days so no lift is trained heavy twice within 48 hours.
    - Increment per extra rep on a rep-out set: about 2.5 kg for lower-body lifts and 1.25 kg for presses.
    - Give each day 2-4 accessories with sets and reps that support the main lifts and keep \
    push and pull, quads and hamstrings in balance. Keep hard sets per muscle around 10-20 a week.
    - Plan a deload at least every 4-6 weeks (deload true halves accessory sets).
    - Use only exercise names from the list you are given, spelled exactly.
    - Use the training log to set sensible maxes and pick accessories they already do; respect \
    their notes. If a one-rep max is missing for a lift, estimate it from the log or leave the lift out.
    - If notes mention pain or injury, avoid loading it and say they should get it checked.
    - rules: 3-6 short sentences on how to progress, what to do after a missed rep-out, and \
    when to repeat a week. Write for a phone: plain words, no markdown.
    """

    static func schema() -> [String: Any] {
        func object(_ properties: [String: Any], _ required: [String]? = nil) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": required ?? Array(properties.keys).sorted(), "properties": properties]
        }
        let string: [String: Any] = ["type": "string"]
        let integer: [String: Any] = ["type": "integer"]
        let number: [String: Any] = ["type": "number"]
        let boolean: [String: Any] = ["type": "boolean"]
        return object([
            "name": ["type": "string", "description": "Short program name, e.g. 12-week bench focus."],
            "summary": ["type": "string", "description": "Two sentences on how the program works and why it fits them."],
            "lifts": [
                "type": "array",
                "description": "Main lifts progressed by percentage of training max.",
                "items": object([
                    "exercise": string,
                    "training_max_kg": number,
                    "increment_kg": ["type": "number", "description": "Kilograms added per rep beaten on a rep-out set."],
                ]),
            ],
            "days": [
                "type": "array",
                "description": "The training days of every week, in order.",
                "items": object([
                    "name": ["type": "string", "description": "e.g. Squat day or Upper A."],
                    "lifts": ["type": "array", "items": string, "description": "Main lifts trained this day, by exercise name."],
                    "accessories": ["type": "array", "items": object(["exercise": string, "sets": integer, "reps": integer, "notes": string])],
                ]),
            ],
            "weeks": [
                "type": "array",
                "description": "Every week in order. The main-lift sets apply to every main lift that week.",
                "items": object([
                    "phase": ["type": "string", "description": "e.g. 10s wave · Accumulation or Week 3 · Strength."],
                    "note": ["type": "string", "description": "What the week is for, one sentence."],
                    "deload": boolean,
                    "amrap_target": ["type": "integer", "description": "Reps to beat on the rep-out set, or 0 when the week has none."],
                    "sets": ["type": "array", "items": object(["percent": number, "reps": integer, "amrap": boolean, "warmup": boolean])],
                ]),
            ],
            "rules": ["type": "array", "items": string],
        ])
    }

    public static func prompt(_ request: ProgramRequest, exercises: [String], log: String) -> String {
        var lines = [
            "Write me a \(request.weeks)-week strength program with \(request.daysPerWeek) training days a week.",
            "My goal: \(request.goal.isEmpty ? "get stronger" : request.goal).",
        ]
        if !request.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Notes from me: \(request.notes)")
        }
        lines.append("")
        lines.append("Estimated one-rep maxes:")
        if request.oneRepMaxes.isEmpty {
            lines.append("- none known")
        } else {
            for (name, max) in request.oneRepMaxes.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(name): \(Plates.round(max, to: 0.5).formatted(.number.precision(.fractionLength(0...1)))) kg")
            }
        }
        lines.append("")
        lines.append("Exercises you can use (exact names):")
        lines.append(exercises.joined(separator: "; "))
        if !log.isEmpty {
            lines.append("")
            lines.append("My recent training:")
            lines.append(log)
        }
        return lines.joined(separator: "\n")
    }

    public static func body(model: CoachModel, prompt: String) throws -> Data {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 32_000,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema()],
            ],
        ]
        if model.supportsFallbacks { body["fallbacks"] = "default" }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public static func request(apiKey: String, model: CoachModel, prompt: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CoachError.missingKey }
        var request = URLRequest(url: CoachAPI.endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(CoachAPI.version, forHTTPHeaderField: "anthropic-version")
        if model.supportsFallbacks { request.setValue(CoachAPI.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try body(model: model, prompt: prompt)
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

    private struct Draft: Decodable {
        struct Lift: Decodable {
            var exercise: String
            var training_max_kg: Double
            var increment_kg: Double
        }

        struct Accessory: Decodable {
            var exercise: String
            var sets: Int
            var reps: Int
            var notes: String
        }

        struct Day: Decodable {
            var name: String
            var lifts: [String]
            var accessories: [Accessory]
        }

        struct MainSet: Decodable {
            var percent: Double
            var reps: Int
            var amrap: Bool
            var warmup: Bool
        }

        struct Week: Decodable {
            var phase: String
            var note: String
            var deload: Bool
            var amrap_target: Int
            var sets: [MainSet]
        }

        var name: String
        var summary: String
        var lifts: [Lift]
        var days: [Day]
        var weeks: [Week]
        var rules: [String]
    }

    /// Reads the answer into a program starting `start`. Out-of-range numbers are clamped and lifts
    /// without a training max are dropped, so a slightly off answer still makes a usable program.
    public static func parse(status: Int, data: Data, start: Date) throws -> StrengthProgram {
        guard (200..<300).contains(status) else { throw CoachAPI.error(status: status, data: data) }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw CoachError.badResponse }
        switch response.stop_reason {
        case "refusal": throw CoachError.refused
        case "max_tokens": throw CoachError.truncated
        default: break
        }
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8), let draft = try? JSONDecoder().decode(Draft.self, from: json) else {
            throw CoachError.badResponse
        }
        return try program(from: draft, start: start)
    }

    private static func program(from draft: Draft, start: Date) throws -> StrengthProgram {
        func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T { min(max(value, range.lowerBound), range.upperBound) }

        let lifts = draft.lifts
            .filter { !$0.exercise.isEmpty && $0.training_max_kg > 0 }
            .map { StrengthProgram.Lift(exercise: $0.exercise, trainingMax: Plates.round($0.training_max_kg, to: 0.5), increment: clamp($0.increment_kg, 0...5)) }
        let liftNames = Set(lifts.map(\.exercise))
        let days = draft.days.prefix(7).map { day in
            StrengthProgram.Day(
                name: day.name.isEmpty ? "Day" : day.name,
                lifts: day.lifts.filter(liftNames.contains),
                accessories: day.accessories.filter { !$0.exercise.isEmpty }.prefix(8).map {
                    .init(exercise: $0.exercise, sets: clamp($0.sets, 1...10), reps: clamp($0.reps, 1...50), notes: $0.notes)
                }
            )
        }
        let weeks = draft.weeks.prefix(24).map { week in
            let sets = week.sets.prefix(12).map {
                StrengthProgram.MainSet(clamp($0.percent, 20...105), clamp($0.reps, 1...30), amrap: $0.amrap, warmup: $0.warmup && !$0.amrap)
            }
            let hasAmrap = sets.contains(where: \.amrap)
            return StrengthProgram.Week(
                phase: week.phase,
                note: week.note,
                sets: sets,
                isDeload: week.deload,
                amrapTarget: hasAmrap && week.amrap_target > 0 ? clamp(week.amrap_target, 1...30) : nil
            )
        }
        guard !days.isEmpty, !weeks.isEmpty, days.contains(where: { !$0.lifts.isEmpty || !$0.accessories.isEmpty }) else {
            throw CoachError.badResponse
        }
        return StrengthProgram(
            name: draft.name.isEmpty ? "\(weeks.count)-week program" : draft.name,
            summary: draft.summary,
            source: .coach,
            startDate: start,
            lifts: lifts,
            days: days,
            weeks: weeks,
            rules: draft.rules
        )
    }
}
