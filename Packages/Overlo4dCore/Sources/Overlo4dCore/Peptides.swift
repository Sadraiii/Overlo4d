import Foundation

// The private peptide tracker: profiles, reconstitution maths for U-100 syringes, a log with
// site rotation, and vial inventory. Arithmetic on the user's own numbers only; nothing here
// suggests an amount.

/// The unit a target amount is typed in.
public enum DoseUnit: String, Codable, CaseIterable, Sendable {
    case mcg, mg

    public var perMcg: Double { self == .mg ? 1000 : 1 }
}

/// U-100 insulin syringes: 100 units = 1 mL, so one unit is 0.01 mL whatever the barrel size.
public enum SyringeSize: Int, Codable, CaseIterable, Sendable {
    case u100 = 100, u50 = 50, u30 = 30

    public var units: Double { Double(rawValue) }
    public var milliliters: Double { units / 100 }
    /// The smaller barrels are the ones sold with half-unit marks.
    public var allowsHalfUnits: Bool { self != .u100 }
    public var label: String {
        switch self {
        case .u100: "1 mL · 100 units"
        case .u50: "0.5 mL · 50 units"
        case .u30: "0.3 mL · 30 units"
        }
    }
}

public enum PeptideSchedule: String, Codable, CaseIterable, Sendable {
    case daily, twiceDaily, everyOtherDay, fiveOnTwoOff, twiceWeekly, weekly, asNeeded

    public var label: String {
        switch self {
        case .daily: "Daily"
        case .twiceDaily: "Twice daily"
        case .everyOtherDay: "Every other day"
        case .fiveOnTwoOff: "5 days on, 2 off"
        case .twiceWeekly: "Twice a week"
        case .weekly: "Weekly"
        case .asNeeded: "As needed"
        }
    }

    /// Average entries per week; nil when there is no fixed rhythm.
    public var perWeek: Double? {
        switch self {
        case .daily: 7
        case .twiceDaily: 14
        case .everyOtherDay: 3.5
        case .fiveOnTwoOff: 5
        case .twiceWeekly: 2
        case .weekly: 1
        case .asNeeded: nil
        }
    }

    /// How many entries are still open today. `logDays` are the days this peptide was logged
    /// (one element per entry, any order). 5 on / 2 off runs Monday to Friday.
    public func dueToday(logDays: [DayKey], today: DayKey, calendar: Calendar = .current) -> Int {
        let doneToday = logDays.filter { $0 == today }.count
        let lastBefore = logDays.filter { $0 < today }.max()
        func gapAtLeast(_ days: Int) -> Bool {
            guard let lastBefore else { return true }
            return lastBefore <= today.adding(days: -days, calendar: calendar)
        }
        let planned: Int
        switch self {
        case .daily: planned = 1
        case .twiceDaily: planned = 2
        case .everyOtherDay: planned = gapAtLeast(2) ? 1 : 0
        case .fiveOnTwoOff:
            let weekday = calendar.component(.weekday, from: today.date(calendar: calendar))
            planned = (2...6).contains(weekday) ? 1 : 0
        case .twiceWeekly: planned = gapAtLeast(3) ? 1 : 0
        case .weekly: planned = gapAtLeast(7) ? 1 : 0
        case .asNeeded: planned = 0
        }
        return max(0, planned - doneToday)
    }
}

public enum InjectionSite: String, Codable, CaseIterable, Sendable {
    case abdomenLeft, abdomenRight, thighLeft, thighRight, armLeft, armRight, gluteLeft, gluteRight

    public var label: String {
        switch self {
        case .abdomenLeft: "Abdomen left"
        case .abdomenRight: "Abdomen right"
        case .thighLeft: "Thigh left"
        case .thighRight: "Thigh right"
        case .armLeft: "Arm left"
        case .armRight: "Arm right"
        case .gluteLeft: "Glute left"
        case .gluteRight: "Glute right"
        }
    }

    /// Rotation: a site not used yet (in list order), otherwise the one used longest ago.
    public static func next(after logs: [PeptideLogEntry], among sites: [InjectionSite] = InjectionSite.allCases) -> InjectionSite? {
        var lastUsed: [InjectionSite: Date] = [:]
        for log in logs {
            guard let site = log.site else { continue }
            lastUsed[site] = max(lastUsed[site] ?? .distantPast, log.date)
        }
        if let unused = sites.first(where: { lastUsed[$0] == nil }) { return unused }
        return sites.min { (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast) }
    }
}

