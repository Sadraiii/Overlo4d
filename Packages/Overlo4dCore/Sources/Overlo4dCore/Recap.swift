import Foundation

/// A finished workout, reduced to what the weekly recap needs.
public struct SessionSummary: Sendable, Equatable {
    public var start: Date
    public var duration: TimeInterval
    public var volume: Double
    public var sets: Int
    public var records: Int
    /// Best estimated one-rep max per exercise in this session (weight exercises only).
    public var bestOneRepMax: [UUID: Double]

    public init(start: Date, duration: TimeInterval, volume: Double, sets: Int, records: Int, bestOneRepMax: [UUID: Double]) {
        self.start = start
        self.duration = duration
        self.volume = volume
        self.sets = sets
        self.records = records
        self.bestOneRepMax = bestOneRepMax
    }
}

/// A workout recorded by another app, e.g. a run on Apple Watch.
public struct ActivitySummary: Sendable, Equatable {
    public var start: Date
    public var duration: TimeInterval
    public var energy: Double?

    public init(start: Date, duration: TimeInterval, energy: Double?) {
        self.start = start
        self.duration = duration
        self.energy = energy
    }
}

public struct WeekTotals: Sendable, Equatable {
    public var workouts = 0
    public var duration: TimeInterval = 0
    public var volume: Double = 0
    public var sets = 0
    public var records = 0
    public var activities = 0
    public var activityEnergy: Double = 0

    public init() {}
}

public struct Improvement: Sendable, Equatable {
    public var exerciseID: UUID
    public var before: Double
    public var after: Double
    public var change: Double { after - before }

    public init(exerciseID: UUID, before: Double, after: Double) {
        self.exerciseID = exerciseID
        self.before = before
        self.after = after
    }
}

public struct WeeklyRecap: Sendable, Equatable {
    public var week: DateInterval
    public var totals: WeekTotals
    public var previous: WeekTotals
    /// The exercise whose best estimated 1RM rose the most against its last session before the week.
    public var mostImproved: Improvement?
}

public enum Recaps {
    /// The recap for the week containing `date`, compared with the week before.
    public static func recap(weekOf date: Date, sessions: [SessionSummary], activities: [ActivitySummary], calendar: Calendar = .current) -> WeeklyRecap? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: week.start),
              let previousWeek = calendar.dateInterval(of: .weekOfYear, for: previousDay) else { return nil }
        return WeeklyRecap(
            week: week,
            totals: totals(in: week, sessions: sessions, activities: activities),
            previous: totals(in: previousWeek, sessions: sessions, activities: activities),
            mostImproved: mostImproved(in: week, sessions: sessions)
        )
    }

    /// Starts of the weeks that have at least one session, newest first.
    public static func weeks(with sessions: [SessionSummary], calendar: Calendar = .current) -> [Date] {
        Set(sessions.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start }).sorted(by: >)
    }

    /// `DateInterval.contains` includes the end, which is the first instant of the next week.
    static func contains(_ week: DateInterval, _ date: Date) -> Bool {
        date >= week.start && date < week.end
    }

    static func totals(in week: DateInterval, sessions: [SessionSummary], activities: [ActivitySummary]) -> WeekTotals {
        var totals = WeekTotals()
        for session in sessions where contains(week, session.start) {
            totals.workouts += 1
            totals.duration += session.duration
            totals.volume += session.volume
            totals.sets += session.sets
            totals.records += session.records
        }
        for activity in activities where contains(week, activity.start) {
            totals.activities += 1
            totals.activityEnergy += activity.energy ?? 0
        }
        return totals
    }

    static func mostImproved(in week: DateInterval, sessions: [SessionSummary]) -> Improvement? {
        let earlier = sessions.filter { $0.start < week.start }.sorted { $0.start > $1.start }
        var thisWeek: [UUID: Double] = [:]
        for session in sessions where contains(week, session.start) {
            for (id, value) in session.bestOneRepMax {
                thisWeek[id] = max(thisWeek[id] ?? 0, value)
            }
        }
        var best: Improvement?
        for (id, after) in thisWeek {
            guard let before = earlier.lazy.compactMap({ $0.bestOneRepMax[id] }).first, after > before else { continue }
            let candidate = Improvement(exerciseID: id, before: before, after: after)
            // Ties go to the lower UUID string so the result doesn't depend on dictionary order.
            if let current = best,
               candidate.change < current.change
                || (candidate.change == current.change && candidate.exerciseID.uuidString > current.exerciseID.uuidString) {
                continue
            }
            best = candidate
        }
        return best
    }
}
