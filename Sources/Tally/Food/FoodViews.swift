import Charts
import SwiftUI
import TallyCore
import TallyKit

enum Macro: CaseIterable {
    case carbs, protein, fat

    var label: String {
        switch self {
        case .carbs: "Carbs"
        case .protein: "Protein"
        case .fat: "Fat"
        }
    }

    var color: Color {
        switch self {
        case .carbs: Theme.accent
        case .protein: Theme.good
        case .fat: Theme.hot
        }
    }

    func value(_ nutrients: Nutrients) -> Double {
        switch self {
        case .carbs: nutrients.carbs
        case .protein: nutrients.protein
        case .fat: nutrients.fat
        }
    }
}

extension Fmt {
    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted()) kcal"
    }

    static func grams(_ value: Double) -> String {
        value < 10 ? "\(value.formatted(.number.precision(.fractionLength(0...1)))) g" : "\(Int(value.rounded()).formatted()) g"
    }

    /// "Today", "Yesterday" or "Mon 20 Oct".
    static func day(_ day: DayKey) -> String {
        let today = DayKey(.now)
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        if day == today.adding(days: 1) { return "Tomorrow" }
        return day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Calories left today, with a ring and macros. Opens the food diary.
struct FoodCard: View {
    @Environment(FoodStore.self) private var food
    @Environment(HealthManager.self) private var health
    let onOpen: () -> Void

    var body: some View {
        let summary = food.summary(food.today)
        Button(action: onOpen) {
            HStack(spacing: 16) {
                ZStack {
                    GoalRing(progress: summary.progress, lineWidth: 8)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Food today").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Int(abs(summary.remaining).rounded()))")
                            .font(Typo.display(36))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(summary.remaining < 0 ? Theme.danger : Theme.ink)
                        Text(summary.remaining < 0 ? "kcal over" : "kcal left")
                            .font(Typo.display(19))
                            .foregroundStyle(Theme.ink3)
                    }
                    HStack(spacing: 10) {
                        ForEach(Macro.allCases, id: \.self) { macro in
                            HStack(spacing: 4) {
                                Circle().fill(macro.color).frame(width: 6, height: 6)
                                Text("\(Int(macro.value(summary.eaten).rounded()))/\(Int(macro.value(summary.goal)))g")
                                    .monospacedDigit()
                            }
                        }
                    }
                    .font(Typo.body(12, .medium))
                    .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onChange(of: health.today.activeEnergy, initial: true) { _, kcal in
            food.recordExercise(kcal, on: food.today)
        }
    }
}

/// The day's food by meal, like Lifesum's diary.
struct FoodDiaryView: View {
    enum SheetKind: Identifiable {
        case add(Meal)
        case edit(FoodEntry)
        case goals

        var id: String {
            switch self {
            case .add(let meal): "add-\(meal.rawValue)"
            case .edit(let entry): "edit-\(entry.id)"
            case .goals: "goals"
            }
        }
    }

    @Environment(FoodStore.self) private var food
    @Environment(HealthManager.self) private var health
    @State private var day = DayKey(.now)
    @State private var sheet: SheetKind?

    var body: some View {
        let summary = food.summary(day)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DayPicker(day: $day)

                if !food.hasGoal {
                    GoalPrompt { sheet = .goals }
                }

                FoodSummaryCard(summary: summary, showsExercise: food.countsExercise && health.isConnected)

                WaterCard(day: day)

                ForEach(Meal.allCases) { meal in
                    MealSection(
                        meal: meal,
                        day: day,
                        total: summary.byMeal[meal] ?? .zero,
                        onAdd: { sheet = .add(meal) },
                        onEdit: { sheet = .edit($0) }
                    )
                }

                CalorieWeekCard(endingOn: day)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.snappy, value: day)
        }
        .screenBackground()
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Goals", systemImage: "target") { sheet = .goals }
            }
        }
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .add(let meal): AddFoodSheet(meal: meal, day: day)
                case .edit(let entry): EntryEditSheet(entry: entry)
                case .goals: FoodGoalsSheet()
                }
            }
            .environment(food)
            .environment(health)
        }
        .task {
            await health.refresh()
            food.recordExercise(health.today.activeEnergy, on: food.today)
        }
    }
}

