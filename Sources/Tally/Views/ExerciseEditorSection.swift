import TallyCore
import TallyKit
import SwiftUI

/// List section for one exercise inside a workout or plan: header menu, notes, set rows, "Add set".
struct ExerciseEditorSection: View {
    @Environment(GymStore.self) private var gym
    @Binding var exercise: WorkoutExercise
    /// true in an active workout (previous column + checkmarks); false when editing a plan or past workout.
    let isLive: Bool
    /// Where this exercise sits in a superset (drawn as a bar on the header row).
    var supersetPosition: Supersets.Position = .none
    /// "Superset A", "Giant set B", "Circuit A" for a grouped exercise.
    var groupLabel: String?
    /// The exercise the next set belongs to (shown as "Up next" in a live workout).
    var isNext = false
    /// Exercises this one can be put in a superset with.
    var supersetCandidates: [(id: UUID, name: String)] = []
    var onSuperset: (UUID) -> Void = { _ in }
    var onLeaveSuperset: () -> Void = {}
    var onRemove: () -> Void
    var onMove: (Int) -> Void = { _ in }
    var onSetCompleted: (WorkoutExercise) -> Void = { _ in }

    @AppStorage("progression.enabled") private var showsProgression = true
    @State private var showingPlates = false
    @State private var showingDemo = false
    @State private var addingNote = false
    @State private var editingPin = false
    @State private var replacing = false

    private static let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let def = gym.exercise(exercise.exerciseID)
        let kind = def?.kind ?? .weightReps
        let previous: [WorkoutSet?] = isLive ? gym.previousMatches(for: exercise) : []

