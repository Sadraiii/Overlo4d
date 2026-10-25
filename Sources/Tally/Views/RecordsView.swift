import TallyKit
import SwiftUI

/// Every exercise's all-time bests, most recently improved first.
struct RecordsView: View {
    @Environment(GymStore.self) private var gym
    @State private var search = ""
    @State private var muscle: MuscleGroup?

    private struct Entry: Identifiable {
        var id: UUID { exercise.id }
        let exercise: ExerciseDef
        let bests: [(kind: RecordKind, value: Double, date: Date)]
        var latest: Date { bests.map(\.date).max() ?? .distantPast }
    }

    private var entries: [Entry] {
        let logged = Set(gym.workouts.flatMap { $0.exercises.map(\.exerciseID) })
        return gym.exercises
            .filter { logged.contains($0.id) }
            .filter { muscle == nil || $0.muscle == muscle }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .map { Entry(exercise: $0, bests: gym.bests(for: $0)) }
            .filter { !$0.bests.isEmpty }
            .sorted { $0.latest > $1.latest }
    }

    var body: some View {
        let entries = entries
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", isOn: muscle == nil) { muscle = nil }
                        ForEach(MuscleGroup.allCases) { group in
                            chip(group.label, isOn: muscle == group) { muscle = group }
                        }
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "No records yet",
                        systemImage: "trophy",
                        description: Text("Finish a workout and your bests show up here.")
                    )
                    .padding(.top, 40)
                }

                ForEach(entries) { entry in
                    NavigationLink(value: entry.exercise) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                ExerciseBadge(exercise: entry.exercise, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.exercise.name).display(20).lineLimit(1)
                                    Text("Last record \(entry.latest.formatted(.dateTime.day().month().year()))")
                                        .font(Typo.body(12.5))
                                        .foregroundStyle(Theme.ink3)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink3)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                ForEach(entry.bests, id: \.kind) { best in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Fmt.record(best.value, kind: best.kind, exercise: entry.exercise.kind))
                                            .font(Typo.display(20))
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                        Text(best.kind.label).eyebrow(9.5)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Theme.paper, in: .rect(cornerRadius: 12))
                                }
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .card(padding: 12, cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Records")
        .searchable(text: $search, prompt: "Search")
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title) { withAnimation(.snappy) { action() } }
            .font(Typo.body(13, .semibold))
            .foregroundStyle(isOn ? Theme.paper : Theme.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(isOn ? Theme.ink : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line2, lineWidth: 1))
            .buttonStyle(.plain)
    }
}