/// Everything derived from a vial, its water and a target amount.
public struct Reconstitution: Equatable, Sendable {
    public let vialMg: Double
    public let waterMl: Double
    public let doseMcg: Double
    public let syringe: SyringeSize
    public let halfUnits: Bool

    public init(vialMg: Double, waterMl: Double, doseMcg: Double, syringe: SyringeSize = .u100, halfUnits: Bool = false) {
        self.vialMg = vialMg
        self.waterMl = waterMl
        self.doseMcg = doseMcg
        self.syringe = syringe
        self.halfUnits = halfUnits && syringe.allowsHalfUnits
    }

    /// Vial and water are both set, so concentration means something.
    public var hasConcentration: Bool { vialMg > 0 && waterMl > 0 && vialMg.isFinite && waterMl.isFinite }
    public var hasDose: Bool { hasConcentration && doseMcg > 0 && doseMcg.isFinite }

    /// mg per mL = vial mg ÷ water mL.
    public var mgPerMl: Double { hasConcentration ? vialMg / waterMl : 0 }
    public var mcgPerMl: Double { mgPerMl * 1000 }
    /// One unit is 0.01 mL, so it holds a hundredth of a mL's worth.
    public var mcgPerUnit: Double { mcgPerMl / 100 }
    /// Units between two marks on this syringe.
    public var tickUnits: Double { halfUnits ? 0.5 : 1 }
    public var mcgPerTick: Double { mcgPerUnit * tickUnits }

    /// Units to draw for the target amount, before rounding to a mark.
    public var exactUnits: Double { hasDose ? doseMcg / mcgPerUnit : 0 }
    /// The nearest mark that can be read on the syringe; halfway goes up.
    public var units: Double { (exactUnits / tickUnits + 1e-9).rounded() * tickUnits }
    public var milliliters: Double { units / 100 }
    /// What the rounded draw really holds.
    public var drawnMcg: Double { units * mcgPerUnit }
    /// The target doesn't land on a mark, so the draw is slightly off it.
    public var isRounded: Bool { abs(units - exactUnits) > 1e-6 }
    /// Too small to reach the first mark.
    public var belowFirstMark: Bool { hasDose && units < tickUnits }
    public var fitsSyringe: Bool { units <= syringe.units + 1e-9 }
    /// How many syringes of this size the draw needs.
    public var syringesNeeded: Int { max(1, Int((units / syringe.units - 1e-9).rounded(.up))) }

    /// Whole portions in a full vial.
    public var dosesPerVial: Int { Self.wholeDoses(inMcg: vialMg * 1000, doseMcg: doseMcg) }

    public static func wholeDoses(inMcg amount: Double, doseMcg: Double) -> Int {
        guard amount > 0, doseMcg > 0, amount.isFinite, doseMcg.isFinite else { return 0 }
        return Int((amount / doseMcg + 1e-9).rounded(.down))
    }
}

