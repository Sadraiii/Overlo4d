import TallyKit
import SwiftUI
import WidgetKit

struct FoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.food, provider: FoodProvider()) { entry in
            FoodWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
                .widgetURL(URL(string: "tally://food"))
        }
        .configurationDisplayName("Food")
        .description("Calories left today, your macros, water and your fast.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct FoodWidgetEntry: TimelineEntry {
    let date: Date
    let food: FoodSnapshot
}

struct FoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodWidgetEntry {
        FoodWidgetEntry(date: .now, food: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodWidgetEntry) -> Void) {
        let food = FoodSnapshot.load()
        let shown = context.isPreview && food == nil ? .placeholder : (food ?? FoodSnapshot(day: "", goalKcal: 2000))
        completion(FoodWidgetEntry(date: .now, food: shown.on(.now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodWidgetEntry>) -> Void) {
        let food = FoodSnapshot.load() ?? FoodSnapshot(day: "", goalKcal: 2000)
        let midnight = MidnightTimeline.nextMidnight
        var dates = [Date.now]
        // While fasting, move the fast ring along every 15 minutes for the next 4 hours.
        if food.fastStart != nil {
            dates += (1...16).map { Date.now.addingTimeInterval(Double($0) * 900) }.filter { $0 < midnight }
        }
        dates.append(midnight)
        // Ask again after the last fast step, or at midnight when there's no fast.
        let reload = food.fastStart != nil && dates.count > 2 ? dates[dates.count - 2] : midnight
        completion(Timeline(entries: dates.map { FoodWidgetEntry(date: $0, food: food.on($0)) }, policy: .after(reload)))
    }
}

struct FoodWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var hasBackground
    let entry: FoodWidgetEntry

    private var food: FoodSnapshot { entry.food }
    private var over: Bool { food.remaining < 0 }
    private var left: Int { Int(abs(food.remaining).rounded()) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Label(over ? "\(left) kcal over" : "\(left) kcal left", systemImage: "fork.knife")
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home screen

    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            WidgetRing(progress: food.progress, lineWidth: lineWidth)
            VStack(spacing: -3) {
                Text(left.formatted())
                    .font(Typo.display(size * 0.3))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(over ? Theme.danger : Theme.ink)
                Text(over ? "kcal over" : "kcal left")
                    .font(Typo.body(max(9.5, size * 0.09), .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, lineWidth + 4)
        }
        .frame(width: size, height: size)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Food", symbol: "fork.knife")
            ring(size: hasBackground ? 96 : 112, lineWidth: 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(fastText ?? "\(Int(food.eatenKcal.rounded()).formatted()) of \(Int(food.goalKcal + food.exerciseKcal).formatted()) kcal")
                .font(Typo.body(11.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ring(size: 118, lineWidth: 10)
            VStack(alignment: .leading, spacing: 7) {
                WidgetHeader(title: "Food today", symbol: "fork.knife")
                macro("Carbs", food.carbs, food.goalCarbs, Theme.accent)
                macro("Protein", food.protein, food.goalProtein, Theme.good)
                macro("Fat", food.fat, food.goalFat, Theme.hot)
                extras
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "Food today", symbol: "fork.knife", note: entry.date.formatted(.dateTime.weekday(.wide)))
            HStack(spacing: 18) {
                ring(size: 132, lineWidth: 12)
                VStack(alignment: .leading, spacing: 10) {
                    budgetRow("Goal", food.goalKcal, symbol: "target")
                    budgetRow("Eaten", food.eatenKcal, symbol: "fork.knife")
                    budgetRow("Exercise", food.exerciseKcal, symbol: "flame.fill")
                }
            }
            VStack(spacing: 10) {
                macro("Carbs", food.carbs, food.goalCarbs, Theme.accent)
                macro("Protein", food.protein, food.goalProtein, Theme.good)
                macro("Fat", food.fat, food.goalFat, Theme.hot)
            }
            .padding(12)
            .background(WidgetColors(mode: mode).well, in: .rect(cornerRadius: 16))
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                WaterGlasses(count: food.water, goal: food.waterGoal)
                Spacer(minLength: 8)
                if let fastText {
                    Chip(text: fastText, symbol: "timer", color: Theme.accent)
                }
            }
        }
    }

    private func budgetRow(_ name: String, _ kcal: Double, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .frame(width: 16)
            Text(name)
                .font(Typo.body(13, .medium))
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 4)
            Text(Int(kcal.rounded()).formatted())
                .font(Typo.display(22))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    private var extras: some View {
        HStack(spacing: 10) {
            Label("\(food.water)/\(food.waterGoal)", systemImage: "drop.fill")
            if let fastText { Label(fastText, systemImage: "timer") }
        }
        .font(Typo.body(11.5, .semibold))
        .foregroundStyle(Theme.ink2)
        .lineLimit(1)
    }

    private func macro(_ name: String, _ eaten: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(Typo.body(11.5, .semibold)).foregroundStyle(Theme.ink2)
                Spacer()
                Text("\(Int(eaten.rounded())) / \(Int(goal)) g")
                    .font(Typo.body(11.5, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }
            Meter(progress: goal > 0 ? eaten / goal : 0, color: color, height: 5)
        }
    }

    /// "Fasting 9h 20m" or "Fast done" while a fast runs.
    private var fastText: String? {
        guard let start = food.fastStart else { return nil }
        let minutes = max(Int(entry.date.timeIntervalSince(start) / 60), 0)
        if minutes >= food.fastHours * 60 { return "Fast done" }
        return "Fasting \(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: min(max(food.progress, 0), 1)) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text("\(left)").font(Typo.display(18)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(left.formatted()).font(Typo.display(24)).monospacedDigit()
                Text(over ? "kcal over" : "kcal left").font(Typo.body(13, .semibold))
            }
            .widgetAccentable()
            Gauge(value: min(max(food.progress, 0), 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(fastText ?? "Protein \(Int(food.protein.rounded())) / \(Int(food.goalProtein)) g")
                .font(Typo.body(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Water for the day as drops, filled up to the glasses drunk.
struct WaterGlasses: View {
    let count: Int
    let goal: Int

    var body: some View {
        let shown = min(max(goal, 1), 10)
        HStack(spacing: 3) {
            ForEach(0..<shown, id: \.self) { index in
                Image(systemName: index < count ? "drop.fill" : "drop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(index < count ? Theme.accent : Theme.ink3)
                    .widgetAccentable(index < count)
            }
            Text("\(count)/\(goal)")
                .font(Typo.body(11.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .padding(.leading, 3)
        }
    }
}
