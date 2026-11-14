import Charts
import SwiftUI
import TallyCore
import TallyKit

/// Progress over a chosen stretch: totals against the stretch before, strength per lift, how the
/// work is spread over the body, and (for long ranges) workouts per month.
struct TrendsSection: View {
    @Environment(GymStore.self) private var gym
    @AppStorage("progress.range") private var rangeRaw = TrendRange.month.rawValue

    var body: some View {
        let range = TrendRange(rawValue: rangeRaw) ?? .month
        let sessions = gym.sessionSummaries
        let comparison = Trends.compare(sessions: sessions, days: range.days, now: .now)
        let lifts = Trends.lifts(sessions: sessions, in: comparison.current)
        let muscleSets = gym.weeklyMuscleSets(in: comparison.current)
        let shares = TrainingBalance.shares(muscleSets: Dictionary(uniqueKeysWithValues: muscleSets.map { ($0.key.rawValue, $0.value) }))

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text("Trends").display(25)
                Spacer()
                RangePicker(selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue }))
            }
            .padding(.top, 8)
            .padding(.horizontal, 2)

            PeriodCard(comparison: comparison, range: range)

            if !lifts.isEmpty {
                StrengthTrendsCard(lifts: lifts, range: range)
            }

            if !shares.isEmpty {
                BalanceCard(shares: shares, note: TrainingBalance.note(shares), range: range)
            }

            if range == .half || range == .year {
                MonthsCard(months: Trends.months(sessions: sessions, count: range == .year ? 12 : 6, now: .now))
            }
        }
    }
}

/// Small segmented control for the trend range.
private struct RangePicker: View {
    @Binding var selection: TrendRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrendRange.allCases) { range in
                let selected = selection == range
                Button(range.label) {
                    withAnimation(.snappy) { selection = range }
                }
                .font(Typo.body(12.5, .semibold))
                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(selected ? Theme.card : .clear, in: .rect(cornerRadius: 9))
                .buttonStyle(.plain)
                .accessibilityLabel(range.phrase)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.line, in: .rect(cornerRadius: 12))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Totals for the period, each with its change from the period before.
private struct PeriodCard: View {
    let comparison: PeriodComparison
    let range: TrendRange

