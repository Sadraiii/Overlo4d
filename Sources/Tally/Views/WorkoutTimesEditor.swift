import SwiftUI
import TallyCore
import TallyKit

/// Date, start, end and duration rows for a workout. Moving the date or start keeps the duration.
struct WorkoutTimesRows: View {
    @Binding var workout: Workout
    /// A workout in progress can't start in the future, and ends when Finish is tapped unless an end is set.
    var isLive = false

    private var times: WorkoutTimes { WorkoutTimes(start: workout.startedAt, end: workout.endedAt) }

    var body: some View {
        DatePicker(
            "Date",
            selection: Binding(get: { workout.startedAt }, set: { apply(times.movedToDay($0)) }),
            in: ...Date.now,
            displayedComponents: .date
        )
        DatePicker(
            "Start",
            selection: Binding(get: { workout.startedAt }, set: { apply(times.withStartTime($0)) }),
            displayedComponents: .hourAndMinute
        )
        if let end = workout.endedAt {
            DatePicker(
                "End",
                selection: Binding(get: { end }, set: { apply(times.withEndTime($0)) }),
                displayedComponents: .hourAndMinute
            )
            if !Calendar.current.isDate(end, inSameDayAs: workout.startedAt) {
                Text("Ends the next day, \(end.formatted(.dateTime.weekday(.wide).day().month()))")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
            }
            LabeledContent("Duration") {
                TimeField(
                    seconds: Binding(
                        get: { times.duration.map { Int($0) } },
                        set: { if let seconds = $0 { apply(times.withDuration(TimeInterval(seconds))) } }
                    ),
                    placeholder: "h:mm:ss"
                )
                .frame(width: 130)
            }
            if isLive {
                Button("End when I tap Finish", systemImage: "arrow.uturn.backward") { workout.endedAt = nil }
            }
        } else if isLive {
            Button("Set end time", systemImage: "flag.checkered") {
                apply(times.withDuration(Date.now.timeIntervalSince(workout.startedAt)))
            }
        }
    }

    private func apply(_ new: WorkoutTimes) {
        let new = isLive ? new.clampedForLiveWorkout(now: .now) : new
        workout.startedAt = new.start
        workout.endedAt = new.end
        workout.timesEdited = true
    }
}

/// Fix the times of the workout in progress, e.g. when it was started late or finished earlier.
struct WorkoutTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var workout: Workout

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkoutTimesRows(workout: $workout, isLive: true)
                } footer: {
                    Text(workout.endedAt == nil
                         ? "The workout ends when you tap Finish. Set an end time if you finished earlier."
                         : "The workout is saved with this end time when you tap Finish.")
                }
                .font(Typo.body(15))
                .cardRow()
            }
            .screenBackground()
            .navigationTitle("Workout time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
