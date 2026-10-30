import SwiftUI
import TallyCore
import TallyKit

/// Programs at the top of the Plans tab.
struct ProgramsSection: View {
    @Environment(ProgramStore.self) private var store
    let onOpen: (UUID) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SectionHead("Programs") {
                Button("New", systemImage: "plus", action: onNew)
            }
            if store.programs.isEmpty {
                Button(action: onNew) {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 42, height: 42)
                            .background(Theme.accentSoft, in: .rect(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get stronger with a program").font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                            Text("Juggernaut 16 weeks, a 4–8 week block, or one the coach writes for you.")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 14, cornerRadius: 18)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            ForEach(store.programs) { program in
                ProgramCard(program: program) { onOpen(program.id) }
            }
            SectionHead("Plans")
        }
    }
}

/// A program with where you are in it and the next day to do.
struct ProgramCard: View {
    @Environment(ProgramStore.self) private var store
    @Environment(GymStore.self) private var gym
    let program: StrengthProgram
    let onOpen: () -> Void

    var body: some View {
        let logs = store.logs(for: program, gym: gym)
        let progress = program.progress(logs: logs)
        let next = program.next(logs: logs)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(next.map { "Week \($0.week + 1) of \(program.weeks.count) · \(program.weeks[$0.week].phase)" } ?? "Finished")
                    .eyebrow(11)
                    .lineLimit(1)
                Text(program.name).display(27).lineLimit(2)
            }
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .tint(Theme.accent)
            HStack(spacing: 6) {
                Text("\(progress.done) of \(progress.total) days done")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 0)
                if let next {
                    Button {
                        store.start(program, week: next.week, day: next.day, gym: gym)
                    } label: {
                        Label(program.days[next.day].name, systemImage: "play.fill").lineLimit(1)
                    }
                    .buttonStyle(.smallPrimary)
                    .disabled(gym.activeWorkout != nil)
                }
            }
        }
        .card(padding: 16, cornerRadius: 18)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
    }
}

/// A program week by week: training maxes, each day's sets with weights, and how to progress.
struct ProgramDetailView: View {
    @Environment(ProgramStore.self) private var store
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    let programID: UUID

    @State private var week: Int?
    @State private var deleting = false
    @State private var editing: StrengthProgram?

