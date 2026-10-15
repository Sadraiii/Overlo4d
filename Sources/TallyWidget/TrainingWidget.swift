import TallyKit
import SwiftUI
import WidgetKit

struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.training, provider: TrainingProvider()) { entry in
            TrainingWidgetView(entry: entry)
                .containerBackground(Theme.card, for: .widget)
                .widgetURL(URL(string: "tally://train"))
        }
        .configurationDisplayName("Training week")
        .description("This week's workouts, streak and last session.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TrainingEntry: TimelineEntry {
    let date: Date
    let snapshot: ActivitySnapshot

    var days: [Bool] { snapshot.trainedDays(inWeekOf: date) }
    var workoutsThisWeek: Int { snapshot.workoutsThisWeek(date) }
    var todayIndex: Int { ActivitySnapshot.weekdayIndex(of: date) }
}

struct TrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: .now, snapshot: ActivitySnapshot(workoutDates: [.now], weekStreak: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        completion(TrainingEntry(date: .now, snapshot: ActivitySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let snapshot = ActivitySnapshot.load()
        let midnight = MidnightTimeline.nextMidnight
        completion(Timeline(
            entries: [TrainingEntry(date: .now, snapshot: snapshot), TrainingEntry(date: midnight, snapshot: snapshot)],
            policy: .after(midnight)
        ))
    }
}

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var count: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text("\(entry.workoutsThisWeek)")
                .font(Typo.display(52))
                .foregroundStyle(Theme.ink)
            Text(entry.workoutsThisWeek == 1 ? "workout" : "workouts")
                .font(Typo.body(12, .semibold))
                .foregroundStyle(Theme.ink3)
        }
    }

    @ViewBuilder
    private var streak: some View {
        if entry.snapshot.weekStreak > 0 {
            Label("\(entry.snapshot.weekStreak) wk streak", systemImage: "flame.fill")
                .font(Typo.body(11.5, .bold))
                .foregroundStyle(Theme.hot)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetLabel(text: "This week")
            count
            Spacer(minLength: 0)
            WeekStrip(days: entry.days, todayIndex: entry.todayIndex, size: 15)
                .widgetAccentable()
            streak.padding(.top, 2)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetLabel(text: "This week")
                    count
                    streak
                }
                Spacer(minLength: 0)
                if let last = entry.snapshot.lastWorkout {
                    HStack(alignment: .top, spacing: 10) {
                        Bib(date: last.date, size: .small)
                        VStack(alignment: .leading, spacing: 3) {
                            WidgetLabel(text: "Last")
                            Text(last.name)
                                .font(Typo.display(18))
                                .textCase(.uppercase)
                                .lineLimit(2)
                                .foregroundStyle(Theme.ink)
                            Text("\(Int(last.volume.rounded()).formatted()) kg · \(last.sets) sets")
                                .font(Typo.body(11.5))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .frame(maxWidth: 160, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            WeekStrip(days: entry.days, todayIndex: entry.todayIndex, size: 20)
                .widgetAccentable()
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .widgetAccentable()
                Text("\(entry.snapshot.weekStreak)")
                    .font(Typo.display(24))
                Text("WK")
                    .font(Typo.body(8, .bold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(entry.workoutsThisWeek) workouts · \(entry.snapshot.weekStreak) wk streak")
                .font(Typo.body(12.5, .semibold))
                .lineLimit(1)
                .widgetAccentable()
            WeekStrip(days: entry.days, todayIndex: entry.todayIndex, size: 13, showsLabels: false)
        }
    }
}
