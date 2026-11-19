import Foundation

// Cycles, adherence, reminders and the training view of the private peptide tracker.
// Like Peptides.swift, this only works on the user's own numbers.

/// Weeks on and weeks off from a start day. With no weeks off it is one block that then ends.
public struct PeptideCycle: Codable, Hashable, Sendable {
    public var start: DayKey
    public var weeksOn: Int
    public var weeksOff: Int

    public init(start: DayKey, weeksOn: Int, weeksOff: Int = 0) {
        self.start = start
        self.weeksOn = max(1, weeksOn)
        self.weeksOff = max(0, weeksOff)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decode(DayKey.self, forKey: .start),
                  weeksOn: try c.decodeIfPresent(Int.self, forKey: .weeksOn) ?? 1,
                  weeksOff: try c.decodeIfPresent(Int.self, forKey: .weeksOff) ?? 0)
    }

    public enum Phase: Equatable, Sendable {
        case notStarted(inDays: Int)
        /// Week numbers count from 1 within the block; `daysLeft` includes today.
        case on(week: Int, of: Int, daysLeft: Int)
        case off(week: Int, of: Int, daysLeft: Int)
        case finished

        public var isOn: Bool { if case .on = self { true } else { false } }

        public var label: String {
            switch self {
            case .notStarted(let days): days == 1 ? "Starts tomorrow" : "Starts in \(days) days"
            case .on(let week, let of, _): "Week \(week) of \(of)"
            case .off(let week, let of, _): "Off, week \(week) of \(of)"
            case .finished: "Cycle finished"
            }
        }
    }

    public func phase(on day: DayKey, calendar: Calendar = .current) -> Phase {
        let offset = PeptideDays.between(start, day, calendar: calendar)
        if offset < 0 { return .notStarted(inDays: -offset) }
        let onDays = weeksOn * 7
        let length = onDays + weeksOff * 7
        if weeksOff == 0 && offset >= onDays { return .finished }
        let position = offset % length
        if position < onDays {
            return .on(week: position / 7 + 1, of: weeksOn, daysLeft: onDays - position)
        }
        let offPosition = position - onDays
        return .off(week: offPosition / 7 + 1, of: weeksOff, daysLeft: weeksOff * 7 - offPosition)
    }
}

/// Whole days between two day keys.
enum PeptideDays {
    static func between(_ from: DayKey, _ to: DayKey, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from.date(calendar: calendar), to: to.date(calendar: calendar)).day ?? 0
    }
}

/// Planned against logged entries over a past window.
public struct PeptideAdherence: Equatable, Sendable {
    public let planned: Int
    public let logged: Int
    public let days: Int

    /// 0...1; logging extra never goes past 1.
    public var fraction: Double { planned > 0 ? min(1, Double(logged) / Double(planned)) : 1 }
    public var percent: Int { Int((fraction * 100).rounded()) }
}

/// The training side of a peptide: workouts and body weight since it was started, against the
/// same length of time before.
public struct PeptideTrainingSummary: Equatable, Sendable {
    public let since: DayKey
    public let days: Int
    public let workouts: Int
    public let perWeek: Double
    /// Workouts a week in the same number of days before `since`; nil when there were none at all.
    public let previousPerWeek: Double?
    public let weightStart: Double?
    public let weightNow: Double?

    public var weightChange: Double? {
        guard let weightStart, let weightNow else { return nil }
        return weightNow - weightStart
    }

    /// `workoutDays` has one element per workout. `weights` are kg, any order.
    public static func build(since: DayKey, today: DayKey, workoutDays: [DayKey], weights: [WeightPoint],
                             calendar: Calendar = .current) -> PeptideTrainingSummary {
        let days = max(1, PeptideDays.between(since, today, calendar: calendar) + 1)
        let weeks = Double(days) / 7
        let during = workoutDays.filter { $0 >= since && $0 <= today }.count
        let before = since.adding(days: -days, calendar: calendar)
        let previous = workoutDays.filter { $0 >= before && $0 < since }.count
        let sorted = weights.sorted { $0.day < $1.day }
        // The weight that held when it started: the last one on or before that day, or else the first after.
        let start = sorted.last { $0.day <= since } ?? sorted.first { $0.day <= today }
        let now = sorted.last { $0.day <= today }
        return PeptideTrainingSummary(
            since: since, days: days, workouts: during,
            perWeek: Double(during) / max(weeks, 1),
            previousPerWeek: workoutDays.contains { $0 < since } ? Double(previous) / max(weeks, 1) : nil,
            weightStart: start?.kg, weightNow: now == start ? start?.kg : now?.kg
        )
    }
}