public struct PeptideProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var vialMg: Double
    public var waterMl: Double
    public var dose: Double
    public var doseUnit: DoseUnit
    public var schedule: PeptideSchedule
    public var syringe: SyringeSize
    public var halfUnits: Bool
    /// Count the active vial down with every log entry.
    public var tracksVial: Bool
    public var remainingMg: Double?
    public var vialOpened: Date?
    public var notes: String

    public init(id: UUID = UUID(), name: String = "", vialMg: Double = 0, waterMl: Double = 0, dose: Double = 0,
                doseUnit: DoseUnit = .mcg, schedule: PeptideSchedule = .daily, syringe: SyringeSize = .u100,
                halfUnits: Bool = false, tracksVial: Bool = true, remainingMg: Double? = nil, vialOpened: Date? = nil,
                notes: String = "") {
        self.id = id
        self.name = name
        self.vialMg = vialMg
        self.waterMl = waterMl
        self.dose = dose
        self.doseUnit = doseUnit
        self.schedule = schedule
        self.syringe = syringe
        self.halfUnits = halfUnits
        self.tracksVial = tracksVial
        self.remainingMg = remainingMg
        self.vialOpened = vialOpened
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        vialMg = try c.decodeIfPresent(Double.self, forKey: .vialMg) ?? 0
        waterMl = try c.decodeIfPresent(Double.self, forKey: .waterMl) ?? 0
        dose = try c.decodeIfPresent(Double.self, forKey: .dose) ?? 0
        doseUnit = (try? c.decodeIfPresent(DoseUnit.self, forKey: .doseUnit)) ?? .mcg
        schedule = (try? c.decodeIfPresent(PeptideSchedule.self, forKey: .schedule)) ?? .daily
        syringe = (try? c.decodeIfPresent(SyringeSize.self, forKey: .syringe)) ?? .u100
        halfUnits = try c.decodeIfPresent(Bool.self, forKey: .halfUnits) ?? false
        tracksVial = try c.decodeIfPresent(Bool.self, forKey: .tracksVial) ?? true
        remainingMg = try c.decodeIfPresent(Double.self, forKey: .remainingMg)
        vialOpened = try c.decodeIfPresent(Date.self, forKey: .vialOpened)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public var doseMcg: Double { dose * doseUnit.perMcg }

    public var reconstitution: Reconstitution {
        Reconstitution(vialMg: vialMg, waterMl: waterMl, doseMcg: doseMcg, syringe: syringe, halfUnits: halfUnits)
    }

    /// What is left in the active vial; a vial never counted down is full.
    public var leftMg: Double { min(max(remainingMg ?? vialMg, 0), max(vialMg, 0)) }
    public var leftFraction: Double { vialMg > 0 ? leftMg / vialMg : 0 }
    public var dosesLeft: Int { Reconstitution.wholeDoses(inMcg: leftMg * 1000, doseMcg: doseMcg) }
    /// Days the active vial lasts on this schedule; nil without a fixed rhythm.
    public var daysLeft: Int? {
        guard let perWeek = schedule.perWeek, doseMcg > 0 else { return nil }
        return Int((Double(dosesLeft) / perWeek * 7).rounded(.down))
    }

    public mutating func startNewVial(at date: Date) {
        remainingMg = vialMg
        vialOpened = date
    }
}

public struct PeptideLogEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var peptideID: UUID
    /// Kept on the entry, so history still reads right after a profile is renamed or deleted.
    public var peptideName: String
    public var amountMcg: Double
    /// The unit the amount was typed in, for display.
    public var unit: DoseUnit
    /// Syringe units drawn.
    public var units: Double
    public var site: InjectionSite?
    public var notes: String
    /// The entry was counted against the vial, so deleting it gives the amount back.
    public var countedInVial: Bool

    public init(id: UUID = UUID(), date: Date, peptideID: UUID, peptideName: String, amountMcg: Double,
                unit: DoseUnit = .mcg, units: Double, site: InjectionSite? = nil, notes: String = "", countedInVial: Bool = false) {
        self.id = id
        self.date = date
        self.peptideID = peptideID
        self.peptideName = peptideName
        self.amountMcg = amountMcg
        self.unit = unit
        self.units = units
        self.site = site
        self.notes = notes
        self.countedInVial = countedInVial
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        peptideID = try c.decodeIfPresent(UUID.self, forKey: .peptideID) ?? UUID()
        peptideName = try c.decodeIfPresent(String.self, forKey: .peptideName) ?? ""
        amountMcg = try c.decodeIfPresent(Double.self, forKey: .amountMcg) ?? 0
        unit = (try? c.decodeIfPresent(DoseUnit.self, forKey: .unit)) ?? .mcg
        units = try c.decodeIfPresent(Double.self, forKey: .units) ?? 0
        site = try? c.decodeIfPresent(InjectionSite.self, forKey: .site)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        countedInVial = try c.decodeIfPresent(Bool.self, forKey: .countedInVial) ?? false
    }
}

