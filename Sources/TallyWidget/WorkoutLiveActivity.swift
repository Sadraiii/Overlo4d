import ActivityKit
import TallyKit
import SwiftUI
import WidgetKit

/// Lock screen banner and Dynamic Island while a workout is running.
/// Between sets it turns into a rest timer that counts down and drains a bar on its own,
/// then shows "Rest over" when the time is up, even with the app closed.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Theme.card)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(URL(string: "tally://train"))
        } dynamicIsland: { context in
            let phase = RestPhase(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.workoutName)
                        .font(Typo.display(18))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Typo.display(20))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetail(state: context.state, phase: phase)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: phase.symbol)
                    .foregroundStyle(phase.isOver ? Theme.good : Theme.accent)
            } compactTrailing: {
                switch phase {
                case .resting(let rest):
                    Text(timerInterval: Date.now...max(rest.upperBound, Date.now), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: 44)
                case .over:
                    Text("Go").foregroundStyle(Theme.good)
                case .training:
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                switch phase {
                case .resting(let rest):
                    Text(timerInterval: Date.now...max(rest.upperBound, Date.now), countsDown: true)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.accent)
                default:
                    Image(systemName: phase.symbol)
                        .foregroundStyle(phase.isOver ? Theme.good : Theme.accent)
                }
            }
            .keylineTint(Theme.accent)
            .widgetURL(URL(string: "tally://train"))
        }
    }
}

/// Whether the activity is counting down a rest, has just finished one, or is between rests.
enum RestPhase {
    case resting(ClosedRange<Date>)
    case over
    case training

    init(_ context: ActivityViewContext<WorkoutActivityAttributes>) {
        self.init(state: context.state, isStale: context.isStale)
    }

    init(state: WorkoutActivityAttributes.ContentState, isStale: Bool) {
        guard let rest = state.restInterval else { self = .training; return }
        // The activity goes stale when the rest ends (see LiveActivityManager).
        self = isStale || rest.upperBound <= .now ? .over : .resting(rest)
    }

    var isOver: Bool { if case .over = self { true } else { false } }

    var symbol: String {
        switch self {
        case .resting: "timer"
        case .over: "bell.fill"
        case .training: "figure.strengthtraining.traditional"
        }
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        switch RestPhase(context) {
        case .resting(let rest):
            RestBanner(state: context.state, workoutName: context.attributes.workoutName, rest: rest)
        case .over:
            RestOverBanner(state: context.state, workoutName: context.attributes.workoutName)
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
                    .font(Typo.display(24))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                NextUp(state: context.state)
                ProgressView(value: Double(context.state.setsDone), total: Double(max(context.state.setsTotal, 1)))
                    .tint(Theme.accent)
                Text("\(context.state.setsDone)/\(context.state.setsTotal) sets")
                    .font(Typo.body(11.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
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

/// Lock screen while resting: big countdown, a bar that drains to zero, and what's next.
struct RestBanner: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String
    let rest: ClosedRange<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    WidgetLabel(text: "Rest")
                }
                Spacer()
                Text(workoutName)
                    .font(Typo.body(11.5, .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 14) {
                Text(timerInterval: Date.now...max(rest.upperBound, Date.now), countsDown: true)
                    .font(Typo.display(52))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(width: 130, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    NextUp(state: state, alignment: .trailing)
                    Text("\(state.setsDone)/\(state.setsTotal) sets")
                        .font(Typo.body(11.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                }
            }

            RestBar(rest: rest)
        }
        .padding(16)
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
                    .font(Typo.display(30))
                    .textCase(.uppercase)
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

/// "Bench Press · Set 3 of 4", or "All sets done".
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

/// Expanded Dynamic Island: rest countdown, rest over, or the next exercise with set progress.
struct ActivityDetail: View {
    let state: WorkoutActivityAttributes.ContentState
    let phase: RestPhase

    var body: some View {
        switch phase {
        case .resting(let rest):
            VStack(spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Rest", systemImage: "timer")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(.secondary)
                        NextUp(state: state)
                    }
                    Spacer()
                    Text(timerInterval: Date.now...max(rest.upperBound, Date.now), countsDown: true)
                        .font(Typo.display(34))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100, alignment: .trailing)
                }
                RestBar(rest: rest)
            }
        case .over:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Rest over", systemImage: "bell.fill")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.good)
                    NextUp(state: state)
                }
                Spacer()
                Text("Go")
                    .font(Typo.display(30))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.good)
            }
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
                }
                ProgressView(value: Double(state.setsDone), total: Double(max(state.setsTotal, 1)))
                    .tint(Theme.accent)
            }
        }
    }
}