    var body: some View {
        Group {
            if let program = store.program(programID) {
                content(program)
            } else {
                ContentUnavailableView("Program deleted", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let program = store.program(programID) {
                Button("Edit", systemImage: "pencil") { editing = program }
            }
        }
        .sheet(item: $editing) { ProgramEditor(program: $0) }
    }

    private func content(_ program: StrengthProgram) -> some View {
        let logs = store.logs(for: program, gym: gym)
        let next = program.next(logs: logs)
        let shown = min(week ?? next?.week ?? max(program.weeks.count - 1, 0), max(program.weeks.count - 1, 0))
        let plan = program.weeks.isEmpty ? nil : program.weeks[shown]

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(program.weeks.count) weeks · \(program.days.count) days a week").eyebrow(11)
                    Text(program.name).display(40)
                    if !program.summary.isEmpty {
                        Text(program.summary).font(Typo.body(15)).foregroundStyle(Theme.ink2)
                    }
                }

                if !program.lifts.isEmpty {
                    SectionHead("Training maxes")
                    VStack(spacing: 0) {
                        ForEach(Array(program.lifts.enumerated()), id: \.offset) { index, lift in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            let now = program.trainingMax(for: lift.exercise, week: shown, logs: logs)
                            HStack {
                                Text(lift.exercise).font(Typo.body(15, .semibold))
                                Spacer()
                                if now > lift.trainingMax {
                                    Text("+\(Fmt.weight(now - lift.trainingMax))")
                                        .font(Typo.body(13, .semibold))
                                        .foregroundStyle(Theme.good)
                                }
                                Text("\(Fmt.weight(now)) kg").font(Typo.body(15, .semibold)).monospacedDigit()
                            }
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, 14)
                    .card(padding: 0, cornerRadius: 18)
                }

                SectionHead("Weeks")
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(program.weeks.indices, id: \.self) { index in
                                let done = program.days.indices.allSatisfy { day in logs.contains { $0.week == index && $0.day == day } }
                                Button {
                                    week = index
                                } label: {
                                    Text("\(index + 1)")
                                        .font(Typo.body(15, .semibold))
                                        .frame(width: 40, height: 40)
                                        .foregroundStyle(index == shown ? Theme.accentInk : (done ? Theme.good : Theme.ink))
                                        .background(index == shown ? Theme.accent : (done ? Theme.goodSoft : Theme.card), in: .circle)
                                        .overlay(Circle().strokeBorder(program.weeks[index].isDeload ? Theme.line2 : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(shown, anchor: .center) }
                }

                if let plan {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.phase).font(Typo.body(16, .semibold))
                        Text(plan.note).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                    }

                    ForEach(program.days.indices, id: \.self) { day in
                        ProgramDayCard(
                            program: program,
                            week: shown,
                            day: day,
                            items: program.items(week: shown, day: day, logs: logs),
                            logged: store.workout(for: program, week: shown, day: day, gym: gym),
                            isNext: next.map { $0 == (shown, day) } ?? false
                        ) {
                            store.start(program, week: shown, day: day, gym: gym)
                        }
                    }
                }

                if !program.rules.isEmpty {
                    SectionHead("How to progress")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(program.rules, id: \.self) { rule in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                                Text(rule).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14, cornerRadius: 20)
                }

                Button("Delete program", systemImage: "trash", role: .destructive) { deleting = true }
                    .buttonStyle(OOButtonStyle(kind: .danger, fullWidth: true))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .confirmationDialog("Delete \(program.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(program)
                dismiss()
            }
        } message: {
            Text("Workouts you logged from it stay in History.")
        }
    }
}

/// One day of a week: each exercise with its sets, and a Start button.
struct ProgramDayCard: View {
    @Environment(GymStore.self) private var gym
    let program: StrengthProgram
    let week: Int
    let day: Int
    let items: [ProgramItem]
    let logged: Workout?
    let isNext: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(program.days[day].name).display(22)
                Spacer()
                if let logged {
                    Label(logged.startedAt.formatted(.dateTime.day().month()), systemImage: "checkmark.circle.fill")
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.good)
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.exercise).font(Typo.body(14, .semibold)).foregroundStyle(item.isMainLift ? Theme.ink : Theme.ink2)
                    Text(Self.describe(item))
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                        .monospacedDigit()
                }
            }
            Button(action: onStart) {
                Label(logged == nil ? "Start" : "Do again", systemImage: "play.fill")
            }
            .buttonStyle(OOButtonStyle(kind: isNext ? .primary : .outline, shape: .pill, height: 40))
            .disabled(gym.activeWorkout != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 20)
    }

    /// "60 × 5, 70 × 3, 80 × 8+ kg" for main lifts (warm-ups in brackets), "3 × 10" for accessories.
    static func describe(_ item: ProgramItem) -> String {
        guard item.isMainLift else {
            return "\(item.sets.count) × \(item.sets.first?.reps ?? 0)" + (item.notes.isEmpty ? "" : " · \(item.notes)")
        }
        var groups: [(set: ProgramItem.Set, count: Int)] = []
        for set in item.sets {
            if let last = groups.last, last.set == set {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((set, 1))
            }
        }
        return groups.map { group in
            let weight = group.set.weight.map(Fmt.weight) ?? "–"
            var text = group.count > 1 ? "\(group.count) × \(group.set.reps) @ \(weight)" : "\(weight) × \(group.set.reps)"
            if group.set.amrap { text += "+" }
            return group.set.warmup ? "(\(text))" : text
        }
        .joined(separator: ", ") + " kg"
    }
}

