import Foundation
import Observation
import TallyCore
import UserNotifications

/// How a night felt and what happened that evening, for any night (Health or hand-logged).
struct SleepCheckIn: Codable, Equatable {
    var quality: Int?
    var tags: [String] = []
}

/// A step of the evening wind-down routine.
struct WindDownStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
}

/// Sleep from Apple Health and hand-logged nights, check-ins, the sleep schedule, the wind-down
/// routine and bedtime reminders.
@MainActor
@Observable
final class SleepStore {
    /// Things that often change a night, offered when checking in.
    nonisolated static let suggestedTags = [
        "Late caffeine", "Alcohol", "Late workout", "Big late meal",
        "Screens in bed", "Stressed", "Nap", "Ill",
    ]
    /// Added to a night automatically when every wind-down step was ticked off that evening.
    nonisolated static let windDownTag = "Wind-down done"

    nonisolated static let defaultSteps = [
        "Phone away and on charge outside the bed",
        "Dim the lights",
        "Cool, dark room (about 18 °C)",
        "Write down tomorrow's to-dos",
        "Read or stretch for 10 minutes",
    ].map { WindDownStep(title: $0) }

    private struct File: Codable {
        var logs: [ManualSleep] = []
        var checkIns: [String: SleepCheckIn] = [:]
        var steps: [WindDownStep] = SleepStore.defaultSteps
        /// Step IDs ticked off, by the night they lead into ("2026-10-21").
        var stepsDone: [String: Set<UUID>] = [:]
        /// Set by Good night, cleared by I'm up.
        var nightStarted: Date?
    }

    private var file: File
    private(set) var healthNights: [SleepNight] = []
    private(set) var isLoading = false

    var goalHours: Double = UserDefaults.standard.object(forKey: "sleep.goalHours") as? Double ?? 8 {
        didSet { UserDefaults.standard.set(goalHours, forKey: "sleep.goalHours"); scheduleReminders() }
    }
    /// Alarm time in minutes after midnight.
    var wakeMinutes: Int = UserDefaults.standard.object(forKey: "sleep.wakeMinutes") as? Int ?? 7 * 60 {
        didSet { UserDefaults.standard.set(wakeMinutes, forKey: "sleep.wakeMinutes"); scheduleReminders() }
    }
    var remindersOn: Bool = UserDefaults.standard.bool(forKey: "sleep.reminders") {
        didSet { UserDefaults.standard.set(remindersOn, forKey: "sleep.reminders"); scheduleReminders() }
    }
    /// How long before bedtime the wind-down reminder comes.
    var windDownMinutes: Int = UserDefaults.standard.object(forKey: "sleep.windDownMinutes") as? Int ?? 45 {
        didSet { UserDefaults.standard.set(windDownMinutes, forKey: "sleep.windDownMinutes"); scheduleReminders() }
    }

    private static let fileURL = URL.documentsDirectory.appending(path: "sleep.json")
    private static let windDownID = "sleep.windDown"
    private static let bedtimeID = "sleep.bedtime"

    init() {
        file = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
    }

    // MARK: Nights

    var goal: TimeInterval { goalHours * 3600 }

    /// Every night, newest first, with check-ins applied.
    var nights: [SleepNight] {
        SleepAnalysis.combine(health: healthNights, manual: file.logs).map { night in
            var night = night
            let key = Self.key(night.day)
            if let checkIn = file.checkIns[key] {
                night.quality = checkIn.quality ?? night.quality
                night.tags = checkIn.tags
            }
            if !file.steps.isEmpty, let done = file.stepsDone[key], Set(file.steps.map(\.id)).isSubset(of: done),
               !night.tags.contains(Self.windDownTag) {
                night.tags.append(Self.windDownTag)
            }
            return night
        }
    }

    var lastNight: SleepNight? { nights.first { $0.day == Calendar.current.startOfDay(for: .now) } }

    func report(now: Date = .now) -> SleepReport {
        SleepInsights.report(nights, goal: goal, now: now)
    }

    func score(_ night: SleepNight, report: SleepReport) -> Int {
        SleepScore.score(night, goal: goal, usualBedtime: report.usualBedtime)
    }

    /// Lines for the coach; empty when there's no sleep logged.
    func coachLines() -> [String] {
        SleepDigest.lines(nights, goal: goal)
    }

