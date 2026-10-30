import SwiftUI
import TallyCore
import TallyKit

/// Navigation value for the coach screen.
struct CoachRoute: Hashable {}

/// The load check on Home. Opens the coach screen.
struct CoachCard: View {
    @Environment(GymStore.self) private var gym
    @Environment(CoachCloudStore.self) private var cloud

    var body: some View {
        let flags = gym.workouts.isEmpty ? [] : gym.loadReport().flags
        let serious = flags.filter { $0.severity == 2 }.count
        let headline = if !cloud.inbox.isEmpty {
            "Claude sent \(cloud.inbox.count) \(cloud.inbox.count == 1 ? "change" : "changes") to look at"
        } else if gym.workouts.isEmpty {
            "Log a workout for feedback"
        } else if serious > 0 {
            "\(serious) \(serious == 1 ? "thing" : "things") to ease off"
        } else if !flags.isEmpty {
            "\(flags.count) \(flags.count == 1 ? "thing" : "things") to look at"
        } else {
            "Training load looks good"
        }

        NavigationLink(value: CoachRoute()) {
            HStack(spacing: 14) {
                Image(systemName: serious > 0 ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(serious > 0 ? Theme.hot : Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(serious > 0 ? Theme.hot.opacity(0.16) : Theme.accentSoft, in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach").eyebrow(11)
                    Text(headline).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                    if let first = flags.first {
                        Text(first.title)
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .card(padding: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Training load, weekly sets per muscle and Claude's review of the last weeks.
struct CoachView: View {
    @Environment(GymStore.self) private var gym
    @Environment(CoachCloudStore.self) private var cloud
    @Environment(SleepStore.self) private var sleep
    @State private var reviewing: Workout?

    var body: some View {
        let report = gym.loadReport()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach").display(40)
                    Text("How your training is going, what to change and where you're doing too much.")
                        .font(Typo.body(15))
                        .foregroundStyle(Theme.ink2)
                }

                if let readiness = sleep.report().readiness {
                    ReadinessRow(readiness: readiness)
                }

                CoachInboxSection()

                SectionHead("Training load")
                if gym.workouts.isEmpty {
                    Text("Finish a workout and the load check starts here.")
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14, cornerRadius: 20)
                } else if report.flags.isEmpty {
                    Label("Nothing stands out. Volume and recovery look fine.", systemImage: "checkmark.circle.fill")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.good)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14, cornerRadius: 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(report.flags.enumerated()), id: \.offset) { index, flag in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            LoadFlagRow(flag: flag)
                        }
                    }
                    .card(padding: 0, cornerRadius: 18)
                }

                if !report.lastWeek.isEmpty {
                    SectionHead("Sets in 7 days")
                    WeeklySetsCard(report: report)
                }

                SectionHead("AI feedback")
                NavigationLink(value: CoachChatRoute()) {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ask the coach").font(Typo.body(15, .semibold))
                            Text("Questions about your training, sleep or food, and changes to your plans")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                    }
                    .foregroundStyle(Theme.ink)
                    .card(padding: 14, cornerRadius: 20)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                CoachFeedbackPanel(scope: .overall, askTitle: "Review my training")
                CoachProgramRow()

                if let last = gym.workouts.first {
                    Button {
                        reviewing = last
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Feedback on last workout").font(Typo.body(15, .semibold))
                                Text("\(last.name) · \(last.startedAt.formatted(.dateTime.weekday(.wide).day().month()))")
                                    .font(Typo.body(13))
                                    .foregroundStyle(Theme.ink3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                        }
                        .foregroundStyle(Theme.ink)
                        .card(padding: 14, cornerRadius: 20)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewing) { WorkoutCoachSheet(workout: $0) }
        .task { await cloud.refreshInbox() }
    }
}

struct LoadFlagRow: View {
    let flag: LoadFlag

    var body: some View {
        let tint = switch flag.severity {
        case 2: Theme.danger
        case 1: Theme.hot
        default: Theme.ink2
        }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: flag.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(flag.title).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                Text(flag.detail).font(Typo.body(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// Hard sets per muscle in the last 7 days against the 10–20 range most people grow in.
struct WeeklySetsCard: View {
    let report: LoadReport

    var body: some View {
        let rows = report.lastWeek.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let scale = max(TrainingLoad.highSets * 1.25, rows.first?.value ?? 0)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.key) { row in
                let color = row.value > TrainingLoad.highSets ? Theme.danger
                    : row.value >= TrainingLoad.productiveSets ? Theme.good : Theme.ink3
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Muscle.label(row.key)).font(Typo.body(14, .semibold))
                        Spacer()
                        if let usual = report.usualWeek[row.key] {
                            Text("usual \(Self.format(usual))").font(Typo.body(12)).foregroundStyle(Theme.ink3)
                        }
                        Text(Self.format(row.value)).font(Typo.display(18)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            // The productive range.
                            Rectangle()
                                .fill(Theme.good.opacity(0.14))
                                .frame(width: width * (TrainingLoad.highSets - TrainingLoad.productiveSets) / scale)
                                .offset(x: width * TrainingLoad.productiveSets / scale)
                            Capsule().fill(color).frame(width: max(6, width * min(row.value, scale) / scale))
                        }
                    }
                    .frame(height: 8)
                    .clipShape(.capsule)
                }
            }
            HStack(spacing: 14) {
                legend(Theme.ink3, "Under 10")
                legend(Theme.good, "10–20")
                legend(Theme.danger, "Over 20")
            }
            .padding(.top, 4)
            Text("Secondary muscles count as half a set.")
                .font(Typo.body(12))
                .foregroundStyle(Theme.ink3)
        }
        .card(padding: 14, cornerRadius: 20)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(Typo.body(12, .semibold)).foregroundStyle(Theme.ink2)
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Claude's feedback for a scope: a key prompt, the ask button, progress, an error or the answer.
struct CoachFeedbackPanel: View {
    @Environment(CoachStore.self) private var coach
    @Environment(GymStore.self) private var gym
    @Environment(SleepStore.self) private var sleep
    @Environment(FoodStore.self) private var food
    @Environment(CoachCloudStore.self) private var cloud
    let scope: CoachScope
    var askTitle = "Get feedback"
    /// Asks as soon as the panel appears, when there's a key and no earlier answer.
    var askOnAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coach.hasKey {
                CoachConnectorHint(question: claudeQuestion)
                if !cloud.isConnected { CoachKeyPrompt() }
            } else if coach.isLoading(scope) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(scope == .sleep ? "Claude is reading your sleep…" : "Claude is reading your log…").font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .card(padding: 14, cornerRadius: 20)
            } else if let saved = coach.feedback(for: scope) {
                CoachFeedbackContent(feedback: saved.feedback, nextTitle: scope == .sleep ? "Tonight" : "Next session")
                HStack {
                    Text("\(CoachModel(rawValue: saved.model)?.label ?? saved.model) · \(saved.date.formatted(.relative(presentation: .named)))")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { ask() }
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                Button(askTitle, systemImage: "sparkles") { ask() }
                    .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 50, fullWidth: true))
            }

            if let error = coach.error(for: scope) {
                Text(error.message)
                    .font(Typo.body(13, .semibold))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if askOnAppear && coach.hasKey && coach.feedback(for: scope) == nil && coach.error(for: scope) == nil {
                await coach.ask(scope, gym: gym, sleep: sleep.coachLines(), nutrition: food.coachLines())
            }
        }
    }

    /// What to ask Claude through the connector instead.
    private var claudeQuestion: String {
        switch scope {
        case .workout(let id):
            "Give me feedback on my \(gym.workout(id)?.name ?? "last") workout in Overlo4d and what to do next session"
        case .overall:
            "Review my training in Overlo4d over the last 4 weeks: what's going well, what to change, and where I'm doing too much"
        case .sleep:
            "Review my sleep in Overlo4d over the last two weeks and how it affects my training"
        }
    }

    private func ask() {
        Task { await coach.ask(scope, gym: gym, sleep: sleep.coachLines(), nutrition: food.coachLines()) }
    }
}

struct CoachFeedbackContent: View {
    let feedback: CoachFeedback
    var nextTitle = "Next session"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(feedback.summary)
                .font(Typo.body(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14, cornerRadius: 20)

            if !feedback.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(feedback.warnings.enumerated()), id: \.offset) { index, warning in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        WarningRow(warning: warning)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1))
            }

            if !feedback.goingWell.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Going well").eyebrow(11)
                    ForEach(feedback.goingWell, id: \.self) { point in
                        Label {
                            Text(point).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(Theme.good)
                        }
                        .font(Typo.body(14))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14, cornerRadius: 20)
            }

