import SwiftUI
import WidgetKit
import RepCore

@main
struct RepWidgetBundle: WidgetBundle {
    var body: some Widget {
        RepWidget()
    }
}

struct RepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RepStorage.widgetKind, provider: Provider()) { entry in
            RepWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Reps")
        .description("See how many reps you've done today.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            // Lock screen
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct RepWidgetEntry: TimelineEntry {
    struct Row: Identifiable {
        let id: UUID
        let name: String
        let symbol: String
        let reps: Int
    }

    let date: Date
    let total: Int
    let rows: [Row]

    init(date: Date, data: RepData) {
        self.date = date
        total = data.repsToday(on: date)
        rows = data.exercises.map {
            Row(id: $0.id, name: $0.name, symbol: $0.symbol, reps: data.reps(for: $0.id, on: date))
        }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RepWidgetEntry {
        RepWidgetEntry(date: .now, data: RepData())
    }

    func getSnapshot(in context: Context, completion: @escaping (RepWidgetEntry) -> Void) {
        completion(RepWidgetEntry(date: .now, data: RepStorage.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RepWidgetEntry>) -> Void) {
        let data = RepStorage.load()
        let now = Date.now
        // Add a second entry at midnight so the counts reset to zero for the new day.
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let entries = [
            RepWidgetEntry(date: now, data: data),
            RepWidgetEntry(date: midnight, data: data),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct RepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RepWidgetEntry

    private var visibleRows: [RepWidgetEntry.Row] {
        switch family {
        case .systemSmall: Array(entry.rows.prefix(3))
        case .systemMedium: Array(entry.rows.prefix(6))
        default: Array(entry.rows.prefix(10))
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: homeScreen
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                Text("\(entry.total)")
                    .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(4)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(entry.total) reps today")
                    .lineLimit(1)
            }
            .font(.headline)
            .widgetAccentable()
            ForEach(entry.rows.filter { $0.reps > 0 }.prefix(2)) { row in
                Text("\(row.name): \(row.reps)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label("\(entry.total) reps today", systemImage: "flame.fill")
    }

    // MARK: Home screen

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(entry.total)")
                    .font(.title.bold().monospacedDigit())
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if family == .systemSmall {
                ForEach(visibleRows) { row in
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(row.reps)").bold().monospacedDigit()
                    }
                    .font(.caption)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    alignment: .leading,
                    spacing: family == .systemLarge ? 12 : 6
                ) {
                    ForEach(visibleRows) { row in
                        HStack(spacing: 6) {
                            Image(systemName: row.symbol)
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(row.reps)").bold().monospacedDigit()
                        }
                        .font(family == .systemLarge ? .subheadline : .caption)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
