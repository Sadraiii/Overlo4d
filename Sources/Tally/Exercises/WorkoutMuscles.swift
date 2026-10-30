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

/// The workout's muscles on a large front and back figure, with a ranked list of sets per muscle
/// underneath. Tapping a muscle on the figure or in the list picks it out on both.
struct WorkoutMusclesCard: View {
    @Environment(GymStore.self) private var gym
    let workout: Workout

    @State private var selected: Muscle?
    @State private var showingAll = false

    /// Rows shown before "Show all".
    private let collapsedCount = 5

    var body: some View {
        let summary = WorkoutMuscles(workout, gym: gym)
        if !summary.entries.isEmpty {
            let entries = summary.entries
            let shown = showingAll ? entries : Array(entries.prefix(collapsedCount))
            let scale = max(entries.map(\.sets).max() ?? 0, 1)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Muscles worked").font(Typo.title(17)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(entries.count == 1 ? "1 muscle" : "\(entries.count) muscles")
                        .font(Typo.body(13.5))
                        .foregroundStyle(Theme.ink3)
                }

                AnatomyFigure(
                    primary: summary.muscles(.primary),
                    secondary: summary.muscles(.secondary),
                    tertiary: summary.muscles(.tertiary),
                    selected: selected,
                    onTap: select,
                    labels: true
                )
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityHidden(true)

                HStack(spacing: 16) {
                    ForEach(MuscleRole.allCases, id: \.self) { role in
                        HStack(spacing: 6) {
                            Circle().fill(role.color).frame(width: 9, height: 9)
                            Text(role.label).font(Typo.body(12.5, .medium)).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

                VStack(spacing: 2) {
                    ForEach(shown) { entry in
                        row(entry, scale: scale)
                    }
                }

                if entries.count > collapsedCount {
                    Button {
                        withAnimation(.snappy) { showingAll.toggle() }
                    } label: {
                        Text(verbatim: showingAll ? "Show less" : "Show all \(entries.count) muscles")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy, value: entries.map(\.muscle))
        }
    }

    private func select(_ muscle: Muscle) {
        withAnimation(.snappy) { selected = selected == muscle ? nil : muscle }
    }

    private func row(_ entry: WorkoutMuscles.Entry, scale: Double) -> some View {
        Button { select(entry.muscle) } label: {
            VStack(spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.muscle.label)
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(entry.role.label)
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 4)
                    Text(entry.sets > 0 ? VolumeZone.format(entry.sets) + (entry.sets == 1 ? " set" : " sets") : "No sets")
                        .font(Typo.body(13.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Theme.line
                        Capsule()
                            .fill(entry.role.color)
                            .frame(width: entry.sets > 0 ? max(proxy.size.width * CGFloat(entry.sets / scale), 6) : 0)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(selected == entry.muscle ? Theme.fill : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .accessibilityLabel("\(entry.muscle.label), \(entry.role.label.lowercased()), \(VolumeZone.format(entry.sets)) sets")
    }
}