        Section {
            HStack(spacing: 12) {
                if supersetPosition != .none {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 4, height: 40)
                }
                // Tap the badge to see how the exercise is done; the play mark says so.
                let hasDemo = def.flatMap { ExerciseMediaStore.shared.media(for: $0) } != nil
                Button { showingDemo = true } label: {
                    ExerciseBadge(exercise: def, size: 44)
                        .overlay(alignment: .bottomTrailing) {
                            if hasDemo {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Theme.accentInk)
                                    .frame(width: 16, height: 16)
                                    .background(Theme.accent, in: .circle)
                                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 1.5))
                                    .offset(x: 4, y: 4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!hasDemo)
                .accessibilityLabel(def.map { "How to do \($0.name)" } ?? "")
                if let def {
                    NavigationLink(value: def) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.name).display(22).foregroundStyle(Theme.ink).lineLimit(2)
                            MuscleSummaryText(exercise: def, size: 12.5)
                            HStack(spacing: 8) {
                                if isNext && isLive {
                                    Text("Up next")
                                        .font(Typo.body(11, .bold))
                                        .foregroundStyle(Theme.accentInk)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent, in: .capsule)
                                }
                                if supersetPosition != .none {
                                    Label(groupLabel ?? "Superset", systemImage: "link")
                                        .font(Typo.body(12, .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                // Only the last exercise of a superset starts the rest timer.
                                if exercise.restSeconds > 0 && (supersetPosition == .none || supersetPosition == .last) {
                                    Label("Rest \(Fmt.rest(exercise.restSeconds))", systemImage: "timer")
                                        .font(Typo.body(12, .semibold))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                        }
                    }
                } else {
                    Text("Deleted exercise").display(22)
                }
                Menu {
                    Picker(selection: $exercise.restSeconds) {
                        ForEach(Self.restOptions, id: \.self) { Text(Fmt.rest($0)).tag($0) }
                    } label: {
                        Label("Rest timer: \(Fmt.rest(exercise.restSeconds))", systemImage: "timer")
                    }
                    .pickerStyle(.menu)
                    if !supersetCandidates.isEmpty {
                        Menu {
                            ForEach(supersetCandidates, id: \.id) { candidate in
                                Button(candidate.name) { onSuperset(candidate.id) }
                            }
                        } label: {
                            Label(supersetPosition == .none ? "Superset with" : "Add to this group", systemImage: "link")
                        }
                    }
                    if supersetPosition != .none {
                        Button("Take out of the group", systemImage: "minus.circle", action: onLeaveSuperset)
                    }
                    if exercise.notes.isEmpty && !addingNote {
                        Button("Add note for today", systemImage: "note.text") { addingNote = true }
                    }
                    Button(gym.pinnedNote(for: exercise.exerciseID).isEmpty ? "Pin a note" : "Edit pinned note", systemImage: "pin") {
                        editingPin = true
                    }
                    if !exercise.sets.contains(where: \.isDone) {
                        Button("Replace exercise", systemImage: "arrow.triangle.2.circlepath") { replacing = true }
                    }
                    if kind == .weightReps {
                        if !warmUps(for: def).isEmpty {
                            Button("Add warm-up sets", systemImage: "flame") { addWarmUps(for: def) }
                        }
                        Button("Plate calculator", systemImage: "circle.grid.2x1") { showingPlates = true }
                    }
                    Button("Move up", systemImage: "arrow.up") { onMove(-1) }
                    Button("Move down", systemImage: "arrow.down") { onMove(1) }
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
            }
            .cardRow()
            .id(exercise.id)
            .sheet(isPresented: $showingPlates) {
                PlateCalculatorSheet(target: exercise.sets.compactMap(\.weight).max())
            }
            .sheet(isPresented: $showingDemo) {
                if let def { ExerciseDemoSheet(exercise: def) }
            }
            .pinnedNoteEditor(for: exercise.exerciseID, isPresented: $editingPin)
            .sheet(isPresented: $replacing) {
                ExercisePicker(single: true) { picked in
                    if let replacement = picked.first { replace(with: replacement) }
                }
            }

            if !gym.pinnedNote(for: exercise.exerciseID).isEmpty {
                PinnedNoteRow(exerciseID: exercise.exerciseID, isEditing: $editingPin)
                    .cardRow()
            }

            if isLive, let last = gym.lastSession(for: exercise.exerciseID) {
                LastTimeRow(
                    session: last,
                    kind: kind,
                    suggestion: kind == .weightReps && showsProgression
                        ? gym.progression(for: exercise.exerciseID, targetReps: exercise.sets.first { $0.type == .normal }?.reps)
                        : nil
                ) { suggestion in
                    // Fills the sets still to do; reps stay as typed or planned.
                    for index in exercise.sets.indices where !exercise.sets[index].isDone && exercise.sets[index].type == .normal {
                        exercise.sets[index].weight = suggestion.weight
                        if exercise.sets[index].reps == nil { exercise.sets[index].reps = suggestion.reps }
                    }
                }
                .cardRow()
            }

            if !exercise.notes.isEmpty || addingNote {
                TextField("Note", text: $exercise.notes, axis: .vertical)
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
                    .cardRow()
            }

            SetHeader(kind: kind, showsPrevious: isLive, showsCheck: isLive)
                .cardRow()

            ForEach($exercise.sets) { $set in
                let index = exercise.sets.firstIndex { $0.id == set.id } ?? 0
                SetRow(
                    set: $set,
                    number: exercise.sets.prefix(index + 1).filter { $0.type != .warmup }.count,
                    kind: kind,
                    previous: previous.indices.contains(index) ? previous[index] : nil,
                    showsCheck: isLive,
                    isRecord: gym.records[set.id] != nil,
                    weightStep: gym.progressionStep(for: exercise.exerciseID, weight: set.weight ?? previous.compactMap { $0?.weight }.max() ?? 20),
                    onAddDrop: kind == .weightReps || kind == .weightedBodyweight ? { addDropSet(after: set.id) } : nil
                ) {
                    onSetCompleted(exercise)
                }
            }
            .onDelete { exercise.sets.remove(atOffsets: $0) }

            Button {
                // Same values as the set above (assistance and distance too), as a normal set.
                var new = exercise.sets.last?.copyForNewSet() ?? WorkoutSet()
                new.type = .normal
                exercise.sets.append(new)
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.fill, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .cardRow()
        }
    }

    /// A drop set straight after `id`: about 20% lighter, rounded to the exercise's step.
    private func addDropSet(after id: WorkoutSet.ID) {
        guard let index = exercise.sets.firstIndex(where: { $0.id == id }) else { return }
        let source = exercise.sets[index]
        var drop = WorkoutSet(type: .drop)
        if let weight = source.weight, weight > 0 {
            let step = gym.progressionStep(for: exercise.exerciseID, weight: weight)
            drop.weight = max(step, Plates.round(weight * 0.8, to: step))
        }
        exercise.sets.insert(drop, at: index + 1)
    }

    /// Swaps in another exercise (e.g. the machine is taken), keeping the number and types of sets.
    private func replace(with replacement: ExerciseDef) {
        guard replacement.id != exercise.exerciseID else { return }
        let count = max(exercise.sets.filter { $0.type != .warmup }.count, 1)
        exercise.exerciseID = replacement.id
        exercise.sets = (0..<count).map { _ in WorkoutSet() }
        if replacement.kind == .duration || replacement.kind == .distanceDuration {
            exercise.restSeconds = min(exercise.restSeconds, 60)
        }
    }

    /// Ramp-up sets to the heaviest working set, starting from the empty bar on barbell lifts.
    private func warmUps(for def: ExerciseDef?) -> [WorkoutSet] {
        guard let working = exercise.sets.filter({ $0.type != .warmup }).compactMap(\.weight).max() else { return [] }
        let bar: Double = switch def?.equipment ?? .other {
        case .barbell, .smith: 20
        case .ezBar: 10
        default: 0
        }
        return WarmUp.sets(working: working, bar: bar).map { WorkoutSet(type: .warmup, weight: $0.weight, reps: $0.reps) }
    }

    /// Replaces warm-ups not done yet with a fresh ramp, placed before the working sets.
    private func addWarmUps(for def: ExerciseDef?) {
        let sets = warmUps(for: def)
        exercise.sets.removeAll { $0.type == .warmup && !$0.isDone }
        let index = exercise.sets.lastIndex { $0.type == .warmup }.map { $0 + 1 } ?? 0
        exercise.sets.insert(contentsOf: sets, at: index)
    }
}

/// What was done last time, and what to aim for today.
struct LastTimeRow: View {
    let session: ExerciseSession
    let kind: ExerciseKind
    let suggestion: Progression.Suggestion?
    let apply: (Progression.Suggestion) -> Void

