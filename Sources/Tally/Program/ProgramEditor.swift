import SwiftUI
import TallyCore
import TallyKit

/// Changes a program after it's made: its name, starting training maxes, day names and accessories.
/// Weeks stay as they are, so logged days keep matching.
struct ProgramEditor: View {
    @Environment(ProgramStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var program: StrengthProgram
    /// The day an accessory is being added to.
    @State private var addingTo: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $program.name)
                        .font(Typo.display(26))
                }
                .cardRow()

                if !program.lifts.isEmpty {
                    Section {
                        ForEach(program.lifts.indices, id: \.self) { index in
                            HStack {
                                Text(program.lifts[index].exercise).font(Typo.body(15))
                                Spacer()
                                TextField("kg", value: $program.lifts[index].trainingMax, format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("kg").foregroundStyle(Theme.ink3)
                            }
                        }
                    } header: {
                        Text("Starting training maxes")
                    } footer: {
                        Text("Every main-lift weight is a percentage of these. Rep-out sets still raise them for later weeks.")
                    }
                    .cardRow()
                }

                ForEach(program.days.indices, id: \.self) { day in
                    Section {
                        TextField("Day name", text: $program.days[day].name)
                            .font(Typo.body(15, .semibold))
                        if !program.days[day].lifts.isEmpty {
                            Text("Main: " + program.days[day].lifts.joined(separator: ", "))
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                        }
                        ForEach(program.days[day].accessories.indices, id: \.self) { index in
                            AccessoryRow(accessory: $program.days[day].accessories[index])
                        }
                        .onDelete { program.days[day].accessories.remove(atOffsets: $0) }
                        .onMove { program.days[day].accessories.move(fromOffsets: $0, toOffset: $1) }
                        Button("Add accessory", systemImage: "plus") { addingTo = day }
                    } header: {
                        Text("Day \(day + 1)")
                    }
                    .cardRow()
                }
            }
            .screenBackground()
            .navigationTitle("Edit program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        if program.name.trimmingCharacters(in: .whitespaces).isEmpty { program.name = "Program" }
                        for index in program.lifts.indices where program.lifts[index].trainingMax < 0 {
                            program.lifts[index].trainingMax = 0
                        }
                        store.update(program)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
                ExercisePicker { exercises in
                    guard let day = addingTo else { return }
                    program.days[day].accessories += exercises.map { .init(exercise: $0.name, sets: 3, reps: 10) }
                }
            }
        }
    }
}

private struct AccessoryRow: View {
    @Binding var accessory: StrengthProgram.Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(accessory.exercise).font(Typo.body(15))
            HStack(spacing: 16) {
                Stepper("\(accessory.sets) sets", value: $accessory.sets, in: 1...10)
                Stepper("\(accessory.reps) reps", value: $accessory.reps, in: 1...50)
            }
            .font(Typo.body(13))
        }
    }
}
