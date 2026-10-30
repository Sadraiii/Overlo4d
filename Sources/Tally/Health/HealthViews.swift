import Charts
import SwiftUI
import TallyKit

/// Today's steps, energy and exercise minutes on Home, or a prompt to connect.
struct HealthCard: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        if !health.isAvailable {
            EmptyView()
        } else if health.isConnected {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Activity").eyebrow()
                    Spacer()
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                HStack(spacing: 12) {
                    StatBlock(label: "Steps", value: health.today.steps.map { Int($0).formatted() } ?? "–")
                    StatBlock(label: "Active", value: health.today.activeEnergy.map { "\(Int($0)) kcal" } ?? "–")
                    StatBlock(label: "Exercise", value: health.today.exerciseMinutes.map { "\(Int($0)) min" } ?? "–")
                }
            }
            .card()
        } else {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 42, height: 42)
                    .background(Theme.fill, in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health").font(Typo.body(15, .semibold))
                    Text("Steps, energy and body weight")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
                Button("Connect") { Task { await health.connect() } }
                    .buttonStyle(.smallOutline)
            }
            .card(padding: 14)
        }
    }
}

/// Energy and heart rate Health recorded during a workout (e.g. from an Apple Watch).
struct WorkoutHealthTiles: View {
    @Environment(HealthManager.self) private var health
    let workout: Workout
    @Binding var stats: HealthManager.WorkoutHealth?

    var body: some View {
        Group {
            if let stats, !stats.isEmpty {
                HStack(spacing: 8) {
                    if let kcal = stats.activeEnergy, kcal >= 1 {
                        Tile(value: "\(Int(kcal.rounded()))", label: "Active kcal")
                    }
                    if let average = stats.averageHeartRate {
                        Tile(value: "\(Int(average.rounded()))", label: "Avg bpm")
                    }
                    if let max = stats.maxHeartRate {
                        Tile(value: "\(Int(max.rounded()))", label: "Max bpm")
                    }
                }
            }
        }
        .task(id: workout.id) {
            stats = await health.health(for: workout)
        }
    }
}

/// Body weight from Health over the last six months.
struct WeightCard: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        if let latest = health.weights.last {
            let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            let reference = health.weights.first { $0.date >= monthAgo }
            let change = reference.map { latest.kg - $0.kg }
            let kgs = health.weights.map(\.kg)
            let low = (kgs.min() ?? latest.kg) - 1
            let high = (kgs.max() ?? latest.kg) + 1

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Body weight").display(16)
                    Spacer()
                    Text("Apple Health").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.weight(latest.kg)).font(Typo.display(44)).monospacedDigit()
                    Text("kg").eyebrow(12)
                    Spacer()
                    if let change, abs(change) >= 0.05, health.weights.count > 1 {
                        Text("\(change > 0 ? "+" : "−")\(Fmt.weight(abs(change))) kg in 30 days")
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink2)
                    }
                }
                if health.weights.count > 1 {
                    Chart(health.weights) { weight in
                        LineMark(x: .value("Date", weight.date), y: .value("kg", weight.kg))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    .chartYScale(domain: low...high)
                    .frame(height: 130)
                }
            }
            .card(padding: 14, cornerRadius: 20)
        }
    }
}

/// Health connection and the "save workouts" toggle in Settings.
struct HealthSettingsSection: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        @Bindable var health = health

        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health").eyebrow(11.5)
            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink3)
            } else if !health.isConnected {
                Button("Connect Apple Health") { Task { await health.connect() } }
                    .buttonStyle(OOButtonStyle(kind: .outline, fullWidth: true))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Save workouts to Health", isOn: $health.savesWorkouts)
                        .font(Typo.body(15, .semibold))
                        .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("Change access in Health › Profile › Apps › Overlo4d.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                        .padding(14)
                }
                .card(padding: 0, cornerRadius: 18)
            }
        }
    }
}
