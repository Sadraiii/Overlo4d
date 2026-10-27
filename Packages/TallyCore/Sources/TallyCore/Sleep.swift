import Foundation

/// A stage of sleep as Apple Health records it. Watches record core, deep and REM; other sources
/// often only "asleep" or "in bed".
public enum SleepStage: String, Codable, Sendable, CaseIterable {
    case inBed, awake, asleep, core, deep, rem

    public var isAsleep: Bool {
        switch self {
        case .asleep, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }

    /// When two sources overlap, the more specific record wins: a Watch's stages beat a phone's
    /// "asleep", and a Watch's "awake" beats a broad "asleep" that covers it.
    var priority: Int {
        switch self {
        case .inBed: 0
        case .asleep: 1
        case .awake: 2
        case .core: 3
        case .rem: 4
        case .deep: 5
        }
    }
}

/// One sample from Apple Health.
public struct SleepSegment: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

/// One night of sleep, from Health or logged by hand.
public struct SleepNight: Sendable, Equatable, Identifiable {
    public var id: Date { day }
    /// Start of the day the night ended on: Tuesday's night is the one you wake up from on Tuesday.
    public var day: Date
    public var bedtime: Date
    public var wake: Date
    /// Time actually asleep.
    public var asleep: TimeInterval
    /// Time awake between `bedtime` and `wake`, when the source records it.
    public var awake: TimeInterval
    /// Stage times; nil when the source doesn't record stages.
    public var deep: TimeInterval?
    public var rem: TimeInterval?
    public var core: TimeInterval?
    /// The night's segments, merged so they don't overlap, for the stage chart.
    public var segments: [SleepSegment]
    public var isManual: Bool
    /// How it felt, 1 (awful) to 5 (great), if the user said.
    public var quality: Int?
    /// Things the user noted about the evening, e.g. "Late caffeine".
    public var tags: [String]
    /// Sleep apart from the main night, such as an evening nap on the sofa. Not counted in `asleep`.
    public var naps: [DateInterval]

    public init(
        day: Date, bedtime: Date, wake: Date, asleep: TimeInterval, awake: TimeInterval = 0,
        deep: TimeInterval? = nil, rem: TimeInterval? = nil, core: TimeInterval? = nil,
        segments: [SleepSegment] = [], isManual: Bool = false, quality: Int? = nil, tags: [String] = [],
        naps: [DateInterval] = []
    ) {
        self.day = day
        self.bedtime = bedtime
        self.wake = wake
        self.asleep = asleep
        self.awake = awake
        self.deep = deep
        self.rem = rem
        self.core = core
        self.segments = segments
        self.isManual = isManual
        self.quality = quality
        self.tags = tags
        self.naps = naps
    }

    public var inBed: TimeInterval { wake.timeIntervalSince(bedtime) }

    /// Share of the time in bed spent asleep. Nil for hand-logged nights, which only know bed and wake times.
    public var efficiency: Double? {
        guard !isManual, inBed > 0 else { return nil }
        return min(asleep / inBed, 1)
    }

    public var hasStages: Bool { deep != nil || rem != nil }
}

/// A night logged by hand: bed and wake times, with an optional estimate of how long it took to fall asleep.
public struct ManualSleep: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var bedtime: Date
    public var wake: Date
    /// Minutes awake in the night, including falling asleep.
    public var awakeMinutes: Int
    public var quality: Int?
    public var tags: [String]
    public var note: String
    /// Recorded with the Good night / I'm up buttons rather than typed in. Health's record of the
    /// same night, when there is one, is more accurate and wins.
    public var tapped: Bool

    public init(
        id: UUID = UUID(), bedtime: Date, wake: Date, awakeMinutes: Int = 0, quality: Int? = nil,
        tags: [String] = [], note: String = "", tapped: Bool = false
    ) {
        self.id = id
        self.bedtime = bedtime
        self.wake = wake
        self.awakeMinutes = awakeMinutes
        self.quality = quality
        self.tags = tags
        self.note = note
        self.tapped = tapped
    }
}

public enum SleepAnalysis {
    /// Sleep that starts at or after this hour counts towards the next morning (as in Apple Health).
    static let dayBoundaryHour = 18

    /// The day a night belongs to: the date you wake up on.
    public static func day(for start: Date, calendar: Calendar = .current) -> Date {
        let shifted = start.addingTimeInterval(TimeInterval(24 - dayBoundaryHour) * 3600)
        return calendar.startOfDay(for: shifted)
    }

