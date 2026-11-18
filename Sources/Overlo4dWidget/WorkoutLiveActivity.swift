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
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.workoutName)
                            .font(Typo.title(15))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: phase.symbol)
                            .foregroundStyle(phase.tint)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Typo.display(20))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetail(state: context.state, phase: phase)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.good).frame(width: 7, height: 7)
                    WidgetLabel(text: "In progress")
                }
                Text(context.attributes.workoutName)
                    .font(Typo.title(20))
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                NextUp(state: context.state)
                ProgressView(value: Double(context.state.setsDone), total: Double(max(context.state.setsTotal, 1)))
                    .tint(Theme.accent)
                SetCount(state: context.state)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                WidgetLabel(text: "Time")
                Text(context.attributes.startedAt, style: .timer)
                    .font(Typo.display(40))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 130, alignment: .trailing)
            }
        }
        .padding(16)
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

/// "Next: Bench Press · Set 3 of 4", or "All sets done".
struct NextUp: View {
    let state: WorkoutActivityAttributes.ContentState
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(state.exerciseName.map { "Next: \($0)" } ?? "All sets done")
                .font(Typo.body(13, .semibold))
                .foregroundStyle(Theme.ink2)
            if let set = state.nextSet {
                Text(set)
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

/// Expanded Dynamic Island: rest countdown, paused rest, rest over, or the next exercise with set progress.
struct ActivityDetail: View {
    let state: WorkoutActivityAttributes.ContentState
    let phase: WorkoutActivityPhase

    var body: some View {
        switch phase {
        case .resting(let rest):
            VStack(spacing: 6) {
                HStack(alignment: .center) {
                    NextUp(state: state)
                    Spacer()
                    Text(timerInterval: countdown(rest), countsDown: true)
                        .font(Typo.display(34))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100, alignment: .trailing)
                }
                RestBar(rest: rest)
            }
        case .restPaused(let remaining):
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest paused")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(.secondary)
                    NextUp(state: state)
                }
                Spacer()
                Text(clock(remaining))
                    .font(Typo.display(34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }
        case .restOver:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest over")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.good)
                    NextUp(state: state)
                }
                Spacer()
                Text("Go")
                    .font(Typo.title(24))
                    .foregroundStyle(Theme.good)
            }
        case .finished(let summary):
            Text(summary)
                .font(Typo.body(14, .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .training:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(state.exerciseName.map { "Next: \($0)" } ?? "All sets done")
                        .font(Typo.body(14))
                        .lineLimit(1)
                    Spacer()
                    Text("\(state.setsDone)/\(state.setsTotal) sets")
                        .font(Typo.body(12, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressView(value: Double(state.setsDone), total: Double(max(state.setsTotal, 1)))
                    .tint(Theme.accent)
            }
        }
    }
}
