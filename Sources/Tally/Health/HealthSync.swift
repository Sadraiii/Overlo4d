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
}
