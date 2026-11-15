import Foundation

/// What kind of cardio a logged session was.
public enum CardioActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case run, walk, cycle, row, swim, elliptical, stairs, hike, hiit, jumpRope, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .cycle: "Cycling"
        case .row: "Rowing"
        case .swim: "Swim"
        case .elliptical: "Elliptical"
        case .stairs: "Stairs"
        case .hike: "Hike"
        case .hiit: "HIIT"
        case .jumpRope: "Jump rope"
        case .other: "Cardio"
        }
    }

    /// Whether a distance makes sense for it.
    public var hasDistance: Bool {
        switch self {
        case .run, .walk, .cycle, .row, .swim, .hike, .elliptical: true
        case .stairs, .hiit, .jumpRope, .other: false
        }
    }

    /// Shown as speed (km/h) instead of pace (min/km).
    public var usesSpeed: Bool { self == .cycle }

    /// Energy cost at an easy, steady and hard effort, in METs (Compendium of Physical Activities).
    func met(_ effort: CardioEffort) -> Double {
        let (easy, steady, hard): (Double, Double, Double) = switch self {
        case .run: (7, 9.8, 11.8)
        case .walk: (2.8, 3.8, 5)
        case .cycle: (4, 6.8, 10)
        case .row: (4.8, 7, 8.5)
        case .swim: (5.8, 7, 9.8)
        case .elliptical: (4.6, 5, 6.3)
        case .stairs: (4, 8.8, 9.3)
        case .hike: (5.3, 6, 7.8)
        case .hiit: (6, 8, 11)
        case .jumpRope: (8.8, 11.8, 12.3)
        case .other: (4, 6, 8)
        }
        return switch effort {
        case .easy: easy
        case .steady: steady
        case .hard: hard
        }
    }
}

public enum CardioEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy, steady, hard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .easy: "Easy"
        case .steady: "Steady"
        case .hard: "Hard"
        }
    }
}

/// One cardio session logged by hand.
public struct CardioSession: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var activity: CardioActivity
    public var start: Date
    public var seconds: Int
    public var meters: Double?
    public var effort: CardioEffort
    /// Active energy typed in by hand; nil to estimate it.
    public var kcal: Double?
    public var averageHeartRate: Double?
    public var notes: String
    /// The workout the app saved to Apple Health for this session.
    public var savedHealthID: UUID?

    public init(
        id: UUID = UUID(), activity: CardioActivity, start: Date, seconds: Int, meters: Double? = nil,
        effort: CardioEffort = .steady, kcal: Double? = nil, averageHeartRate: Double? = nil, notes: String = "", savedHealthID: UUID? = nil
    ) {
        self.id = id
        self.activity = activity
        self.start = start
        self.seconds = seconds
        self.meters = meters
        self.effort = effort
        self.kcal = kcal
        self.averageHeartRate = averageHeartRate
        self.notes = notes
        self.savedHealthID = savedHealthID
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(seconds)) }
    public var duration: TimeInterval { TimeInterval(seconds) }

    /// Seconds per kilometre, when there is a distance and a time.
    public var secondsPerKm: Double? {
        guard let meters, meters > 0, seconds > 0 else { return nil }
        return Double(seconds) / (meters / 1000)
    }

    /// Kilometres per hour, when there is a distance and a time.
    public var kmPerHour: Double? {
        guard let meters, meters > 0, seconds > 0 else { return nil }
        return (meters / 1000) / (Double(seconds) / 3600)
    }

    /// The typed-in energy, or an estimate from the activity, effort, time and body weight
    /// (kcal = MET × kg × hours). Nil without a body weight to estimate from.
    public func energy(bodyMass: Double?) -> Double? {
        if let kcal, kcal > 0 { return kcal }
        guard let bodyMass, bodyMass > 0, seconds > 0 else { return nil }
        return activity.met(effort) * bodyMass * Double(seconds) / 3600
    }

    /// "5.2 km · 28:10 · 5:25 /km", "20 km · 45:00 · 26.7 km/h" or just "30:00".
    public var summary: String {
        var parts: [String] = []
        if let meters, meters > 0 { parts.append(Pace.distance(meters)) }
        parts.append(TimeEntry.format(seconds))
        if activity.usesSpeed, let speed = kmPerHour {
            parts.append("\((speed * 10).rounded() / 10) km/h")
        } else if let pace = secondsPerKm {
            parts.append(Pace.format(secondsPerKm: pace))
        }
        return parts.joined(separator: " · ")
    }
}

/// Totals over a set of cardio sessions.
public enum CardioTotals {
    public struct Week: Equatable, Sendable {
        public var sessions = 0
        public var seconds = 0
        public var meters: Double = 0
    }

    /// Sessions that start in [start, end).
    public static func totals(_ sessions: [CardioSession], in interval: DateInterval) -> Week {
        var week = Week()
        for session in sessions where session.start >= interval.start && session.start < interval.end {
            week.sessions += 1
            week.seconds += session.seconds
            week.meters += session.meters ?? 0
        }
        return week
    }

    /// The fastest pace (seconds per km) over at least `minMeters`, for a personal best.
    public static func bestPace(_ sessions: [CardioSession], activity: CardioActivity, minMeters: Double = 1000) -> CardioSession? {
        sessions
            .filter { $0.activity == activity && ($0.meters ?? 0) >= minMeters && $0.secondsPerKm != nil }
            .min { ($0.secondsPerKm ?? .infinity, $0.start) < ($1.secondsPerKm ?? .infinity, $1.start) }
    }

    public static func longest(_ sessions: [CardioSession], activity: CardioActivity) -> CardioSession? {
        sessions
            .filter { $0.activity == activity && ($0.meters ?? 0) > 0 }
            .max { ($0.meters ?? 0, $1.start) < ($1.meters ?? 0, $0.start) }
    }
}
