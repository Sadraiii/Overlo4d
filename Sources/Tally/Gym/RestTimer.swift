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
    /// Seconds left while the countdown is paused.
    private(set) var pausedRemaining: TimeInterval?

    /// Ends the countdown in the app, whichever screen is showing.
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    private static let notificationID = "rest-timer"
    private enum Keys {
        static let end = "rest.endDate"
        static let total = "rest.total"
        static let paused = "rest.pausedRemaining"
    }

    /// Picks up a countdown that was running (or paused) when the app was closed.
    init() {
        let defaults = UserDefaults.standard
        let savedTotal = defaults.double(forKey: Keys.total)
        if let paused = defaults.object(forKey: Keys.paused) as? Double, paused > 0 {
            pausedRemaining = paused
            total = max(savedTotal, paused)
        } else if let end = defaults.object(forKey: Keys.end) as? Double, end > Date.now.timeIntervalSince1970 {
            endDate = Date(timeIntervalSince1970: end)
            total = max(savedTotal, end - Date.now.timeIntervalSince1970)
        } else {
            Self.clearSaved()
        }
        scheduleFinish()
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        guard let end = endDate else { finishTask = nil; return }
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.endDate == end else { return }
            self.finish()
        }
    }

    /// Counting down or paused.
    var isRunning: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    /// From when the countdown started (moved by the +/− buttons) to when it ends.
    var interval: ClosedRange<Date>? {
        endDate.map { $0.addingTimeInterval(-total)...$0 }
    }

    /// Start the rest countdown automatically when a set is ticked off.
    /// Set in Settings.
    var autoStart: Bool { UserDefaults.standard.object(forKey: "rest.autoStart") as? Bool ?? true }

    /// Called when the countdown reaches zero while the app is open: sound and haptic, then hide.
    /// Coming back to the app long after the end only hides it; the notification already rang.
    func finish() {
        guard let endDate else { return }
        if Date.now.timeIntervalSince(endDate) < 3 {
            AudioServicesPlaySystemSound(1005)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
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
        pausedRemaining = nil
        endDate = .now.addingTimeInterval(total)
        persist()
        scheduleNotification()
        scheduleFinish()
    }

    func adjust(by seconds: Int) {
        if let remaining = pausedRemaining {
            let new = remaining + TimeInterval(seconds)
            guard new > 0 else { stop(); return }
            pausedRemaining = new
            total = max(total + TimeInterval(seconds), new)
            persist()
            return
        }
        guard let endDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { stop(); return }
        self.endDate = newEnd
        total = max(total + TimeInterval(seconds), newEnd.timeIntervalSinceNow)
        persist()
        scheduleNotification()
        scheduleFinish()
    }

    /// Holds the countdown where it is (someone is using the bench, a chat ran long).
    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(1, endDate.timeIntervalSinceNow)
        self.endDate = nil
        scheduleFinish()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        persist()
    }

    func resume() {
        guard let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        endDate = .now.addingTimeInterval(remaining)
        persist()
        scheduleNotification()
        scheduleFinish()
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
        scheduleFinish()
        Self.clearSaved()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// The end time is what's kept, so the countdown is right again after the app was closed.
    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(total, forKey: Keys.total)
        if let pausedRemaining {
            defaults.set(pausedRemaining, forKey: Keys.paused)
            defaults.removeObject(forKey: Keys.end)
        } else if let endDate {
            defaults.set(endDate.timeIntervalSince1970, forKey: Keys.end)
            defaults.removeObject(forKey: Keys.paused)
        }
    }

    private static func clearSaved() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.end)
        defaults.removeObject(forKey: Keys.paused)
        defaults.removeObject(forKey: Keys.total)
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