    /// Groups Health samples into nights, newest first. Overlapping samples from several sources
    /// (an iPhone and a Watch, say) are merged so no minute is counted twice.
    public static func nights(from segments: [SleepSegment], calendar: Calendar = .current) -> [SleepNight] {
        let valid = segments.filter { $0.end > $0.start }
        let grouped = Dictionary(grouping: valid) { day(for: $0.start, calendar: calendar) }
        return grouped.compactMap { day, segments in night(day: day, segments: segments) }
            .sorted { $0.day > $1.day }
    }

    /// A break this long with nothing recorded splits sleep into separate blocks.
    static let blockGap: TimeInterval = 90 * 60

    static func night(day: Date, segments: [SleepSegment]) -> SleepNight? {
        // The block with the most sleep is the night; other blocks with sleep are naps.
        let blocks = self.blocks(merge(segments))
        let asleepIn: ([SleepSegment]) -> TimeInterval = { block in
            block.filter(\.stage.isAsleep).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }
        guard let merged = blocks.max(by: { asleepIn($0) < asleepIn($1) }), asleepIn(merged) > 0 else { return nil }
        let naps = blocks.filter { $0 != merged && asleepIn($0) > 0 }.compactMap { block -> DateInterval? in
            let sleep = block.filter(\.stage.isAsleep)
            guard let start = sleep.first?.start, let end = sleep.last?.end else { return nil }
            return DateInterval(start: start, end: end)
        }
        let segments = segments.filter { $0.end > merged.first!.start && $0.start < merged.last!.end }
        let bedtime = merged.map(\.start).min()!
        let wake = merged.map(\.end).max()!
        var totals: [SleepStage: TimeInterval] = [:]
        for segment in merged {
            totals[segment.stage, default: 0] += segment.end.timeIntervalSince(segment.start)
        }
        let staged = segments.contains { [.core, .deep, .rem].contains($0.stage) }
        let asleep = SleepStage.allCases.filter(\.isAsleep).reduce(0) { $0 + (totals[$1] ?? 0) }
        // Gaps with no record at all between bed and wake count as awake.
        let awake = wake.timeIntervalSince(bedtime) - asleep
        return SleepNight(
            day: day, bedtime: bedtime, wake: wake, asleep: asleep, awake: max(0, awake),
            deep: staged ? totals[.deep] ?? 0 : nil,
            rem: staged ? totals[.rem] ?? 0 : nil,
            core: staged ? (totals[.core] ?? 0) + (totals[.asleep] ?? 0) : nil,
            segments: merged,
            naps: naps.sorted { $0.start < $1.start }
        )
    }

    /// Splits merged, time-ordered segments wherever nothing is recorded for `blockGap` or more.
    static func blocks(_ merged: [SleepSegment]) -> [[SleepSegment]] {
        var blocks: [[SleepSegment]] = []
        for segment in merged {
            if let last = blocks.last?.last, segment.start.timeIntervalSince(last.end) < blockGap {
                blocks[blocks.count - 1].append(segment)
            } else {
                blocks.append([segment])
            }
        }
        return blocks
    }

    /// Splits the timeline at every boundary and keeps the highest-priority stage in each slice,
    /// joining neighbouring slices of the same stage.
    static func merge(_ segments: [SleepSegment]) -> [SleepSegment] {
        let edges = Set(segments.flatMap { [$0.start, $0.end] }).sorted()
        var result: [SleepSegment] = []
        for (start, end) in zip(edges, edges.dropFirst()) {
            let covering = segments.filter { $0.start <= start && $0.end >= end }
            guard let stage = covering.max(by: { $0.stage.priority < $1.stage.priority })?.stage else { continue }
            if let last = result.last, last.stage == stage, last.end == start {
                result[result.count - 1].end = end
            } else {
                result.append(SleepSegment(start: start, end: end, stage: stage))
            }
        }
        return result
    }

    /// A hand-logged night as a `SleepNight`.
    public static func night(from log: ManualSleep, calendar: Calendar = .current) -> SleepNight {
        let inBed = max(0, log.wake.timeIntervalSince(log.bedtime))
        let awake = min(inBed, TimeInterval(log.awakeMinutes) * 60)
        return SleepNight(
            day: day(for: log.bedtime, calendar: calendar), bedtime: log.bedtime, wake: log.wake,
            asleep: inBed - awake, awake: awake, isManual: true, quality: log.quality, tags: log.tags
        )
    }

