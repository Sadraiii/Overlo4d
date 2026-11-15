import Foundation

/// Something about recent sleep worth pointing out, most serious first.
public enum SleepFlag: Sendable, Equatable {
    /// Averaging well under the goal over the last week.
    case short(average: TimeInterval, goal: TimeInterval)
    /// Hours short of the goal, added up over the last 7 nights.
    case debt(hours: Double)
    /// Bedtime moves around a lot from night to night.
    case irregular(spreadMinutes: Double)
    /// A lot of the time in bed is spent awake.
    case restless(efficiency: Double)
    /// Bedtime is regularly after midnight while the alarm doesn't move.
    case lateBedtime(averageMinutesAfterNoon: Double)
    /// Sleeping much later at weekends than on weekdays ("social jet lag"), in minutes.
    case weekendShift(minutes: Double)

    /// 2 = fix this, 1 = keep an eye on it.
    public var severity: Int {
        switch self {
        case .short, .debt: 2
        case .irregular, .restless, .lateBedtime, .weekendShift: 1
        }
    }
}

/// How ready for a hard session last night's sleep leaves you.
public enum SleepReadiness: String, Sendable, Equatable {
    /// Slept enough: train as planned.
    case ready
    /// A short night or a lot of debt: keep the weights, cut a set or two and stay off failure.
    case easy
    /// Very little sleep: a light session, mobility or a rest day.
    case recover
}

/// What the tags a user adds to nights seem to do to their score.
public struct SleepTagEffect: Sendable, Equatable {
    public var tag: String
    /// Average score on nights with the tag minus nights without it.
    public var scoreChange: Double
    /// Average time asleep with the tag minus without, in seconds.
    public var durationChange: TimeInterval
    public var nights: Int
}

public struct SleepReport: Sendable, Equatable {
    /// Nights in the last 7 days.
    public var week: [SleepNight]
    public var averageAsleep: TimeInterval?
    /// Hours short of the goal over the last 7 nights (nights over the goal don't pay it back).
    public var debtHours: Double
    /// Average bedtime in minutes after noon, over the last 14 nights.
    public var usualBedtime: Double?
    /// Average wake time in minutes after midnight, over the last 14 nights.
    public var usualWake: Double?
    /// Standard deviation of bedtime over the last 14 nights, in minutes.
    public var bedtimeSpread: Double?
    public var flags: [SleepFlag]
    public var readiness: SleepReadiness?
    public var tagEffects: [SleepTagEffect]
}

public enum SleepInsights {
    /// Bedtimes that vary by more than this (standard deviation, minutes) unsettle the body clock.
    static let irregularMinutes = 45.0
    /// Below this share of time in bed asleep is restless sleep.
    static let restlessEfficiency = 0.85
    /// Weekend sleep this much later than weekday sleep throws the body clock off on Mondays.
    static let weekendShiftMinutes = 60.0
    /// Tags need this many nights with and without them before they're compared.
    static let tagMinimum = 3

    public static func report(
        _ nights: [SleepNight], goal: TimeInterval, now: Date = .now, calendar: Calendar = .current
    ) -> SleepReport {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let fortnightStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let week = nights.filter { $0.day >= weekStart && $0.day <= today }
        let fortnight = nights.filter { $0.day >= fortnightStart && $0.day <= today }

        let averageAsleep = SleepClock.mean(week.map(\.asleep))
        let debt = week.reduce(0) { $0 + max(0, goal - $1.asleep) } / 3600
        let bedtimes = fortnight.map { SleepClock.bedtimeMinutes($0.bedtime, calendar: calendar) }
        let usualBedtime = SleepClock.mean(bedtimes)
        let usualWake = SleepClock.mean(fortnight.map { SleepClock.wakeMinutes($0.wake, calendar: calendar) })
        let spread = SleepClock.standardDeviation(bedtimes)

        var flags: [SleepFlag] = []
        if week.count >= 3, let averageAsleep {
            if averageAsleep < goal - 30 * 60 {
                flags.append(.short(average: averageAsleep, goal: goal))
            }
            if debt >= 5 {
                flags.append(.debt(hours: debt))
            }
        }
        if fortnight.count >= 5, let spread, spread > irregularMinutes {
            flags.append(.irregular(spreadMinutes: spread))
        }
        let efficiencies = week.compactMap(\.efficiency)
        if efficiencies.count >= 3, let average = SleepClock.mean(efficiencies), average < restlessEfficiency {
            flags.append(.restless(efficiency: average))
        }
        // Midnight is 720 minutes after noon.
        if fortnight.count >= 5, let usualBedtime, usualBedtime > 750 {
            flags.append(.lateBedtime(averageMinutesAfterNoon: usualBedtime))
        }
        if let shift = weekendShift(nights, now: now, calendar: calendar), shift >= weekendShiftMinutes {
            flags.append(.weekendShift(minutes: shift))
        }
        flags.sort { $0.severity > $1.severity }

        return SleepReport(
            week: week,
            averageAsleep: averageAsleep,
            debtHours: debt,
            usualBedtime: usualBedtime,
            usualWake: usualWake,
            bedtimeSpread: spread,
            flags: flags,
            readiness: readiness(nights, goal: goal, debtHours: debt, now: now, calendar: calendar),
            tagEffects: tagEffects(nights, goal: goal, usualBedtime: usualBedtime, calendar: calendar)
        )
    }

