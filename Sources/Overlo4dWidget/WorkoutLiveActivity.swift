import ActivityKit
import Overlo4dKit
import SwiftUI
import WidgetKit

/// Lock screen banner and Dynamic Island while a workout is running.
/// Between sets it turns into a rest timer that counts down and drains on its own, then shows
/// "Rest over" when the time is up, even with the app closed. A paused rest shows the time left,
/// and a finished workout leaves a short summary on the Lock Screen.
/// Countdowns use the system's timer views, so the app only sends an update when something changes.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            let phase = context.state.phase(isStale: context.isStale)
            LockScreenActivityView(context: context, phase: phase)
                .activityBackgroundTint(Theme.card)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(phase.link)
        } dynamicIsland: { context in
            let phase = context.state.phase(isStale: context.isStale)
            // Expanded: the set ring on the left, what's happening in the middle, the time that
            // matters on the right in big numbers, and the next set (or the draining rest) below.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SetsRing(done: context.state.setsDone, total: context.state.setsTotal, size: 50)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.attributes.workoutName)
                            .font(Typo.body(12, .semibold))
                            .foregroundStyle(.secondary)
                        Text(phase.headline(for: context.state))
                            .font(Typo.title(17))
                            .foregroundStyle(phase.isAlert ? phase.tint : .primary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigTime(phase: phase, startedAt: context.attributes.startedAt)
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetail(state: context.state, phase: phase)
                        .padding(.top, 6)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                CompactIndicator(phase: phase)
            } compactTrailing: {
                CompactTrailing(phase: phase, startedAt: context.attributes.startedAt)
            } minimal: {
                MinimalIndicator(phase: phase)
            }
            .keylineTint(Theme.accent)
            .widgetURL(phase.link)
        }
    }
}

extension WorkoutActivityPhase {
    /// Where a tap goes: the running workout, or History once it is saved.
    /// Same hosts as `AppLink` in Overlo4dCore ("active" never starts a workout).
    var link: URL? {
        if case .finished = self { return URL(string: "overlo4d://history") }
        return URL(string: "overlo4d://active")
    }

    var symbol: String {
        switch self {
        case .training: "figure.strengthtraining.traditional"
        case .resting: "timer"
        case .restPaused: "pause.fill"
        case .restOver: "bell.fill"
        case .finished: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .training, .resting: Theme.accent
        case .restPaused: Theme.ink3
        case .restOver, .finished: Theme.good
        }
    }

    /// States that call for the next set, drawn in their colour.
    var isAlert: Bool {
        switch self {
        case .restOver, .finished: true
        default: false
        }
    }

    /// The bold line in the middle of the expanded island.
    func headline(for state: WorkoutActivityAttributes.ContentState) -> String {
        switch self {
        case .restOver: "Rest over"
        case .finished: "Workout saved"
        case .restPaused: "Rest paused"
        case .training, .resting: state.exerciseName ?? "All sets done"
        }
    }
}

/// Sets done as a ring that fills up, with the count inside; green once every set is ticked.
struct SetsRing: View {
    let done: Int
    let total: Int
    var size: CGFloat = 50

    var body: some View {
        let progress = total > 0 ? min(1, Double(done) / Double(total)) : 0
        let complete = total > 0 && done >= total
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.22), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(complete ? Theme.good : Theme.accent, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(done)")
                    .font(Typo.display(size * 0.42))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(total)")
                    .font(Typo.body(size * 0.17, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) sets done")
    }
}

/// The big number on the right of the expanded island: the rest countdown, or the workout time.
struct BigTime: View {
    let phase: WorkoutActivityPhase
    let startedAt: Date

    var body: some View {
        Group {
            switch phase {
            case .resting(let rest):
                Text(timerInterval: countdown(rest), countsDown: true)
                    .foregroundStyle(Theme.accent)
            case .restPaused(let remaining):
                Text(clock(remaining))
                    .foregroundStyle(Theme.ink3)
            case .restOver:
                Text("Go")
                    .foregroundStyle(Theme.good)
            case .training, .finished:
                Text(startedAt, style: .timer)
            }
        }
        .font(Typo.display(36))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .frame(width: 96, alignment: .trailing)
    }
}

/// The range a countdown text runs over: from now, so it never shows more than is left.
private func countdown(_ rest: ClosedRange<Date>) -> ClosedRange<Date> {
    Date.now...max(rest.upperBound, Date.now)
}

/// "1:05" for a paused rest, which has no running timer to draw it.
private func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let rest = total % 60
    return "\(total / 60):\(rest < 10 ? "0" : "")\(rest)"
}

/// A ring that drains over the rest, animated by the system.
struct DrainingRing: View {
    let rest: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: rest, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Theme.accent)
    }
}

/// Leading side of the compact Dynamic Island: the draining ring while resting, else the phase's symbol.
struct CompactIndicator: View {
    let phase: WorkoutActivityPhase

    var body: some View {
        switch phase {
        case .resting(let rest):
            DrainingRing(rest: rest)
                .frame(width: 22, height: 22)
        default:
            Image(systemName: phase.symbol)
                .foregroundStyle(phase.tint)
        }
    }
}

/// Trailing side of the compact Dynamic Island: the time that matters right now.
struct CompactTrailing: View {
    let phase: WorkoutActivityPhase
    let startedAt: Date

    var body: some View {
        switch phase {
        case .resting(let rest):
            Text(timerInterval: countdown(rest), countsDown: true)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: 44)
        case .restPaused(let remaining):
            Text(clock(remaining))
                .monospacedDigit()
                .foregroundStyle(Theme.ink3)
        case .restOver:
            Text("Go").foregroundStyle(Theme.good)
        case .finished:
            Text("Done").foregroundStyle(Theme.good)
        case .training:
            Text(startedAt, style: .timer)
                .monospacedDigit()
                .frame(maxWidth: 52)
        }
    }
}