extension PeptideProfile {
    /// Whole days since the active vial was mixed.
    public func mixedDays(now: Date, calendar: Calendar = .current) -> Int? {
        guard let vialOpened else { return nil }
        return max(0, PeptideDays.between(DayKey(vialOpened, calendar: calendar), DayKey(now, calendar: calendar), calendar: calendar))
    }

    /// The mixed vial has reached the number of days the user said it is used for.
    public func pastKeepDays(now: Date, calendar: Calendar = .current) -> Bool {
        guard let keepsDays, keepsDays > 0, let mixed = mixedDays(now: now, calendar: calendar) else { return false }
        return mixed >= keepsDays
    }

    /// Few portions left and no spare vial to open next.
    public var runningLow: Bool { tracksVial && doseMcg > 0 && dosesLeft <= 2 && spareVials == 0 }

    /// The day this profile counts from: its cycle start, else when it was added.
    public func startDay(calendar: Calendar = .current) -> DayKey? {
        cycle?.start ?? createdAt.map { DayKey($0, calendar: calendar) }
    }
}

extension PeptideData {
    /// Planned and logged entries over the last `days` full days (today is left out, as it isn't over).
    /// Counts from when the profile was added or first logged; nil without a fixed rhythm or history.
    public func adherence(_ profile: PeptideProfile, days: Int = 28, now: Date, calendar: Calendar = .current) -> PeptideAdherence? {
        guard profile.schedule.perWeek != nil else { return nil }
        let today = DayKey(now, calendar: calendar)
        let entries = logs(for: profile.id).map { DayKey($0.date, calendar: calendar) }
        let firstLog = entries.min()
        let added = profile.createdAt.map { DayKey($0, calendar: calendar) }
        guard let begin = [firstLog, added].compactMap({ $0 }).min() else { return nil }
        let windowStart = max(begin, today.adding(days: -days, calendar: calendar))
        guard windowStart < today else { return nil }

        var planned = 0
        var day = windowStart
        while day < today {
            let on = profile.cycle.map { $0.phase(on: day, calendar: calendar).isOn } ?? true
            if on {
                let before = entries.filter { $0 < day }
                planned += profile.schedule.dueToday(logDays: before, today: day, calendar: calendar)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        let logged = entries.filter { $0 >= windowStart && $0 < today }.count
        let span = PeptideDays.between(windowStart, today, calendar: calendar)
        return PeptideAdherence(planned: planned, logged: logged, days: span)
    }

    /// When to remind over the next `days` days: the profile's time on each day something is due,
    /// assuming each due entry gets logged. Times already past today are left out.
    public func reminders(_ profile: PeptideProfile, days: Int = 14, now: Date, calendar: Calendar = .current) -> [Date] {
        guard let minutes = profile.reminderMinutes, (0..<1440).contains(minutes) else { return [] }
        let today = DayKey(now, calendar: calendar)
        var logDays = logs(for: profile.id).map { DayKey($0.date, calendar: calendar) }
        var result: [Date] = []
        for offset in 0..<max(0, days) {
            let day = today.adding(days: offset, calendar: calendar)
            if let cycle = profile.cycle, !cycle.phase(on: day, calendar: calendar).isOn { continue }
            let due = profile.schedule.dueToday(logDays: logDays, today: day, calendar: calendar)
            guard due > 0 else { continue }
            logDays += Array(repeating: day, count: due)
            guard let at = calendar.date(byAdding: .minute, value: minutes, to: day.date(calendar: calendar)), at > now else { continue }
            result.append(at)
        }
        return result
    }

    /// Entries by day between two days, both included.
    public func entriesByDay(from: DayKey, to: DayKey, calendar: Calendar = .current) -> [DayKey: [PeptideLogEntry]] {
        var result: [DayKey: [PeptideLogEntry]] = [:]
        for entry in logs {
            let day = DayKey(entry.date, calendar: calendar)
            if day >= from && day <= to { result[day, default: []].append(entry) }
        }
        return result
    }

    /// Mean feeling (1–5) of a profile's entries in the last `days` days; nil when none were rated.
    public func averageFeeling(_ id: UUID, days: Int = 28, now: Date) -> Double? {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let ratings = logs(for: id).filter { $0.date >= since }.compactMap(\.feeling)
        return ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
    }
}
