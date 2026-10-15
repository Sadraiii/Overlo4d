import TallyKit
import SwiftUI

/// Quick rep counter, laid out like Outdoor Office's counters.
struct QuickCountView: View {
    @Environment(RepModel.self) private var model
    @State private var showingAddExercise = false
    @State private var newExerciseName = ""
    @State private var customTarget: QuickExercise?
    @State private var customAmount = ""
    @State private var deleting: QuickExercise?
    @State private var sharing = false

    private static let goals = [50, 100, 150, 200, 300, 500, 1000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TodayCard(goals: Self.goals)
                WeekRepsCard()

                SectionHead("Exercises") {
                    Button("Add") {
                        newExerciseName = ""
                        showingAddExercise = true
                    }
                }

                ForEach(model.exercises) { exercise in
                    RepCounterCard(exercise: exercise) {
                        customAmount = ""
                        customTarget = exercise
                    }
                    .contextMenu {
                        Button("Undo last", systemImage: "arrow.uturn.backward") { withAnimation { model.undoLast(for: exercise) } }
                        Button("Reset today", systemImage: "arrow.counterclockwise") { withAnimation { model.resetToday(for: exercise) } }
                        Button("Move up", systemImage: "arrow.up") { model.move(exercise, by: -1) }
                        Button("Move down", systemImage: "arrow.down") { model.move(exercise, by: 1) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = exercise }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Reps")
        .toolbar {
            Button("Share today", systemImage: "square.and.arrow.up") { sharing = true }
                .disabled(model.repsToday == 0)
        }
        .sheet(isPresented: $sharing) { ShareSheet(model: .reps(model)) }
        .alert("New exercise", isPresented: $showingAddExercise) {
            TextField("Burpees", text: $newExerciseName)
            Button("Add") { model.addExercise(named: newExerciseName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Add reps to \(customTarget?.name ?? "")",
            isPresented: Binding(get: { customTarget != nil }, set: { if !$0 { customTarget = nil } })
        ) {
            TextField("Reps", text: $customAmount)
                .keyboardType(.numberPad)
            Button("Add") {
                if let exercise = customTarget, let reps = Int(customAmount) {
                    withAnimation { model.add(reps, to: exercise) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "exercise")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { model.delete(deleting) }
            }
        } message: {
            Text("Its rep history is deleted too.")
        }
    }
}

/// Today's total against the daily goal, with tally marks (each mark is 5% of the goal).
struct TodayCard: View {
    @Environment(RepModel.self) private var model
    let goals: [Int]

    var body: some View {
        let progress = model.progress
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").eyebrow()
                Spacer()
                Menu {
                    Picker("Daily goal", selection: Binding(get: { model.dailyGoal }, set: model.setGoal)) {
                        ForEach(goals, id: \.self) { Text("\($0) reps").tag($0) }
                    }
                } label: {
                    Label("Goal \(model.dailyGoal)", systemImage: "target")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(model.repsToday)")
                    .font(Typo.display(68))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(model.dailyGoal)")
                    .font(Typo.display(30))
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if progress >= 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.good)
                        .frame(width: 28, height: 28)
                        .background(Theme.goodSoft, in: .circle)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.ink3)
                        .monospacedDigit()
                }
            }
            Tally(marks: Int(min(progress, 1) * 20), groups: 4, done: progress >= 1)
                .padding(.vertical, 6)
        }
        .animation(.snappy, value: model.repsToday)
        .card(padding: 15)
    }
}

/// Reps per day this week, as Outdoor Office's week bars.
struct WeekRepsCard: View {
    @Environment(RepModel.self) private var model

    var body: some View {
        let days = model.dailyTotals(days: 7)
        let most = max(days.map(\.reps).max() ?? 0, model.dailyGoal, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days").display(16)
                Spacer()
                Text("\(days.reduce(0) { $0 + $1.reps }.formatted()) reps").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.date) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Theme.paper)
                            if day.reps > 0 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(day.reps >= model.dailyGoal ? Theme.good : Theme.accent)
                                    .frame(height: max(8, 54 * CGFloat(day.reps) / CGFloat(most)))
                            }
                        }
                        .frame(height: 54)
                        .clipShape(.rect(cornerRadius: 6))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(Typo.body(10.5, isToday ? .bold : .semibold))
                            .foregroundStyle(isToday ? Theme.accent : Theme.ink3)
                    }
                }
            }
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

/// One exercise: name, today's count, tally (each mark is 10 reps) and buttons.
struct RepCounterCard: View {
    @Environment(RepModel.self) private var model
    let exercise: QuickExercise
    let onCustom: () -> Void

    @State private var bump = false

    var body: some View {
        let today = model.repsToday(for: exercise)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exercise.name).display(23)
                Spacer()
                Text("All time \(model.totalReps(for: exercise).formatted())")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(today)")
                    .font(Typo.display(60))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .scaleEffect(bump ? 1.06 : 1, anchor: .bottomLeading)
                Spacer()
                Text("Reps").eyebrow(12)
            }
            Tally(marks: min(today / 10, 20), groups: 4)
                .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button("Undo", systemImage: "arrow.uturn.backward") { withAnimation(.snappy) { model.undoLast(for: exercise) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(OOButtonStyle(kind: .outline, height: 46))
                Button("+10") { add(10) }
                    .buttonStyle(OOButtonStyle(kind: .ink, height: 46, fullWidth: true))
                Button("+20") { add(20) }
                    .buttonStyle(OOButtonStyle(kind: .ink, height: 46, fullWidth: true))
                Button("Other", action: onCustom)
                    .buttonStyle(OOButtonStyle(kind: .outline, height: 46))
            }
            .monospacedDigit()
        }
        .card(padding: 15)
        .sensoryFeedback(.increase, trigger: today)
    }

    private func add(_ reps: Int) {
        withAnimation(.snappy) { model.add(reps, to: exercise) }
        withAnimation(.easeOut(duration: 0.12)) { bump = true }
        withAnimation(.easeIn(duration: 0.2).delay(0.12)) { bump = false }
    }
}