    private func compact(_ set: WorkoutSet) -> String {
        switch kind {
        case .weightReps: "\(Fmt.weight(set.weight ?? 0))×\(set.reps ?? 0)"
        case .repsOnly: "\(set.reps ?? 0)"
        case .duration: Fmt.seconds(set.seconds ?? 0)
        case .weightedBodyweight, .assistedBodyweight, .distanceDuration: Fmt.set(set, kind: kind)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last time · \(session.date.formatted(.dateTime.weekday(.abbreviated).day().month()))").eyebrow(10.5)
                Text(session.sets.filter { $0.type != .warmup }.map(compact).joined(separator: "  ·  "))
                    .font(Typo.body(13.5, .medium))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            if let suggestion {
                Button {
                    apply(suggestion)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: symbol(suggestion.action))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.card, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Today: \(Fmt.weight(suggestion.weight)) kg × \(suggestion.reps)")
                                .font(Typo.body(14, .bold))
                                .foregroundStyle(Theme.ink)
                            Text(suggestion.reason)
                                .font(Typo.body(12))
                                .foregroundStyle(Theme.ink2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text("Use")
                            .font(Typo.body(13, .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(Fmt.weight(suggestion.weight)) kilos for \(suggestion.reps) reps. \(suggestion.reason)")
            }
        }
    }

    private func symbol(_ action: Progression.Action) -> String {
        switch action {
        case .increase: "arrow.up"
        case .addReps: "plus"
        case .hold: "equal"
        case .deload: "arrow.down"
        }
    }
}
