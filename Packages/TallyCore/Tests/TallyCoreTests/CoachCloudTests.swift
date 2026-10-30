import Foundation
import Testing
@testable import TallyCore

@Suite struct CoachCloudTests {
    @Test func parsesWorkerAndConnectorAddresses() throws {
        let plain = try #require(CoachCloud.parse(" overlo4d.mahmud.workers.dev/ "))
        #expect(plain.base.absoluteString == "https://overlo4d.mahmud.workers.dev")
        #expect(plain.token == nil)

        let token = "abcdefghijklmnopqrstuvwxyz123456"
        let full = try #require(CoachCloud.parse("https://overlo4d.mahmud.workers.dev/mcp/\(token)"))
        #expect(full.base.absoluteString == "https://overlo4d.mahmud.workers.dev")
        #expect(full.token == token)
        #expect(CoachCloud(base: full.base, token: token).connectorURL.absoluteString == "https://overlo4d.mahmud.workers.dev/mcp/\(token)")

        #expect(CoachCloud.parse("not an address") == nil)
        #expect(CoachCloud.parse("localhost") == nil)
        #expect(CoachCloud.newToken().count == 32)
    }

    @Test func requestsCarryTheToken() throws {
        let cloud = CoachCloud(base: URL(string: "https://x.workers.dev")!, token: "t".padding(toLength: 32, withPad: "t", startingAt: 0))
        let snapshot = CoachSnapshot(generatedAt: .now, timeZone: "UTC", goal: "", workouts: [], exerciseHistory: [:], exerciseNames: [],
                                     exercises: [], weeklySets: [], sleep: [], food: [], body: [], plans: "", planNames: [], programs: "", programNames: [])
        let upload = try cloud.uploadRequest(snapshot)
        #expect(upload.url?.absoluteString == "https://x.workers.dev/api/sync")
        #expect(upload.httpMethod == "POST")
        #expect(upload.value(forHTTPHeaderField: "authorization") == "Bearer \(cloud.token)")
        let body = try #require(try JSONSerialization.jsonObject(with: upload.httpBody!) as? [String: Any])
        #expect(body["format"] as? Int == 1)
        #expect(cloud.ackRequest(["a"]).url?.path == "/api/inbox/ack")
    }

    @Test func fingerprintIgnoresTheTime() {
        func make(_ date: Date, goal: String) -> CoachSnapshot {
            CoachSnapshot(generatedAt: date, timeZone: "UTC", goal: goal, workouts: [], exerciseHistory: [:], exerciseNames: [],
                          exercises: [], weeklySets: [], sleep: [], food: [], body: [], plans: "", planNames: [], programs: "", programNames: [])
        }
        #expect(make(.now, goal: "a").fingerprint == make(.distantPast, goal: "a").fingerprint)
        #expect(make(.now, goal: "a").fingerprint != make(.now, goal: "b").fingerprint)
    }

    @Test func readsInboxItems() throws {
        let data = Data("""
        {"items":[
          {"id":"1","createdAt":"2026-10-30T20:00:00.000Z","kind":"plan_change","title":"Change to Push",
           "input":{"plan":"Push","summary":"More rear delts","changes":[{"action":"add","exercise":"Face Pull (Cable)","new_exercise":"","sets":3,"reps":15}]}},
          {"id":"2","createdAt":"2026-10-30T20:01:00Z","kind":"program","title":"Program: Block",
           "input":{"name":"Block","summary":"s","lifts":[{"exercise":"Squat (Barbell)","training_max_kg":120,"increment_kg":2.5}],
            "days":[{"name":"A","lifts":["Squat (Barbell)"],"accessories":[]}],
            "weeks":[{"phase":"W1","note":"","deload":false,"amrap_target":0,"sets":[{"percent":70,"reps":5,"amrap":false,"warmup":false}]}],
            "rules":[]}}
        ]}
        """.utf8)
        let items = try CoachCloud.parseInbox(status: 200, data: data)
        #expect(items.count == 2)
        let proposal = try #require(items[0].planProposal)
        #expect(proposal.plan == "Push")
        #expect(proposal.changes.first?.sets == 3)
        #expect(items[1].planProposal == nil)
        let program = try #require(items[1].program(start: .now))
        #expect(program.name == "Block")
        #expect(program.lifts.first?.trainingMax == 120)
        #expect(program.source == .coach)
    }

    @Test func claimedServerHasItsOwnError() {
        let data = Data(#"{"error":"This server is linked to another token."}"#.utf8)
        #expect(throws: CoachCloudError.claimed) { try CoachCloud.check(status: 403, data: data) }
        #expect(throws: CoachCloudError.server(500, "")) { try CoachCloud.check(status: 500, data: Data()) }
    }
}