/// "‹ Today ›" with a jump back to today.
private struct DayPicker: View {
    @Binding var day: DayKey

    var body: some View {
        HStack {
            Button("Previous day", systemImage: "chevron.left") { day = day.adding(days: -1) }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            Spacer()
            Button {
                day = DayKey(.now)
            } label: {
                Text(Fmt.day(day)).display(26)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Next day", systemImage: "chevron.right") { day = day.adding(days: 1) }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(day >= DayKey(.now))
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .sensoryFeedback(.selection, trigger: day)
    }
}

private struct GoalPrompt: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set your calorie goal").font(Typo.body(15, .semibold))
                    Text("Using 2,000 kcal until you do")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 12, cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Eaten · remaining ring · burned, then macro bars.
struct FoodSummaryCard: View {
    let summary: DaySummary
    let showsExercise: Bool

    var body: some View {
        let over = summary.remaining < 0
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                SideStat(value: summary.eaten.kcal, label: "Eaten")
                Spacer()
                ZStack {
                    GoalRing(progress: summary.progress, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text("\(Int(abs(summary.remaining).rounded()))")
                            .font(Typo.display(44))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(over ? Theme.danger : Theme.ink)
                        Text(over ? "kcal over" : "kcal left").eyebrow(11)
                    }
                }
                .frame(width: 150, height: 150)
                Spacer()
                SideStat(value: showsExercise ? summary.exercise : 0, label: "Burned", dimmed: !showsExercise)
            }

            HStack(spacing: 14) {
                ForEach(Macro.allCases, id: \.self) { macro in
                    MacroBar(macro: macro, eaten: macro.value(summary.eaten), goal: macro.value(summary.goal))
                }
            }

            Text("Goal \(Fmt.kcal(summary.goal.kcal))\(summary.exercise > 0 ? " + \(Fmt.kcal(summary.exercise)) exercise" : "")")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
        }
        .card(padding: 16, cornerRadius: 22)
        .animation(.snappy, value: summary)
    }

    private struct SideStat: View {
        let value: Double
        let label: String
        var dimmed = false

        var body: some View {
            VStack(spacing: 2) {
                Text(dimmed ? "–" : "\(Int(value.rounded()))")
                    .font(Typo.display(26))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).eyebrow(10.5)
            }
            .frame(width: 70)
        }
    }
}

