import SwiftUI
import TallyCore
import TallyKit

/// Estimated one-rep max from a set, and the weight to use at each percentage of it.
struct OneRepMaxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double?
    @State private var reps: Int?

    init(weight: Double? = nil, reps: Int? = nil) {
        _weight = State(initialValue: weight ?? 100)
        _reps = State(initialValue: reps ?? 5)
    }

    var body: some View {
        let oneRepMax = OneRepMax.estimate(weight: weight ?? 0, reps: reps ?? 0)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight").eyebrow(11.5)
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                NumberField(value: $weight, placeholder: "100", decimal: true)
                                Text("kg").eyebrow(13)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reps").eyebrow(11.5)
                            NumberField(value: $reps, placeholder: "5")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated 1RM").eyebrow(11)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(oneRepMax > 0 ? Fmt.weight(Plates.round(oneRepMax, to: 0.5)) : "–")
                                .font(Typo.display(64))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("kg").eyebrow(13)
                        }
                        if (reps ?? 0) > 12 {
                            Text("Estimates get less reliable above 12 reps.")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, cornerRadius: 20)
                    .animation(.snappy, value: oneRepMax)

                    if oneRepMax > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Percentages").eyebrow(11.5)
                            VStack(spacing: 0) {
                                ForEach(Array(OneRepMax.table(oneRepMax: oneRepMax).enumerated()), id: \.offset) { index, row in
                                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                    HStack {
                                        Text("\(row.percent)%")
                                            .font(Typo.body(15, .semibold))
                                            .frame(width: 56, alignment: .leading)
                                        Text("~\(row.reps) \(row.reps == 1 ? "rep" : "reps")")
                                            .font(Typo.body(13))
                                            .foregroundStyle(Theme.ink3)
                                        Spacer()
                                        Text("\(Fmt.weight(row.weight)) kg")
                                            .font(Typo.display(22))
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                }
                            }
                            .card(padding: 0, cornerRadius: 18)
                            Text("Epley formula, rounded to 2.5 kg.")
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("1RM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
