import SwiftUI
import TallyCore
import TallyKit

/// A workout from Apple Health in History, e.g. a run recorded on Apple Watch.
struct HealthWorkoutCard: View {
    let workout: HealthWorkout

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Bib(date: workout.start)
            VStack(alignment: .leading, spacing: 7) {
                Text(workout.name).display(23).lineLimit(1)
                Text(Self.details(workout))
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                Label(workout.sourceName, systemImage: "applewatch")
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            Image(systemName: workout.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .card(padding: 12, cornerRadius: 16)
    }

    static func details(_ workout: HealthWorkout) -> String {
        [
            Fmt.duration(workout.duration),
            workout.meters.map { Pace.distance($0) },
            workout.energy.map { "\(Int($0.rounded())) kcal" },
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct HealthWorkoutDetailView: View {
    @Environment(HealthManager.self) private var health
    let workout: HealthWorkout

    @State private var stats: HealthManager.WorkoutHealth?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Bib(date: workout.start, size: .large)
                Text(workout.name).display(40).multilineTextAlignment(.center)
                Text(workout.start.formatted(date: .complete, time: .shortened))
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
                HStack(spacing: 8) {
                    Tile(value: Fmt.duration(workout.duration), label: "Duration")
                    if let meters = workout.meters { Tile(value: Pace.distance(meters), label: "Distance") }
                    if let energy = workout.energy { Tile(value: "\(Int(energy.rounded()))", label: "Active kcal") }
                }
                HStack(spacing: 8) {
                    if let meters = workout.meters, meters >= 1000,
                       let pace = Pace.secondsPerKm(meters: meters, seconds: Int(workout.duration)) {
                        Tile(value: Fmt.seconds(Int(pace.rounded())), label: "Pace /km")
                    }
                    if let average = stats?.averageHeartRate { Tile(value: "\(Int(average.rounded()))", label: "Avg bpm") }
                    if let max = stats?.maxHeartRate { Tile(value: "\(Int(max.rounded()))", label: "Max bpm") }
                }
                Label("Recorded by \(workout.sourceName)", systemImage: "applewatch")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { stats = await health.health(from: workout.start, to: workout.end, key: workout.id) }
    }
}
