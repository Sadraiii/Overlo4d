import TallyKit
import SwiftUI
import WidgetKit

@main
struct TallyWidgets: WidgetBundle {
    init() {
        Typo.registerFonts()
    }

    var body: some Widget {
        TrainingWidget()
        FoodWidget()
        RepsWidget()
        WorkoutLiveActivity()
    }
}

/// Small grey sentence-case label, like `.eyebrow()` in the app.
struct WidgetLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.body(12.5, .medium))
            .foregroundStyle(Theme.ink3)
            .lineLimit(1)
    }
}

/// Widget title row: accent icon, sentence-case title and an optional note on the right.
struct WidgetHeader: View {
    let title: String
    let symbol: String
    var note: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .widgetAccentable()
            Text(title)
                .font(Typo.body(13, .semibold))
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 4)
            if let note {
                Text(note)
                    .font(Typo.body(12, .medium))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .lineLimit(1)
    }
}

/// Track and well colours that still read when the system tints the widget
/// (tinted and clear Home Screen icons, StandBy at night), where every colour turns into the tint.
struct WidgetColors {
    let mode: WidgetRenderingMode

    var isFullColor: Bool { mode == .fullColor }
    /// The empty part of a ring or bar.
    var track: Color { isFullColor ? Theme.line : Color.primary.opacity(0.16) }
    /// Background of chips and empty day dots.
    var well: Color { isFullColor ? Theme.fill : Color.primary.opacity(0.1) }
}

/// Horizontal progress bar toward a goal.
struct Meter: View {
    @Environment(\.widgetRenderingMode) private var mode
    let progress: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        let value = min(max(progress, 0), 1)
        Capsule()
            .fill(WidgetColors(mode: mode).track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if value > 0 {
                        Capsule()
                            .fill(color)
                            .frame(width: max(height, proxy.size.width * value))
                            .widgetAccentable()
                    }
                }
            }
            .frame(height: height)
    }
}

/// Progress ring toward a goal; turns green when reached.
struct WidgetRing: View {
    @Environment(\.widgetRenderingMode) private var mode
    let progress: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        let done = progress >= 1
        ZStack {
            Circle()
                .stroke(WidgetColors(mode: mode).track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(done ? Theme.good : Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

/// The week as seven dots (first weekday → last): filled on workout days, ringed for today.
struct WeekDots: View {
    @Environment(\.widgetRenderingMode) private var mode
    let days: [Bool]
    let todayIndex: Int
    var size: CGFloat = 18
    var showsLabels = true

    var body: some View {
        let colors = WidgetColors(mode: mode)
        let symbols = WeekStrip.weekdaySymbols
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    if showsLabels {
                        Text(symbols[index])
                            .font(Typo.body(max(9.5, size * 0.5), .medium))
                            .foregroundStyle(index == todayIndex ? Theme.accent : Theme.ink3)
                    }
                    ZStack {
                        if days.indices.contains(index), days[index] {
                            Circle().fill(Theme.accent).widgetAccentable()
                            if colors.isFullColor {
                                Image(systemName: "checkmark")
                                    .font(.system(size: size * 0.42, weight: .bold))
                                    .foregroundStyle(Theme.accentInk)
                            }
                        } else if index == todayIndex {
                            Circle().strokeBorder(Theme.accent, lineWidth: max(1.5, size * 0.1)).widgetAccentable()
                        } else {
                            Circle().fill(colors.well)
                        }
                    }
                    .frame(width: size, height: size)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A big condensed number with a small unit after it.
struct BigNumber: View {
    let value: String
    var unit: String?
    var size: CGFloat = 46
    var color: Color = Theme.ink

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(Typo.display(size))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(Typo.body(max(11, size * 0.26), .semibold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .lineLimit(1)
    }
}

/// Small rounded chip with an icon, e.g. the streak.
struct Chip: View {
    @Environment(\.widgetRenderingMode) private var mode
    let text: String
    let symbol: String
    var color: Color = Theme.hot

    var body: some View {
        Label(text, systemImage: symbol)
            .font(Typo.body(11.5, .semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WidgetColors(mode: mode).well, in: .capsule)
    }
}

enum MidnightTimeline {
    /// Widgets refresh at midnight so daily counts reset.
    static var nextMidnight: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)
    }
}
