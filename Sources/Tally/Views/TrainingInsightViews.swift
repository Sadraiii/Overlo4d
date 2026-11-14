import SwiftUI
import TallyCore
import TallyKit

/// On Home: a deload week that is running, or the advice to take one.
struct DeloadCard: View {
    @Environment(GymStore.self) private var gym
    /// Advice is hidden until this time after "Not now".
    @AppStorage("deload.snoozedUntil") private var snoozedUntil = 0.0

    var body: some View {
        if gym.isDeloading, let start = gym.deloadStart {
            running(daysLeft: Deload.daysLeft(start: start, now: .now))
        } else if Date.now.timeIntervalSince1970 >= snoozedUntil, let advice = gym.deloadAdvice() {
            suggestion(advice)
        }
    }

    private func running(daysLeft: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Deload week", systemImage: "leaf.fill")
                    .font(Typo.title(17))
                    .foregroundStyle(Theme.good)
                Spacer()
                Text(daysLeft == 1 ? "Last day" : "\(daysLeft) days left")
                    .font(Typo.body(13, .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            Text("Workouts start with fewer sets and suggest about 10% less weight. Leave the gym feeling you could have done more.")
                .font(Typo.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("End deload now") { withAnimation(.snappy) { gym.endDeload() } }
                .font(Typo.body(13.5, .bold))
                .foregroundStyle(Theme.ink2)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 20)
    }

    private func suggestion(_ advice: Deload.Advice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(advice.level == .due ? "Time for a deload week" : "Consider a deload week", systemImage: "leaf.fill")
                .font(Typo.title(17))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(advice.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(Typo.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("One easier week lets your body catch up, and most people come back stronger. " + Deload.plan.joined(separator: " "))
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Start deload week") { withAnimation(.snappy) { gym.startDeload() } }
                    .buttonStyle(.smallPrimary)
                Button("Not now") {
                    withAnimation(.snappy) { snoozedUntil = Date.now.addingTimeInterval(7 * 86_400).timeIntervalSince1970 }
                }
                .buttonStyle(.smallOutline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 20)
    }
}

/// On an exercise: where the estimated one-rep max is heading, and what beats the record today.
struct ForecastCard: View {
    @Environment(GymStore.self) private var gym
    let exercise: ExerciseDef

    var body: some View {
        if let forecast = gym.forecast(for: exercise) {
            let step = gym.progressionStep(for: exercise.id, weight: forecast.best)
            let targets = StrengthForecast.targets(toBeat: forecast.best, step: step)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Prediction").display(16)
                    Spacer()
                    Text(confidence(forecast)).font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
                HStack(spacing: 8) {
                    Tile(value: Fmt.load(forecast.current.rounded()), label: "Est. 1RM now")
                    Tile(
                        value: Fmt.load(forecast.inFourWeeks.rounded()),
                        label: "In 4 weeks",
                        tint: forecast.trend == .rising ? Theme.good : Theme.ink
                    )
                    Tile(
                        value: Fmt.load(forecast.inTwelveWeeks.rounded()),
                        label: "In 12 weeks",
                        tint: forecast.trend == .rising ? Theme.good : Theme.ink
                    )
                }
                Text(trendText(forecast))
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !targets.isEmpty {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("Beat your record today with").eyebrow(11)
                    HStack(spacing: 6) {
                        ForEach(targets, id: \.reps) { target in
                            VStack(spacing: 2) {
                                Text(Fmt.load(target.weight))
                                    .font(Typo.display(20))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("× \(target.reps)")
                                    .font(Typo.body(12, .semibold))
                                    .foregroundStyle(Theme.ink3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.fill, in: .rect(cornerRadius: 12))
                        }
                    }
                    Text("Weights in \(Fmt.unit). Any of these sets tops your best estimated max of \(Fmt.mass(forecast.best)).")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func confidence(_ forecast: StrengthForecast.Result) -> String {
        let level = switch forecast.confidence {
        case .high: "Steady trend"
        case .medium: "Rough trend"
        case .low: "Early guess"
        }
        return "\(level) · \(forecast.sessions) sessions"
    }

    private func trendText(_ forecast: StrengthForecast.Result) -> String {
        let goal = Fmt.mass(forecast.milestone.weight)
        switch forecast.trend {
        case .rising:
            let pace = "Up about \(Fmt.mass(abs(forecast.perWeek))) a week."
            if let date = forecast.milestone.date {
                return "\(pace) At this pace you reach \(goal) around \(date.formatted(.dateTime.day().month(.wide)))."
            }
            return "\(pace) Next round number: \(goal)."
        case .flat:
            return "Holding steady over the last weeks. Next round number: \(goal). A small change in reps or sets can get it moving."
        case .falling:
            return "Down about \(Fmt.mass(abs(forecast.perWeek))) a week lately. Check sleep, food and whether a lighter week is due."
        }
    }
}

/// The written review of a week, at the top of its recap.
struct CoachReportCard: View {
    let report: WeeklyReport.Report

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.line, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(report.score) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(report.score)")
                        .font(Typo.display(24))
                        .monospacedDigit()
                }
                .frame(width: 62, height: 62)
                .accessibilityLabel("Score \(report.score) out of 100")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coach report").eyebrow(11)
                    Text(report.headline).font(Typo.title(21)).foregroundStyle(Theme.ink)
                    Text(report.summary)
                        .font(Typo.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            group("Went well", symbol: "checkmark.circle.fill", color: Theme.good, lines: report.wins)
            group("Keep an eye on", symbol: "exclamationmark.circle.fill", color: Theme.hot, lines: report.watch)
            group("Next week", symbol: "arrow.right.circle.fill", color: Theme.accent, lines: report.next)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 20)
    }

    private var scoreColor: Color {
        report.score >= 65 ? Theme.good : report.score >= 40 ? Theme.hot : Theme.ink3
    }

    @ViewBuilder private func group(_ title: String, symbol: String, color: Color, lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).eyebrow(11)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                        Text(line)
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
