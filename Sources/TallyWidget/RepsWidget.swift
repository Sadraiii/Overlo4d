import TallyKit
import SwiftUI
import WidgetKit

struct RepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.reps, provider: RepsProvider()) { entry in
            RepsWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
                .widgetURL(URL(string: "tally://reps"))
        }
        .configurationDisplayName("Reps")
        .description("Today's reps toward your daily goal, by exercise.")
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
        RepsEntry(date: .now, data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RepsEntry) -> Void) {
        let data = RepStorage.load()
        // The widget gallery shows sample reps until something is logged.
        let shown = context.isPreview && data.repsToday() == 0 ? .preview : data
        completion(RepsEntry(date: .now, data: shown))
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

extension RepData {
    /// Sample day for the widget gallery.
    static var preview: RepData {
        let exercises = RepData.defaultExercises
        let reps = [40, 18, 0, 15, 0, 0]
        let entries = zip(exercises, reps).filter { $0.1 > 0 }.map { RepEntry(exerciseID: $0.0.id, reps: $0.1) }
        return RepData(exercises: exercises, entries: entries, dailyGoal: 100)
    }
}

struct RepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var hasBackground
    let entry: RepsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Label("\(entry.total)/\(entry.goal) reps today", systemImage: "figure.strengthtraining.functional")
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home screen

    private var done: Bool { entry.progress >= 1 }

    private var goalNote: String {
        done ? "Goal hit" : "\(max(entry.goal - entry.total, 0)) to go"
    }

    private func total(size: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(entry.total)")
                .font(Typo.display(size))
                .monospacedDigit()
                .foregroundStyle(done ? Theme.good : Theme.ink)
                .minimumScaleFactor(0.5)
            Text("/ \(entry.goal)")
                .font(Typo.display(size * 0.42))
                .monospacedDigit()
                .foregroundStyle(Theme.ink3)
        }
        .lineLimit(1)
    }

    /// Tally marks in full colour; a plain bar when the system tints the widget, where marks blur together.
    @ViewBuilder
    private func progress(height: CGFloat) -> some View {
        if WidgetColors(mode: mode).isFullColor {
            Tally(marks: Int(min(entry.progress, 1) * 20), groups: 4, done: done, height: height)
        } else {
            Meter(progress: entry.progress, height: 6)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Reps today", symbol: "figure.strengthtraining.functional")
            Spacer(minLength: 0)
            total(size: hasBackground ? 52 : 62)
            Text(goalNote)
                .font(Typo.body(11.5, .semibold))
                .foregroundStyle(done ? Theme.good : Theme.ink2)
            progress(height: 16).padding(.top, 4)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Reps today", symbol: "figure.strengthtraining.functional")
                Spacer(minLength: 0)
                total(size: 52)
                Text(goalNote)
                    .font(Typo.body(11.5, .semibold))
                    .foregroundStyle(done ? Theme.good : Theme.ink2)
                progress(height: 16).padding(.top, 4)
            }
            .frame(width: 136)
            VStack(spacing: 0) {
                ForEach(Array(entry.rows.prefix(4).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(WidgetColors(mode: mode).track).frame(height: 1) }
                    exerciseRow(row).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .background(WidgetColors(mode: mode).well, in: .rect(cornerRadius: 14))
        }
    }

    private var large: some View {
        let most = max(entry.rows.map(\.reps).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Reps today", symbol: "figure.strengthtraining.functional", note: goalNote)
            total(size: 62)
            progress(height: 18)
            VStack(spacing: 10) {
                ForEach(entry.rows.prefix(6)) { row in
                    VStack(spacing: 5) {
                        exerciseRow(row)
                        Meter(progress: Double(row.reps) / Double(most), height: 5)
                    }
                }
            }
            .padding(12)
            .background(WidgetColors(mode: mode).well, in: .rect(cornerRadius: 16))
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private func exerciseRow(_ row: RepsEntry.Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.name)
                .font(Typo.body(13, .medium))
                .foregroundStyle(row.reps > 0 ? Theme.ink2 : Theme.ink3)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(row.reps)")
                .font(Typo.display(20))
                .monospacedDigit()
                .foregroundStyle(row.reps > 0 ? Theme.ink : Theme.ink3)
        }
    }

    // MARK: Lock screen

    /// "Push-ups 40" for the exercise with the most reps today.
    private var topExercise: String? {
        guard let top = entry.rows.first, top.reps > 0 else { return nil }
        return "\(top.name) \(top.reps)"
    }

    private var circular: some View {
        Gauge(value: min(entry.progress, 1)) {
            Image(systemName: "figure.strengthtraining.functional")
        } currentValueLabel: {
            Text("\(entry.total)")
                .font(Typo.display(20))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(entry.total)").font(Typo.display(24)).monospacedDigit()
                Text("/ \(entry.goal) reps").font(Typo.body(13, .semibold))
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold))
                }
            }
            .widgetAccentable()
            Gauge(value: min(entry.progress, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(topExercise ?? goalNote)
                .font(Typo.body(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
