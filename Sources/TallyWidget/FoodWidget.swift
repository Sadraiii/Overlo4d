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
        .description("Calories left today, your macros and your fast.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
        completion(FoodWidgetEntry(date: .now, food: FoodSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodWidgetEntry>) -> Void) {
        let food = FoodSnapshot.load() ?? FoodSnapshot(day: "", goalKcal: 2000)
        let midnight = MidnightTimeline.nextMidnight
        var dates = [Date.now]
        // While fasting, move the fast ring along every 15 minutes.
        if food.fastStart != nil {
            dates += (1...16).map { Date.now.addingTimeInterval(Double($0) * 900) }.filter { $0 < midnight }
        }
        dates.append(midnight)
        completion(Timeline(entries: dates.map { FoodWidgetEntry(date: $0, food: food.on($0)) }, policy: .after(dates[dates.count - 2])))
    }
}

struct FoodWidgetView: View {
    @Environment(\.widgetFamily) private var family
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
        default: small
        }
    }

    private var ring: some View {
        ZStack {
            GoalRing(progress: food.progress, lineWidth: 9)
            VStack(spacing: -2) {
                Text("\(left)")
                    .font(Typo.display(30))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(over ? Theme.danger : Theme.ink)
                Text(over ? "over" : "left")
                    .font(Typo.body(10, .semibold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .widgetAccentable()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(text: "Food today")
            ring.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let fast = fastText {
                Text(fast).font(Typo.body(11, .semibold)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(text: "Food today")
                ring.frame(width: 104, height: 104)
            }
            VStack(alignment: .leading, spacing: 8) {
                macro("Carbs", food.carbs, food.goalCarbs, Theme.accent)
                macro("Protein", food.protein, food.goalProtein, Theme.good)
                macro("Fat", food.fat, food.goalFat, Theme.hot)
                HStack(spacing: 10) {
                    Label("\(food.water)/\(food.waterGoal)", systemImage: "drop.fill")
                    if let fast = fastText { Label(fast, systemImage: "timer") }
                }
                .font(Typo.body(11.5, .semibold))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            }
        }
    }

    private func macro(_ name: String, _ eaten: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(Typo.body(11.5, .semibold)).foregroundStyle(Theme.ink3)
                Spacer()
                Text("\(Int(eaten.rounded()))/\(Int(goal)) g").font(Typo.body(11.5, .semibold)).monospacedDigit().foregroundStyle(Theme.ink2)
            }
            GeometryReader { proxy in
                Capsule().fill(Theme.line).overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * min(goal > 0 ? eaten / goal : 0, 1))
                        .widgetAccentable()
                }
            }
            .frame(height: 4)
        }
    }

    /// "Fasting 9h 20m" or "Fast done" while a fast runs.
    private var fastText: String? {
        guard let start = food.fastStart else { return nil }
        let minutes = Int(entry.date.timeIntervalSince(start) / 60)
        if minutes >= food.fastHours * 60 { return "Fast done" }
        return "Fasting \(minutes / 60)h \(minutes % 60)m"
    }

    private var circular: some View {
        Gauge(value: min(food.progress, 1)) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text("\(left)").font(Typo.display(18)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(left)").font(Typo.display(24))
                Text(over ? "kcal over" : "kcal left").font(Typo.body(13, .semibold))
            }
            .widgetAccentable()
            Gauge(value: min(food.progress, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(fastText ?? "P \(Int(food.protein.rounded()))/\(Int(food.goalProtein)) g")
                .font(Typo.body(12))
                .lineLimit(1)
        }
    }
}