/// The whole tracker: what is saved to peptides.json and what export and import carry.
public struct PeptideData: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var profiles: [PeptideProfile]
    /// Newest first.
    public var logs: [PeptideLogEntry]

    public init(profiles: [PeptideProfile] = [], logs: [PeptideLogEntry] = []) {
        version = Self.currentVersion
        self.profiles = profiles
        self.logs = logs.sorted { $0.date > $1.date }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profiles = try c.decodeIfPresent([PeptideProfile].self, forKey: .profiles) ?? []
        logs = (try c.decodeIfPresent([PeptideLogEntry].self, forKey: .logs) ?? []).sorted { $0.date > $1.date }
    }

    public var isEmpty: Bool { profiles.isEmpty && logs.isEmpty }

    public func profile(_ id: UUID) -> PeptideProfile? { profiles.first { $0.id == id } }
    public func logs(for id: UUID) -> [PeptideLogEntry] { logs.filter { $0.peptideID == id } }

    /// Adds or replaces a profile. A new one that tracks its vial starts full.
    public mutating func save(_ profile: PeptideProfile, now: Date) {
        var profile = profile
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            // A different vial size means a different vial.
            if profiles[index].vialMg != profile.vialMg { profile.startNewVial(at: now) }
            profiles[index] = profile
        } else {
            if profile.remainingMg == nil { profile.startNewVial(at: now) }
            profiles.append(profile)
        }
    }

    /// Removes a profile. Its log entries stay, with the name they were logged under.
    public mutating func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
    }

    public mutating func startNewVial(_ id: UUID, now: Date) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].startNewVial(at: now)
    }

    /// Records one entry at the profile's target, drawn to the nearest mark, and counts the
    /// vial down when the profile tracks it. Returns nil when the profile has no usable numbers.
    @discardableResult
    public mutating func log(_ id: UUID, at date: Date, site: InjectionSite?, notes: String = "") -> PeptideLogEntry? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let profile = profiles[index]
        let math = profile.reconstitution
        guard math.hasDose, math.units > 0 else { return nil }
        let entry = PeptideLogEntry(date: date, peptideID: id, peptideName: profile.name, amountMcg: math.drawnMcg,
                                    unit: profile.doseUnit, units: math.units, site: site,
                                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), countedInVial: profile.tracksVial)
        if profile.tracksVial {
            profiles[index].remainingMg = max(0, profile.leftMg - math.drawnMcg / 1000)
        }
        logs.append(entry)
        logs.sort { $0.date > $1.date }
        return entry
    }

    /// Deletes an entry and, if it was counted against the vial that is still open, gives it back.
    public mutating func deleteLog(_ id: UUID) {
        guard let entry = logs.first(where: { $0.id == id }) else { return }
        logs.removeAll { $0.id == id }
        guard entry.countedInVial, let index = profiles.firstIndex(where: { $0.id == entry.peptideID }) else { return }
        let profile = profiles[index]
        guard profile.tracksVial, entry.date >= (profile.vialOpened ?? .distantPast) else { return }
        profiles[index].remainingMg = min(profile.vialMg, profile.leftMg + entry.amountMcg / 1000)
    }

    /// Entries still open today for a profile.
    public func dueToday(_ profile: PeptideProfile, now: Date, calendar: Calendar = .current) -> Int {
        let days = logs(for: profile.id).map { DayKey($0.date, calendar: calendar) }
        return profile.schedule.dueToday(logDays: days, today: DayKey(now, calendar: calendar), calendar: calendar)
    }

    public func nextSite() -> InjectionSite? { InjectionSite.next(after: logs) }

    /// Import without losing anything: profiles and entries are matched by id, and the
    /// imported copy wins where both sides have one.
    public mutating func merge(_ other: PeptideData) {
        for profile in other.profiles {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
        }
        var byID = Dictionary(logs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for log in other.logs { byID[log.id] = log }
        logs = byID.values.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
    }

    // MARK: File format

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PeptideData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PeptideData.self, from: data)
    }
}

/// Number formatting for the tracker: short, with trailing zeros dropped.
public enum PeptideFormat {
    /// e.g. 2.5, 10, 0.333.
    public static func number(_ value: Double, places: Int = 2) -> String {
        guard value.isFinite else { return "–" }
        var text = String(format: "%.\(max(0, places))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// An amount in the unit it was typed in, e.g. "250 mcg" or "0.25 mg".
    public static func amount(mcg: Double, unit: DoseUnit) -> String {
        unit == .mg ? "\(number(mcg / 1000, places: 3)) mg" : "\(number(mcg, places: 1)) mcg"
    }

    /// Syringe units, e.g. "10 units", "7.5 units", "1 unit".
    public static func units(_ units: Double) -> String {
        "\(number(units, places: 1)) \(units == 1 ? "unit" : "units")"
    }

    /// Names offered when adding a profile. Names only: no amounts come with them.
    public static let commonNames = ["BPC-157", "TB-500", "Semaglutide", "Tirzepatide", "CJC-1295", "Ipamorelin"]
}