/// Sets up a program: a template from one-rep maxes, or one the coach writes.
struct NewProgramSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case coach, juggernaut, block
        var id: String { rawValue }
        var label: String {
            switch self {
            case .coach: "Coach"
            case .juggernaut: "Juggernaut"
            case .block: "Block"
            }
        }
    }

    @Environment(ProgramStore.self) private var store
    @Environment(GymStore.self) private var gym
    @Environment(CoachStore.self) private var coach
    @Environment(\.dismiss) private var dismiss

    @State var kind: Kind = .juggernaut
    /// Called with the new program once it's saved.
    var onCreated: (StrengthProgram) -> Void = { _ in }

    @State private var maxes: [String: Double] = [:]
    @State private var blockWeeks = 6
    @State private var coachWeeks = 12
    @State private var days = 4
    @State private var notes = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Program", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(explanation).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                }
                .cardRow()

                Section {
                    ForEach(ProgramTemplates.bigFour, id: \.self) { lift in
                        HStack {
                            Text(lift).font(Typo.body(15))
                            Spacer()
                            TextField("kg", value: Binding(get: { maxes[lift] }, set: { maxes[lift] = $0 }), format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("kg").foregroundStyle(Theme.ink3)
                        }
                    }
                } header: {
                    Text("One-rep maxes")
                } footer: {
                    Text("Filled in from your log where possible. Leave a lift empty to skip it\(kind == .coach ? ", or let the coach estimate it" : ""). Weights use 90 % of these.")
                }
                .cardRow()

                switch kind {
                case .juggernaut:
                    EmptyView()
                case .block:
                    Section {
                        Stepper("\(blockWeeks) weeks", value: $blockWeeks, in: 4...8)
                    }
                    .cardRow()
                case .coach:
                    Section {
                        Stepper("\(coachWeeks) weeks", value: $coachWeeks, in: 4...16)
                        Stepper("\(days) days a week", value: $days, in: 2...6)
                        TextField("Anything else? e.g. bigger bench, sore knee, no deadlifts", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    } footer: {
                        Text("Goal: \(CoachGoal.current.label). The coach also reads your last 8 weeks of training. Uses \(coach.model.label) with your API key.")
                    }
                    .cardRow()

                    if let error = store.error {
                        Section {
                            Label(error.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                        }
                        .cardRow()
                    }
                }
            }
            .screenBackground()
            .navigationTitle("New program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: create) {
                    if store.isGenerating {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.accentInk)
                            Text("Writing your program…")
                        }
                    } else {
                        Text(kind == .coach ? "Write my program" : "Create program")
                    }
                }
                .buttonStyle(.bigPrimary)
                .disabled(!canCreate)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .onAppear(perform: fillMaxes)
        }
        .interactiveDismissDisabled(store.isGenerating)
    }

    private var explanation: String {
        switch kind {
        case .coach: "The coach writes a program around your goal, your lifts and what you already do, with phases, deloads and how to progress."
        case .juggernaut: "16 weeks in four waves of 10s, 8s, 5s and 3s. Each wave ends with a rep-out set that raises your weights, then a deload."
        case .block: "A short block: weights go up and reps go down every week, a rep-out set at the peak, then a deload."
        }
    }

    private var validMaxes: [String: Double] { maxes.filter { $0.value > 0 } }

    private var canCreate: Bool {
        if store.isGenerating { return false }
        return kind == .coach ? coach.hasKey : !validMaxes.isEmpty
    }

    private func fillMaxes() {
        guard maxes.isEmpty else { return }
        for lift in ProgramTemplates.bigFour {
            if let max = ProgramStore.estimatedMax(lift, gym: gym) { maxes[lift] = Plates.round(max, to: 2.5) }
        }
    }

    private func create() {
        switch kind {
        case .juggernaut:
            finish(ProgramTemplates.juggernaut(oneRepMaxes: validMaxes, start: .now))
        case .block:
            finish(ProgramTemplates.block(weeks: blockWeeks, oneRepMaxes: validMaxes, start: .now))
        case .coach:
            let request = ProgramRequest(weeks: coachWeeks, daysPerWeek: days, goal: CoachGoal.current.label, notes: notes, oneRepMaxes: validMaxes)
            task = Task {
                if let program = await store.generate(request, gym: gym, coach: coach) {
                    onCreated(program)
                    dismiss()
                }
            }
        }
    }

    private func finish(_ program: StrengthProgram) {
        store.add(program)
        onCreated(program)
        dismiss()
    }
}

/// On the coach screen: have the coach write a strength program.
struct CoachProgramRow: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Write me a strength program").font(Typo.body(15, .semibold))
                    Text("4–16 weeks with phases, deloads and weights filled in. It shows up in Plans.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 14, cornerRadius: 20)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { NewProgramSheet(kind: .coach) }
    }
}
