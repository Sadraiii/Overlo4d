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
    /// Exercises this one can be put in a superset with.
    var supersetCandidates: [(id: UUID, name: String)] = []
    var onSuperset: (UUID) -> Void = { _ in }
    var onLeaveSuperset: () -> Void = {}
    var onRemove: () -> Void
    var onMove: (Int) -> Void = { _ in }
    var onSetCompleted: (WorkoutExercise) -> Void = { _ in }

    @State private var showingPlates = false
    @State private var addingNote = false

    private static let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let def = gym.exercise(exercise.exerciseID)
        let kind = def?.kind ?? .weightReps
        let previous = isLive ? gym.previousSets(for: exercise.exerciseID) : []

        Section {
            HStack(spacing: 12) {
                if supersetPosition != .none {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 4, height: 40)
                }
                ExerciseBadge(exercise: def, size: 42)
                if let def {
                    NavigationLink(value: def) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.name).display(22).foregroundStyle(Theme.ink).lineLimit(2)
                            HStack(spacing: 8) {
                                if supersetPosition != .none {
                                    Label("Superset", systemImage: "link")
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
                            Label("Superset with", systemImage: "link")
                        }
                    }
                    if supersetPosition != .none {
                        Button("Remove from superset", systemImage: "minus.circle", action: onLeaveSuperset)
                    }
                    if exercise.notes.isEmpty && !addingNote {
                        Button("Add note", systemImage: "note.text") { addingNote = true }
                    }
                    if kind == .weightReps {
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
            .sheet(isPresented: $showingPlates) {
                PlateCalculatorSheet(target: exercise.sets.compactMap(\.weight).max())
            }

            if isLive, let last = gym.lastSession(for: exercise.exerciseID) {
                LastTimeRow(
                    session: last,
                    kind: kind,
                    suggestion: kind == .weightReps
                        ? gym.suggestedWeight(for: exercise.exerciseID, targetReps: exercise.sets.first { $0.type == .normal }?.reps)
                        : nil
                ) { weight in
                    for index in exercise.sets.indices where !exercise.sets[index].isDone && exercise.sets[index].type == .normal {
                        exercise.sets[index].weight = weight
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
                    isRecord: gym.records[set.id] != nil
                ) {
                    onSetCompleted(exercise)
                }
            }
            .onDelete { exercise.sets.remove(atOffsets: $0) }

            Button {
                let last = exercise.sets.last
                exercise.sets.append(WorkoutSet(type: .normal, weight: last?.weight, reps: last?.reps, seconds: last?.seconds))
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.paper, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .cardRow()
        }
    }
}

/// What was done last time, and the weight to try next.
struct LastTimeRow: View {
    let session: ExerciseSession
    let kind: ExerciseKind
    let suggestion: (weight: Double, increase: Bool)?
    let apply: (Double) -> Void

    private func compact(_ set: WorkoutSet) -> String {
        switch kind {
        case .weightReps: "\(Fmt.weight(set.weight ?? 0))×\(set.reps ?? 0)"
        case .repsOnly: "\(set.reps ?? 0)"
        case .duration: Fmt.seconds(set.seconds ?? 0)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last time · \(session.date.formatted(.dateTime.weekday(.abbreviated).day().month()))").eyebrow(10.5)
                Text(session.sets.filter { $0.type != .warmup }.map(compact).joined(separator: "  ·  "))
                    .font(Typo.body(13.5, .medium))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if let suggestion {
                Button {
                    apply(suggestion.weight)
                } label: {
                    Label("\(Fmt.weight(suggestion.weight)) kg", systemImage: suggestion.increase ? "arrow.up" : "equal")
                        .font(Typo.body(13, .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(Theme.accentSoft, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(suggestion.increase ? "Use \(Fmt.weight(suggestion.weight)) kg, up from last time" : "Use \(Fmt.weight(suggestion.weight)) kg, same as last time")
            }
        }
    }
}
