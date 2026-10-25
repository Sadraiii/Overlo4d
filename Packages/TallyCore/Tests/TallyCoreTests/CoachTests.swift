import Foundation
import Testing
@testable import TallyCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    try! Date(text + "Z", strategy: .iso8601)
}

private func json(_ text: String) -> Data { Data(text.utf8) }

private let answer = """
{"summary":"Solid week.","going_well":["Bench is up 5 kg."],"changes":[{"title":"Add a pull day","detail":"Rows twice a week."}],\
"warnings":[{"area":"Chest","detail":"24 sets is a lot.","level":"reduce"}],"next_session":"Back and legs."}
"""

@Suite struct CoachTests {
    @Test func bodyAsksForStructuredFeedbackWithFallbacks() throws {
        let data = try CoachAPI.body(model: .opus, prompt: "Hello")
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["temperature"] == nil)
        #expect(body["thinking"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["content"] as? String == "Hello")
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "medium")
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["summary", "going_well", "changes", "warnings", "next_session"])
    }

    @Test func haikuHasNoServerSideFallback() throws {
        let body = try #require(try JSONSerialization.jsonObject(with: CoachAPI.body(model: .haiku, prompt: "x")) as? [String: Any])
        #expect(body["fallbacks"] == nil)
        let request = try CoachAPI.request(apiKey: "key", model: .haiku, prompt: "x")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func requestSendsTheKeyAndVersion() throws {
        let request = try CoachAPI.request(apiKey: "sk-test", model: .sonnet, prompt: "x")
        #expect(request.url == CoachAPI.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(throws: CoachError.missingKey) { try CoachAPI.request(apiKey: "", model: .opus, prompt: "x") }
    }

    @Test func parsesTheTextBlockAfterThinking() throws {
        let response = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn",
         "content":[{"type":"thinking","thinking":"","signature":"abc"},{"type":"text","text":\(String(reflecting: answer))}]}
        """
        let feedback = try CoachAPI.parse(status: 200, data: json(response))
        #expect(feedback.summary == "Solid week.")
        #expect(feedback.goingWell == ["Bench is up 5 kg."])
        #expect(feedback.changes == [.init(title: "Add a pull day", detail: "Rows twice a week.")])
        #expect(feedback.warnings == [.init(area: "Chest", detail: "24 sets is a lot.", level: .reduce)])
        #expect(feedback.nextSession == "Back and legs.")
    }

    @Test func roundTripsFeedbackForTheCache() throws {
        let feedback = try JSONDecoder().decode(CoachFeedback.self, from: json(answer))
        let again = try JSONDecoder().decode(CoachFeedback.self, from: JSONEncoder().encode(feedback))
        #expect(again == feedback)
    }

    @Test func mapsStopReasonsAndErrors() {
        #expect(throws: CoachError.refused) {
            try CoachAPI.parse(status: 200, data: json(#"{"content":[],"stop_reason":"refusal"}"#))
        }
        #expect(throws: CoachError.truncated) {
            try CoachAPI.parse(status: 200, data: json(#"{"content":[{"type":"text","text":"{\"sum"}],"stop_reason":"max_tokens"}"#))
        }
        #expect(throws: CoachError.badResponse) {
            try CoachAPI.parse(status: 200, data: json(#"{"content":[{"type":"text","text":"not json"}],"stop_reason":"end_turn"}"#))
        }
        #expect(throws: CoachError.invalidKey) {
            try CoachAPI.parse(status: 401, data: json(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#))
        }
        #expect(throws: CoachError.rateLimited) {
            try CoachAPI.parse(status: 429, data: json(#"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#))
        }
        #expect(throws: CoachError.overloaded) {
            try CoachAPI.parse(status: 529, data: json(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        }
        #expect(throws: CoachError.api("model: bad")) {
            try CoachAPI.parse(status: 400, data: json(#"{"type":"error","error":{"type":"invalid_request_error","message":"model: bad"}}"#))
        }
        #expect(throws: CoachError.overloaded) { try CoachAPI.parse(status: 502, data: json("<html>")) }
    }

    @Test func promptListsLoadAndWorkoutsOldestFirst() {
        let workouts = [
            DigestWorkout(name: "Push", date: date("2026-10-20T18:00:00"), minutes: 55, exercises: [
                .init(name: "Bench Press (Barbell)", muscles: "Chest; also Triceps", sets: ["W 40 kg × 10", "60 kg × 8"], notes: "Felt strong"),
            ], isFocus: true),
            DigestWorkout(name: "Legs", date: date("2026-10-18T09:30:00"), minutes: 70, exercises: [
                .init(name: "Squat (Barbell)", muscles: "Quads, Glutes", sets: ["100 kg × 5"]),
            ], notes: "Knee a bit sore"),
        ]
        let text = CoachAPI.prompt(
            focus: .workout(name: "Push", date: date("2026-10-20T18:00:00")),
            goal: "Build muscle",
            workouts: workouts,
            load: ["Chest: 24 sets this week"],
            weekly: [(muscle: "Chest", sets: 24, usual: 12), (muscle: "Triceps", sets: 1.5, usual: nil)],
            now: date("2026-10-21T08:00:00"),
            calendar: utc
        )
        #expect(text.hasPrefix("Give feedback on my workout \"Push\""))
        #expect(text.contains("My goal: Build muscle."))
        #expect(text.contains("- Chest: 24 (usual 12)\n- Triceps: 1.5\n"))
        #expect(text.contains("- Chest: 24 sets this week"))
        #expect(text.contains("- Bench Press (Barbell) [Chest; also Triceps]: W 40 kg × 10, 60 kg × 8\n  Notes: Felt strong"))
        #expect(text.contains("Notes: Knee a bit sore"))
        let legs = text.range(of: "## Legs")
        let push = text.range(of: "## FOCUS Push")
        #expect(legs != nil && push != nil && legs!.lowerBound < push!.lowerBound)
    }

    @Test func promptForAnEmptyLog() {
        let text = CoachAPI.prompt(focus: .overall, goal: "", workouts: [], load: [], weekly: [], now: date("2026-10-21T08:00:00"), calendar: utc)
        #expect(text.hasPrefix("Review my training"))
        #expect(!text.contains("My goal"))
        #expect(text.contains("- nothing flagged"))
        #expect(text.contains("- none logged yet"))
    }
}
