import SwiftUI
import Overlo4dCore
import Overlo4dKit

/// Workouts and body weight handed to the tracker when it opens. A snapshot of plain values, so
/// the tracker reads the training log but the rest of the app never reads the tracker.
struct PeptideTrainingContext: Sendable {
    /// One element per workout, strength, cardio or from Health.
    var workoutDays: [DayKey] = []
    var weights: [WeightPoint] = []

    var trainedDays: Set<DayKey> { Set(workoutDays) }
}

/// Five weeks, Monday first: a dot per entry and a ring on training days.
struct PeptideCalendarCard: View {
    let data: PeptideData
    let training: PeptideTrainingContext

    @State private var weeksBack = 0
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        let today = DayKey(.now)
        let end = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: .now) ?? .now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: end)?.start ?? end
        let first = DayKey(calendar.date(byAdding: .day, value: -28, to: weekStart) ?? weekStart)
        let last = first.adding(days: 34)
        let entries = data.entriesByDay(from: first, to: last)
        let trained = training.trainedDays
        let symbols = calendar.veryShortWeekdaySymbols
        let order = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Earlier", systemImage: "chevron.left") { weeksBack += 5 }
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
                Spacer()
                Text(rangeLabel(first, last)).font(Typo.body(15, .semibold))
                Spacer()
                Button("Later", systemImage: "chevron.right") { weeksBack = max(0, weeksBack - 5) }
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
                    .disabled(weeksBack == 0)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    ForEach(order.indices, id: \.self) { index in
                        Text(order[index]).eyebrow(10).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<5, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = first.adding(days: week * 7 + weekday)
                            dayCell(day, count: entries[day]?.count ?? 0, trained: trained.contains(day),
                                    isToday: day == today, isFuture: day > today)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legend("Logged") { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
                legend("Trained") { Circle().strokeBorder(Theme.good, lineWidth: 2).frame(width: 12, height: 12) }
            }
        }
        .card(padding: 14, cornerRadius: 20)
    }

    private func dayCell(_ day: DayKey, count: Int, trained: Bool, isToday: Bool, isFuture: Bool) -> some View {
        VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day.date()))")
                .font(Typo.body(13, isToday ? .bold : .medium))
                .foregroundStyle(isFuture ? Theme.ink3.opacity(0.5) : isToday ? Theme.accent : Theme.ink)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.good, lineWidth: 2).opacity(trained ? 1 : 0))
            HStack(spacing: 2) {
                ForEach(0..<min(count, 3), id: \.self) { _ in
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date().formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue([count > 0 ? "\(count) logged" : nil, trained ? "trained" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private func legend<Mark: View>(_ label: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 6) {
            mark()
            Text(label).font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
        }
    }

    private func rangeLabel(_ first: DayKey, _ last: DayKey) -> String {
        let style = Date.FormatStyle().day().month(.abbreviated)
        return "\(first.date().formatted(style)) – \(last.date().formatted(style))"
    }
}

/// Training since a peptide was started, against the same time before.
struct PeptideTrainingCard: View {
    let summary: PeptideTrainingSummary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).eyebrow(11.5)
                Spacer()
                Text("Since \(summary.since.date().formatted(date: .abbreviated, time: .omitted))")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
            }
            HStack(alignment: .top, spacing: 12) {
                StatBlock(label: "Workouts", value: "\(summary.workouts)")
                StatBlock(label: "Per week", value: PeptideFormat.number(summary.perWeek, places: 1))
                StatBlock(label: "Body weight", value: weightText)
            }
            if let line = comparison {
                Text(line)
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 20)
    }

    private var weightText: String {
        guard let change = summary.weightChange else { return summary.weightNow.map { "\(PeptideFormat.number($0, places: 1)) kg" } ?? "–" }
        let sign = change > 0.04 ? "+" : change < -0.04 ? "−" : "±"
        return "\(sign)\(PeptideFormat.number(abs(change), places: 1)) kg"
    }

    private var comparison: String? {
        var parts: [String] = []
        if let before = summary.previousPerWeek {
            parts.append("\(PeptideFormat.number(before, places: 1)) workouts a week in the \(summary.days) days before.")
        }
        if let start = summary.weightStart, let now = summary.weightNow, summary.weightChange != nil {
            parts.append("Weight \(PeptideFormat.number(start, places: 1)) → \(PeptideFormat.number(now, places: 1)) kg.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Small facts under a peptide card: cycle, mixed-vial age, spares, how often it was logged.
struct PeptideFacts: View {
    let profile: PeptideProfile
    let adherence: PeptideAdherence?

    var body: some View {
        let facts = items
        if !facts.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(facts.indices, id: \.self) { index in
                    let fact = facts[index]
                    Label(fact.text, systemImage: fact.symbol)
                        .font(Typo.body(12.5, .semibold))
                        .foregroundStyle(fact.warning ? Theme.hot : Theme.ink2)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(fact.warning ? Theme.hot.opacity(0.14) : Theme.fill, in: .capsule)
                }
            }
        }
    }

    private struct Fact {
        let text: String
        let symbol: String
        var warning = false
    }

    private var items: [Fact] {
        var result: [Fact] = []
        if let cycle = profile.cycle {
            let phase = cycle.phase(on: DayKey(.now))
            result.append(Fact(text: phase.label, symbol: phase.isOn ? "calendar" : "pause.circle"))
        }
        if profile.tracksVial, let mixed = profile.mixedDays(now: .now) {
            let text = mixed == 0 ? "Mixed today" : "Mixed \(mixed) \(mixed == 1 ? "day" : "days") ago"
            if profile.pastKeepDays(now: .now) {
                result.append(Fact(text: "\(text), past your \(profile.keepsDays ?? 0) days", symbol: "exclamationmark.circle", warning: true))
            } else {
                result.append(Fact(text: text, symbol: "drop"))
            }
        }
        if profile.spareVials > 0 {
            result.append(Fact(text: "\(profile.spareVials) spare", symbol: "shippingbox"))
        } else if profile.runningLow {
            result.append(Fact(text: "Running low", symbol: "exclamationmark.triangle", warning: true))
        }
        if let adherence, adherence.planned > 0 {
            result.append(Fact(text: "\(adherence.percent)% on schedule, \(adherence.days) days", symbol: "checkmark.circle"))
        }
        return result
    }
}

/// 1 to 5, or nothing.
struct FeelingPicker: View {
    @Binding var feeling: Int?

    private static let labels = [1: "Bad", 2: "Meh", 3: "Okay", 4: "Good", 5: "Great"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                let selected = feeling == value
                Button {
                    feeling = selected ? nil : value
                } label: {
                    VStack(spacing: 1) {
                        Text("\(value)").font(Typo.display(22)).monospacedDigit()
                        Text(Self.labels[value] ?? "").font(Typo.body(11, .medium))
                    }
                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected ? Theme.accent : Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.clear : Theme.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: feeling)
    }
}