/// Minimal Dynamic Island (next to another app's activity): the rest countdown, like the Timer app,
/// or the phase's symbol.
struct MinimalIndicator: View {
    let phase: WorkoutActivityPhase

    var body: some View {
        switch phase {
        case .resting(let rest):
            Text(timerInterval: countdown(rest), countsDown: true)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.accent)
        default:
            Image(systemName: phase.symbol)
                .foregroundStyle(phase.tint)
        }
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    let phase: WorkoutActivityPhase

    var body: some View {
        let name = context.attributes.workoutName
        switch phase {
        case .resting(let rest):
            RestBanner(state: context.state, workoutName: name, rest: rest)
        case .restPaused(let remaining):
            PausedBanner(state: context.state, workoutName: name, remaining: remaining)
        case .restOver:
            RestOverBanner(state: context.state, workoutName: name)
        case .finished(let summary):
            FinishedBanner(workoutName: name, summary: summary)
        case .training:
            training
        }
    }

    private var training: some View {
        HStack(alignment: .center, spacing: 14) {
            SetsRing(done: context.state.setsDone, total: context.state.setsTotal, size: 58)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.good).frame(width: 7, height: 7)
                    WidgetLabel(text: context.attributes.workoutName)
                }
                Text(context.state.exerciseName ?? "All sets done")
                    .font(Typo.title(19))
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                if let line = context.state.setLine {
                    Text(line)
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(context.attributes.startedAt, style: .timer)
                .font(Typo.display(42))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .frame(width: 112, alignment: .trailing)
        }
        .padding(14)
    }
}

/// "7/18 sets", rolling to the new number when a set is ticked off.
struct SetCount: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Text("\(state.setsDone)/\(state.setsTotal) sets")
            .font(Typo.body(11.5, .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.ink3)
            .contentTransition(.numericText())
    }
}

/// Lock screen while resting: big countdown, a bar that drains to zero, and what's next.
struct RestBanner: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String
    let rest: ClosedRange<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BannerHeader(symbol: "timer", title: "Rest", tint: Theme.accent, workoutName: workoutName)

            HStack(alignment: .center, spacing: 14) {
                Text(timerInterval: countdown(rest), countsDown: true)
                    .font(Typo.display(52))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(width: 130, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    NextUp(state: state, alignment: .trailing)
                    SetCount(state: state)
                }
            }

            RestBar(rest: rest)
        }
        .padding(16)
    }
}

/// Lock screen while a rest is paused: the time left, held, in grey.
struct PausedBanner: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String
    let remaining: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BannerHeader(symbol: "pause.fill", title: "Rest paused", tint: Theme.ink3, workoutName: workoutName)

            HStack(alignment: .center, spacing: 14) {
                Text(clock(remaining))
                    .font(Typo.display(52))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
                    .frame(width: 130, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    NextUp(state: state, alignment: .trailing)
                    SetCount(state: state)
                }
            }
        }
        .padding(16)
    }
}

/// Small header row of the rest banners: symbol and state on the left, workout name on the right.
struct BannerHeader: View {
    let symbol: String
    let title: String
    let tint: Color
    let workoutName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                WidgetLabel(text: title)
            }
            Spacer()
            Text(workoutName)
                .font(Typo.body(12.5, .semibold))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
    }
}

/// Lock screen once the rest is up, until the app updates it.
struct RestOverBanner: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.good).frame(width: 7, height: 7)
                    WidgetLabel(text: "Rest over")
                }
                Text("Next set")
                    .font(Typo.title(24))
                    .foregroundStyle(Theme.good)
                NextUp(state: state)
            }
            Spacer(minLength: 0)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.good)
        }
        .padding(16)
    }
}

/// Lock screen after the workout is saved, until the system takes it down.
struct FinishedBanner: View {
    let workoutName: String
    let summary: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.good)
                .frame(width: 44, height: 44)
                .background(Theme.goodSoft, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                WidgetLabel(text: "Workout saved")
                Text(workoutName)
                    .font(Typo.title(20))
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                Text(summary)
                    .font(Typo.body(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

extension WorkoutActivityAttributes.ContentState {
    /// "Set 3 of 4 · 80 kg × 8", or just the set when it has no values yet.
    var setLine: String? {
        guard let nextSet else { return nil }
        return nextTarget.map { "\(nextSet) · \($0)" } ?? nextSet
    }
}

/// "Next: Bench Press" over "Set 3 of 4 · 80 kg × 8", or "All sets done".
struct NextUp: View {
    let state: WorkoutActivityAttributes.ContentState
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(state.exerciseName.map { "Next: \($0)" } ?? "All sets done")
                .font(Typo.body(13, .semibold))
                .foregroundStyle(Theme.ink2)
            if let line = state.setLine {
                Text(line)
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .lineLimit(1)
    }
}

/// Drains from full to empty over the rest, animated by the system.
struct RestBar: View {
    let rest: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: rest, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(Theme.accent)
    }
}

/// Bottom of the expanded Dynamic Island. The headline and big time above already say what is
/// happening, so this adds what comes next: the set and its weight, and the rest draining away.
struct ActivityDetail: View {
    let state: WorkoutActivityAttributes.ContentState
    let phase: WorkoutActivityPhase

    var body: some View {
        switch phase {
        case .resting(let rest):
            VStack(alignment: .leading, spacing: 8) {
                NextUp(state: state)
                RestBar(rest: rest)
            }
        case .restPaused, .restOver:
            NextUp(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .finished(let summary):
            Text(summary)
                .font(Typo.body(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .training:
            HStack {
                if let line = state.setLine {
                    Text(line)
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.2), in: .capsule)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }
}