            if !feedback.changes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Change").eyebrow(11)
                    ForEach(Array(feedback.changes.enumerated()), id: \.offset) { index, change in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(Typo.display(18))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 28, height: 28)
                                .background(Theme.accent, in: .circle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.title).font(Typo.body(15, .semibold))
                                Text(change.detail).font(Typo.body(13.5)).foregroundStyle(Theme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14, cornerRadius: 20)
            }

            if !feedback.nextSession.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(nextTitle).eyebrow(11)
                    Text(feedback.nextSession)
                        .font(Typo.body(15, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.accentSoft, in: .rect(cornerRadius: 16))
            }
        }
    }

    private struct WarningRow: View {
        let warning: CoachFeedback.Warning

        var body: some View {
            let (label, color): (String, Color) = switch warning.level {
            case .watch: ("Watch", Theme.ink2)
            case .reduce: ("Reduce", Theme.hot)
            case .rest: ("Rest", Theme.danger)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(warning.area).font(Typo.body(15, .semibold))
                    Text(label)
                        .font(Typo.body(11.5, .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.14), in: .capsule)
                }
                Text(warning.detail).font(Typo.body(13.5)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

/// Feedback on one workout, from the summary screen or History.
struct WorkoutCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.name).display(32).lineLimit(2)
                        Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink2)
                    }
                    CoachFeedbackPanel(scope: .workout(workout.id), askOnAppear: true)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Asks for an API key where feedback would be, so it works from any screen.
