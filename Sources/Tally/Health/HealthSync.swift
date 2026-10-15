import Foundation
import TallyCore

/// Keeps Tally and Apple Health in step: imports workouts from other apps, merges a Watch session
/// into the Tally workout it overlaps, and removes Tally's own copy from Health when that happens.
@MainActor
enum HealthSync {
    static func refresh(gym: GymStore, health: HealthManager) async {
        await health.refresh()
        guard health.isConnected else { return }
        let since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let duplicates = gym.applyHealthWorkouts(await health.workouts(since: since))
        for healthID in duplicates {
            if await health.deleteWorkout(healthID) {
                gym.healthCopyDeleted(healthID)
            }
        }
    }

    /// Puts a just-finished workout in Health, unless a Watch session already covers it.
    static func finished(_ workout: Workout, gym: GymStore, health: HealthManager) async {
        guard health.isConnected, let end = workout.endedAt else { return }
        let nearby = await health.workouts(since: workout.startedAt.addingTimeInterval(-3 * 3600))
        let candidates = nearby.filter(\.isStrengthLike).map { (id: $0.id, interval: $0.interval) }
        if let match = Overlap.bestMatch(for: DateInterval(start: workout.startedAt, end: end), in: candidates) {
            gym.setHealthLink(for: workout.id, linked: match, saved: nil)
        } else if let saved = await health.save(workout) {
            gym.setHealthLink(for: workout.id, linked: nil, saved: saved)
        }
    }
}
