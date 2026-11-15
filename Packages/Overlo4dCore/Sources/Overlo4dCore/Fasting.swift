import Foundation

/// Intermittent fasting, like Lifesum's fasting tracker: a plan (hours fasting), the fast running now and past fasts.
public struct FastingLog: Codable, Equatable, Sendable {
    public struct Fast: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var start: Date
        public var end: Date
        public var goalHours: Int

        public init(id: UUID = UUID(), start: Date, end: Date, goalHours: Int) {
            self.id = id
            self.start = start
            self.end = end
            self.goalHours = goalHours
        }

        public var hours: Double { end.timeIntervalSince(start) / 3600 }
        public var reachedGoal: Bool { hours >= Double(goalHours) }
    }

    /// Fasting hours of the plan: 16 means 16:8.
    public var planHours = 16
    /// When the fast running now started.
    public var current: Date?
    /// Finished fasts, newest first.
    public var history: [Fast] = []

    public init() {}

    public static let plans = [12, 14, 16, 18, 20, 23]
    public static let maxHistory = 120

    /// "16:8", or "OMAD" for one meal a day.
    public static func label(hours: Int) -> String {
        hours >= 23 ? "OMAD" : "\(hours):\(24 - hours)"
    }

    public var isFasting: Bool { current != nil }

    public mutating func start(at date: Date = .now) {
        current = date
    }

    /// Ends the running fast and keeps it if it lasted at least an hour. Returns the fast.
    @discardableResult
    public mutating func end(at date: Date = .now) -> Fast? {
        guard let start = current else { return nil }
        current = nil
        guard date.timeIntervalSince(start) >= 3600 else { return nil }
        let fast = Fast(start: start, end: date, goalHours: planHours)
        history.insert(fast, at: 0)
        if history.count > Self.maxHistory { history.removeLast(history.count - Self.maxHistory) }
        return fast
    }

    public func elapsed(at date: Date = .now) -> TimeInterval {
        current.map { max(date.timeIntervalSince($0), 0) } ?? 0
    }

    /// Share of the plan done, 0...1+.
    public func progress(at date: Date = .now) -> Double {
        elapsed(at: date) / (Double(planHours) * 3600)
    }

    /// When the running fast reaches the plan.
    public var goalDate: Date? {
        current.map { $0.addingTimeInterval(Double(planHours) * 3600) }
    }

    /// Fasts in a row, newest first, that reached their goal.
    public var streak: Int {
        history.prefix { $0.reachedGoal }.count
    }

    /// Average length of the last `count` fasts, in hours.
    public func averageHours(last count: Int = 7) -> Double? {
        let recent = history.prefix(count)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.hours } / Double(recent.count)
    }
}

/// What the body is roughly doing at each point of a fast. General guidance, not medical advice.
public enum FastingStage: Int, CaseIterable, Sendable {
    case digesting, settling, fasted, fatBurning, deepFast

    public static func at(hours: Double) -> FastingStage {
        switch hours {
        case ..<4: .digesting
        case ..<8: .settling
        case ..<12: .fasted
        case ..<18: .fatBurning
        default: .deepFast
        }
    }

    /// Hours into the fast when the stage starts.
    public var startHours: Int {
        switch self {
        case .digesting: 0
        case .settling: 4
        case .fasted: 8
        case .fatBurning: 12
        case .deepFast: 18
        }
    }

    public var title: String {
        switch self {
        case .digesting: "Digesting"
        case .settling: "Blood sugar settling"
        case .fasted: "Fasted"
        case .fatBurning: "Using more fat"
        case .deepFast: "Long fast"
        }
    }

    public var detail: String {
        switch self {
        case .digesting: "Your body is using energy from your last meal."
        case .settling: "Blood sugar and insulin are coming down."
        case .fasted: "Your body starts to draw on stored energy."
        case .fatBurning: "With glycogen running lower, more energy comes from fat."
        case .deepFast: "Drink water, and break the fast gently with protein and vegetables."
        }
    }
}
