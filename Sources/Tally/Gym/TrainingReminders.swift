import Foundation
import TallyCore
import UserNotifications

/// Local notifications for training days, a nudge after a break and the weekly report.
@MainActor
enum TrainingReminders {
    enum Keys {
        static let enabled = "reminders.enabled"
        static let days = "reminders.days"
        static let minutes = "reminders.minutes"
        static let nudgeDays = "reminders.nudgeDays"
        static let weeklyReport = "reminders.weeklyReport"
    }

    static let defaultMinutes = 17 * 60 + 30
    private static let prefix = "train."
    private static let reportID = "train.report"
    private static let nudgeID = "train.nudge"

    static var settings: WorkoutReminders.Settings {
        let defaults = UserDefaults.standard
        return WorkoutReminders.Settings(
            days: defaults.bool(forKey: Keys.enabled) ? WorkoutReminders.decode(defaults.string(forKey: Keys.days) ?? "") : [],
            minutes: defaults.object(forKey: Keys.minutes) as? Int ?? defaultMinutes,
            nudgeAfterDays: defaults.integer(forKey: Keys.nudgeDays)
        )
    }

    static func requestPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// Replaces every pending training notification with what the settings and the log call for now.
    /// Run when the app opens, goes to the background or a setting changes.
    static func reschedule(gym: GymStore, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        let settings = settings
        let weeklyReport = UserDefaults.standard.bool(forKey: Keys.weeklyReport)
        let calendar = Calendar.current
        let last = gym.activityDates.max()
        let trainedToday = last.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let upcoming = WorkoutReminders.upcoming(settings, now: now, trainedToday: trainedToday, calendar: calendar)
        let nudge = WorkoutReminders.nudge(settings, lastWorkout: last, now: now, calendar: calendar)
        let planName = gym.upNext(now: now)?.plan.name
        let deloading = gym.isDeloading

        let horizon = 21
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<horizon).map { "\(prefix)day.\($0)" } + [nudgeID, reportID]
        )

        for (index, date) in upcoming.prefix(horizon).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time to train"
            // Only the next reminder can name the plan; later ones would be out of date.
            if index == 0, let planName {
                content.body = deloading ? "Up next: \(planName). Deload week, so keep it light." : "Up next: \(planName)."
            } else {
                content.body = "Your workout is waiting."
            }
            content.sound = .default
            add(content, id: "\(prefix)day.\(index)", at: date, calendar: calendar, center: center)
        }

        // A nudge on a day that already has a reminder would only repeat it.
        if let nudge, !upcoming.contains(where: { calendar.isDate($0, inSameDayAs: nudge) }) {
            let content = UNMutableNotificationContent()
            content.title = "Ready for the next one?"
            content.body = "It's been a few days since your last workout. Even a short session keeps the habit."
            content.sound = .default
            add(content, id: nudgeID, at: nudge, calendar: calendar, center: center)
        }

        if weeklyReport {
            let content = UNMutableNotificationContent()
            content.title = "Your weekly report is ready"
            content.body = "See how last week went and what to do this week."
            content.sound = .default
            var when = DateComponents()
            when.weekday = calendar.firstWeekday
            when.hour = 8
            when.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: reportID, content: content, trigger: trigger))
        }
    }

    private static func add(_ content: UNMutableNotificationContent, id: String, at date: Date, calendar: Calendar, center: UNUserNotificationCenter) {
        let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
