import Foundation

/// Summary of recent training that the app writes for the Training widget.
public struct ActivitySnapshot: Codable, Sendable {
    public struct LastWorkout: Codable, Sendable {
        public var name: String
        public var date: Date
        public var duration: TimeInterval
        public var volume: Double
        public var sets: Int
        public var records: Int

        public init(name: String, date: Date, duration: TimeInterval, volume: Double, sets: Int, records: Int) {
            self.name = name
            self.date = date
            self.duration = duration
            self.volume = volume
            self.sets = sets
            self.records = records
        }
    }

    /// Start dates of recent workouts (last ~60 days).
    public var workoutDates: [Date]
    public var weekStreak: Int
    public var lastWorkout: LastWorkout?

    public init(workoutDates: [Date] = [], weekStreak: Int = 0, lastWorkout: LastWorkout? = nil) {
        self.workoutDates = workoutDates
        self.weekStreak = weekStreak
        self.lastWorkout = lastWorkout
    }

    /// Seven flags (first weekday → last) for whether a workout happened that day.
    public func trainedDays(inWeekOf date: Date = .now, calendar: Calendar = .current) -> [Bool] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return Array(repeating: false, count: 7)
        }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return false }
            return workoutDates.contains { calendar.isDate($0, inSameDayAs: day) }
        }
    }

    public func workoutsThisWeek(_ date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return workoutDates.filter { week.contains($0) }.count
    }

    /// The streak as of `date`. The app saves it when data changes, so if neither this week
    /// nor last week has a workout by now, the streak has ended even though the file still has it.
    public func currentStreak(at date: Date = .now, calendar: Calendar = .current) -> Int {
        guard weekStreak > 0,
              let last = workoutDates.max(),
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        else { return 0 }
        return last >= lastWeek ? weekStreak : 0
    }

    /// Workouts in each of the last `weeks` weeks, oldest first, ending with the week of `date`.
    public func weeklyCounts(weeks: Int, endingAt date: Date = .now, calendar: Calendar = .current) -> [Int] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return Array(repeating: 0, count: weeks)
        }
        return (0..<weeks).reversed().map { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else { return 0 }
            return workoutDates.filter { $0 >= start && $0 < end }.count
        }
    }

    /// Index of `date` within its week (0 = first weekday).
    public static func weekdayIndex(of date: Date = .now, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    public static func load() -> ActivitySnapshot {
        SharedStorage.load(ActivitySnapshot.self, from: SharedStorage.activityFile) ?? ActivitySnapshot()
    }
}
