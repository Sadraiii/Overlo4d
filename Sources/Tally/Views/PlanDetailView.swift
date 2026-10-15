import Charts
import SwiftUI
import TallyKit

/// A plan's progress: last session against the one before, volume over time, and every session.
struct PlanDetailView: View {
    @Environment(GymStore.self) private var gym
    let planID: UUID

    @State private var editing: Plan?

    var body: some View {
        Group {
            if let plan = gym.plans.first(where: { $0.id == planID }) {
                content(plan)
            } else {
                ContentUnavailableView("Plan deleted", systemImage: "list.bullet")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { PlanEditor(plan: $0) }
    }

    private func content(_ plan: Plan) -> some View {
        let sessions = gym.sessions(of: plan)
        let last = sessions.first
        let before = sessions.dropFirst().first

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(plan.exercises.count) exercises · \(plan.exercises.reduce(0) { $0 + $1.sets.count }) sets").eyebrow(11)
                    Text(plan.name).display(44)
                }

                HStack(spacing: 8) {
                    Tile(value: "\(sessions.count)", label: "Sessions")
                    Tile(value: last.map { Self.ago($0.startedAt) } ?? "–", label: "Last done")
                    Tile(value: sessions.isEmpty ? "–" : Fmt.duration(sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)), label: "Avg time")
                }

                Button {
                    gym.startWorkout(from: plan)
                } label: {
                    Label(gym.activeWorkout == nil ? "Start plan" : "Workout in progress", systemImage: "play.fill")
                }
                .buttonStyle(.bigPrimary)
                .disabled(gym.activeWorkout != nil)

                if sessions.count >= 2 {
                    VolumeTrend(sessions: Array(sessions.prefix(10).reversed()))
                }

                if let last {
                    SectionHead("Last session") {
                        Text(last.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .foregroundStyle(Theme.ink3)
                    }
                    ForEach(plan.exercises) { exercise in
                        ExerciseComparison(
                            def: gym.exercise(exercise.exerciseID),
                            last: last.exercises.first { $0.exerciseID == exercise.exerciseID }?.sets ?? [],
                            before: before?.exercises.first { $0.exerciseID == exercise.exerciseID }?.sets ?? [],
                            beforeDate: before?.startedAt
                        )
                    }

                    SectionHead("Sessions")
                    ForEach(sessions) { session in
                        NavigationLink(value: session.id) {
                            WorkoutCard(workout: session)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("No sessions yet").display(20)
                        Text("Start this plan to see your sets and progress here.")
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .toolbar {
            Button("Edit", systemImage: "pencil") { editing = plan }
        }
    }

    static func ago(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }
}

/// Volume per session for the last ten sessions of a plan.
private struct VolumeTrend: View {
    let sessions: [Workout]

    var body: some View {
        let last = sessions.last?.volume ?? 0
        let previous = sessions.dropLast().last?.volume ?? 0
        let change = last - previous

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Volume").display(16)
                Spacer()
                Text("\(change >= 0 ? "+" : "−")\(Fmt.volume(abs(change))) vs previous")
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(change > 0 ? Theme.good : change < 0 ? Theme.danger : Theme.ink3)
            }
            Chart(Array(sessions.enumerated()), id: \.element.id) { index, session in
                BarMark(x: .value("Session", index), y: .value("kg", session.volume))
                    .foregroundStyle(index == sessions.count - 1 ? Theme.accent : Theme.accent.opacity(0.35))
                    .clipShape(.rect(cornerRadius: 5))
            }
            .chartXAxis {
                AxisMarks(values: Array(sessions.indices)) { value in
                    if let index = value.as(Int.self), sessions.indices.contains(index) {
                        AxisValueLabel(sessions[index].startedAt.formatted(.dateTime.day().month(.defaultDigits)))
                    }
                }
            }
            .frame(height: 140)
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

/// One exercise of a plan: each set last time next to the time before, with what changed.
struct ExerciseComparison: View {
    let def: ExerciseDef?
    let last: [WorkoutSet]
    let before: [WorkoutSet]
    let beforeDate: Date?

    var body: some View {
        let kind = def?.kind ?? .weightReps
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ExerciseBadge(exercise: def, size: 30)
                Text(def?.name ?? "Deleted exercise").display(20).lineLimit(1)
            }

            if last.isEmpty {
                Text("Skipped last time").font(Typo.body(13)).foregroundStyle(Theme.ink3)
            } else {
                HStack(spacing: 8) {
                    Text("Set").frame(width: 28, alignment: .leading)
                    Text(beforeDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "Before")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Last").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Change").frame(width: 84, alignment: .trailing)
                }
                .eyebrow(10)

                ForEach(Array(last.enumerated()), id: \.element.id) { index, set in
                    let previous = before.indices.contains(index) ? before[index] : nil
                    let change = SetChange(from: previous, to: set, kind: kind)
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(Typo.display(16))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 28, alignment: .leading)
                        Text(previous.map { Fmt.set($0, kind: kind) } ?? "–")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.set(set, kind: kind))
                            .font(Typo.display(19))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(change.text)
                            .font(Typo.body(12.5, .semibold))
                            .foregroundStyle(change.color)
                            .frame(width: 84, alignment: .trailing)
                    }
                }
            }
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

/// How a set changed from the same set last time: "+2.5 kg", "+1 rep", "Same", "New".
struct SetChange {
    let text: String
    let color: Color

    init(from previous: WorkoutSet?, to set: WorkoutSet, kind: ExerciseKind) {
        guard let previous else {
            text = "New"
            color = Theme.ink3
            return
        }
        let dr = (set.reps ?? 0) - (previous.reps ?? 0)
        let reps = dr == 0 ? nil : "\(dr > 0 ? "+" : "−")\(abs(dr)) \(abs(dr) == 1 ? "rep" : "reps")"
        switch kind {
        case .weightReps:
            let dw = (set.weight ?? 0) - (previous.weight ?? 0)
            if abs(dw) >= 0.01 {
                text = "\(dw > 0 ? "+" : "−")\(Fmt.weight(abs(dw))) kg"
                color = dw > 0 ? Theme.good : Theme.danger
            } else if let reps {
                text = reps
                color = dr > 0 ? Theme.good : Theme.danger
            } else {
                text = "Same"
                color = Theme.ink3
            }
        case .repsOnly:
            text = reps ?? "Same"
            color = dr > 0 ? Theme.good : dr < 0 ? Theme.danger : Theme.ink3
        case .duration:
            let ds = (set.seconds ?? 0) - (previous.seconds ?? 0)
            text = ds == 0 ? "Same" : "\(ds > 0 ? "+" : "−")\(abs(ds))s"
            color = ds > 0 ? Theme.good : ds < 0 ? Theme.danger : Theme.ink3
        }
    }
}
