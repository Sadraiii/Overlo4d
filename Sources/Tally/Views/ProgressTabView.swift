import Charts
import TallyKit
import SwiftUI

struct ProgressTabView: View {
    @Environment(GymStore.self) private var gym
    @State private var page = Page.overview
    @State private var search = ""
    @State private var showingCreate = false
    @State private var sharingWeek = false

    enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case exercises = "Exercises"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Segmented(selection: $page)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                switch page {
                case .overview:
                    ScrollView {
                        ProgressOverview()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }
                case .exercises:
                    ExerciseList(search: search) { exercise in
                        NavigationLink(value: exercise) {
                            HStack {
                                ExerciseLabel(exercise: exercise)
                                Spacer()
                                let count = gym.sessions(for: exercise.id).count
                                if count > 0 {
                                    Text("\(count)×").font(Typo.display(18)).foregroundStyle(Theme.ink3)
                                }
                            }
                        }
                        .cardRow()
                        .swipeActions {
                            if exercise.isCustom && !gym.isUsed(exercise) {
                                Button("Delete", systemImage: "trash", role: .destructive) { gym.deleteExercise(exercise) }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search")
                }
            }
            .background(ScreenBackground())
            .navigationTitle("Progress")
            .navigationDestination(for: ExerciseDef.self) { ExerciseDetailView(exercise: $0) }
            .navigationDestination(for: RecapRoute.self) { RecapView(weekStart: $0.weekStart) }
            .toolbar {
                if page == .exercises {
                    Button("New exercise", systemImage: "plus") { showingCreate = true }
                } else {
                    Button("Share week", systemImage: "square.and.arrow.up") { sharingWeek = true }
                }
            }
            .sheet(isPresented: $showingCreate) { ExerciseEditor() }
            .sheet(isPresented: $sharingWeek) { ShareSheet(model: .week(containing: .now, gym: gym)) }
        }
    }
}

/// Two- or three-way segmented control.
struct Segmented<Value: Hashable & Identifiable & RawRepresentable<String> & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Value.allCases) { value in
                let selected = selection == value
                Button(value.rawValue) {
                    withAnimation(.snappy) { selection = value }
                }
                .font(Typo.body(14, .semibold))
                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Theme.card : .clear, in: .rect(cornerRadius: 11))
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 2, y: 1)
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.line, in: .rect(cornerRadius: 15))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct ProgressOverview: View {
    @Environment(GymStore.self) private var gym

    private struct WeekStat: Identifiable {
        var id: Date { week }
        let week: Date
        let workouts: Int
        let volume: Double
    }

    private var weeks: [WeekStat] {
        let thisWeek = gym.weekStart(.now)
        return (0..<12).reversed().compactMap { offset -> WeekStat? in
            guard let week = Calendar.current.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            let workouts = gym.workouts.filter { gym.weekStart($0.startedAt) == week }
            return WeekStat(week: week, workouts: workouts.count, volume: workouts.reduce(0) { $0 + $1.volume })
        }
    }

    private struct RecordItem: Identifiable {
        var id: UUID { workoutSet.id }
        let date: Date
        let exercise: ExerciseDef?
        let workoutSet: WorkoutSet
        let kinds: [RecordKind]
    }

    private var recentRecords: [RecordItem] {
        var result: [RecordItem] = []
        for workout in gym.workouts {
            for exercise in workout.exercises {
                for set in exercise.sets {
                    if let kinds = gym.records[set.id] {
                        result.append(RecordItem(date: workout.startedAt, exercise: gym.exercise(exercise.exerciseID), workoutSet: set, kinds: kinds))
                    }
                }
            }
            if result.count >= 8 { break }
        }
        return Array(result.prefix(8))
    }

    var body: some View {
        let weeks = weeks
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                RecapListView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accentSoft, in: .rect(cornerRadius: 10))
                    Text("Weekly recaps").font(Typo.body(15, .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
                .foregroundStyle(Theme.ink)
                .card(padding: 10, cornerRadius: 18)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Tile(value: "\(gym.workouts.count)", label: "Workouts")
                Tile(value: "\(gym.weekStreak)", label: "Week streak", tint: gym.weekStreak > 0 ? Theme.hot : Theme.ink, symbol: gym.weekStreak > 0 ? "flame.fill" : nil)
                Tile(value: "\(weeks.last?.workouts ?? 0)", label: "This week")
            }

            // Workouts per week as bars.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workouts per week").display(16)
                    Spacer()
                    Text("Last 12 weeks").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
                let most = max(weeks.map(\.workouts).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                        let isNow = index == weeks.count - 1
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isNow && week.workouts == 0 ? .clear : Theme.fill)
                                    .overlay {
                                        if isNow && week.workouts == 0 {
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                        }
                                    }
                                if week.workouts > 0 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.accent)
                                        .frame(height: 54 * CGFloat(week.workouts) / CGFloat(most))
                                        .overlay(alignment: .bottom) {
                                            Text("\(week.workouts)")
                                                .font(Typo.body(11, .bold))
                                                .foregroundStyle(Theme.accentInk)
                                                .padding(.bottom, 4)
                                        }
                                }
                            }
                            .frame(height: 54)
                            .clipShape(.rect(cornerRadius: 6))
                            Text("\(Calendar.current.component(.weekOfYear, from: week.week))")
                                .font(Typo.body(10.5, isNow ? .bold : .semibold))
                                .foregroundStyle(isNow ? Theme.accent : Theme.ink3)
                        }
                    }
                }
            }
            .card(padding: 14, cornerRadius: 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Volume per week").display(16)
                    Spacer()
                    Text("kg").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.week, unit: .weekOfYear), y: .value("Volume", week.volume))
                        .foregroundStyle(Theme.accent)
                        .clipShape(.rect(cornerRadius: 5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 150)
            }
            .card(padding: 14, cornerRadius: 20)

            WeightCard()

            // Averaged over the last 4 weeks, or since the first workout for newer users.
            let muscleSince = min(max(Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now, gym.workouts.last?.startedAt ?? .now), .now)
            let muscleVolume = gym.weeklyMuscleSets(in: DateInterval(start: muscleSince, end: .now))
            if !muscleVolume.isEmpty {
                SectionHead("Muscles")
                MuscleVolumeCard(weeklySets: muscleVolume, caption: "Average working sets per week, last 4 weeks")
                    .card()
            }

            if !recentRecords.isEmpty {
                SectionHead("Records") {
                    NavigationLink("See all") { RecordsView() }
                }
                VStack(spacing: 0) {
                    ForEach(Array(recentRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.exercise?.name ?? "Exercise").display(20).lineLimit(1)
                                Text("\(record.kinds.map(\.label).joined(separator: ", ")) · \(record.date.formatted(.dateTime.day().month()))")
                                    .font(Typo.body(12.5))
                                    .foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            Text(Fmt.set(record.workoutSet, kind: record.exercise?.kind ?? .weightReps))
                                .font(Typo.display(24))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .card(padding: 0, cornerRadius: 18)
            }
        }
    }
}
