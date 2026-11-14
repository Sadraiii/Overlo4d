import TallyKit
import SwiftUI

/// Plus and minus steps for the number field being typed in, shown above the keyboard.
struct FieldStepper: Sendable {
    /// e.g. "2.5" or "1".
    let label: String
    /// Called with -1 or +1.
    let adjust: @MainActor @Sendable (Int) -> Void
}

extension FocusedValues {
    @Entry var fieldStepper: FieldStepper?
}

/// Text field bound to an optional number. Keeps its own text so partial input like "62." isn't reformatted while typing.
struct NumberField<Value: Numeric & Comparable & LosslessStringConvertible & Equatable & Sendable>: View {
    @Binding var value: Value?
    var placeholder: String
    var decimal = false
    /// Size of one tap on the keyboard's − and + buttons; nil for no buttons.
    var step: Value?
    /// Where − and + start from while the field is empty (last time's value).
    var base: Value?

    @State private var text = ""

    var body: some View {
        field
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .setField()
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

    @ViewBuilder private var field: some View {
        if let step {
            TextField(placeholder, text: $text)
                .focusedValue(\.fieldStepper, Self.stepper(binding: $value, step: step, base: base))
        } else {
            TextField(placeholder, text: $text)
        }
    }

    /// − and + for this field. An empty field starts from last time's value, so one tap on + gives
    /// "last time plus a step". Going to zero or below clears the field.
    private static func stepper(binding: Binding<Value?>, step: Value, base: Value?) -> FieldStepper {
        FieldStepper(label: format(step)) { direction in
            let start = binding.wrappedValue ?? base ?? Value.zero
            let next = direction > 0 ? start + step : start - step
            binding.wrappedValue = next > Value.zero ? next : nil
        }
    }

    private static func format(_ value: Value?) -> String {
        guard let value else { return "" }
        if let double = value as? Double { return Fmt.weight(double).replacingOccurrences(of: ",", with: "") }
        return String(describing: value)
    }
}

extension View {
    /// Look of the number and time inputs in set rows.
    func setField() -> some View {
        multilineTextAlignment(.center)
            .font(Typo.display(22))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .frame(height: 40)
            .background(Theme.fill, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
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
            case .weightReps, .weightedBodyweight, .assistedBodyweight:
                Text(kind == .weightedBodyweight ? "+Kg" : kind == .assistedBodyweight ? "−Kg" : "Kg").frame(width: 66)
                Text("Reps").frame(width: 58)
            case .repsOnly:
                Text("Reps").frame(width: 76)
            case .duration:
                Text("Time").frame(width: 76)
            case .distanceDuration:
                Text("Km").frame(width: 66)
                Text("Time").frame(width: 70)
            }
            if !showsPrevious { Spacer() }
            if showsCheck { Image(systemName: "checkmark").frame(width: 42) }
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
    /// The jump for the keyboard's − and + on the weight field.
    var weightStep = 2.5
    /// Adds a lighter drop set straight after this one; nil where that isn't offered.
    var onAddDrop: (() -> Void)?
    var onCompleted: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Set type", selection: $set.type) {
                    ForEach(SetType.allCases) { Text($0.label).tag($0) }
                }
                Menu {
                    Picker("Effort", selection: $set.rpe) {
                        Text("Not set").tag(Double?.none)
                        ForEach(RPE.options, id: \.self) { value in
                            Text("RPE \(RPE.format(value)) · \(RPE.meaning(value))").tag(Double?.some(value))
                        }
                    }
                } label: {
                    Label(set.rpe.map { "Effort: RPE \(RPE.format($0))" } ?? "Effort (RPE)", systemImage: "gauge.with.dots.needle.67percent")
                }
                if let onAddDrop {
                    Button("Add drop set", systemImage: "arrow.down.right", action: onAddDrop)
                }
            } label: {
                Text(set.type == .normal ? "\(number)" : set.type.badge)
                    .font(Typo.display(18))
                    .foregroundStyle(badgeColor)
                    .frame(width: 30, height: 30)
                    .background(set.type == .normal ? Theme.line : badgeColor.opacity(0.16), in: .circle)
                    .overlay(alignment: .bottom) {
                        if let rpe = set.rpe {
                            Text("@\(RPE.format(rpe))")
                                .font(Typo.body(9, .bold))
                                .foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 4)
                                .background(Theme.accent, in: .capsule)
                                .offset(y: 7)
                        }
                    }
                    .frame(width: 32)
            }
            .accessibilityLabel(set.rpe.map { "Set \(number), RPE \(RPE.format($0))" } ?? "Set \(number)")

            if showsCheck {
                Button {
                    if let previous { fill(from: previous) }
                } label: {
                    // Once a set is done, show how it compares with the same set last time.
                    let change = set.isDone ? previous.map { SetChange(from: $0, to: set, kind: kind) } : nil
                    Text(change?.text ?? previous.map { Fmt.set($0, kind: kind) } ?? "–")
                        .font(Typo.body(13, change == nil ? .medium : .bold))
                        .foregroundStyle(change?.color ?? Theme.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            switch kind {
            case .weightReps, .weightedBodyweight:
                NumberField(value: $set.weight, placeholder: previous?.weight.map(Fmt.weight) ?? "0", decimal: true, step: weightStep, base: previous?.weight)
                    .frame(width: 66)
                NumberField(value: $set.reps, placeholder: previous?.reps.map(String.init) ?? "0", step: 1, base: previous?.reps)
                    .frame(width: 58)
            case .assistedBodyweight:
                NumberField(value: $set.assistance, placeholder: previous?.assistance.map(Fmt.weight) ?? "0", decimal: true, step: weightStep, base: previous?.assistance)
                    .frame(width: 66)
                NumberField(value: $set.reps, placeholder: previous?.reps.map(String.init) ?? "0", step: 1, base: previous?.reps)
                    .frame(width: 58)
            case .repsOnly:
                NumberField(value: $set.reps, placeholder: previous?.reps.map(String.init) ?? "0", step: 1, base: previous?.reps)
                    .frame(width: 76)
            case .duration:
                TimeField(seconds: $set.seconds, placeholder: previous?.seconds.map(Fmt.seconds) ?? "0:00")
                    .frame(width: 76)
            case .distanceDuration:
                NumberField(value: kilometres, placeholder: previous?.meters.map { Fmt.weight($0 / 1000) } ?? "0", decimal: true)
                    .frame(width: 66)
                TimeField(seconds: $set.seconds, placeholder: previous?.seconds.map(Fmt.seconds) ?? "0:00")
                    .frame(width: 70)
            }

            if !showsCheck { Spacer() }

            if showsCheck {
                Button {
                    toggleDone()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(set.isDone ? Theme.card : Theme.ink3)
                        .frame(width: 42, height: 40)
                        .background(set.isDone ? Theme.good : Theme.line, in: .rect(cornerRadius: 12))
                        .symbolEffect(.bounce, value: set.isDone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isDone ? "Set \(number) done. Tap to undo" : "Complete set \(number)")
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

    /// Distance is typed in km and stored in metres.
    private var kilometres: Binding<Double?> {
        Binding(get: { set.meters.map { $0 / 1000 } }, set: { set.meters = $0.map { $0 * 1000 } })
    }

    private func fill(from source: WorkoutSet) {
        if set.weight == nil { set.weight = source.weight }
        if set.reps == nil { set.reps = source.reps }
        if set.seconds == nil { set.seconds = source.seconds }
        if set.assistance == nil { set.assistance = source.assistance }
        if set.meters == nil { set.meters = source.meters }
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

/// Rate of perceived exertion: how hard a set was, 10 meaning nothing left in the tank.
enum RPE {
    static let options: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Reps left in reserve, in words.
    static func meaning(_ value: Double) -> String {
        switch value {
        case 10...: "max effort"
        case 9.5...: "maybe 1 more"
        case 9...: "1 more"
        case 8.5...: "1–2 more"
        case 8...: "2 more"
        case 7...: "3 more"
        default: "4+ more"
        }
    }
}
