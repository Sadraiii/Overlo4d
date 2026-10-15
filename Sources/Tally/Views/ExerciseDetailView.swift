import Charts
import TallyKit
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(GymStore.self) private var gym
    let exercise: ExerciseDef

    @State private var metric: ChartMetric?

    enum ChartMetric: String, CaseIterable, Identifiable {
        case heaviest = "Heaviest"
        case oneRepMax = "Best 1RM"
        case volume = "Volume"
        case reps = "Reps"
        case time = "Time"

        var id: String { rawValue }

        static func metrics(for kind: ExerciseKind) -> [ChartMetric] {
            switch kind {
            case .weightReps: [.heaviest, .oneRepMax, .volume]
            case .repsOnly: [.reps]
            case .duration: [.time]
            }
        }

        func value(_ session: ExerciseSession) -> Double {
            let sets = session.sets.filter { $0.type != .warmup }
            switch self {
            case .heaviest: return sets.map { $0.weight ?? 0 }.max() ?? 0
            case .oneRepMax: return sets.map(\.estimatedOneRepMax).max() ?? 0
            case .volume: return sets.reduce(0) { $0 + $1.volume }
            case .reps: return Double(sets.reduce(0) { $0 + ($1.reps ?? 0) })
            case .time: return Double(sets.reduce(0) { $0 + ($1.seconds ?? 0) })
            }
        }

        var unit: String {
            switch self {
            case .heaviest, .oneRepMax, .volume: "kg"
            case .reps: "reps"
            case .time: "sec"
            }
        }
    }

    var body: some View {
        let sessions = gym.sessions(for: exercise.id)
        let metrics = ChartMetric.metrics(for: exercise.kind)
        let selected = metric ?? metrics[0]
        let points = sessions.reversed().map { (date: $0.date, value: selected.value($0)) }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ExerciseBadge(exercise: exercise, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(exercise.muscle.label) · \(exercise.kind.label)").eyebrow(11)
                        Text(exercise.name).display(34).lineLimit(2)
                    }
                }

                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        Text("No history").display(20)
                        Text("Log this exercise in a workout to see progress and records.")
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(gym.bests(for: exercise), id: \.kind) { best in
                            Tile(value: Fmt.record(best.value, kind: best.kind), label: best.kind.label)
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
                                Text(Fmt.weight(latest.value))
                                    .font(Typo.display(54))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text(selected.unit).eyebrow(12)
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
    }
}
