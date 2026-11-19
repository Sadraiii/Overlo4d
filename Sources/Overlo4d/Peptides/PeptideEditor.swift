import SwiftUI
import Overlo4dCore
import Overlo4dKit

/// The inputs of one peptide. Used for a new profile and, saving as you type, for an existing one.
struct PeptideForm: View {
    @Binding var profile: PeptideProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").eyebrow(11.5)
                    TextField("Name", text: $profile.name)
                        .font(Typo.body(16, .semibold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.fill, in: .rect(cornerRadius: 12))
                    if profile.name.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(PeptideFormat.commonNames, id: \.self) { name in
                                    Button(name) { profile.name = name }
                                        .font(Typo.body(13, .semibold))
                                        .foregroundStyle(Theme.ink2)
                                        .padding(.horizontal, 11)
                                        .frame(height: 30)
                                        .background(Theme.fill, in: .capsule)
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vial, mg").eyebrow(11.5)
                        PeptideNumberField(value: $profile.vialMg, placeholder: "5")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Water, mL").eyebrow(11.5)
                        PeptideNumberField(value: $profile.waterMl, placeholder: "2")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target amount").eyebrow(11.5)
                    HStack(spacing: 12) {
                        PeptideNumberField(value: $profile.dose, placeholder: profile.doseUnit == .mg ? "0.25" : "250")
                        Picker("Unit", selection: $profile.doseUnit) {
                            ForEach(DoseUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }
                }

                VStack(spacing: 0) {
                    menuRow("Schedule") {
                        Picker("Schedule", selection: $profile.schedule) {
                            ForEach(PeptideSchedule.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    divider
                    menuRow("Syringe") {
                        Picker("Syringe", selection: $profile.syringe) {
                            ForEach(SyringeSize.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    if profile.syringe.allowsHalfUnits {
                        divider
                        Toggle("Half-unit marks", isOn: $profile.halfUnits)
                            .font(Typo.body(15, .semibold))
                            .padding(.vertical, 10)
                    }
                    divider
                    Toggle(isOn: $profile.tracksVial) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Count the vial down").font(Typo.body(15, .semibold))
                            Text("Each log entry takes its amount off the active vial.")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    .padding(.vertical, 10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").eyebrow(11.5)
                    TextField("Optional", text: $profile.notes, axis: .vertical)
                        .font(Typo.body(15))
                        .lineLimit(1...4)
                        .padding(12)
                        .background(Theme.fill, in: .rect(cornerRadius: 12))
                }
            }
            .card(padding: 16, cornerRadius: 20)
            PeptidePlanForm(profile: $profile)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func menuRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(Typo.body(15, .semibold))
            Spacer()
            content().pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }
}

/// Stock, mixed-vial age, cycle and reminder of one peptide.
struct PeptidePlanForm: View {
    @Binding var profile: PeptideProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan and stock").eyebrow(11.5).padding(.bottom, 6)
            Stepper(value: $profile.spareVials, in: 0...99) {
                row("Spare vials", profile.spareVials == 0 ? "None" : "\(profile.spareVials) unopened")
            }
            .padding(.vertical, 8)
            divider
            Stepper(value: keepsDays, in: 0...90) {
                row("Use a mixed vial for", profile.keepsDays.map { "\($0) \($0 == 1 ? "day" : "days"), as you set it" } ?? "No limit shown")
            }
            .padding(.vertical, 8)
            divider
            Toggle(isOn: hasCycle) {
                row("Cycle", "Weeks on, then weeks off")
            }
            .padding(.vertical, 8)
            if let cycle = profile.cycle {
                DatePicker("Started", selection: cycleStart, displayedComponents: .date)
                    .font(Typo.body(15, .semibold))
                    .padding(.vertical, 4)
                Stepper(value: cycleBinding(\.weeksOn), in: 1...52) {
                    Text("\(cycle.weeksOn) \(cycle.weeksOn == 1 ? "week" : "weeks") on").font(Typo.body(15, .semibold))
                }
                .padding(.vertical, 6)
                Stepper(value: cycleBinding(\.weeksOff), in: 0...52) {
                    Text(cycle.weeksOff == 0 ? "No break, then it ends" : "\(cycle.weeksOff) \(cycle.weeksOff == 1 ? "week" : "weeks") off")
                        .font(Typo.body(15, .semibold))
                }
                .padding(.vertical, 6)
            }
            divider
            Toggle(isOn: hasReminder) {
                row("Reminder", "On days something is due. The text doesn't say what for.")
            }
            .padding(.vertical, 8)
            if profile.reminderMinutes != nil {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .font(Typo.body(15, .semibold))
                    .padding(.vertical, 4)
            }
        }
        .card(padding: 16, cornerRadius: 20)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typo.body(15, .semibold))
            Text(detail).font(Typo.body(13)).foregroundStyle(Theme.ink3)
        }
    }

    private var keepsDays: Binding<Int> {
        Binding(get: { profile.keepsDays ?? 0 }, set: { profile.keepsDays = $0 > 0 ? $0 : nil })
    }

    private var hasCycle: Binding<Bool> {
        Binding(
            get: { profile.cycle != nil },
            set: { profile.cycle = $0 ? PeptideCycle(start: DayKey(.now), weeksOn: 4) : nil }
        )
    }

    private var cycleStart: Binding<Date> {
        Binding(
            get: { profile.cycle?.start.date() ?? .now },
            set: { profile.cycle?.start = DayKey($0) }
        )
    }

    private func cycleBinding(_ keyPath: WritableKeyPath<PeptideCycle, Int>) -> Binding<Int> {
        Binding(
            get: { profile.cycle?[keyPath: keyPath] ?? 0 },
            set: { profile.cycle?[keyPath: keyPath] = $0 }
        )
    }

    private var hasReminder: Binding<Bool> {
        Binding(
            get: { profile.reminderMinutes != nil },
            set: { on in
                profile.reminderMinutes = on ? 9 * 60 : nil
                if on { PeptideReminders.requestPermission() }
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: profile.reminderMinutes ?? 0, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                profile.reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// Decimal field for the calculator. Keeps its own text, so "0." and "0.125" survive typing;
/// an empty field counts as zero.
struct PeptideNumberField: View {
    @Binding var value: Double
    var placeholder: String

    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .setField()
            .onAppear { text = value > 0 ? PeptideFormat.number(value, places: 4) : "" }
            .onChange(of: text) { _, newText in
                let parsed = Double(newText.replacingOccurrences(of: ",", with: ".")) ?? 0
                let clean = parsed.isFinite ? max(0, parsed) : 0
                if clean != value { value = clean }
            }
    }
}

/// What the numbers work out to, updated as they are typed.
struct PeptideResults: View {
    let profile: PeptideProfile

    var body: some View {
        let math = profile.reconstitution
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Draw to").eyebrow(11)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(math.hasDose ? PeptideFormat.number(math.units, places: 1) : "–")
                        .font(Typo.display(64))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(math.units == 1 ? "unit" : "units").eyebrow(13)
                    Spacer()
                    if math.hasDose {
                        Text("\(PeptideFormat.number(math.milliliters, places: 3)) mL")
                            .font(Typo.display(24))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink2)
                    }
                }
                if let note = note(math) {
                    Text(note.text)
                        .font(Typo.body(13))
                        .foregroundStyle(note.warning ? Theme.danger : Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(.snappy, value: math.units)

            SyringeGauge(syringe: math.syringe, halfUnits: math.halfUnits, units: math.hasDose ? math.units : 0)

            Rectangle().fill(Theme.line).frame(height: 1)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 14) {
                StatBlock(label: "Concentration", value: math.hasConcentration ? "\(PeptideFormat.number(math.mgPerMl, places: 3)) mg/mL" : "–")
                StatBlock(label: "Per mL", value: math.hasConcentration ? "\(PeptideFormat.number(math.mcgPerMl, places: 1)) mcg" : "–")
                StatBlock(label: "Per unit (1 tick)", value: math.hasConcentration ? "\(PeptideFormat.number(math.mcgPerUnit, places: 2)) mcg" : "–")
                if math.halfUnits {
                    StatBlock(label: "Per half unit", value: math.hasConcentration ? "\(PeptideFormat.number(math.mcgPerTick, places: 2)) mcg" : "–")
                }
                StatBlock(label: "Portions per vial", value: math.hasDose ? "\(math.dosesPerVial)" : "–")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 20)
    }

    private func note(_ math: Reconstitution) -> (text: String, warning: Bool)? {
        guard math.hasDose else {
            return ("Fill in vial, water and target amount.", false)
        }
        if math.belowFirstMark {
            return ("Too small to measure on this syringe. More water makes each unit hold less.", true)
        }
        if !math.fitsSyringe {
            return ("More than this syringe holds (\(math.syringe.rawValue) units). Pick a bigger syringe or use less water.", true)
        }
        if math.isRounded {
            let exact = PeptideFormat.number(math.exactUnits, places: 2)
            return ("Nearest mark to \(exact) units. It holds \(PeptideFormat.amount(mcg: math.drawnMcg, unit: profile.doseUnit)).", false)
        }
        return nil
    }
}

/// A U-100 syringe lying on its side: needle on the left, the barrel with its unit marks, and the
/// stopper where the plunger should sit. Everything is laid out from the view's own width, so
/// it never draws past its card.
struct SyringeGauge: View {
    let syringe: SyringeSize
    let halfUnits: Bool
    let units: Double

    var body: some View {
        Canvas { context, size in
            let needle: CGFloat = 20
            let hub: CGFloat = 10
            let flange: CGFloat = 5
            // The scale starts a little inside the barrel and stops before the flange.
            let barrel = CGRect(x: needle + hub, y: 34, width: max(60, size.width - needle - hub - flange - 4), height: 34)
            let zero = barrel.minX + 8
            let full = barrel.maxX - 12
            let perUnit = (full - zero) / CGFloat(syringe.units)
            let shown = min(max(units, 0), syringe.units)
            let stop = zero + CGFloat(shown) * perUnit
            let middle = barrel.midY
            let shape = Path(roundedRect: barrel, cornerRadius: 6)

            // Needle and hub.
            var steel = Path()
            steel.move(to: CGPoint(x: 2, y: middle))
            steel.addLine(to: CGPoint(x: needle, y: middle))
            context.stroke(steel, with: .color(Theme.ink3), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            context.fill(Path(roundedRect: CGRect(x: needle, y: middle - 6, width: hub + 2, height: 12), cornerRadius: 3),
                         with: .color(Theme.line2))

            // Barrel, liquid and flange.
            context.fill(shape, with: .color(Theme.fill))
            if shown > 0 {
                var liquid = context
                liquid.clip(to: shape)
                liquid.fill(Path(CGRect(x: barrel.minX, y: barrel.minY, width: stop - barrel.minX, height: barrel.height)),
                            with: .color(Theme.accent.opacity(0.28)))
            }
            context.stroke(shape, with: .color(Theme.line2), lineWidth: 1.5)
            context.fill(Path(roundedRect: CGRect(x: barrel.maxX - 1, y: barrel.minY - 6, width: flange, height: barrel.height + 12), cornerRadius: 2),
                         with: .color(Theme.line2))

            // Marks: every unit (and half unit where the syringe has them), longer at 5 and 10.
            let step = halfUnits ? 0.5 : 1.0
            let count = Int((syringe.units / step).rounded())
            let labelEvery = syringe == .u100 ? 10 : 5
            for index in 0...count {
                let value = Double(index) * step
                let x = zero + CGFloat(value) * perUnit
                let whole = index % (halfUnits ? 2 : 1) == 0
                let number = Int(value.rounded())
                let labelled = whole && number % labelEvery == 0
                let five = whole && number % 5 == 0
                let length: CGFloat = labelled ? 15 : five ? 11 : whole ? 7 : 4
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: barrel.maxY - length))
                tick.addLine(to: CGPoint(x: x, y: barrel.maxY - 1))
                context.stroke(tick, with: .color(labelled ? Theme.ink2 : Theme.ink3), lineWidth: labelled ? 1.5 : 1)
                if labelled {
                    context.draw(Text("\(number)").font(Typo.body(10, .medium)).foregroundStyle(Theme.ink3),
                                 at: CGPoint(x: x, y: barrel.maxY + 11))
                }
            }

            // Stopper, and a label above it that stays inside the view.
            if shown > 0 {
                context.fill(Path(roundedRect: CGRect(x: stop - 2.5, y: barrel.minY + 2, width: 5, height: barrel.height - 4), cornerRadius: 2),
                             with: .color(Theme.accent))
                let label = context.resolve(Text(PeptideFormat.units(units)).font(Typo.body(12, .bold)).foregroundStyle(Theme.accentInk))
                let text = label.measure(in: CGSize(width: 160, height: 30))
                let bubble = CGSize(width: text.width + 16, height: 22)
                let x = min(max(stop, bubble.width / 2 + 1), size.width - bubble.width / 2 - 1)
                context.fill(Path(roundedRect: CGRect(x: x - bubble.width / 2, y: 2, width: bubble.width, height: bubble.height), cornerRadius: 11),
                             with: .color(Theme.accent))
                var pointer = Path()
                pointer.move(to: CGPoint(x: stop, y: 2 + bubble.height))
                pointer.addLine(to: CGPoint(x: stop, y: barrel.minY + 2))
                context.stroke(pointer, with: .color(Theme.accent), lineWidth: 1.5)
                context.draw(label, at: CGPoint(x: x, y: 2 + bubble.height / 2))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Syringe, \(syringe.rawValue) units")
        .accessibilityValue(units > 0 ? "Stopper at \(PeptideFormat.units(units))" : "Empty")
    }
}

/// A new profile: the form with its live result, saved with Add.
struct PeptideAddSheet: View {
    let store: PeptideStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PeptideProfile()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PeptideForm(profile: $draft)
                    PeptideResults(profile: draft)
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New peptide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        store.save(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
