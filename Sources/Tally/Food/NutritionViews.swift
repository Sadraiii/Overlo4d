import Charts
import SwiftUI
import TallyCore
import TallyKit

extension FoodRating {
    var color: Color {
        switch self {
        case .great: Theme.good
        case .good: Theme.good.opacity(0.55)
        case .ok: Theme.hot
        case .limit: Theme.danger
        }
    }
}

/// A coloured dot for the food's rating, with the verdict when `showsLabel`.
struct FoodRatingBadge: View {
    let rating: FoodRating
    var showsLabel = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(rating.color).frame(width: 8, height: 8)
            if showsLabel {
                Text(rating.label)
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating.label)
    }
}

/// Sugar, fibre, saturated fat and salt for an amount of food, in a compact two-column grid.
struct NutrientDetails: View {
    let nutrients: Nutrients

    var body: some View {
        let optional: [(String, Double?)] = [
            ("of which sugar", nutrients.sugar),
            ("Fibre", nutrients.fiber),
            ("Saturated fat", nutrients.saturatedFat),
            ("Salt", nutrients.salt),
        ]
        let items = optional.compactMap { item in item.1.map { (item.0, $0) } }
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0)
                        Spacer()
                        Text(Fmt.grams(item.1)).monospacedDigit()
                    }
                    .padding(.trailing, 8)
                }
            }
            .font(Typo.body(12.5))
            .foregroundStyle(Theme.ink3)
        }
    }
}

/// The day's or week's nutrition: where the calories came from, macros against the goal, and fibre, sugar,
/// saturated fat and salt against everyday guidelines.
struct NutritionView: View {
    enum Span: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var label: String { self == .day ? "Day" : "7 days" }
        var days: Int { self == .day ? 1 : 7 }
    }

    @Environment(FoodStore.self) private var food
    let day: DayKey
    @State private var span: Span = .day

    var body: some View {
        let report = food.diary.report(days: span.days, endingOn: day)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $span) {
                    ForEach(Span.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if report.days == 0 {
                    ContentUnavailableView(
                        "Nothing logged",
                        systemImage: "fork.knife",
                        description: Text(span == .day ? "Log food on this day to see its nutrition." : "Log food this week to see your averages.")
                    )
                    .padding(.top, 40)
                } else {
                    MacroSplitCard(report: report, target: food.diary.profile?.macros ?? .balanced, isAverage: span == .week)
                    NutrientRowsCard(report: report, isAverage: span == .week)
                    if span == .day {
                        TopFoodsCard(entries: food.diary.entries(on: day))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.snappy, value: span)
        }
        .screenBackground()
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MacroSplitCard: View {
    let report: NutritionReport
    let target: MacroSplit
    let isAverage: Bool

    private struct Slice: Identifiable {
        let macro: Macro
        let share: Int
        let goal: Int
        var id: String { macro.label }
    }

    var body: some View {
        let shares = report.macroShares
        let slices = [
            Slice(macro: .carbs, share: shares.carbs, goal: target.carbs),
            Slice(macro: .protein, share: shares.protein, goal: target.protein),
            Slice(macro: .fat, share: shares.fat, goal: target.fat),
        ]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isAverage ? "Daily average" : "Calories").eyebrow()
                Spacer()
                Text(Fmt.kcal(report.average.kcal))
                    .font(Typo.body(13, .semibold))
                    .foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 18) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Share", max(slice.share, 0)), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(slice.macro.color)
                        .cornerRadius(3)
                }
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle().fill(slice.macro.color).frame(width: 8, height: 8)
                            Text(slice.macro.label).font(Typo.body(14, .medium))
                            Spacer()
                            Text("\(slice.share)%")
                                .font(Typo.display(20))
                                .monospacedDigit()
                            Text("of \(slice.goal)%")
                                .font(Typo.body(12))
                                .foregroundStyle(Theme.ink3)
                                .frame(width: 44, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .card(padding: 16)
    }
}

