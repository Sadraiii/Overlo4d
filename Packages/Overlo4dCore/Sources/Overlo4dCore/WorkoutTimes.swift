import Foundation

/// A workout's start and end, edited as a day, a start time, an end time and a duration.
/// Each change keeps the other values sensible: moving the day or the start keeps the duration,
/// and an end time earlier than the start means the workout ran past midnight.
public struct WorkoutTimes: Equatable, Sendable {
    public var start: Date
    /// nil while the workout is still going and no end has been set.
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }

    /// Same start time and duration on another day.
    public func movedToDay(_ day: Date, calendar: Calendar = .current) -> WorkoutTimes {
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        let newStart = calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) ?? start
        return shifted(by: newStart.timeIntervalSince(start))
    }

    /// The start set to the hour and minute of `time` on the same day, keeping the duration.
    public func withStartTime(_ time: Date, calendar: Calendar = .current) -> WorkoutTimes {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        guard let newStart = calendar.date(
            bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0,
            of: calendar.startOfDay(for: start)
        ) else { return self }
        return shifted(by: newStart.timeIntervalSince(start))
    }

    /// The end set to the first time after the start with the hour and minute of `time`,
    /// so 00:30 after a 23:15 start is the next day.
    public func withEndTime(_ time: Date, calendar: Calendar = .current) -> WorkoutTimes {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        guard var newEnd = calendar.date(
            bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0,
            of: calendar.startOfDay(for: start)
        ) else { return self }
        if newEnd <= start {
            newEnd = calendar.date(byAdding: .day, value: 1, to: newEnd) ?? newEnd
        }
        return WorkoutTimes(start: start, end: newEnd)
    }

    /// The end moved so the workout lasts `seconds` (at least a minute).
    public func withDuration(_ seconds: TimeInterval) -> WorkoutTimes {
        WorkoutTimes(start: start, end: start.addingTimeInterval(max(60, seconds)))
    }

    /// Keeps a workout in progress from starting in the future; an end that lands in the past stays.
    public func clampedForLiveWorkout(now: Date) -> WorkoutTimes {
        guard start > now else { return self }
        return shifted(by: now.timeIntervalSince(start))
    }

    private func shifted(by offset: TimeInterval) -> WorkoutTimes {
        WorkoutTimes(start: start.addingTimeInterval(offset), end: end?.addingTimeInterval(offset))
    }
}
