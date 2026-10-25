import TallyKit
import SwiftUI

/// Shown after finishing a workout.
struct WorkoutSummaryView: View {
    @Environment(GymStore.self) private var gym
    @Environment(HealthManager.self) private var health
    let workout: Workout

    @State private var appeared = false
    @State private var savedPlan = false
    @State private var sharing = false
    @State private var coaching = false
    @State private var workoutHealth: HealthManager.WorkoutHealth?

    var body: some View {
        let records = workout.exercises.flatMap { exercise in
            exercise.sets.compactMap { set in
                gym.records[set.id].map { (exercise: gym.exercise(exercise.exerciseID), set: set, kinds: $0) }
            }
        }

        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Theme.good)
                    .frame(width: 104, height: 104)
                    .background(Theme.goodSoft, in: .circle)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 36)

                VStack(spacing: 6) {
                    Text("Workout saved").display(40)
                    Text("\(workout.name) · \(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month()))")
                        .font(Typo.body(15))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                    if health.isConnected && health.savesWorkouts {
                        Label("Added to Apple Health", systemImage: "heart.fill")
                            .font(Typo.body(12.5, .semibold))
                            .foregroundStyle(Theme.ink3)
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 8) {
                    Tile(value: Fmt.duration(workout.duration), label: "Duration")
                    Tile(value: Fmt.volume(workout.volume), label: "Volume")
                    Tile(value: "\(workout.completedSets.count)", label: "Sets")
                }
                WorkoutHealthTiles(workout: workout, stats: $workoutHealth)

                if !records.isEmpty {
                    SectionHead("Records")
                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.exercise?.name ?? "Exercise").display(20).lineLimit(1)
                                    Text(record.kinds.map(\.label).joined(separator: ", "))
                                        .font(Typo.body(12.5))
                                        .foregroundStyle(Theme.hot)
                                }
                                Spacer()
                                Text(Fmt.set(record.set, kind: record.exercise?.kind ?? .weightReps))
                                    .font(Typo.display(24))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
                }

                VStack(spacing: 10) {
                    Button("Done") { gym.closeSummary() }
                        .buttonStyle(.bigPrimary)
                    Button("Coach feedback", systemImage: "sparkles") { coaching = true }
                        .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 50, fullWidth: true))
                    HStack(spacing: 10) {
                        Button("Share", systemImage: "square.and.arrow.up") { sharing = true }
                            .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 50, fullWidth: true))
                        Button(savedPlan ? "Saved" : "Save as plan") {
                            gym.savePlan(gym.plan(from: workout))
                            savedPlan = true
                        }
                        .buttonStyle(OOButtonStyle(kind: savedPlan ? .done : .outline, shape: .pill, height: 50, fullWidth: true))
                        .disabled(savedPlan)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appeared = true }
        }
        .sheet(isPresented: $sharing) {
            ShareSheet(model: .workout(workout, gym: gym, health: workoutHealth))
        }
        .sheet(isPresented: $coaching) { WorkoutCoachSheet(workout: workout) }
    }
}
