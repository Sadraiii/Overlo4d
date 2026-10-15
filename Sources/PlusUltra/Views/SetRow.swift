import PlusUltraKit
import SwiftUI

/// Text field bound to an optional number. Keeps its own text so partial input like "62." isn't reformatted while typing.
struct NumberField<Value: Numeric & LosslessStringConvertible & Equatable>: View {
    @Binding var value: Value?
    var placeholder: String
    var decimal = false

    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(Typo.display(22))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .frame(height: 40)
            .background(Theme.paper, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Value(newText.replacingOccurrences(of: ",", with: "."))
                if parsed != value { value = newText.isEmpty ? nil : parsed }
            }
            .onChange(of: value) { _, newValue in
                let current = Value(text.replacingOccurrences(of: ",", with: "."))
                if current != newValue { text = Self.format(newValue) }
            }
    }

    private static func format(_ value: Value?) -> String {
        guard let value else { return "" }
        if let double = value as? Double { return Fmt.weight(double).replacingOccurrences(of: ",", with: "") }
        return String(describing: value)
    }
}

/// Column headers above the set rows.
struct SetHeader: View {
    let kind: ExerciseKind
    var showsPrevious = true
    var showsCheck = true

    var body: some View {
        HStack(spacing: 8) {
            Text("Set").frame(width: 32)
            if showsPrevious { Text("Previous").frame(maxWidth: .infinity) }
            switch kind {
            case .weightReps:
                Text("Kg").frame(width: 66)
                Text("Reps").frame(width: 58)
            case .repsOnly:
                Text("Reps").frame(width: 76)
            case .duration:
                Text("Sec").frame(width: 76)
            }
            if !showsPrevious { Spacer() }
            if showsCheck { Image(systemName: "checkmark").frame(width: 38) }
        }
        .eyebrow(10.5)
    }
}

/// One set: type/number, previous value, inputs and the done checkmark.
struct SetRow: View {
    @Binding var set: WorkoutSet
    let number: Int
    let kind: ExerciseKind
    var previous: WorkoutSet?
    var showsCheck = true
    var isRecord = false
    var onCompleted: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Set type", selection: $set.type) {
                    ForEach(SetType.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Text(set.type == .normal ? "\(number)" : set.type.badge)
                    .font(Typo.display(18))
                    .foregroundStyle(badgeColor)
                    .frame(width: 30, height: 30)
                    .background(set.type == .normal ? Theme.line : badgeColor.opacity(0.16), in: .circle)
                    .frame(width: 32)
            }

            if showsCheck {
                Button {
                    if let previous { fill(from: previous) }
                } label: {
                    Text(previous.map { Fmt.set($0, kind: kind) } ?? "–")
                        .font(Typo.body(13, .medium))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            switch kind {
            case .weightReps:
                NumberField(value: $set.weight, placeholder: previous?.weight.map(Fmt.weight) ?? "0", decimal: true)
                    .frame(width: 66)
                NumberField(value: $set.reps, placeholder: previous?.reps.map(String.init) ?? "0")
                    .frame(width: 58)
            case .repsOnly:
                NumberField(value: $set.reps, placeholder: previous?.reps.map(String.init) ?? "0")
                    .frame(width: 76)
            case .duration:
                NumberField(value: $set.seconds, placeholder: previous?.seconds.map(String.init) ?? "0")
                    .frame(width: 76)
            }

            if !showsCheck { Spacer() }

            if showsCheck {
                Button {
                    toggleDone()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(set.isDone ? Theme.card : Theme.ink3)
                        .frame(width: 38, height: 38)
                        .background(set.isDone ? Theme.good : Theme.line, in: .rect(cornerRadius: 11))
                        .symbolEffect(.bounce, value: set.isDone)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isRecord {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.hot)
                    .offset(x: 4, y: -6)
            }
        }
        .listRowBackground(set.isDone ? Theme.goodSoft : Theme.card)
        .animation(.snappy, value: set.isDone)
        .sensoryFeedback(.success, trigger: set.isDone) { _, done in done }
    }

    private var badgeColor: Color {
        switch set.type {
        case .normal: Theme.ink
        case .warmup: Theme.hot
        case .drop: Theme.accent
        case .failure: Theme.danger
        }
    }

    private func fill(from source: WorkoutSet) {
        if set.weight == nil { set.weight = source.weight }
        if set.reps == nil { set.reps = source.reps }
        if set.seconds == nil { set.seconds = source.seconds }
    }

    private func toggleDone() {
        if set.isDone {
            set.isDone = false
            return
        }
        // Like Hevy: completing an empty set uses the previous values.
        if let previous { fill(from: previous) }
        guard set.hasValues else { return }
        set.isDone = true
        onCompleted()
    }
}
