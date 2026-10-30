import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What the app uploads to the user's coach server (cloudflare/coach-mcp), so Claude can read the log
/// through the Overlo4d connector. The texts are the same ones the in-app chat's tools return.
public struct CoachSnapshot: Codable, Equatable, Sendable {
    public struct Workout: Codable, Equatable, Sendable {
        public var date: Date
        public var text: String

        public init(date: Date, text: String) {
            self.date = date
            self.text = text
        }
    }

    public static let currentFormat = 1

    public var format: Int
    public var generatedAt: Date
    public var timeZone: String
    public var goal: String
    /// The last year, newest first.
    public var workouts: [Workout]
    /// Exercise name → every session of it, for exercises that have been logged.
    public var exerciseHistory: [String: String]
    /// Every exercise name the app knows, so the server can check the names Claude uses.
    public var exerciseNames: [String]
    /// One line per exercise with muscles and equipment, for search.
    public var exercises: [String]
    /// One line per week, newest first, 12 weeks.
    public var weeklySets: [String]
    public var sleep: [String]
    public var food: [String]
    public var body: [String]
    public var plans: String
    public var planNames: [String]
    public var programs: String
    public var programNames: [String]

    public init(generatedAt: Date, timeZone: String, goal: String, workouts: [Workout], exerciseHistory: [String: String],
                exerciseNames: [String], exercises: [String], weeklySets: [String], sleep: [String], food: [String],
                body: [String], plans: String, planNames: [String], programs: String, programNames: [String]) {
        format = Self.currentFormat
        self.generatedAt = generatedAt
        self.timeZone = timeZone
        self.goal = goal
        self.workouts = workouts
        self.exerciseHistory = exerciseHistory
        self.exerciseNames = exerciseNames
        self.exercises = exercises
        self.weeklySets = weeklySets
        self.sleep = sleep
        self.food = food
        self.body = body
        self.plans = plans
        self.planNames = planNames
        self.programs = programs
        self.programNames = programNames
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Changes with the contents, not with the time it was made. Used to skip uploads when nothing changed.
    public var fingerprint: String {
        var copy = self
        copy.generatedAt = Date(timeIntervalSince1970: 0)
        return Backup.fingerprint(["snapshot": (try? copy.encoded()) ?? Data()])
    }
}

/// Something Claude sent back through the connector, waiting for the user to apply it.
public struct CoachInboxItem: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case planChange = "plan_change"
        case program
    }

    public var id: String
    public var createdAt: String
    public var kind: Kind
    public var title: String
    public var input: JSONValue

    public init(id: String, createdAt: String, kind: Kind, title: String, input: JSONValue) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.title = title
        self.input = input
    }

    public var date: Date? { try? Date(createdAt, strategy: .iso8601) }

    /// For plan changes.
    public var planProposal: PlanProposal? {
        kind == .planChange ? PlanProposal(input: input) : nil
    }

    /// For programs, starting `start`.
    public func program(start: Date) -> StrengthProgram? {
        guard kind == .program, let data = try? JSONEncoder().encode(input) else { return nil }
        return try? ProgramCoach.program(json: data, start: start)
    }
}

public enum CoachCloudError: Error, Equatable, Sendable {
    case badAddress
    case claimed
    case server(Int, String)
    case badResponse

    public var message: String {
        switch self {
        case .badAddress: "That isn't a web address. Paste the workers.dev address of your Worker."
        case .claimed: "This server is linked to another phone or token. Paste the full connector address from Claude instead, or reset the server (see the setup guide)."
        case .server(let status, let detail): detail.isEmpty ? "The server answered \(status)." : detail
        case .badResponse: "The server's answer couldn't be read. Is this the Overlo4d coach Worker?"
        }
    }
}

/// The address and token of the user's coach server, and the requests the app makes to it.
public struct CoachCloud: Equatable, Sendable {
    public var base: URL
    public var token: String

    public init(base: URL, token: String) {
        self.base = base
        self.token = token
    }

    /// Reads what the user pasted: the Worker's address ("overlo4d.name.workers.dev"), or the full
    /// connector address with the token ("https://…/mcp/<token>"), which links a second phone.
    /// Returns the base address and the token if one was in it.
    public static func parse(_ text: String) -> (base: URL, token: String?)? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed), components.scheme == "https" || components.scheme == "http",
              let host = components.host, host.contains(".") else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        var token: String?
        if let index = parts.firstIndex(of: "mcp"), index + 1 < parts.count, parts[index + 1].count >= 20 {
            token = parts[index + 1]
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let base = components.url else { return nil }
        return (base, token)
    }

    /// 32 random letters and digits.
    public static func newToken() -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// What the user adds in Claude as a custom connector.
    public var connectorURL: URL {
        base.appending(path: "mcp").appending(path: token)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path), timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
        }
        return request
    }

    public func uploadRequest(_ snapshot: CoachSnapshot) throws -> URLRequest {
        request("api/sync", method: "POST", body: try snapshot.encoded())
    }

    public func inboxRequest() -> URLRequest {
        request("api/inbox")
    }

    public func ackRequest(_ ids: [String]) -> URLRequest {
        let body = try? JSONEncoder().encode(["ids": ids])
        return request("api/inbox/ack", method: "POST", body: body)
    }

    /// Throws for anything but a 2xx answer.
    public static func check(status: Int, data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? ""
        if status == 403, detail.contains("another token") { throw CoachCloudError.claimed }
        throw CoachCloudError.server(status, detail)
    }

    public static func parseInbox(status: Int, data: Data) throws -> [CoachInboxItem] {
        try check(status: status, data: data)
        struct Response: Decodable { var items: [CoachInboxItem] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw CoachCloudError.badResponse }
        return response.items
    }
}