private struct NutrientRowsCard: View {
    let report: NutritionReport
    let isAverage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isAverage ? "Nutrients, per day" : "Nutrients").eyebrow()
            ForEach(report.rows) { row in
                NutrientRowView(row: row)
            }
            Text("Fibre, sugar, saturated fat and salt follow the EU daily reference intakes, scaled to your calorie goal.")
                .font(Typo.body(12))
                .foregroundStyle(Theme.ink3)
        }
        .card(padding: 16)
    }
}

private struct NutrientRowView: View {
    let row: NutritionReport.Row

    private var color: Color {
        switch row.status {
        case .onTrack: Theme.good
        case .close: Theme.hot
        case .off: row.kind == .atLeast ? Theme.hot : Theme.danger
        }
    }

    private var targetText: String {
        switch row.kind {
        case .goal: "of \(Fmt.grams(row.target))"
        case .atLeast: "aim for \(Fmt.grams(row.target))+"
        case .atMost: "under \(Fmt.grams(row.target))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(Typo.body(14.5, .medium))
                Spacer()
                Text(Fmt.grams(row.amount))
                    .font(Typo.body(14.5, .semibold))
                    .monospacedDigit()
                Text(targetText)
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(row.fraction, 1))
                }
            }
            .frame(height: 6)
            if row.coverage < 0.8 {
                Text("Only \(Int((row.coverage * 100).rounded()))% of what you ate lists \(row.label.lowercased()), so this is likely low.")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The foods that gave the most calories today, with their rating.
private struct TopFoodsCard: View {
    let entries: [FoodEntry]

    var body: some View {
        let top = entries.sorted { $0.nutrients.kcal > $1.nutrients.kcal }.prefix(5)
        let total = entries.reduce(0) { $0 + $1.nutrients.kcal }
        VStack(alignment: .leading, spacing: 12) {
            Text("Most calories from").eyebrow()
            ForEach(Array(top)) { entry in
                HStack(spacing: 10) {
                    if let rating = FoodRating(entry.food) {
                        FoodRatingBadge(rating: rating)
                    }
                    Text(entry.food.name)
                        .font(Typo.body(14.5))
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.kcal(entry.nutrients.kcal))
                        .font(Typo.body(13.5, .semibold))
                        .monospacedDigit()
                    if total > 0 {
                        Text("\(Int((entry.nutrients.kcal / total * 100).rounded()))%")
                            .font(Typo.body(12))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .card(padding: 16)
    }
}

/// "This week: 2,450 kcal under maintenance ≈ −0.3 kg", under the week's calorie chart.
struct CalorieBalanceLine: View {
    let balance: CalorieBalance
    let profile: NutritionProfile?

    var body: some View {
        if balance.loggedDays > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goalText)
                        .font(Typo.body(13.5, .semibold))
                        .foregroundStyle(balance.versusGoal > 0 ? Theme.hot : Theme.good)
                    Spacer()
                    Text("\(balance.loggedDays) finished day\(balance.loggedDays == 1 ? "" : "s")")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                }
                if let kg = balance.estimatedKg, let off = balance.versusMaintenance {
                    Text("\(Fmt.kcal(abs(off))) \(off < 0 ? "under" : "over") maintenance, about \(kgText(kg)) of body weight\(planText)")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    private var goalText: String {
        let off = balance.versusGoal
        if abs(off) < 50 * Double(balance.loggedDays) { return "Right on your goal" }
        return "\(Fmt.kcal(abs(off))) \(off < 0 ? "under" : "over") your goal"
    }

    private func kgText(_ kg: Double) -> String {
        "\(kg < 0 ? "−" : "+")\(abs(kg).formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var planText: String {
        guard let profile, profile.goal != .maintain else { return "." }
        let verb = profile.goal == .lose ? "lose" : "gain"
        return ". Your plan is to \(verb) \(profile.weeklyRateKg.formatted()) kg a week."
    }
}
