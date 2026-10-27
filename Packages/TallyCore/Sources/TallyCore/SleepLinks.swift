import Foundation

/// Tags worked out from the rest of the app: workouts and the food diary.
public enum SleepAutoTags {
    public static let lateWorkout = "Late workout"
    public static let bigLateMeal = "Big late meal"
    public static let lateCaffeine = "Late caffeine"

    /// Something eaten or drunk, as logged in the food diary.
    public struct Intake: Sendable, Equatable {
        public var time: Date
        public var kcal: Double
        public var name: String

        public init(time: Date, kcal: Double, name: String) {
            self.time = time
            self.kcal = kcal
            self.name = name
        }
    }

    /// Training within this long before bed keeps the body too awake to fall asleep easily.
    static let workoutWindow: TimeInterval = 3 * 3600
    static let mealWindow: TimeInterval = 3 * 3600
    static let mealKcal = 500.0
    /// Caffeine takes about 5 hours to halve, so 8 hours before bed is a common cut-off.
    static let caffeineWindow: TimeInterval = 8 * 3600

    static let caffeineWords = [
        "coffee", "espresso", "latte", "cappuccino", "americano", "macchiato", "flat white", "cold brew",
        "energy drink", "red bull", "monster", "cola", "coke", "pepsi", "pre workout", "preworkout",
        "matcha", "black tea", "green tea", "caffeine",
    ]

    /// Tags for a night that started at `bedtime`.
    public static func tags(bedtime: Date, workouts: [DateInterval], intake: [Intake]) -> [String] {
        var tags: [String] = []
        let workoutStart = bedtime.addingTimeInterval(-workoutWindow)
        if workouts.contains(where: { $0.end > workoutStart && $0.start < bedtime }) {
            tags.append(lateWorkout)
        }
        let mealStart = bedtime.addingTimeInterval(-mealWindow)
        let lateKcal = intake.filter { $0.time >= mealStart && $0.time <= bedtime }.reduce(0) { $0 + $1.kcal }
        if lateKcal >= mealKcal {
            tags.append(bigLateMeal)
        }
        let caffeineStart = bedtime.addingTimeInterval(-caffeineWindow)
        if intake.contains(where: { $0.time >= caffeineStart && $0.time <= bedtime && hasCaffeine($0.name) }) {
            tags.append(lateCaffeine)
        }
        return tags
    }

    /// Whole-word match, so "chocolate" isn't cola and "decaf coffee" doesn't count.
    static func hasCaffeine(_ name: String) -> Bool {
        let words = name.lowercased().map { $0.isLetter ? $0 : " " }
        let text = " " + String(words).split(separator: " ").joined(separator: " ") + " "
        if text.contains(" decaf ") || text.contains(" decaffeinated ") { return false }
        return caffeineWords.contains { text.contains(" \($0) ") }
    }
}

/// How workouts after a good night compare with workouts after a short one.
public struct SleepTrainingLink: Sendable, Equatable {
    /// Average volume against that workout's usual, as a fraction: 0.05 is 5% more than usual.
    public var afterRested: Double
    public var afterShort: Double
    public var restedCount: Int
    public var shortCount: Int

    public var difference: Double { afterRested - afterShort }
}

public enum SleepTraining {
    /// A finished workout. Workouts are compared with others of the same name.
    public struct Session: Sendable, Equatable {
        public var start: Date
        public var name: String
        public var volume: Double

        public init(start: Date, name: String, volume: Double) {
            self.start = start
            self.name = name
            self.volume = volume
        }
    }

    /// Workouts need this many sessions of the same name to have a usual volume.
    static let sessionsPerName = 3
    /// And each group this many workouts before the comparison means anything.
    static let groupMinimum = 3

    /// Nil until there are enough workouts after both kinds of night.
    public static func link(
        nights: [SleepNight], sessions: [Session], goal: TimeInterval, calendar: Calendar = .current
    ) -> SleepTrainingLink? {
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(grouping: sessions.filter { $0.volume > 0 }, by: \.name)
            .filter { $0.value.count >= sessionsPerName }

        var rested: [Double] = []
        var short: [Double] = []
        for (_, group) in byName {
            let usual = group.reduce(0) { $0 + $1.volume } / Double(group.count)
            for session in group {
                // The night before: the one you woke up from on the workout's day, if it ended before the workout.
                guard let night = byDay[calendar.startOfDay(for: session.start)], night.wake <= session.start else { continue }
                let relative = session.volume / usual - 1
                if night.asleep >= goal - 30 * 60 {
                    rested.append(relative)
                } else if night.asleep < goal - 60 * 60 {
                    short.append(relative)
                }
            }
        }
        guard rested.count >= groupMinimum, short.count >= groupMinimum,
              let restedMean = SleepClock.mean(rested), let shortMean = SleepClock.mean(short) else { return nil }
        return SleepTrainingLink(afterRested: restedMean, afterShort: shortMean, restedCount: rested.count, shortCount: short.count)
    }
}