    /// Health nights and hand-logged ones together, newest first. A typed-in night replaces
    /// Health's for the same day, since the user entered it on purpose; a tapped one doesn't.
    public static func combine(health: [SleepNight], manual: [ManualSleep], calendar: Calendar = .current) -> [SleepNight] {
        var byDay = Dictionary(health.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        for log in manual {
            let night = night(from: log, calendar: calendar)
            if log.tapped, byDay[night.day].map({ !$0.isManual }) == true { continue }
            byDay[night.day] = night
        }
        return byDay.values.sorted { $0.day > $1.day }
    }
}

/// A 0–100 score for one night.
public enum SleepScore {
    public struct Parts: Sendable, Equatable {
        /// Out of 50: time asleep against the goal.
        public var duration: Int
        /// Out of 20: how much of the time in bed was sleep (or how it felt, for hand-logged nights).
        public var efficiency: Int
        /// Out of 15: deep and REM sleep, when the source records stages.
        public var restoration: Int
        /// Out of 15: going to bed near the usual time.
        public var timing: Int

        public var total: Int { duration + efficiency + restoration + timing }
    }

    /// Deep and REM together are usually 35–45% of a night.
    static let restorativeShare = 0.40

    /// `usualBedtime` is in minutes after noon (see `SleepClock`); without it timing scores full marks.
    public static func parts(_ night: SleepNight, goal: TimeInterval, usualBedtime: Double? = nil, calendar: Calendar = .current) -> Parts {
        let durationShare = goal > 0 ? min(night.asleep / goal, 1) : 1
        let duration = Int((durationShare * 50).rounded())

        let efficiency: Int
        if let value = night.efficiency {
            // 70% or less scores nothing, 95% or more scores full.
            efficiency = Int((clamp((value - 0.70) / 0.25) * 20).rounded())
        } else if let quality = night.quality {
            efficiency = Int((Double(quality - 1) / 4 * 20).rounded())
        } else {
            efficiency = Int((Double(max(0, night.inBed - night.awake)) / max(night.inBed, 1) * 20).rounded())
        }

        let restoration: Int
        if night.hasStages, night.asleep > 0 {
            let share = ((night.deep ?? 0) + (night.rem ?? 0)) / night.asleep
            restoration = Int((clamp(share / restorativeShare) * 15).rounded())
        } else {
            // Without stages, longer sleep is the best stand-in: most deep and REM comes with enough of it.
            restoration = Int((durationShare * 15).rounded())
        }

        let timing: Int
        if let usualBedtime {
            let offset = abs(SleepClock.bedtimeMinutes(night.bedtime, calendar: calendar) - usualBedtime)
            // Within 30 minutes is full marks, 2 hours or more off is none.
            timing = Int((clamp(1 - (offset - 30) / 90) * 15).rounded())
        } else {
            timing = 15
        }
        return Parts(duration: duration, efficiency: efficiency, restoration: restoration, timing: timing)
    }

    public static func score(_ night: SleepNight, goal: TimeInterval, usualBedtime: Double? = nil, calendar: Calendar = .current) -> Int {
        parts(night, goal: goal, usualBedtime: usualBedtime, calendar: calendar).total
    }

    static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// Times of day as minutes, so bedtimes either side of midnight can be averaged.
public enum SleepClock {
    /// Minutes after noon: 22:00 is 600, 01:30 is 810.
    public static func bedtimeMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes - 720 + 1440).truncatingRemainder(dividingBy: 1440)
    }

    /// Minutes after midnight.
    public static func wakeMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// Minutes after noon back to an hour and minute of the day.
    public static func timeOfDay(bedtimeMinutes: Double) -> (hour: Int, minute: Int) {
        timeOfDay(minutes: bedtimeMinutes + 720)
    }

    /// Minutes after midnight (any value) to an hour and minute of the day.
    public static func timeOfDay(minutes: Double) -> (hour: Int, minute: Int) {
        let total = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return (total / 60, total % 60)
    }

    /// When to be in bed to get `goal` asleep before `wake` (minutes after midnight), allowing
    /// `latency` minutes to fall asleep. Minutes after midnight, 0..<1440.
    public static func bedtime(forWake wake: Double, goal: TimeInterval, latency: Double = 15) -> Double {
        let minutes = wake - goal / 60 - latency
        return (minutes.truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mean = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
