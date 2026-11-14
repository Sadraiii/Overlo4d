import Foundation

/// When to remind about training.
public enum WorkoutReminders {
    public struct Settings: Sendable, Equatable {
        /// Calendar weekdays to train on: 1 = Sunday … 7 = Saturday.
        public var days: Set<Int>
        /// Minutes after midnight.
        public var minutes: Int
        /// Remind after this many days without a workout; 0 = off.
        public var nudgeAfterDays: Int

        public init(days: Set<Int>, minutes: Int, nudgeAfterDays: Int = 0) {
            self.days = days
            self.minutes = minutes
            self.nudgeAfterDays = nudgeAfterDays
        }
    }

    /// "2,4,6" for Monday, Wednesday and Friday.
    public static func encode(_ days: Set<Int>) -> String {
        days.filter { (1...7).contains($0) }.sorted().map(String.init).joined(separator: ",")
    }

    public static func decode(_ text: String) -> Set<Int> {
        Set(text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) })
    }

    /// The reminder times in the next `horizonDays`, soonest first. Today is left out once it has
    /// passed or a workout was already done.
    public static func upcoming(_ settings: Settings, now: Date, trainedToday: Bool, horizonDays: Int = 21, calendar: Calendar = .current) -> [Date] {
        guard !settings.days.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<max(horizonDays, 1)).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  settings.days.contains(calendar.component(.weekday, from: day)),
                  let fire = time(on: day, minutes: settings.minutes, calendar: calendar),
                  fire > now else { return nil }
            if offset == 0 && trainedToday { return nil }
            return fire
        }
    }

    /// When to nudge after a break: `nudgeAfterDays` after the last workout at the reminder time, or
    /// the next such time if that has passed. Nil when off or nothing was ever logged.
    public static func nudge(_ settings: Settings, lastWorkout: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard settings.nudgeAfterDays > 0, let lastWorkout,
              let day = calendar.date(byAdding: .day, value: settings.nudgeAfterDays, to: calendar.startOfDay(for: lastWorkout)),
              let fire = time(on: day, minutes: settings.minutes, calendar: calendar) else { return nil }
        if fire > now { return fire }
        guard let today = time(on: calendar.startOfDay(for: now), minutes: settings.minutes, calendar: calendar) else { return nil }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    static func time(on day: Date, minutes: Int, calendar: Calendar) -> Date? {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day)
    }

    /// "Mon, Wed, Fri", "Every day" or "Off".
    public static func summary(_ days: Set<Int>, calendar: Calendar = .current) -> String {
        let valid = days.filter { (1...7).contains($0) }
        if valid.isEmpty { return "Off" }
        if valid.count == 7 { return "Every day" }
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday
        let ordered = (0..<7).map { (first - 1 + $0) % 7 + 1 }.filter(valid.contains)
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
