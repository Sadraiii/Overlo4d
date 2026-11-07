import TallyCore
import TallyKit
import SwiftUI

extension MilestoneKind {
    var title: String {
        switch self {
        case .workouts: "Workouts"
        case .sets: "Sets done"
        case .volume: "Weight lifted"
        case .hours: "Time trained"
        case .streak: "Best streak"
        case .records: "Records"
        }
    }

    var symbol: String {
        switch self {
        case .workouts: "dumbbell.fill"
        case .sets: "checkmark.circle.fill"
        case .volume: "scalemass.fill"
        case .hours: "clock.fill"
        case .streak: "flame.fill"
        case .records: "trophy.fill"
        }
    }

    /// "250", "50 t", "100 h", "12 wk".
    func format(_ value: Double) -> String {
        let number = { (v: Double) in v.formatted(.number.precision(.fractionLength(0...1))) }
        return switch self {
        case .workouts, .records, .sets: value.rounded(.down).formatted(.number.precision(.fractionLength(0)))
        case .volume: value >= 1000 ? "\(number(value / 1000)) t" : "\(Int(value)) kg"
        case .hours: "\(number(value)) h"
        case .streak: "\(Int(value)) wk"
        }
    }
}

/// Lifetime milestones as a grid of badges with progress to the next level.
struct MilestonesCard: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        let milestones = Milestones.all(gym.milestoneStats)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(milestones, id: \.kind) { milestone in
                MilestoneTile(milestone: milestone)
            }
        }
    }
}

struct MilestoneTile: View {
    let milestone: Milestone

    var body: some View {
        let kind = milestone.kind
        let earned = milestone.level > 0
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(earned ? Theme.accentInk : Theme.ink3)
                    .frame(width: 32, height: 32)
                    .background(earned ? Theme.accent : Theme.fill, in: .circle)
                Spacer(minLength: 0)
                LevelPips(level: milestone.level, max: milestone.maxLevel)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.format(milestone.value))
                    .font(Typo.display(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(kind.title).eyebrow(10.5)
            }
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.accent)
                            .frame(width: max(milestone.progress > 0 ? 5 : 0, proxy.size.width * milestone.progress))
                    }
                }
                .frame(height: 5)
                Text(milestone.next.map { "Next: \(kind.format($0))" } ?? "All levels done")
                    .font(Typo.body(11.5, .medium))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 13, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// Small dots for levels reached, e.g. ●●●○○○○○.
struct LevelPips: View {
    let level: Int
    let max: Int

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<max, id: \.self) { index in
                Capsule()
                    .fill(index < level ? Theme.accent : Theme.line2)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Level \(level) of \(max)")
    }
}

/// Training days over the last half year, one square per day, in week columns.
struct ConsistencyCard: View {
    @Environment(GymStore.self) private var gym
    var weeks = 26

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let columns = ActivityGrid.columns(ending: today, weeks: weeks)
        let counts = ActivityGrid.counts(gym.activityDates)
        let start = columns.first?.first ?? today
        let inRange = counts.filter { $0.key >= start && $0.key <= today }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency").display(16)
                Spacer()
                Text("Last 6 months").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
            }
            GeometryReader { proxy in
                let gap: CGFloat = 3
                let size = max(4, (proxy.size.width - gap * CGFloat(columns.count - 1)) / CGFloat(max(columns.count, 1)))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, days in
                        VStack(spacing: gap) {
                            ForEach(days, id: \.self) { day in
                                RoundedRectangle(cornerRadius: size * 0.28)
                                    .fill(fill(count: counts[calendar.startOfDay(for: day)] ?? 0, future: day > today))
                                    .overlay {
                                        if day == today {
                                            RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(Theme.ink, lineWidth: 1.2)
                                        }
                                    }
                                    .frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(columns.count) / 7, contentMode: .fit)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                Text("\(inRange.count) active days").font(Typo.body(13, .semibold)).foregroundStyle(Theme.ink)
                Text("\(inRange.values.reduce(0, +)) sessions").font(Typo.body(13)).foregroundStyle(Theme.ink3)
                Spacer()
                HStack(spacing: 3) {
                    Text("Less").font(Typo.body(11)).foregroundStyle(Theme.ink3)
                    ForEach([0, 1, 2], id: \.self) { count in
                        RoundedRectangle(cornerRadius: 2.5).fill(fill(count: count, future: false)).frame(width: 10, height: 10)
                    }
                    Text("More").font(Typo.body(11)).foregroundStyle(Theme.ink3)
                }
            }
        }
        .card(padding: 14, cornerRadius: 20)
    }

    private func fill(count: Int, future: Bool) -> Color {
        if future { return .clear }
        switch count {
        case 0: return Theme.fill
        case 1: return Theme.accent.mix(with: Theme.card, by: 0.35)
        default: return Theme.accent
        }
    }
}
