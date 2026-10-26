import SwiftUI
import TallyCore
import TallyKit

/// Works out a calorie and macro goal from body, activity and goal, or takes one typed in.
struct FoodGoalsSheet: View {
    @Environment(FoodStore.self) private var store
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var profile: NutritionProfile
    @State private var age: Int?
    @State private var height: Double?
    @State private var weight: Double?
    @State private var usesCustom: Bool
    @State private var customKcal: Double? = nil
    @State private var waterGoal: Int
    @State private var countsExercise: Bool

    init() {
        // Filled from the store in onAppear; State needs a starting value.
        let profile = NutritionProfile()
        _profile = State(initialValue: profile)
        _age = State(initialValue: profile.age)
        _height = State(initialValue: profile.heightCm)
        _weight = State(initialValue: profile.weightKg)
        _usesCustom = State(initialValue: false)
        _waterGoal = State(initialValue: Water.defaultGoalGlasses)
        _countsExercise = State(initialValue: true)
    }

    private var draft: NutritionProfile {
        var draft = profile
        draft.age = min(max(age ?? profile.age, 14), 100)
        draft.heightCm = min(max(height ?? profile.heightCm, 120), 230)
        draft.weightKg = min(max(weight ?? profile.weightKg, 35), 250)
        return draft
    }

    private var goalKcal: Double {
        usesCustom ? (customKcal ?? draft.dailyKcal) : draft.dailyKcal
    }

    var body: some View {
        let goal = draft.macros.goal(kcal: goalKcal)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Daily goal").eyebrow(11)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("\(Int(goalKcal).formatted())")
                                .font(Typo.display(56))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("kcal").eyebrow(13)
                        }
                        HStack(spacing: 14) {
                            ForEach(Macro.allCases, id: \.self) { macro in
                                HStack(spacing: 5) {
                                    Circle().fill(macro.color).frame(width: 7, height: 7)
                                    Text("\(macro.label) \(Int(macro.value(goal))) g")
                                }
                            }
                        }
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.ink2)
                        if !usesCustom {
                            Text("Maintenance about \(Fmt.kcal(draft.maintenanceKcal.rounded())). Resting \(Fmt.kcal(draft.restingKcal.rounded())).")
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    .padding(.vertical, 6)
                    .animation(.snappy, value: goalKcal)
                }
                .cardRow()

                Section {
                    Picker("Goal", selection: $profile.goal) {
                        ForEach(NutritionProfile.Goal.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    if profile.goal != .maintain {
                        Picker("Per week", selection: $profile.weeklyRateKg) {
                            ForEach(NutritionProfile.weeklyRates, id: \.self) { Text("\($0.formatted()) kg").tag($0) }
                        }
                        .font(Typo.body(16))
                    }
                } header: {
                    Text("Goal").eyebrow(11)
                } footer: {
                    if profile.goal == .lose && profile.weeklyRateKg > 0.75 {
                        Text("Losing more than 0.75 kg a week makes it hard to keep muscle. Keep protein high.")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .cardRow()

                Section {
                    Picker("Sex", selection: $profile.sex) {
                        ForEach(NutritionProfile.Sex.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    LabeledNumberInt(label: "Age", unit: "yrs", value: $age)
                    LabeledNumber(label: "Height", unit: "cm", value: $height)
                    LabeledNumber(label: "Weight", unit: "kg", value: $weight)
                    if let latest = health.weights.last {
                        Button("Use \(Fmt.weight(latest.kg)) kg from Apple Health") { weight = (latest.kg * 10).rounded() / 10 }
                            .font(Typo.body(14, .semibold))
                    }
                } header: {
                    Text("You").eyebrow(11)
                }
                .cardRow()

                Section {
                    Picker("Activity", selection: $profile.activity) {
                        ForEach(NutritionProfile.Activity.allCases) { activity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.label).font(Typo.body(16))
                                Text(activity.detail).font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                            }
                            .tag(activity)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Activity").eyebrow(11)
                }
                .cardRow()

                Section {
                    ForEach(MacroSplit.presets, id: \.name) { preset in
                        Button {
                            profile.macros = preset.split
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).font(Typo.body(16)).foregroundStyle(Theme.ink)
                                    Text("Carbs \(preset.split.carbs)% · Protein \(preset.split.protein)% · Fat \(preset.split.fat)%")
                                        .font(Typo.body(12.5))
                                        .foregroundStyle(Theme.ink3)
                                }
                                Spacer()
                                if profile.macros == preset.split {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Macros").eyebrow(11)
                } footer: {
                    Text("For building muscle, aim for about 1.6–2.2 g of protein per kg of body weight: \(Int(draft.weightKg * 1.6))–\(Int(draft.weightKg * 2.2)) g for you.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                .cardRow()

                Section {
                    Toggle("Set calories myself", isOn: $usesCustom.animation(.snappy))
                        .font(Typo.body(16))
                    if usesCustom {
                        LabeledNumber(label: "Calories", unit: "kcal", value: $customKcal, placeholder: "\(Int(draft.dailyKcal))")
                    }
                    Toggle("Add exercise calories", isOn: $countsExercise)
                        .font(Typo.body(16))
                    Stepper("Water: \(waterGoal) glasses (\(Water.litres(glasses: waterGoal).formatted()) L)", value: $waterGoal, in: 1...20)
                        .font(Typo.body(16))
                } header: {
                    Text("More").eyebrow(11)
                } footer: {
                    Text(health.isConnected
                        ? "Exercise calories are your active energy from Apple Health, added to the day's budget."
                        : "Connect Apple Health in Settings to add exercise calories to the day's budget.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                .cardRow()
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Food goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        var profile = store.profile ?? NutritionProfile()
        if store.profile == nil, let latest = health.weights.last {
            profile.weightKg = (latest.kg * 10).rounded() / 10
        }
        self.profile = profile
        age = profile.age
        height = profile.heightCm
        weight = profile.weightKg
        usesCustom = store.customKcal != nil
        customKcal = store.customKcal
        waterGoal = store.waterGoal
        countsExercise = store.countsExercise
    }

    private func save() {
        store.profile = draft
        store.customKcal = usesCustom ? customKcal.flatMap { $0 >= 800 ? $0.rounded() : nil } : nil
        store.waterGoal = waterGoal
        store.countsExercise = countsExercise
        dismiss()
    }
}

/// Whole-number version of `LabeledNumber`.
private struct LabeledNumberInt: View {
    let label: String
    let unit: String
    @Binding var value: Int?

    var body: some View {
        HStack {
            Text(label).font(Typo.body(16))
            Spacer()
            NumberField(value: $value, placeholder: "0")
                .frame(width: 96)
            Text(unit)
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink3)
                .frame(width: 34, alignment: .leading)
        }
    }
}
