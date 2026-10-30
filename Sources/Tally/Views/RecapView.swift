import SwiftUI
import TallyCore
import TallyKit

/// Navigation value for a week's recap.
struct RecapRoute: Hashable {
    let weekStart: Date
}

struct RecapView: View {
    @Environment(GymStore.self) private var gym
    let weekStart: Date

    @State private var sharing = false

    var body: some View {
        Group {
            if let recap = gym.recap(weekOf: weekStart) {
                content(recap)
            } else {
                ContentUnavailableView("No recap", systemImage: "calendar")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Share", systemImage: "square.and.arrow.up") { sharing = true }
        }
        .sheet(isPresented: $sharing) { ShareSheet(model: .week(containing: weekStart, gym: gym)) }
    }

    private struct RecordRow: Identifiable {
        let id: UUID
        let exerciseID: UUID
        let set: WorkoutSet
        let kinds: [RecordKind]
    }

    private func records(in week: DateInterval) -> [RecordRow] {
        gym.workouts
            .filter { $0.startedAt >= week.start && $0.startedAt < week.end }
            .flatMap { workout in
                workout.exercises.flatMap { exercise in
                    exercise.sets.compactMap { set in
                        gym.records[set.id].map { RecordRow(id: set.id, exerciseID: exercise.exerciseID, set: set, kinds: $0) }
                    }
                }
            }
    }

    private func content(_ recap: WeeklyRecap) -> some View {
        let last = recap.week.end.addingTimeInterval(-1)
        let records = records(in: recap.week)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week \(Calendar.current.component(.weekOfYear, from: recap.week.start))").eyebrow(11)
                    Text("\(recap.week.start.formatted(.dateTime.day().month(.abbreviated)))–\(last.formatted(.dateTime.day().month(.abbreviated)))")
                        .display(40)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    RecapTile(label: "Workouts", value: "\(recap.totals.workouts)",
                              change: Double(recap.totals.workouts - recap.previous.workouts)) { "\(Int($0))" }
                    RecapTile(label: "Time", value: Fmt.duration(recap.totals.duration),
                              change: recap.totals.duration - recap.previous.duration) { Fmt.duration($0) }
                    RecapTile(label: "Volume", value: Fmt.volume(recap.totals.volume),
                              change: recap.totals.volume - recap.previous.volume) { Fmt.volume($0) }
                    RecapTile(label: "Sets", value: "\(recap.totals.sets)",
                              change: Double(recap.totals.sets - recap.previous.sets)) { "\(Int($0))" }
                }

                if recap.totals.activities > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "applewatch").font(.system(size: 18, weight: .semibold))
                        Text("\(recap.totals.activities) other \(recap.totals.activities == 1 ? "workout" : "workouts")")
                            .font(Typo.body(15, .semibold))
                        Spacer()
                        if recap.totals.activityEnergy >= 1 {
                            Text("\(Int(recap.totals.activityEnergy.rounded())) kcal")
                                .font(Typo.body(14))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .card(padding: 14, cornerRadius: 20)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Muscles").display(16)
                    MuscleVolumeCard(weeklySets: gym.weeklyMuscleSets(in: recap.week), caption: "Working sets this week")
                }
                .card(padding: 14, cornerRadius: 20)

                if let improvement = recap.mostImproved, let def = gym.exercise(improvement.exerciseID) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Most improved").display(16)
                        ExerciseLabel(exercise: def)
                        Text("Est. 1RM \(Fmt.weight(improvement.before)) → \(Fmt.weight(improvement.after)) kg (+\(Fmt.weight(improvement.change)) kg)")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Theme.good)
                    }
                    .card(padding: 14, cornerRadius: 20)
                }

                if !records.isEmpty {
                    SectionHead("Records")
                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            let def = gym.exercise(record.exerciseID)
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(def?.name ?? "Exercise").display(19).lineLimit(1)
                                    Text(record.kinds.map(\.label).joined(separator: ", "))
                                        .font(Typo.body(12.5))
                                        .foregroundStyle(Theme.ink3)
                                }
                                Spacer()
                                Text(Fmt.set(record.set, kind: def?.kind ?? .weightReps))
                                    .font(Typo.display(20))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .card(padding: 0, cornerRadius: 18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

/// A recap number with its change against the week before.
struct RecapTile: View {
    let label: String
    let value: String
    let change: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(Typo.display(30))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                Text(label).eyebrow(10.5)
                if abs(change) >= 1 {
                    Label(format(abs(change)), systemImage: change > 0 ? "arrow.up" : "arrow.down")
                        .font(Typo.body(11.5, .bold))
                        .foregroundStyle(change > 0 ? Theme.good : Theme.danger)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(padding: 0, cornerRadius: 18)
    }
}

/// Every week with a workout, newest first.
struct RecapListView: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        List(Recaps.weeks(with: gym.sessionSummaries), id: \.self) { start in
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            NavigationLink(value: RecapRoute(weekStart: start)) {
                HStack {
                    Text("Week \(Calendar.current.component(.weekOfYear, from: start))").display(20)
                    Spacer()
                    Text("\(start.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .cardRow()
        }
        .screenBackground()
        .navigationTitle("Weekly recaps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Last week's numbers on Home, shown from Monday until dismissed. Opens the full recap.
struct LastWeekCard: View {
    @Environment(GymStore.self) private var gym
    @AppStorage("recap.dismissedWeek") private var dismissedWeek = 0.0

    var body: some View {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -1, to: gym.weekStart(.now)) ?? .now
        if let recap = gym.recap(weekOf: lastWeek), recap.totals.workouts > 0,
           dismissedWeek != recap.week.start.timeIntervalSinceReferenceDate {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink(value: RecapRoute(weekStart: recap.week.start)) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Last week").eyebrow()
                            Text("\(recap.totals.workouts) \(recap.totals.workouts == 1 ? "workout" : "workouts")").display(30)
                            Text("\(Fmt.duration(recap.totals.duration)) · \(Fmt.volume(recap.totals.volume))")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink2)
                        }
                        Spacer(minLength: 0)
                        AnatomyFigure(weeklySets: gym.weeklyMuscleSets(in: recap.week))
                            .frame(height: 70)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button("Dismiss", systemImage: "xmark") {
                    withAnimation(.snappy) { dismissedWeek = recap.week.start.timeIntervalSinceReferenceDate }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink3)
                .frame(width: 30, height: 30)
                .buttonStyle(.plain)
            }
            .card(padding: 14)
        }
    }
}
