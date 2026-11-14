import Foundation

/// How rested each muscle is, from the working sets it got in recent workouts.
public enum Recovery {
    /// Sets one muscle got in one workout (primary sets count fully, secondary half).
    public struct Load: Sendable, Equatable {
        public let muscle: String
        public let date: Date
        public let sets: Double

        public init(muscle: String, date: Date, sets: Double) {
            self.muscle = muscle
            self.date = date
            self.sets = sets
        }
    }

    public struct Status: Sendable, Equatable {
        public let muscle: String
        /// The last workout that worked it.
        public let lastTrained: Date
        /// When it should be fully recovered.
        public let readyAt: Date
        /// 0 just after training, 1 once recovered.
        public let progress: Double

        public var isReady: Bool { progress >= 1 }
    }

    /// Hours to recover from `sets` hard sets: 24 h plus 6 h a set, between 24 and 72 h.
    /// Four sets need 48 h, eight or more need the full 72 h.
    public static func hoursNeeded(sets: Double) -> Double {
        min(72, max(24, 24 + 6 * sets))
    }

    /// The status of every muscle trained in the last `lookback` (default 7 days). Sets on the same
    /// muscle from workouts less than 12 hours apart add up (e.g. a morning and an evening session).
    public static func status(loads: [Load], now: Date, lookback: TimeInterval = 7 * 24 * 3600) -> [String: Status] {
        var result: [String: Status] = [:]
        let recent = loads.filter { $0.sets > 0 && $0.date <= now && now.timeIntervalSince($0.date) <= lookback }
        for (muscle, items) in Dictionary(grouping: recent, by: \.muscle) {
            let sorted = items.sorted { $0.date < $1.date }
            // Merge sessions close together into one bout, timed from the later one.
            var bouts: [(date: Date, sets: Double)] = []
            for item in sorted {
                if let last = bouts.last, item.date.timeIntervalSince(last.date) < 12 * 3600 {
                    bouts[bouts.count - 1] = (item.date, last.sets + item.sets)
                } else {
                    bouts.append((item.date, item.sets))
                }
            }
            // The bout that keeps the muscle busy longest decides.
            guard let worst = bouts.max(by: { ready($0) < ready($1) }) else { continue }
            let readyAt = ready(worst)
            let total = readyAt.timeIntervalSince(worst.date)
            let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(worst.date) / total)) : 1
            result[muscle] = Status(muscle: muscle, lastTrained: sorted.last!.date, readyAt: readyAt, progress: progress)
        }
        return result
    }

    private static func ready(_ bout: (date: Date, sets: Double)) -> Date {
        bout.date.addingTimeInterval(hoursNeeded(sets: bout.sets) * 3600)
    }
}
