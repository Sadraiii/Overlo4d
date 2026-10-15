import AudioToolbox
import Foundation
import Observation
import UIKit
import UserNotifications

/// Countdown between sets. Schedules a local notification so it also fires while the app is in the background.
@MainActor
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var total: TimeInterval = 0

    private static let notificationID = "rest-timer"

    var isRunning: Bool { endDate != nil }

    /// Start the rest countdown automatically when a set is ticked off.
    /// Set in Settings.
    var autoStart: Bool { UserDefaults.standard.object(forKey: "rest.autoStart") as? Bool ?? true }

    /// Called when the countdown reaches zero while the app is open: sound and haptic, then hide.
    func finish() {
        guard endDate != nil else { return }
        AudioServicesPlaySystemSound(1005)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        stop()
    }

    func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        endDate = .now.addingTimeInterval(total)
        scheduleNotification()
    }

    func adjust(by seconds: Int) {
        guard let endDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { stop(); return }
        self.endDate = newEnd
        total = max(total + TimeInterval(seconds), newEnd.timeIntervalSinceNow)
        scheduleNotification()
    }

    func stop() {
        endDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func scheduleNotification() {
        guard let endDate else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endDate.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}
