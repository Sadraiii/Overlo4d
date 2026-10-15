import ActivityKit
import TallyKit
import SwiftUI
import WidgetKit

/// Lock screen banner and Dynamic Island while a workout is running.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Theme.card)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(URL(string: "tally://train"))
        } dynamicIsland: { context in
            DynamicIsland {
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
                    ActivityDetail(state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.restEndsAt == nil ? "figure.strengthtraining.traditional" : "timer")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                if let rest = context.state.restEndsAt {
                    Text(timerInterval: Date.now...max(rest, Date.now), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
            .widgetURL(URL(string: "tally://train"))
        }
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
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
                Text(context.state.exerciseName.map { "Next: \($0)" } ?? "All sets done")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                ProgressView(value: Double(context.state.setsDone), total: Double(max(context.state.setsTotal, 1)))
                    .tint(Theme.accent)
                Text("\(context.state.setsDone)/\(context.state.setsTotal) sets")
                    .font(Typo.body(11.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if let rest = context.state.restEndsAt {
                    WidgetLabel(text: "Rest")
                    Text(timerInterval: Date.now...max(rest, Date.now), countsDown: true)
                        .font(Typo.display(44))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120, alignment: .trailing)
                } else {
                    WidgetLabel(text: "Time")
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Typo.display(40))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 130, alignment: .trailing)
                }
            }
        }
        .padding(16)
    }
}

/// Expanded Dynamic Island: rest countdown, or the next exercise with set progress.
struct ActivityDetail: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let rest = state.restEndsAt {
            HStack {
                Label("Rest", systemImage: "timer")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timerInterval: Date.now...max(rest, Date.now), countsDown: true)
                    .font(Typo.display(30))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.trailing)
            }
        } else {
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
