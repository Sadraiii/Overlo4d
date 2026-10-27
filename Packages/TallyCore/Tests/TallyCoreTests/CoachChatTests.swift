import Foundation
import Testing
@testable import TallyCore

private func json(_ text: String) -> Data { Data(text.utf8) }

@Suite struct CoachChatTests {
    @Test func bodySendsToolsConversationAndContext() throws {
        let messages: [CoachChatMessage] = [.user("How's my bench?")]
        let now = try Date("2026-10-27T18:00:00Z", strategy: .iso8601)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let data = try CoachChat.body(model: .sonnet, messages: messages, goal: "Get stronger", now: now, calendar: utc)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["model"] as? String == "claude-sonnet-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["thinking"] == nil)
        #expect(body["tool_choice"] == nil)
        #expect((body["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        #expect(String(decoding: data, as: UTF8.self).contains("\"max_tokens\":16000"))

        let system = try #require(body["system"] as? [[String: Any]])
        let context = try #require(system.last?["text"] as? String)
        #expect(context.contains("Tuesday, October 27, 2026"))
        #expect(context.contains("Their goal: Get stronger."))

        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == CoachTool.allCases.map(\.rawValue))
        for tool in tools {
            #expect(tool["strict"] as? Bool == true)
            let schema = try #require(tool["input_schema"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false)
        }

        let sent = try #require(body["messages"] as? [[String: Any]])
        #expect(sent.count == 1)
        let content = try #require(sent[0]["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "How's my bench?")
    }

    @Test func haikuHasNoFallbacks() throws {
        let data = try CoachChat.body(model: .haiku, messages: [.user("Hi")], goal: "", now: .now)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["fallbacks"] == nil)
        let request = try CoachChat.request(apiKey: "sk-ant-x", model: .haiku, messages: [.user("Hi")], goal: "")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-x")
    }

    @Test func parseKeepsThinkingAndReadsToolCalls() throws {
        let response = json("""
        {"content":[{"type":"thinking","thinking":"","signature":"abc"},{"type":"text","text":"Let me look."},\
        {"type":"tool_use","id":"toolu_1","name":"get_exercise_history","input":{"exercise":"Bench Press (Barbell)"}}],\
        "stop_reason":"tool_use"}
        """)
        let message = try CoachChat.parse(status: 200, data: response)
        #expect(message.role == "assistant")
        #expect(message.content.count == 3)
        #expect(message.content[0]["signature"] == "abc")
        #expect(message.text == "Let me look.")
        #expect(message.toolCalls == [CoachToolCall(id: "toolu_1", name: "get_exercise_history", input: ["exercise": "Bench Press (Barbell)"])])
    }

    @Test func parseErrors() {
        #expect(throws: CoachError.refused) {
            try CoachChat.parse(status: 200, data: json(#"{"content":[],"stop_reason":"refusal"}"#))
        }
        #expect(throws: CoachError.truncated) {
            try CoachChat.parse(status: 200, data: json(#"{"content":[{"type":"text","text":"Half"}],"stop_reason":"max_tokens"}"#))
        }
        #expect(throws: CoachError.badResponse) {
            try CoachChat.parse(status: 200, data: json(#"{"content":[{"type":"thinking","thinking":""}],"stop_reason":"end_turn"}"#))
        }
        #expect(throws: CoachError.invalidKey) {
            try CoachChat.parse(status: 401, data: json(#"{"type":"error","error":{"type":"authentication_error","message":"bad key"}}"#))
        }
    }

    @Test func fallbackDropsDeclinedThinkingAndToolCalls() throws {
        let response = json("""
        {"content":[{"type":"thinking","thinking":"","signature":"a"},{"type":"tool_use","id":"t0","name":"get_plans","input":{}},\
        {"type":"text","text":"Partial"},{"type":"fallback","from":{"model":"claude-sonnet-5-5"},"to":{"model":"claude-sonnet-5"}},\
        {"type":"thinking","thinking":"","signature":"b"},{"type":"tool_use","id":"t1","name":"get_plans","input":{}}],\
        "stop_reason":"tool_use"}
        """)
        let message = try CoachChat.parse(status: 200, data: response)
        #expect(message.content.compactMap { $0["type"]?.string } == ["text", "fallback", "thinking", "tool_use"])
        #expect(message.toolCalls.map(\.id) == ["t1"])
    }

    @Test func toolResultsMessage() throws {
        let message = CoachChat.results([
            CoachToolResult(id: "t1", text: "3 workouts"),
            CoachToolResult(id: "t2", text: "No plan called Legs.", isError: true),
            CoachToolResult(id: "t3", text: ""),
        ])
        #expect(message.role == "user")
        #expect(message.isToolResults)
        #expect(message.content[0] == ["type": "tool_result", "tool_use_id": "t1", "content": "3 workouts"])
        #expect(message.content[1]["is_error"] == true)
        #expect(message.content[2]["content"] == "Nothing found.")
        #expect(!CoachChatMessage.user("Hi").isToolResults)
    }

    @Test func messagesRoundTripThroughDisk() throws {
        let message = CoachChatMessage(role: "assistant", content: [
            ["type": "tool_use", "id": "t", "name": "get_workouts", "input": ["days": 14]],
            ["type": "text", "text": "Done", "citations": .null, "flag": false],
        ])
        let decoded = try JSONDecoder().decode(CoachChatMessage.self, from: JSONEncoder().encode(message))
        #expect(decoded == message)
        #expect(decoded.toolCalls.first?.input["days"]?.int == 14)
    }

    @Test func planProposalReadsChanges() throws {
        let input: JSONValue = [
            "plan": "Push",
            "summary": "More rear delts.",
            "changes": [
                ["action": "add", "exercise": "Face Pull (Cable)", "new_exercise": "", "sets": 3, "reps": 15],
                ["action": "replace", "exercise": "Dips", "new_exercise": "Close Grip Bench Press", "sets": 0, "reps": 0],
                ["action": "set_sets", "exercise": "Bench Press (Barbell)", "new_exercise": "", "sets": 4, "reps": 0],
                ["action": "remove", "exercise": "Cable Crossover", "new_exercise": "", "sets": 0, "reps": 0],
            ],
        ]
        let proposal = try #require(PlanProposal(input: input))
        #expect(proposal.plan == "Push")
        #expect(proposal.changes.map(\.label) == [
            "Add Face Pull (Cable): 3 × 15",
            "Swap Dips for Close Grip Bench Press",
            "Bench Press (Barbell): 4 sets",
            "Remove Cable Crossover",
        ])
        #expect(proposal.changes[1].sets == nil)
    }

    @Test func planProposalRejectsIncompleteChanges() {
        #expect(PlanProposal(input: ["plan": "Push", "summary": "", "changes": []]) == nil)
        #expect(PlanProposal(input: [
            "plan": "Push", "summary": "",
            "changes": [["action": "replace", "exercise": "Dips", "new_exercise": "", "sets": 0, "reps": 0]],
        ]) == nil)
        #expect(PlanProposal(input: [
            "plan": "Push", "summary": "",
            "changes": [["action": "set_sets", "exercise": "Dips", "new_exercise": "", "sets": 0, "reps": 0]],
        ]) == nil)
        #expect(PlanProposal(input: [
            "plan": "Push", "summary": "",
            "changes": [["action": "shuffle", "exercise": "Dips", "new_exercise": "", "sets": 1, "reps": 1]],
        ]) == nil)
    }
}
