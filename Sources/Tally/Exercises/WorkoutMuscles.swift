import SwiftUI
import TallyKit

/// The muscles a whole workout works, each with its strongest role and a set count.
struct WorkoutMuscles {
    struct Entry: Identifiable {
        let muscle: Muscle
        let role: MuscleRole
        /// Working sets, counting half a set where the muscle is secondary, as weekly volume does.
        let sets: Double

        var id: Muscle { muscle }
    }

    let entries: [Entry]

    init(_ workout: Workout, gym: GymStore) {
        var roles: [Muscle: MuscleRole] = [:]
        var sets: [Muscle: Double] = [:]
        for exercise in workout.exercises {
            guard let def = gym.exercise(exercise.exerciseID) else { continue }
            let count = Double(exercise.sets.filter { $0.type != .warmup }.count)
            for (role, muscles) in [(MuscleRole.primary, def.primary), (.secondary, def.secondary), (.tertiary, def.tertiary)] {
                for muscle in muscles {
                    if roles[muscle].map({ role.rank < $0.rank }) ?? true { roles[muscle] = role }
                    if role == .primary { sets[muscle, default: 0] += count }
                    if role == .secondary { sets[muscle, default: 0] += count / 2 }
                }
            }
        }
        entries = roles
            .map { Entry(muscle: $0.key, role: $0.value, sets: sets[$0.key] ?? 0) }
            .sorted { ($0.role.rank, -$0.sets, $0.muscle.label) < ($1.role.rank, -$1.sets, $1.muscle.label) }
    }

    func muscles(_ role: MuscleRole) -> Set<Muscle> {
        Set(entries.filter { $0.role == role }.map(\.muscle))
    }
}

private extension MuscleRole {
    var rank: Int {
        switch self {
        case .primary: 0
        case .secondary: 1
        case .tertiary: 2
        }
    }
}

/// Front and back figure for a workout, beside the muscles it hits and how many sets each got.
struct WorkoutMusclesCard: View {
    @Environment(GymStore.self) private var gym
    let workout: Workout
    /// Colour of the gaps between muscles; match the background behind the card.
    var gap: Color = Theme.card

    var body: some View {
        let summary = WorkoutMuscles(workout, gym: gym)
        if !summary.entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Muscles worked").eyebrow(11)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(summary.entries.prefix(7)) { entry in
                            row(entry)
                        }
                        if summary.entries.count > 7 {
                            Text("+\(summary.entries.count - 7) more")
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    AnatomyFigure(
                        primary: summary.muscles(.primary),
                        secondary: summary.muscles(.secondary),
                        tertiary: summary.muscles(.tertiary),
                        gap: gap,
                        labels: true
                    )
                    .frame(height: 170)
                    .accessibilityHidden(true)
                }
                HStack(spacing: 14) {
                    ForEach(MuscleRole.allCases, id: \.self) { role in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(role.color).frame(width: 9, height: 9)
                            Text(role.label).eyebrow(9.5).foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            .animation(.snappy, value: summary.entries.map(\.muscle))
        }
    }

    private func row(_ entry: WorkoutMuscles.Entry) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(entry.role.color).frame(width: 10, height: 10)
            Text(entry.muscle.label)
                .font(Typo.body(14.5, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if entry.sets > 0 {
                Text(VolumeZone.format(entry.sets) + (entry.sets == 1 ? " set" : " sets"))
                    .font(Typo.body(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.muscle.label), \(entry.role.label.lowercased())")
    }
}