    /// How much later the middle of the night falls at weekends than on weekdays, over the last
    /// 4 weeks. Nil without at least 2 weekend and 3 weekday nights.
    static func weekendShift(_ nights: [SleepNight], now: Date, calendar: Calendar) -> Double? {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -27, to: today) ?? today
        let recent = nights.filter { $0.day >= start && $0.day <= today }
        let midpoint: (SleepNight) -> Double = {
            SleepClock.bedtimeMinutes($0.bedtime.addingTimeInterval($0.inBed / 2), calendar: calendar)
        }
        // Nights you wake up from on Saturday or Sunday follow a free evening.
        let weekend = recent.filter { calendar.isDateInWeekend($0.day) }.map(midpoint)
        let weekday = recent.filter { !calendar.isDateInWeekend($0.day) }.map(midpoint)
        guard weekend.count >= 2, weekday.count >= 3,
              let weekendMean = SleepClock.mean(weekend), let weekdayMean = SleepClock.mean(weekday) else { return nil }
        return weekendMean - weekdayMean
    }

    /// From last night only (nil if there's no night for today) and the week's debt.
    static func readiness(_ nights: [SleepNight], goal: TimeInterval, debtHours: Double, now: Date, calendar: Calendar) -> SleepReadiness? {
        guard let last = nights.first(where: { $0.day == calendar.startOfDay(for: now) }) else { return nil }
        let hours = last.asleep / 3600
        if hours < 5 { return .recover }
        if hours < 6 || last.asleep < goal - 90 * 60 || debtHours >= 7 { return .easy }
        return .ready
    }

    /// Tags whose nights differ from the rest, biggest difference first. Uses up to the last 60 nights.
    static func tagEffects(_ nights: [SleepNight], goal: TimeInterval, usualBedtime: Double?, calendar: Calendar) -> [SleepTagEffect] {
        let recent = Array(nights.prefix(60))
        let scored = recent.map { (night: $0, score: Double(SleepScore.score($0, goal: goal, usualBedtime: usualBedtime, calendar: calendar))) }
        let tags = Set(recent.flatMap(\.tags))
        return tags.compactMap { tag -> SleepTagEffect? in
            let with = scored.filter { $0.night.tags.contains(tag) }
            let without = scored.filter { !$0.night.tags.contains(tag) }
            guard with.count >= tagMinimum, without.count >= tagMinimum,
                  let scoreWith = SleepClock.mean(with.map(\.score)), let scoreWithout = SleepClock.mean(without.map(\.score)),
                  let asleepWith = SleepClock.mean(with.map(\.night.asleep)), let asleepWithout = SleepClock.mean(without.map(\.night.asleep))
            else { return nil }
            return SleepTagEffect(tag: tag, scoreChange: scoreWith - scoreWithout, durationChange: asleepWith - asleepWithout, nights: with.count)
        }
        .filter { abs($0.scoreChange) >= 3 }
        .sorted { abs($0.scoreChange) != abs($1.scoreChange) ? abs($0.scoreChange) > abs($1.scoreChange) : $0.tag < $1.tag }
    }
}

/// Sleep as lines of text for the coach.
public enum SleepDigest {
    /// A summary line, then one line per night (up to `limit`), newest first.
    public static func lines(
        _ nights: [SleepNight], goal: TimeInterval, link: SleepTrainingLink? = nil, limit: Int = 14,
        now: Date = .now, calendar: Calendar = .current
    ) -> [String] {
        guard !nights.isEmpty else { return [] }
        let report = SleepInsights.report(nights, goal: goal, now: now, calendar: calendar)
        var summary = "Goal \(duration(goal)) asleep."
        if let average = report.averageAsleep {
            summary += " Last 7 nights: average \(duration(average)), \(String(format: "%.1f", report.debtHours)) h short of the goal in total."
        }
        if let bedtime = report.usualBedtime, let wake = report.usualWake {
            summary += " Usual bedtime \(clock(SleepClock.timeOfDay(bedtimeMinutes: bedtime))), wake \(clock(SleepClock.timeOfDay(minutes: wake)))."
        }
        if let spread = report.bedtimeSpread {
            summary += " Bedtime varies by about \(Int(spread.rounded())) min."
        }
        if let link {
            summary += " Workout volume against usual: \(percent(link.afterRested)) after nights near the goal (\(link.restedCount) workouts), \(percent(link.afterShort)) after short nights (\(link.shortCount) workouts)."
        }

        var dayFormat = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.locale = Locale(identifier: "en_US_POSIX")

        let rows = nights.prefix(limit).map { night in
            var text = "\(night.day.formatted(dayFormat)): in bed \(clock(night.bedtime, calendar)) to \(clock(night.wake, calendar)), asleep \(duration(night.asleep))"
            if night.hasStages {
                text += " (deep \(duration(night.deep ?? 0)), REM \(duration(night.rem ?? 0)))"
            }
            text += ", score \(SleepScore.score(night, goal: goal, usualBedtime: report.usualBedtime, calendar: calendar))"
            if let quality = night.quality { text += ", felt \(quality)/5" }
            if !night.tags.isEmpty { text += ", tags: \(night.tags.joined(separator: ", "))" }
            if !night.naps.isEmpty {
                text += ", plus \(night.naps.count == 1 ? "a nap" : "\(night.naps.count) naps") of \(duration(night.naps.reduce(0) { $0 + $1.duration }))"
            }
            if night.isManual { text += " [logged by hand]" }
            return text
        }
        return [summary] + rows
    }

    /// "7 h 05 m"
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
    }

    /// "+6%", "-9%"
    public static func percent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return value > 0 ? "+\(value)%" : "\(value)%"
    }

    static func clock(_ time: (hour: Int, minute: Int)) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clock((parts.hour ?? 0, parts.minute ?? 0))
    }
}