    var body: some View {
        let now = comparison.totals
        let before = comparison.before
        let title = range.phrase.prefix(1).uppercased() + String(range.phrase.dropFirst())
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).display(16)
                Spacer()
                if comparison.hasEarlier {
                    Text("vs the same time before").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
            }
            if now.workouts == 0 {
                Text("No workouts in \(range.phrase).")
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading), count: 3), alignment: .leading, spacing: 14) {
                    stat("Workouts", "\(now.workouts)", change(Double(now.workouts), Double(before.workouts)))
                    stat("Per week", comparison.workoutsPerWeek.formatted(.number.precision(.fractionLength(1))), nil)
                    stat("Records", "\(now.records)", change(Double(now.records), Double(before.records)))
                    stat("Volume", Self.tonnes(now.volume), change(now.volume, before.volume))
                    stat("Sets", "\(now.sets)", change(Double(now.sets), Double(before.sets)))
                    stat("Avg session", Fmt.duration(now.averageDuration), change(now.averageDuration, before.averageDuration))
                }
            }
        }
        .card(padding: 14, cornerRadius: 20)
    }

    private func change(_ now: Double, _ before: Double) -> String? {
        comparison.hasEarlier ? Trends.changeText(now, from: before) : nil
    }

    private func stat(_ label: String, _ value: String, _ change: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow(10.5)
            Text(value)
                .font(Typo.display(26))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let change {
                Text(change)
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(change.hasPrefix("+") ? Theme.good : Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "12.4 t" from 12 400 kg; small totals stay in kg.
    static func tonnes(_ kg: Double) -> String {
        kg >= 10_000 ? "\((kg / 1000).formatted(.number.precision(.fractionLength(1)))) t" : Fmt.volume(kg)
    }
}

/// Estimated one-rep max of the most-trained lifts across the period.
private struct StrengthTrendsCard: View {
    @Environment(GymStore.self) private var gym
    let lifts: [LiftTrend]
    let range: TrendRange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Strength").display(16)
                Spacer()
                Text("Estimated 1RM").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
            }
            .padding(.bottom, 6)
            ForEach(Array(lifts.enumerated()), id: \.element.id) { index, lift in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                row(lift)
            }
        }
        .card(padding: 14, cornerRadius: 20)
    }

    @ViewBuilder private func row(_ lift: LiftTrend) -> some View {
        let percent = Int((lift.fraction * 100).rounded())
        let content = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.name(of: lift.exerciseID))
                    .font(Typo.body(14.5, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(Fmt.weight(lift.first.rounded())) → \(Fmt.weight(lift.last.rounded())) kg · \(lift.points.count) sessions")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Sparkline(points: lift.points)
                .frame(width: 64, height: 26)
                .accessibilityHidden(true)
            Text(percent == 0 ? "same" : percent > 0 ? "+\(percent)%" : "−\(-percent)%")
                .font(Typo.body(13, .bold))
                .foregroundStyle(percent > 0 ? Theme.good : percent < 0 ? Theme.hot : Theme.ink3)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)

        if let exercise = gym.exercise(lift.exerciseID) {
            NavigationLink(value: exercise) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// A plain line through the points, scaled to its own range.
struct Sparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { proxy in
            let low = points.min() ?? 0
            let span = max((points.max() ?? 0) - low, 0.0001)
            Path { path in
                for (index, value) in points.enumerated() {
                    let x = points.count > 1 ? proxy.size.width * CGFloat(index) / CGFloat(points.count - 1) : proxy.size.width / 2
                    let y = proxy.size.height * (1 - CGFloat((value - low) / span)) * 0.84 + proxy.size.height * 0.08
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Share of working sets going to push, pull, legs and core.
private struct BalanceCard: View {
    let shares: [TrainingBalance.Share]
    let note: String?
    let range: TrendRange

    var body: some View {
        let most = max(shares.map(\.fraction).max() ?? 0, 0.0001)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Balance").display(16)
                Spacer()
                Text("Share of working sets").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
            }
            ForEach(shares) { share in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(share.group.label).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink)
                        Text(share.group.detail).font(Typo.body(12)).foregroundStyle(Theme.ink3).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((share.fraction * 100).rounded()))%")
                            .font(Typo.display(18))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fill)
                            Capsule().fill(Theme.accent)
                                .frame(width: share.fraction > 0 ? max(6, proxy.size.width * share.fraction / most) : 0)
                        }
                    }
                    .frame(height: 7)
                }
                .accessibilityElement(children: .combine)
            }
            if let note {
                Label(note, systemImage: "exclamationmark.circle")
                    .font(Typo.body(13, .medium))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 14, cornerRadius: 20)
    }
}

/// Workouts per calendar month.
private struct MonthsCard: View {
    let months: [MonthStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts per month").display(16)
                Spacer()
                Text("\(months.reduce(0) { $0 + $1.workouts }) in total").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
            }
            Chart(months) { month in
                BarMark(x: .value("Month", month.month, unit: .month), y: .value("Workouts", month.workouts))
                    .foregroundStyle(Theme.accent)
                    .clipShape(.rect(cornerRadius: 5))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: months.count > 6 ? 2 : 1)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 140)
        }
        .card(padding: 14, cornerRadius: 20)
    }
}

/// On the workout summary: this session against the last one of the same plan.
struct SessionComparisonCard: View {
    let workout: Workout
    let before: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compared with \(before.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))").eyebrow()
            HStack(spacing: 12) {
                delta("Volume", workout.volume - before.volume) { "\(Fmt.weight(abs($0).rounded())) kg" }
                delta("Sets", Double(workout.completedSets.count - before.completedSets.count)) { "\(Int(abs($0)))" }
                delta("Time", (workout.duration - before.duration) / 60, higherIsBetter: false) { "\(Int(abs($0).rounded())) min" }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 18)
    }

    /// `higherIsBetter: false` keeps the colour neutral (a longer or shorter session is neither good nor bad).
    private func delta(_ label: String, _ change: Double, higherIsBetter: Bool = true, format: (Double) -> String) -> some View {
        let flat = abs(change) < 0.5
        let text = flat ? "Same" : "\(change > 0 ? "+" : "−")\(format(change))"
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow(10.5)
            Text(text)
                .font(Typo.display(24))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(flat || !higherIsBetter ? Theme.ink : change > 0 ? Theme.good : Theme.hot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
