import Foundation
import Overlo4dCore
import UserNotifications

/// Local reminders for peptides. The text never names a peptide, so nothing shows on the Lock
/// Screen. They are planned two weeks ahead whenever the tracker changes and when the app goes
/// to the background.
@MainActor
enum PeptideReminders {
    private static let prefix = "pep."
    /// iOS keeps 64 pending notifications per app; training reminders use some of them.
    private static let limit = 24

    static func requestPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// Reads peptides.json, if there is one, and plans its reminders. Does nothing for people who
    /// never opened the tracker.
    static func refreshFromDisk() {
        guard let raw = try? Data(contentsOf: PeptideStore.fileURL), let data = try? PeptideData.decode(raw) else { return }
        reschedule(data)
    }

    static func reschedule(_ data: PeptideData, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        // Two peptides at the same time share one reminder.
        let times = Set(data.profiles.flatMap { data.reminders($0, days: 14, now: now, calendar: calendar) })
        let upcoming = times.sorted().prefix(limit)
        center.removePendingNotificationRequests(withIdentifiers: (0..<limit).map { "\(prefix)\($0)" })
        for (index, date) in upcoming.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Overlo4d"
            content.body = "You have a reminder."
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(prefix)\(index)", content: content, trigger: trigger))
        }
    }
}
