import Foundation

/// Where a lift's estimated one-rep max is heading, from its recent sessions.
public enum StrengthForecast {
    public struct Point: Sendable, Equatable {
        public let date: Date
        /// Best estimated one-rep max of the session, in kg.
        public let oneRepMax: Double

        public init(date: Date, oneRepMax: Double) {
            self.date = date
            self.oneRepMax = oneRepMax
        }
    }

    public enum Trend: String, Sendable, Equatable {
        case rising, flat, falling
    }

    public enum Confidence: String, Sendable, Equatable {
        case low, medium, high
    }

    public struct Milestone: Sendable, Equatable {
        /// The next round number above the all-time best, in kg.
        public let weight: Double
        /// When the trend reaches it; nil when the lift isn't rising or it is more than a year off.
        public let date: Date?
    }

    public struct Result: Sendable, Equatable {
        /// Best estimate from the last three sessions.
        public let current: Double
        /// Best estimate ever.
        public let best: Double
        /// Change per week on the trend line, in kg.
        public let perWeek: Double
        public let inFourWeeks: Double
        public let inTwelveWeeks: Double
        public let trend: Trend
        public let confidence: Confidence
        /// Sessions the trend is drawn from.
        public let sessions: Int
        public let milestone: Milestone
    }

    /// Fastest gain the forecast will believe: 2.5% of the current max per week.
    static let maxWeeklyGain = 0.025
    /// Twelve weeks out, progress is assumed to have slowed to this share of today's pace.
    static let longRangeShare = 0.75

    /// A straight line through the sessions of the last `windowDays`. Needs four sessions at least
    /// two weeks apart, otherwise there is nothing to say yet.
    public static func forecast(_ points: [Point], now: Date, unit: WeightUnit = .kg, windowDays: Int = 84) -> Result? {
        let all = points.filter { $0.oneRepMax > 0 && $0.date <= now }.sorted { $0.date < $1.date }
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let recent = all.filter { $0.date >= since }
        guard recent.count >= 4, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 14 * 86_400,
              let best = all.map(\.oneRepMax).max() else { return nil }

        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map(\.oneRepMax)
        let n = Double(recent.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
            syy += (y - meanY) * (y - meanY)
        }
        guard sxx > 0 else { return nil }
        let slopePerDay = sxy / sxx
        let fit = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1

        let current = recent.suffix(3).map(\.oneRepMax).max() ?? last.oneRepMax
        let cap = current * maxWeeklyGain
        let perWeek = min(slopePerDay * 7, cap)
        let trend: Trend = perWeek > current * 0.001 ? .rising : perWeek < -current * 0.001 ? .falling : .flat
        // A falling line isn't projected forward: one good session turns it around.
        let gain = max(perWeek, 0)
        let confidence: Confidence = recent.count >= 8 && fit >= 0.5 ? .high : recent.count >= 5 && fit >= 0.25 ? .medium : .low

        let step = unit.toKg(unit.milestoneStep)
        var target = (best / step).rounded(.down) * step + step
        if target - best < step * 0.02 { target += step }
        var reached: Date?
        if gain > 0 {
            let days = (target - current) / (gain / 7)
            if days <= 365 { reached = now.addingTimeInterval(max(days, 0) * 86_400) }
        }

        return Result(
            current: current,
            best: best,
            perWeek: perWeek,
            inFourWeeks: current + gain * 4,
            inTwelveWeeks: current + gain * 12 * longRangeShare,
            trend: trend,
            confidence: confidence,
            sessions: recent.count,
            milestone: Milestone(weight: target, date: reached)
        )
    }

    public struct Target: Sendable, Equatable {
        public let reps: Int
        /// The lightest loadable weight that beats the record for this many reps, in kg.
        public let weight: Double
    }

    /// For each rep count, the lightest weight (a multiple of `step`) whose estimated max beats `best`.
    public static func targets(toBeat best: Double, reps: [Int] = [1, 3, 5, 8], step: Double = 2.5) -> [Target] {
        guard best > 0, step > 0 else { return [] }
        return reps.filter { $0 > 0 }.map { reps in
            let exact = OneRepMax.weight(forReps: reps, oneRepMax: best)
            var count = (exact / step).rounded(.down)
            while OneRepMax.estimate(weight: count * step, reps: reps) <= best + 0.0001 { count += 1 }
            return Target(reps: reps, weight: count * step)
        }
    }
}
