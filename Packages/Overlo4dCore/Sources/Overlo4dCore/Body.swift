import Foundation

/// A body measurement besides weight (weight lives in the food diary).
public enum BodyMeasure: String, Codable, CaseIterable, Sendable, Identifiable {
    case bodyFat, neck, shoulders, chest, waist, hips
    case leftArm, rightArm, leftForearm, rightForearm
    case leftThigh, rightThigh, leftCalf, rightCalf

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .bodyFat: "Body fat"
        case .neck: "Neck"
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .waist: "Waist"
        case .hips: "Hips"
        case .leftArm: "Left arm"
        case .rightArm: "Right arm"
        case .leftForearm: "Left forearm"
        case .rightForearm: "Right forearm"
        case .leftThigh: "Left thigh"
        case .rightThigh: "Right thigh"
        case .leftCalf: "Left calf"
        case .rightCalf: "Right calf"
        }
    }

    /// "%" for body fat, "cm" for the rest.
    public var unit: String { self == .bodyFat ? "%" : "cm" }

    /// Values outside this range are typos and aren't saved.
    public var validRange: ClosedRange<Double> { self == .bodyFat ? 2...70 : 10...250 }

    /// Whether going down counts as progress. The rest are neutral (bigger arms may be the goal, or not).
    public var shrinkingIsProgress: Bool { self == .bodyFat || self == .waist }

    /// How to measure it, shown under the field.
    public var howTo: String {
        switch self {
        case .bodyFat: "From a smart scale, calipers or a DEXA scan. Use the same method each time."
        case .neck: "Just below the Adam's apple, tape level."
        case .shoulders: "Around the widest point of the shoulders, arms relaxed."
        case .chest: "Around the nipples, after breathing out normally."
        case .waist: "At the belly button, relaxed, after breathing out. Don't suck in."
        case .hips: "Around the widest part of the bum, feet together."
        case .leftArm, .rightArm: "Biceps at its widest, arm hanging relaxed (or flexed, but always the same)."
        case .leftForearm, .rightForearm: "Widest part, just below the elbow, hand open."
        case .leftThigh, .rightThigh: "Widest part, just below the bum, standing with weight on both legs."
        case .leftCalf, .rightCalf: "Widest part, standing."
        }
    }

    /// Tracked until the user picks their own.
    public static let defaults: [BodyMeasure] = [.waist, .chest, .hips, .leftArm, .rightArm, .leftThigh, .rightThigh]
}

/// Measurements taken on one day.
public struct BodyEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var day: DayKey
    public var values: [BodyMeasure: Double]
    public var note: String
    /// Made from Apple Health readings only, so it can't be edited or deleted here.
    public var fromHealth: Bool

    public init(id: UUID = UUID(), day: DayKey, values: [BodyMeasure: Double], note: String = "", fromHealth: Bool = false) {
        self.id = id
        self.day = day
        self.values = values
        self.note = note
        self.fromHealth = fromHealth
    }

    private enum CodingKeys: String, CodingKey { case id, day, values, note }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(DayKey.self, forKey: .day)
        // String keys; unknown measures from a newer version are dropped.
        let raw = try container.decodeIfPresent([String: Double].self, forKey: .values) ?? [:]
        values = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in BodyMeasure(rawValue: key).map { ($0, value) } })
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        fromHealth = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }), forKey: .values)
        try container.encode(note, forKey: .note)
    }
}

/// Which way a progress photo faces.
public enum PhotoPose: String, Codable, CaseIterable, Sendable, Identifiable {
    case front, side, back

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
}

/// A progress photo. The image itself is a file named `fileName` in the app's photo folder.
public struct ProgressPhoto: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var day: DayKey
    public var pose: PhotoPose
    public var fileName: String

    public init(id: UUID = UUID(), day: DayKey, pose: PhotoPose, fileName: String? = nil) {
        self.id = id
        self.day = day
        self.pose = pose
        self.fileName = fileName ?? "\(id.uuidString).jpg"
    }
}

/// One row of a before/after comparison.
public struct BodyChange: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let unit: String
    public let from: Double
    public let to: Double
    public let shrinkingIsProgress: Bool

    public init(name: String, unit: String, from: Double, to: Double, shrinkingIsProgress: Bool) {
        self.name = name
        self.unit = unit
        self.from = from
        self.to = to
        self.shrinkingIsProgress = shrinkingIsProgress
    }

    public var delta: Double { to - from }

    /// True when it moved the good way, false the bad way, nil when neutral or unchanged.
    public var isProgress: Bool? {
        guard abs(delta) >= 0.05, shrinkingIsProgress else { return nil }
        return delta < 0
    }
}