struct MacroBar: View {
    let macro: Macro
    let eaten: Double
    let goal: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(macro.label).eyebrow(10.5)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(eaten > goal * 1.1 ? Theme.danger : macro.color)
                        .frame(width: proxy.size.width * min(goal > 0 ? eaten / goal : 0, 1))
                }
            }
            .frame(height: 6)
            Text("\(Int(eaten.rounded())) / \(Int(goal)) g")
                .font(Typo.body(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Glasses of water; tap a glass to fill up to it, tap the last full one to empty it.
struct WaterCard: View {
    @Environment(FoodStore.self) private var food
    let day: DayKey

    var body: some View {
        let glasses = food.water(day)
        let goal = food.waterGoal
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Water").eyebrow()
                Spacer()
                Text("\(Water.litres(glasses: glasses).formatted(.number.precision(.fractionLength(0...2)))) / \(Water.litres(glasses: goal).formatted()) L")
                    .font(Typo.body(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(glasses >= goal ? Theme.good : Theme.ink2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(max(goal, glasses + 1), 10)), spacing: 8) {
                ForEach(0..<max(goal, glasses + 1), id: \.self) { index in
                    let filled = index < glasses
                    Button {
                        food.setWater(index + 1 == glasses ? index : index + 1, on: day)
                    } label: {
                        Image(systemName: filled ? "drop.fill" : (index == glasses ? "plus" : "drop"))
                            .font(.system(size: filled ? 20 : 17, weight: .semibold))
                            .foregroundStyle(filled ? Color.blue : Theme.ink3)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(filled ? Color.blue.opacity(0.12) : Theme.paper, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filled ? "Glass \(index + 1), full" : "Add glass \(index + 1)")
                }
            }
            .sensoryFeedback(.increase, trigger: glasses)
        }
        .card(padding: 14)
    }
}

/// A meal's foods with its calories and an add button.
struct MealSection: View {
    @Environment(FoodStore.self) private var food
    let meal: Meal
    let day: DayKey
    let total: Nutrients
    let onAdd: () -> Void
    let onEdit: (FoodEntry) -> Void

    var body: some View {
        let entries = food.entries(day, meal: meal)
        let yesterday = food.entries(day.adding(days: -1), meal: meal)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.label).display(23)
                    if !entries.isEmpty {
                        Text("C \(Int(total.carbs.rounded())) · P \(Int(total.protein.rounded())) · F \(Int(total.fat.rounded())) g")
                            .font(Typo.body(12))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                Spacer()
                Text(entries.isEmpty ? "" : Fmt.kcal(total.kcal))
                    .font(Typo.body(14, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                Menu {
                    Button("Add food", systemImage: "plus", action: onAdd)
                    if !yesterday.isEmpty {
                        Button("Copy from \(Fmt.day(day.adding(days: -1)).lowercased())", systemImage: "doc.on.doc") {
                            _ = food.copy(meal: meal, from: day.adding(days: -1), to: day)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: .circle)
                } primaryAction: {
                    onAdd()
                }
                .padding(.leading, 6)
                .accessibilityLabel("Add to \(meal.label)")
            }
            .padding(.bottom, entries.isEmpty ? 0 : 10)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                Button { onEdit(entry) } label: {
                    EntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { onEdit(entry) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { food.remove(entry.id) }
                    }
                }
            }
        }
        .card(padding: 14, cornerRadius: 18)
    }
}

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.food.name)
                    .font(Typo.body(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(Self.amount(entry))
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(Int(entry.nutrients.kcal.rounded()))")
                .font(Typo.display(20))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    static func amount(_ entry: FoodEntry) -> String {
        if entry.food.source == .quick { return "Quick add" }
        var parts: [String] = []
        if let brand = entry.food.brand { parts.append(brand) }
        if let servings = entry.servings, servings.truncatingRemainder(dividingBy: 0.25) == 0 {
            parts.append("\(servings.formatted()) × \(entry.food.servingLabel ?? "serving")")
        } else {
            parts.append(Fmt.grams(entry.grams))
        }
        return parts.joined(separator: " · ")
    }
}

/// Calories per day for the week ending on the shown day, against the goal.
struct CalorieWeekCard: View {
    @Environment(FoodStore.self) private var food
    let endingOn: DayKey

    var body: some View {
        let days = food.diary.calories(last: 7, endingOn: endingOn)
        let goal = food.goal.kcal
        let logged = days.filter { $0.kcal > 0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 7 days").eyebrow()
                Spacer()
                if !logged.isEmpty {
                    Text("avg \(Fmt.kcal(logged.reduce(0) { $0 + $1.kcal } / Double(logged.count)))")
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Chart {
                ForEach(days, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day.date(), unit: .day),
                        y: .value("kcal", item.kcal)
                    )
                    .foregroundStyle(item.kcal > goal * 1.05 ? Theme.hot : Theme.accent)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.ink3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 140)

            let streak = food.diary.streak(today: food.today)
            if streak > 1 {
                Label("\(streak) days logged in a row", systemImage: "flame.fill")
                    .font(Typo.body(13, .semibold))
                    .foregroundStyle(Theme.hot)
            }
        }
        .card(padding: 14)
    }
}