struct CoachKeyPrompt: View {
    @Environment(CoachStore.self) private var coach
    @State private var key = ""
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Claude").font(Typo.body(15, .semibold))
            Text("AI feedback uses your own Anthropic API key. It stays in this iPhone's Keychain, and your workouts are only sent when you ask for feedback.")
                .font(Typo.body(13))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Typo.body(15))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.fill, in: .rect(cornerRadius: 12))
                Button("Save") {
                    rejected = !coach.setKey(key)
                    if !rejected { key = "" }
                }
                .buttonStyle(.smallPrimary)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if rejected {
                Text("That doesn't look like an Anthropic API key. They start with sk-ant-.")
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(Theme.danger)
            }
            Link("Get a key at platform.claude.com", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                .font(Typo.body(13, .semibold))
        }
        .card(padding: 14, cornerRadius: 20)
    }
}

/// API key, model and goal in Settings.
struct CoachSettingsSection: View {
    @Environment(CoachStore.self) private var coach
    @AppStorage(CoachGoal.storageKey) private var goal = CoachGoal.muscle.rawValue

    var body: some View {
        @Bindable var coach = coach

        VStack(alignment: .leading, spacing: 12) {
            Text("AI coach").eyebrow(11.5)
            if coach.hasKey {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("API key saved", systemImage: "key.fill").font(Typo.body(15, .semibold))
                        Spacer()
                        Button("Remove", role: .destructive) { coach.removeKey() }
                            .font(Typo.body(14, .semibold))
                    }
                    .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text("Model").font(Typo.body(15, .semibold))
                        Spacer()
                        Picker("Model", selection: $coach.model) {
                            ForEach(CoachModel.allCases) { model in
                                Text("\(model.label) · \(model.note)").tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text("Goal").font(Typo.body(15, .semibold))
                        Spacer()
                        Picker("Goal", selection: $goal) {
                            ForEach(CoachGoal.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .card(padding: 0, cornerRadius: 18)
                Text("When you ask for feedback, your last 4 weeks of workouts and notes, and your last 2 weeks of sleep, are sent to Anthropic. In Ask the coach, only what the coach looks up for your question is sent. Requests are billed to your API account.")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("Goal").font(Typo.body(15, .semibold))
                    Spacer()
                    Picker("Goal", selection: $goal) {
                        ForEach(CoachGoal.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .card(padding: 0, cornerRadius: 18)
                CoachKeyPrompt()
            }
            CoachConnectorSettingsSection()
        }
    }
}
