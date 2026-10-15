import SwiftUI
import TallyKit

/// Month grid with the days you trained, at the top of History.
struct MonthCalendar: View {
    @Environment(GymStore.self) private var gym
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private var calendar: Calendar { .current }

    var body: some View {
        let interval = calendar.dateInterval(of: .month, for: month)
        let workouts = gym.workouts.filter { interval?.contains($0.startedAt) ?? false }
        let trained = Set(workouts.map { calendar.startOfDay(for: $0.startedAt) })
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = ActivitySnapshot.weekdayIndex(of: month)
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)

        VStack(spacing: 12) {
            HStack {
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).display(20)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
                    .disabled(isCurrent)
            }
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(WeekStrip.weekdaySymbols.indices, id: \.self) { index in
                    Text(WeekStrip.weekdaySymbols[index]).eyebrow(10)
                }
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: 34)
                }
                ForEach(1...days, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                    let didTrain = trained.contains(calendar.startOfDay(for: date))
                    let isToday = calendar.isDateInToday(date)
                    Text("\(day)")
                        .font(Typo.body(13, didTrain || isToday ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(didTrain ? Theme.accentInk : isToday ? Theme.accent : Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(didTrain ? Theme.accent : .clear, in: .rect(cornerRadius: 10))
                        .overlay {
                            if isToday && !didTrain {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            }
                        }
                }
            }

            Text("\(workouts.count) \(workouts.count == 1 ? "workout" : "workouts") · \(trained.count) days · \(Fmt.volume(workouts.reduce(0) { $0 + $1.volume }))")
                .font(Typo.body(12.5, .semibold))
                .foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 14, cornerRadius: 18)
        .sensoryFeedback(.selection, trigger: month)
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month), next <= .now else { return }
        withAnimation(.snappy) { month = next }
    }
}
