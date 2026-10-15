import PlusUltraKit
import SwiftUI
import WidgetKit

struct RepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.reps, provider: RepsProvider()) { entry in
            RepsWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
                .widgetURL(URL(string: "plusultra://reps"))
        }
        .configurationDisplayName("Reps")
        .description("Today's reps and your daily goal.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct RepsEntry: TimelineEntry {
    struct Row: Identifiable {
        let id: UUID
        let name: String
        let reps: Int
    }

    let date: Date
    let total: Int
    let goal: Int
    /// Exercises with the most reps today first.
    let rows: [Row]

    var progress: Double { goal > 0 ? Double(total) / Double(goal) : 0 }

    init(date: Date, data: RepData) {
        self.date = date
        total = data.repsToday(on: date)
        goal = data.dailyGoal
        rows = data.exercises
            .map { Row(id: $0.id, name: $0.name, reps: data.reps(for: $0.id, on: date)) }
            .enumerated()
            .sorted { $0.element.reps != $1.element.reps ? $0.element.reps > $1.element.reps : $0.offset < $1.offset }
            .map(\.element)
    }
}

struct RepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RepsEntry {
        RepsEntry(date: .now, data: RepData())
    }

    func getSnapshot(in context: Context, completion: @escaping (RepsEntry) -> Void) {
        completion(RepsEntry(date: .now, data: RepStorage.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RepsEntry>) -> Void) {
        let data = RepStorage.load()
        let midnight = MidnightTimeline.nextMidnight
        // Second entry at midnight resets the counts for the new day.
        completion(Timeline(
            entries: [RepsEntry(date: .now, data: data), RepsEntry(date: midnight, data: data)],
            policy: .after(midnight)
        ))
    }
}

struct RepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RepsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Label("\(entry.total)/\(entry.goal) reps today", systemImage: "flame.fill")
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home screen

    private func total(size: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(entry.total)")
                .font(Typo.display(size))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("/ \(entry.goal)")
                .font(Typo.display(size * 0.42))
                .foregroundStyle(Theme.ink3)
        }
    }

    private var tally: some View {
        Tally(marks: Int(min(entry.progress, 1) * 20), groups: 4, done: entry.progress >= 1, height: 16)
            .widgetAccentable()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetLabel(text: "Reps today")
            Spacer(minLength: 0)
            total(size: 54)
            tally.padding(.top, 4)
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetLabel(text: "Reps today")
                Spacer(minLength: 0)
                total(size: 54)
                tally.padding(.top, 4)
            }
            .frame(width: 140)
            VStack(spacing: 0) {
                ForEach(Array(entry.rows.prefix(4).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    exerciseRow(row).frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var large: some View {
        let most = max(entry.rows.map(\.reps).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            WidgetLabel(text: "Reps today")
            total(size: 64)
            tally
            VStack(spacing: 9) {
                ForEach(entry.rows.prefix(7)) { row in
                    VStack(spacing: 4) {
                        exerciseRow(row)
                        GeometryReader { proxy in
                            Capsule().fill(Theme.line)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Theme.accent)
                                        .frame(width: proxy.size.width * Double(row.reps) / Double(most))
                                        .widgetAccentable()
                                }
                        }
                        .frame(height: 5)
                    }
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private func exerciseRow(_ row: RepsEntry.Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.name)
                .font(Typo.body(13, .medium))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(row.reps)")
                .font(Typo.display(20))
                .monospacedDigit()
                .foregroundStyle(row.reps > 0 ? Theme.ink : Theme.ink3)
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: min(entry.progress, 1)) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(entry.total)")
                .font(Typo.display(20))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(entry.total)").font(Typo.display(24))
                Text("/ \(entry.goal) reps").font(Typo.body(13, .semibold))
            }
            .widgetAccentable()
            Gauge(value: min(entry.progress, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            if let top = entry.rows.first, top.reps > 0 {
                Text("\(top.name) \(top.reps)")
                    .font(Typo.body(12))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
