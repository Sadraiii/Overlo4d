import SwiftUI
import TallyCore
import TallyKit

/// The fasting timer on the food diary: plan, a ring that fills towards the goal, the stage and start/end.
struct FastingCard: View {
    @Environment(FoodStore.self) private var food
    @State private var choosingStart = false
    @State private var showingHistory = false

    var body: some View {
        let log = food.fasting
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fasting").eyebrow()
                Spacer()
                Menu {
                    Picker("Plan", selection: Binding(get: { log.planHours }, set: { food.setFastingPlan($0) })) {
                        ForEach(FastingLog.plans, id: \.self) { hours in
                            Text("\(FastingLog.label(hours: hours)) · \(hours) hours").tag(hours)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(FastingLog.label(hours: log.planHours))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(Typo.body(13, .semibold))
                }
            }

            if let start = log.current {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let elapsed = log.elapsed(at: context.date)
                    let hours = elapsed / 3600
                    let stage = FastingStage.at(hours: hours)
                    HStack(spacing: 16) {
                        ZStack {
                            GoalRing(progress: log.progress(at: context.date), lineWidth: 10)
                            VStack(spacing: 0) {
                                Text(Self.clock(elapsed))
                                    .font(Typo.display(28))
                                    .monospacedDigit()
                                Text("of \(log.planHours)h").eyebrow(10)
                            }
                        }
                        .frame(width: 104, height: 104)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stage.title).font(Typo.body(15, .semibold))
                            Text(stage.detail)
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                            if let goal = log.goalDate {
                                Text(goal > context.date ? "Goal at \(goal.formatted(date: .omitted, time: .shortened))" : "Goal reached")
                                    .font(Typo.body(12.5, .semibold))
                                    .foregroundStyle(goal > context.date ? Theme.ink2 : Theme.good)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Fasting for \(Self.clock(elapsed)) of \(log.planHours) hours. \(stage.title).")
                }
                HStack {
                    Text("Started \(start.formatted(date: .omitted, time: .shortened))")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("End fast") { withAnimation(.snappy) { _ = food.endFast() } }
                        .buttonStyle(.smallOutline)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not fasting").font(Typo.body(15, .semibold))
                        Text("Logging food ends a fast automatically.")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Button("Start fast") { choosingStart = true }
                        .buttonStyle(.smallPrimary)
                }
            }

            if let last = log.history.first {
                Button { showingHistory = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: last.reachedGoal ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(last.reachedGoal ? Theme.good : Theme.ink3)
                        Text("Last fast \(Fmt.hours(last.hours))")
                        if log.streak > 1 { Text("· \(log.streak) in a row") }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
        .sensoryFeedback(.success, trigger: log.isFasting)
        .confirmationDialog("Start fast", isPresented: $choosingStart, titleVisibility: .hidden) {
            Button("Start now") { food.startFast() }
            if let last = food.lastMealTime, Date.now.timeIntervalSince(last) < 20 * 3600 {
                Button("From my last meal at \(last.formatted(date: .omitted, time: .shortened))") { food.startFast(at: last) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingHistory) {
            FastingHistorySheet().environment(food)
        }
    }

    /// "9:05" for 9 hours 5 minutes.
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

extension Fmt {
    /// "15h 30m".
    static func hours(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// Past fasts with their length against the plan.
struct FastingHistorySheet: View {
    @Environment(FoodStore.self) private var food
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let log = food.fasting
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        StatBlock(label: "In a row", value: "\(log.streak)")
                        StatBlock(label: "Average", value: log.averageHours().map(Fmt.hours) ?? "–")
                        StatBlock(label: "Fasts", value: "\(log.history.count)")
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Average of the last 7 fasts. Fasting isn't for everyone: skip it if you're pregnant, have diabetes or a history of eating disorders, and talk to a doctor if unsure.")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                }
                .cardRow()

                Section {
                    ForEach(log.history) { fast in
                        HStack {
                            Image(systemName: fast.reachedGoal ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(fast.reachedGoal ? Theme.good : Theme.ink3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fast.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(Typo.body(15, .medium))
                                Text("\(fast.start.formatted(date: .omitted, time: .shortened)) – \(fast.end.formatted(date: .omitted, time: .shortened)) · goal \(fast.goalHours)h")
                                    .font(Typo.body(12.5))
                                    .foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            Text(Fmt.hours(fast.hours))
                                .font(Typo.display(20))
                                .monospacedDigit()
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { food.deleteFast(fast.id) }
                        }
                    }
                }
                .cardRow()
            }
            .screenBackground()
            .navigationTitle("Fasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
