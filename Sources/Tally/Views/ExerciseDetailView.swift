import Charts
import TallyCore
import TallyKit
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(GymStore.self) private var gym
    let exercise: ExerciseDef

    @State private var metric: ChartMetric?
    @State private var editing = false

    enum ChartMetric: String, CaseIterable, Identifiable {
        case heaviest = "Heaviest"
        case oneRepMax = "Best 1RM"
        case volume = "Volume"
        case reps = "Reps"
        case time = "Time"
        case assistance = "Assistance"
        case distance = "Distance"
        case pace = "Pace"

        var id: String { rawValue }

        static func metrics(for kind: ExerciseKind) -> [ChartMetric] {
            switch kind {
            case .weightReps: [.heaviest, .oneRepMax, .volume]
            case .repsOnly: [.reps]
            case .duration: [.time]
            case .weightedBodyweight: [.heaviest, .reps]
            case .assistedBodyweight: [.assistance, .reps]
            case .distanceDuration: [.distance, .time, .pace]
            }
        }

        /// The session's value for this chart, or nil when the session has nothing to plot
        /// (e.g. a run logged with time only has no distance or pace).
        func value(_ session: ExerciseSession) -> Double? {
            let sets = session.sets.filter { $0.type != .warmup }
            switch self {
            case .heaviest:
                return sets.compactMap(\.weight).max()
            case .oneRepMax:
                return sets.map(\.estimatedOneRepMax).filter { $0 > 0 }.max()
            case .volume:
                let volume = sets.reduce(0) { $0 + $1.volume }
                return volume > 0 ? volume : nil
            case .reps:
                let reps = sets.compactMap(\.reps)
                return reps.isEmpty ? nil : Double(reps.reduce(0, +))
            case .time:
                let seconds = sets.compactMap(\.seconds)
                return seconds.isEmpty ? nil : Double(seconds.reduce(0, +))
            case .assistance:
                return sets.filter { ($0.reps ?? 0) > 0 }.compactMap(\.assistance).min()
            case .distance:
                let meters = sets.compactMap(\.meters)
                return meters.isEmpty ? nil : meters.reduce(0, +) / 1000
            case .pace:
                let timed = sets.filter { ($0.meters ?? 0) > 0 && ($0.seconds ?? 0) > 0 }
                let km = timed.reduce(0) { $0 + ($1.meters ?? 0) } / 1000
                let seconds = Double(timed.reduce(0) { $0 + ($1.seconds ?? 0) })
                return km > 0 ? seconds / km : nil
            }
        }

        var unit: String {
            switch self {
            case .heaviest, .oneRepMax, .volume, .assistance: "kg"
            case .reps: "reps"
            case .time: ""
            case .distance: "km"
            case .pace: "/km"
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .time, .pace: Fmt.seconds(Int(value.rounded()))
            default: Fmt.weight(value)
            }
        }
    }

    var body: some View {
        // Look the exercise up again so edits show straight away.
        if let current = gym.exercise(exercise.id) {
            content(current)
        } else {
            ContentUnavailableView("Exercise deleted", systemImage: "trash")
                .screenBackground()
        }
    }

    private func content(_ exercise: ExerciseDef) -> some View {
        let sessions = gym.sessions(for: exercise.id)
        let metrics = ChartMetric.metrics(for: exercise.kind)
        // Open on the first chart that has data, so a run logged with time only doesn't open on "0 km".
        let selected = metric ?? metrics.first { option in sessions.contains { option.value($0) != nil } } ?? metrics[0]
        let points = sessions.reversed().compactMap { session in selected.value(session).map { (date: session.date, value: $0) } }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.isCustom ? "\(exercise.muscle.label) · Custom" : exercise.muscle.label).eyebrow(11)
                    Text(exercise.name).display(34).lineLimit(2)
                }

                HStack(alignment: .center, spacing: 18) {
                    AnatomyFigure(primary: Set(exercise.primary), secondary: Set(exercise.secondary))
                        .frame(height: 200)
                    MuscleLegend(primary: exercise.primary, secondary: exercise.secondary)
                    Spacer(minLength: 0)
                }
                .card()

                if sessions.isEmpty {
                    Text("Not logged yet")
                        .display(20)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(gym.bests(for: exercise), id: \.kind) { best in
                            Tile(value: Fmt.record(best.value, kind: best.kind, exercise: exercise.kind), label: best.kind.label)
                        }
                        Tile(value: "\(sessions.count)", label: "Sessions")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if metrics.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(metrics) { option in
                                    let isOn = option == selected
                                    Button(option.rawValue) { withAnimation(.snappy) { metric = option } }
                                        .font(Typo.body(13, .semibold))
                                        .foregroundStyle(isOn ? Theme.paper : Theme.ink2)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 34)
                                        .background(isOn ? Theme.ink : .clear, in: .capsule)
                                        .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line2, lineWidth: 1))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        if let latest = points.last {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(selected.format(latest.value))
                                    .font(Typo.display(54))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                if !selected.unit.isEmpty { Text(selected.unit).eyebrow(12) }
                            }
                        }
                        Chart(points, id: \.date) { point in
                            AreaMark(x: .value("Date", point.date), y: .value(selected.rawValue, point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    LinearGradient(colors: [Theme.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                                )
                            LineMark(x: .value("Date", point.date), y: .value(selected.rawValue, point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            PointMark(x: .value("Date", point.date), y: .value(selected.rawValue, point.value))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(30)
                        }
                        .frame(height: 180)
                        .animation(.snappy, value: selected)
                    }
                    .card()

                    if exercise.kind == .weightReps {
                        RepMaxCard(sessions: sessions)
                    }

                    SectionHead("History")
                    ForEach(sessions) { session in
                        HStack(alignment: .top, spacing: 14) {
                            Bib(date: session.date, size: .small)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.workoutName).display(18).lineLimit(1)
                                ForEach(session.sets) { set in
                                    HStack(spacing: 6) {
                                        Text(Fmt.set(set, kind: exercise.kind))
                                            .font(Typo.display(19))
                                            .monospacedDigit()
                                        if set.type != .normal {
                                            Text(set.type.label).eyebrow(10)
                                        }
                                        if gym.records[set.id] != nil {
                                            Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(Theme.hot)
                                        }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .card(padding: 12, cornerRadius: 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if exercise.isCustom {
                Button("Edit", systemImage: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { ExerciseEditor(exercise: exercise) }
    }
}

/// Heaviest weight lifted for 1 to 10 reps.
private struct RepMaxCard: View {
    let sessions: [ExerciseSession]

    var body: some View {
        let lifts = sessions.flatMap { session in
            session.sets.filter { $0.type != .warmup }.compactMap { set -> RepMax.Lift? in
                guard let weight = set.weight, let reps = set.reps else { return nil }
                return RepMax.Lift(weight: weight, reps: reps, date: session.date)
            }
        }
        let table = RepMax.table(lifts, upTo: 10)
        if !table.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rep maxes").display(16)
                    Spacer()
                    Text("Best for at least that many reps").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
                VStack(spacing: 0) {
                    ForEach(Array(table.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(entry.reps)RM")
                                .font(Typo.body(14, .semibold))
                                .frame(width: 48, alignment: .leading)
                            Text(entry.date.formatted(.dateTime.day().month().year(.twoDigits)))
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                            Spacer()
                            Text("\(Fmt.weight(entry.weight)) kg")
                                .font(Typo.display(20))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .card()
        }
    }
}