/// Body measurements and progress photos, saved to body.json.
public struct BodyLog: Codable, Equatable, Sendable {
    /// Oldest first, one per day.
    public private(set) var entries: [BodyEntry] = []
    /// Oldest first.
    public private(set) var photos: [ProgressPhoto] = []
    /// The measurements shown in the log sheet, in this order.
    public var tracked: [BodyMeasure] = BodyMeasure.defaults

    public init() {}

    private enum CodingKeys: String, CodingKey { case entries, photos, tracked }

    // Missing keys decode to defaults so the file can grow without breaking old saves.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try container.decodeIfPresent([BodyEntry].self, forKey: .entries) ?? []).sorted { $0.day < $1.day }
        photos = (try container.decodeIfPresent([ProgressPhoto].self, forKey: .photos) ?? []).sorted { $0.day < $1.day }
        let raw = try container.decodeIfPresent([String].self, forKey: .tracked)
        tracked = raw.map { $0.compactMap(BodyMeasure.init(rawValue:)) } ?? BodyMeasure.defaults
    }

    // MARK: Measurements

    /// Saves the day's measurements. Values out of range are left out; a day with none is removed.
    /// Measures already logged that day but not in `values` are kept.
    public mutating func log(_ values: [BodyMeasure: Double], note: String = "", on day: DayKey) {
        let valid = values.filter { $0.key.validRange.contains($0.value) }.mapValues { ($0 * 10).rounded() / 10 }
        if let index = entries.firstIndex(where: { $0.day == day }) {
            entries[index].values.merge(valid) { _, new in new }
            entries[index].note = note
        } else if !valid.isEmpty || !note.isEmpty {
            entries.append(BodyEntry(day: day, values: valid, note: note))
            entries.sort { $0.day < $1.day }
        }
    }

    /// Replaces a day's entry outright (editing), removing measures that were cleared.
    public mutating func replace(_ entry: BodyEntry) {
        entries.removeAll { $0.id == entry.id || $0.day == entry.day }
        var entry = entry
        entry.values = entry.values.filter { $0.key.validRange.contains($0.value) }
        guard !entry.values.isEmpty || !entry.note.isEmpty else { return }
        entries.append(entry)
        entries.sort { $0.day < $1.day }
    }

    public mutating func deleteEntry(_ id: UUID) { entries.removeAll { $0.id == id } }

    /// Logged entries with Apple Health readings filled in. Logged values win on the same day, and the
    /// last Health reading of a day wins over earlier ones.
    public static func merge(
        _ entries: [BodyEntry],
        health: [(measure: BodyMeasure, date: Date, value: Double)],
        calendar: Calendar = .current
    ) -> [BodyEntry] {
        var byDay = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        for reading in health.sorted(by: { $0.date < $1.date }) where reading.measure.validRange.contains(reading.value) {
            let day = DayKey(reading.date, calendar: calendar)
            if var entry = byDay[day] {
                if entry.fromHealth || entries.first(where: { $0.day == day })?.values[reading.measure] == nil {
                    entry.values[reading.measure] = reading.value
                }
                byDay[day] = entry
            } else {
                byDay[day] = BodyEntry(day: day, values: [reading.measure: reading.value], fromHealth: true)
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Every reading of one measure, oldest first.
    public static func series(_ measure: BodyMeasure, in entries: [BodyEntry]) -> [(day: DayKey, value: Double)] {
        entries.compactMap { entry in entry.values[measure].map { (entry.day, $0) } }
    }

    /// The reading closest to `day`, at most `within` days away. Earlier readings win ties.
    public static func value(_ measure: BodyMeasure, near day: DayKey, within: Int = 14, in entries: [BodyEntry], calendar: Calendar = .current) -> Double? {
        nearest(series(measure, in: entries), to: day, within: within, calendar: calendar)
    }

    static func nearest(_ points: [(day: DayKey, value: Double)], to day: DayKey, within: Int, calendar: Calendar) -> Double? {
        let best = points
            .map { (distance: abs($0.day.days(to: day, calendar: calendar)), before: $0.day <= day, value: $0.value) }
            .filter { $0.distance <= within }
            .min { ($0.distance, $0.before ? 0 : 1) < ($1.distance, $1.before ? 0 : 1) }
        return best?.value
    }

    /// Weight and every measurement known near both days, for a before/after comparison.
    public static func changes(
        from start: DayKey,
        to end: DayKey,
        entries: [BodyEntry],
        weights: [WeightPoint],
        calendar: Calendar = .current
    ) -> [BodyChange] {
        var rows: [BodyChange] = []
        let weightPoints = weights.map { (day: $0.day, value: $0.kg) }
        if let from = nearest(weightPoints, to: start, within: 14, calendar: calendar),
           let to = nearest(weightPoints, to: end, within: 14, calendar: calendar) {
            rows.append(BodyChange(name: "Weight", unit: "kg", from: from, to: to, shrinkingIsProgress: false))
        }
        for measure in BodyMeasure.allCases {
            guard let from = value(measure, near: start, in: entries, calendar: calendar),
                  let to = value(measure, near: end, in: entries, calendar: calendar)
            else { continue }
            rows.append(BodyChange(name: measure.name, unit: measure.unit, from: from, to: to, shrinkingIsProgress: measure.shrinkingIsProgress))
        }
        return rows
    }

    // MARK: Photos

    public mutating func add(_ photo: ProgressPhoto) {
        photos.append(photo)
        photos.sort { $0.day < $1.day }
    }

    /// Removes the photo and returns it, so its file can be deleted.
    @discardableResult
    public mutating func deletePhoto(_ id: UUID) -> ProgressPhoto? {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
        return photos.remove(at: index)
    }

    /// Days with photos, newest first.
    public var photoDays: [DayKey] {
        Array(Set(photos.map(\.day))).sorted(by: >)
    }

    public func photos(on day: DayKey) -> [ProgressPhoto] {
        photos.filter { $0.day == day }.sorted { PhotoPose.allCases.firstIndex(of: $0.pose)! < PhotoPose.allCases.firstIndex(of: $1.pose)! }
    }

    /// The latest photo of a pose on a day (several may be taken).
    public func photo(on day: DayKey, pose: PhotoPose) -> ProgressPhoto? {
        photos.last { $0.day == day && $0.pose == pose }
    }

    /// Days with a photo of `pose`, oldest first.
    public func days(with pose: PhotoPose) -> [DayKey] {
        Array(Set(photos.filter { $0.pose == pose }.map(\.day))).sorted()
    }

    /// The first and the latest day with a photo of `pose`. Nil with fewer than two such days.
    public func defaultComparison(_ pose: PhotoPose) -> (from: DayKey, to: DayKey)? {
        let days = days(with: pose)
        guard let first = days.first, let last = days.last, first != last else { return nil }
        return (first, last)
    }

    /// The pose with the most photo days, so Compare opens on one that has a before and after.
    public var bestComparisonPose: PhotoPose {
        PhotoPose.allCases.max { days(with: $0).count < days(with: $1).count } ?? .front
    }

    // MARK: Coach

    /// Latest measurements with the change over about a month and since the first reading, as lines for the AI coach.
    public static func coachLines(entries: [BodyEntry], photos: [ProgressPhoto], today: DayKey, calendar: Calendar = .current) -> [String] {
        var lines: [String] = []
        let month = today.adding(days: -30, calendar: calendar)
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
        func signed(_ value: Double) -> String { "\(value >= 0 ? "+" : "")\(number(value))" }

        for measure in BodyMeasure.allCases {
            let points = series(measure, in: entries)
            guard let latest = points.last else { continue }
            var line = "\(measure.name): \(number(latest.value)) \(measure.unit) on \(latest.day)"
            let old = points.last { $0.day <= month }
            if let old {
                line += ", \(signed(latest.value - old.value)) since \(old.day)"
            }
            if let first = points.first, first.day != latest.day, first.day != old?.day {
                line += ", \(signed(latest.value - first.value)) since the first on \(first.day)"
            }
            lines.append(line)
        }
        if let first = photos.first, let last = photos.last {
            lines.append("Progress photos: \(Set(photos.map(\.day)).count) days from \(first.day) to \(last.day) (you can't see them).")
        }
        return lines
    }
}

extension DayKey {
    /// Whole days from this day to `other` (negative when `other` is earlier).
    public func days(to other: DayKey, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day ?? 0
    }
}
