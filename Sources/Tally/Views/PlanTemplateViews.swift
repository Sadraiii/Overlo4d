import SwiftUI
import TallyCore
import TallyKit

/// Ready-made routines. Adding one creates a plan per training day, which can then be edited freely.
struct PlanTemplateGallery: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    /// Templates added while the sheet is open, with how many plans each gave.
    @State private var added: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Each routine adds one plan per training day. Weights start from what you last lifted, and you can change anything afterwards.")
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 2)
                    ForEach(PlanTemplates.all) { template in
                        PlanTemplateCard(template: template, addedCount: added[template.id]) {
                            added[template.id] = gym.addPlans(from: template)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: added)
    }
}

struct PlanTemplateCard: View {
    let template: PlanTemplate
    let addedCount: Int?
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(template.name).display(27)
                Text("\(template.level) · \(template.daysPerWeek) days a week · \(template.equipment)")
                    .font(Typo.body(13, .semibold))
                    .foregroundStyle(Theme.accent)
                Text(template.summary)
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Theme.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(template.days, id: \.name) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name)
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(day.items.map(\.exercise).joined(separator: " · "))
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let addedCount {
                Label(addedCount == 1 ? "1 plan added" : "\(addedCount) plans added", systemImage: "checkmark")
                    .font(Typo.body(15, .semibold))
                    .foregroundStyle(Theme.good)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.goodSoft, in: .capsule)
            } else {
                Button(template.days.count == 1 ? "Add 1 plan" : "Add \(template.days.count) plans", systemImage: "plus", action: onAdd)
                    .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 44, fullWidth: true))
            }
        }
        .padding(16)
        .card(padding: 0, cornerRadius: 20)
    }
}
