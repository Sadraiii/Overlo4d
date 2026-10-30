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
        .description("This week's workouts, your streak and your last session.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TrainingEntry: TimelineEntry {
    let date: Date
    let snapshot: ActivitySnapshot

    var days: [Bool] { snapshot.trainedDays(inWeekOf: date) }
    var workoutsThisWeek: Int { snapshot.workoutsThisWeek(date) }
    var todayIndex: Int { ActivitySnapshot.weekdayIndex(of: date) }
    var streak: Int { snapshot.currentStreak(at: date) }
    var trainedToday: Bool { days.indices.contains(todayIndex) && days[todayIndex] }
}

struct TrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        let snapshot = ActivitySnapshot.load()
        // The widget gallery shows sample data until the first workout.
        let shown = context.isPreview && snapshot.workoutDates.isEmpty ? .preview : snapshot
        completion(TrainingEntry(date: .now, snapshot: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let snapshot = ActivitySnapshot.load()
        let midnight = MidnightTimeline.nextMidnight
        // The midnight entry moves "today" on and starts a new week on the first weekday.
        completion(Timeline(
            entries: [TrainingEntry(date: .now, snapshot: snapshot), TrainingEntry(date: midnight, snapshot: snapshot)],
            policy: .after(midnight)
        ))
    }
}

extension ActivitySnapshot {
    /// Sample week for the widget gallery.
    static var preview: ActivitySnapshot {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let dates = [0, 2, -3, -5, -7, -10, -12, -14, -17, -19, -24, -26, -31, -33, -38]
            .compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { $0 <= .now }
            .map { $0.addingTimeInterval(18 * 3600) }
        return ActivitySnapshot(
            workoutDates: dates,
            weekStreak: 6,
            lastWorkout: LastWorkout(name: "Push day", date: dates.first ?? .now, duration: 3240, volume: 8420, sets: 18, records: 2)
        )
    }
}

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var hasBackground
    @Environment(\.widgetRenderingMode) private var mode
    let entry: TrainingEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home screen

    private var countUnit: String { entry.workoutsThisWeek == 1 ? "workout" : "workouts" }

    @ViewBuilder
    private var streakChip: some View {
        if entry.streak > 0 {
            Chip(text: "\(entry.streak) wk", symbol: "flame.fill")
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "This week", symbol: "dumbbell.fill")
            Spacer(minLength: 2)
            BigNumber(value: "\(entry.workoutsThisWeek)", unit: countUnit, size: hasBackground ? 50 : 60)
            HStack(spacing: 4) {
                if entry.streak > 0 {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.hot)
                    Text("\(entry.streak) week streak")
                } else {
                    Text(entry.trainedToday ? "Trained today" : "Start a streak")
                }
            }
            .font(Typo.body(11.5, .semibold))
            .foregroundStyle(Theme.ink2)
            .lineLimit(1)
            Spacer(minLength: 6)
            WeekDots(days: entry.days, todayIndex: entry.todayIndex, size: 14, showsLabels: false)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Training week", symbol: "dumbbell.fill")
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    BigNumber(value: "\(entry.workoutsThisWeek)", unit: countUnit, size: 50)
                    streakChip
                }
                Spacer(minLength: 0)
                if let last = entry.snapshot.lastWorkout {
                    lastWorkout(last, compact: true)
                        .frame(maxWidth: 170, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            WeekDots(days: entry.days, todayIndex: entry.todayIndex, size: 18)
        }
    }

    private var large: some View {
        let counts = entry.snapshot.weeklyCounts(weeks: 8, endingAt: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Training week", symbol: "dumbbell.fill", note: entry.date.formatted(.dateTime.weekday(.wide)))
            HStack(alignment: .center) {
                BigNumber(value: "\(entry.workoutsThisWeek)", unit: "\(countUnit) this week", size: 56)
                Spacer(minLength: 4)
                streakChip
            }
            .padding(.top, 6)
            WeekDots(days: entry.days, todayIndex: entry.todayIndex, size: 26)
                .padding(.top, 8)
            Spacer(minLength: 10)
            if let last = entry.snapshot.lastWorkout {
                lastWorkout(last, compact: false)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WidgetColors(mode: mode).well, in: .rect(cornerRadius: 16))
            }
            Spacer(minLength: 10)
            WidgetLabel(text: "Last 8 weeks")
            WeekBars(counts: counts)
                .frame(height: 54)
                .padding(.top, 6)
        }
    }

    private func lastWorkout(_ last: ActivitySnapshot.LastWorkout, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Bib(date: last.date, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                WidgetLabel(text: "Last workout")
                Text(last.name)
                    .font(Typo.title(compact ? 15 : 17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(compact ? 2 : 1)
                Text(details(of: last, compact: compact))
                    .font(Typo.body(11.5, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
        }
    }

    private func details(of last: ActivitySnapshot.LastWorkout, compact: Bool) -> String {
        var parts = ["\(Int(last.volume.rounded()).formatted()) kg", "\(last.sets) sets"]
        if !compact {
            if last.duration >= 60 { parts.append("\(Int(last.duration / 60)) min") }
            if last.records > 0 { parts.append(last.records == 1 ? "1 PR" : "\(last.records) PRs") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            // Seven arcs around the edge, one per day, filled on workout days.
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .trim(from: Double(index) / 7 + 0.012, to: Double(index + 1) / 7 - 0.012)
                    .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(entry.days[index] ? 1 : 0.25)
                    .widgetAccentable(entry.days[index])
            }
            .padding(3)
            VStack(spacing: -3) {
                Text("\(entry.workoutsThisWeek)")
                    .font(Typo.display(26))
                    .monospacedDigit()
                Text(entry.streak > 0 ? "\(entry.streak) wk" : "week")
                    .font(Typo.body(9, .bold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill").font(.system(size: 11, weight: .bold))
                Text("\(entry.workoutsThisWeek) this week")
                    .font(Typo.body(14, .bold))
                if entry.streak > 0 {
                    Spacer(minLength: 2)
                    Text("\(Image(systemName: "flame.fill")) \(entry.streak)")
                        .font(Typo.body(12.5, .semibold))
                }
            }
            .widgetAccentable()
            .lineLimit(1)
            WeekDots(days: entry.days, todayIndex: entry.todayIndex, size: 13, showsLabels: false)
            if let last = entry.snapshot.lastWorkout {
                Text("\(last.name) · \(last.date.formatted(.dateTime.weekday(.abbreviated)))")
                    .font(Typo.body(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if entry.streak > 0 {
            Label("\(entry.workoutsThisWeek) this week · \(entry.streak) wk streak", systemImage: "flame.fill")
        } else {
            Label("\(entry.workoutsThisWeek) \(countUnit) this week", systemImage: "dumbbell.fill")
        }
    }
}

/// Workouts per week as bars, this week last and in the accent colour.
struct WeekBars: View {
    @Environment(\.widgetRenderingMode) private var mode
    let counts: [Int]

    var body: some View {
        let most = max(counts.max() ?? 0, 1)
        let colors = WidgetColors(mode: mode)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                let current = index == counts.count - 1
                VStack(spacing: 3) {
                    Text("\(count)")
                        .font(Typo.body(10, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(current ? Theme.accent : Theme.ink3)
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(current ? Theme.accent : (colors.isFullColor ? Theme.accentSoft : Color.primary.opacity(0.3)))
                                .frame(height: max(4, proxy.size.height * Double(count) / Double(most)))
                                .widgetAccentable(current)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