    func refresh(health: HealthManager) async {
        guard health.isConnected, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let since = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
        healthNights = SleepAnalysis.nights(from: await health.sleepSegments(since: since))
    }

    func log(_ entry: ManualSleep) {
        file.logs.removeAll { $0.id == entry.id }
        file.logs.append(entry)
        save()
    }

    func log(for night: SleepNight) -> ManualSleep? {
        guard night.isManual else { return nil }
        return file.logs.first { SleepAnalysis.day(for: $0.bedtime) == night.day }
    }

    func deleteLog(for night: SleepNight) {
        file.logs.removeAll { SleepAnalysis.day(for: $0.bedtime) == night.day }
        save()
    }

    func checkIn(for day: Date) -> SleepCheckIn {
        file.checkIns[Self.key(day)] ?? SleepCheckIn()
    }

    func setCheckIn(_ checkIn: SleepCheckIn, for day: Date) {
        file.checkIns[Self.key(day)] = checkIn
        save()
    }

    // MARK: Good night / I'm up

    var nightStarted: Date? { file.nightStarted }

    func startNight() {
        file.nightStarted = .now
        save()
    }

    /// Ends the night started with Good night and logs it. Nights under an hour are dropped as mistakes.
    func endNight() {
        guard let start = file.nightStarted else { return }
        file.nightStarted = nil
        if Date.now.timeIntervalSince(start) >= 3600 {
            file.logs.append(ManualSleep(bedtime: start, wake: .now, awakeMinutes: 15, tapped: true))
        }
        save()
    }

    func cancelNight() {
        file.nightStarted = nil
        save()
    }

    // MARK: Schedule and wind-down

    /// When to be in bed, in minutes after midnight, for the goal before the alarm.
    var bedtimeMinutes: Int {
        Int(SleepClock.bedtime(forWake: Double(wakeMinutes), goal: goal))
    }

    var windDownStartMinutes: Int {
        (bedtimeMinutes - windDownMinutes + 1440) % 1440
    }

    var steps: [WindDownStep] { file.steps }

    /// The night tonight's routine leads into.
    private var tonightKey: String { Self.key(SleepAnalysis.day(for: .now)) }

    func isDone(_ step: WindDownStep) -> Bool {
        file.stepsDone[tonightKey]?.contains(step.id) == true
    }

    func toggle(_ step: WindDownStep) {
        var done = file.stepsDone[tonightKey] ?? []
        if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
        file.stepsDone[tonightKey] = done
        // Keep a couple of months for the tag comparison.
        let cutoff = Self.key(Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now)
        file.stepsDone = file.stepsDone.filter { $0.key >= cutoff }
        save()
    }

    func addStep(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        file.steps.append(WindDownStep(title: trimmed))
        save()
    }

    func deleteStep(_ step: WindDownStep) {
        file.steps.removeAll { $0.id == step.id }
        save()
    }

    // MARK: Reminders

    /// Two daily notifications: start winding down, then go to bed.
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.windDownID, Self.bedtimeID])
        guard remindersOn else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        let bedtime = SleepClock.timeOfDay(minutes: Double(bedtimeMinutes))
        let windDown = SleepClock.timeOfDay(minutes: Double(windDownStartMinutes))

        let windDownContent = UNMutableNotificationContent()
        windDownContent.title = "Time to wind down"
        windDownContent.body = "Bed at \(Self.clock(bedtimeMinutes)). Lights down, phone away."
        center.add(UNNotificationRequest(
            identifier: Self.windDownID,
            content: windDownContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: windDown.hour, minute: windDown.minute), repeats: true)
        ))

        let bedtimeContent = UNMutableNotificationContent()
        bedtimeContent.title = "Bedtime"
        bedtimeContent.body = "In bed now for \(Fmt.sleep(goal)) before your \(Self.clock(wakeMinutes)) alarm."
        bedtimeContent.sound = .default
        center.add(UNNotificationRequest(
            identifier: Self.bedtimeID,
            content: bedtimeContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: bedtime.hour, minute: bedtime.minute), repeats: true)
        ))
    }

    // MARK: Helpers

    /// "22:45" from minutes after midnight, in the user's 12/24-hour style.
    nonisolated static func clock(_ minutes: Int) -> String {
        let time = SleepClock.timeOfDay(minutes: Double(minutes))
        let date = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private nonisolated static func key(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }
}

extension Fmt {
    /// "7 h 05" for time asleep.
    static func sleep(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}
