import SwiftUI
import TallyCore
import TallyKit

/// How it felt (1–5) and what happened that evening.
struct CheckInFields: View {
    @Binding var checkIn: SleepCheckIn
    /// Tags worked out from workouts and food; on unless the user turns them off.
    var autoTags: [String] = []

    private static let labels = ["Awful", "Poor", "OK", "Good", "Great"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How did you sleep?").eyebrow(11.5)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { value in
                        let selected = checkIn.quality == value
                        Button {
                            checkIn.quality = selected ? nil : value
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(value)").font(Typo.display(22))
                                Text(Self.labels[value - 1]).font(Typo.body(11, .semibold))
                            }
                            .foregroundStyle(selected ? Theme.accentInk : Theme.ink2)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(selected ? Theme.accent : Theme.card, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? .clear : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: selected)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What happened that evening?").eyebrow(11.5)
                FlowLayout(spacing: 8) {
                    ForEach(SleepStore.suggestedTags, id: \.self) { tag in
                        let isAuto = autoTags.contains(tag)
                        let selected = checkIn.tags.contains(tag) || (isAuto && !checkIn.dismissed.contains(tag))
                        Button {
                            toggle(tag, selected: selected, isAuto: isAuto)
                        } label: {
                            HStack(spacing: 5) {
                                if isAuto { Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)) }
                                Text(tag)
                            }
                        }
                        .font(Typo.body(13.5, .semibold))
                        .foregroundStyle(selected ? Theme.accentInk : Theme.ink2)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(selected ? Theme.accent : Theme.card, in: .capsule)
                        .overlay(Capsule().strokeBorder(selected ? .clear : Theme.line, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
                Text("Tags let the app work out what helps you sleep. Ones with \(Image(systemName: "sparkles")) are filled in from your workouts and food diary, and \"\(SleepStore.windDownTag)\" is added when you tick off the whole wind-down routine.")
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(_ tag: String, selected: Bool, isAuto: Bool) {
        if selected {
            checkIn.tags.removeAll { $0 == tag }
            if isAuto, !checkIn.dismissed.contains(tag) { checkIn.dismissed.append(tag) }
        } else if isAuto {
            checkIn.dismissed.removeAll { $0 == tag }
        } else {
            checkIn.tags.append(tag)
        }
    }
}

/// Log a night by hand, or edit one logged earlier.
struct SleepLogSheet: View {
    @Environment(SleepStore.self) private var sleep
    @Environment(\.dismiss) private var dismiss
    let entry: ManualSleep?

    @State private var bedtime: Date
    @State private var wake: Date
    @State private var awakeMinutes: Int
    @State private var checkIn = SleepCheckIn()

    private static let awakeOptions = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    init(entry: ManualSleep?) {
        self.entry = entry
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let defaultWake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? today
        let defaultBed = calendar.date(byAdding: .hour, value: -8, to: defaultWake) ?? today
        _bedtime = State(initialValue: entry?.bedtime ?? defaultBed)
        _wake = State(initialValue: entry?.wake ?? min(defaultWake, .now))
        _awakeMinutes = State(initialValue: entry?.awakeMinutes ?? 15)
    }

    var body: some View {
        let length = wake.timeIntervalSince(bedtime)
        let valid = length > 0 && length < 20 * 3600

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 0) {
                        DatePicker("In bed", selection: $bedtime, in: ...Date.now)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        DatePicker("Woke up", selection: $wake, in: ...Date.now)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        HStack {
                            Text("Awake in the night")
                            Spacer()
                            Picker("Awake in the night", selection: $awakeMinutes) {
                                ForEach(Self.awakeOptions, id: \.self) { Text("\($0) min").tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .font(Typo.body(15, .semibold))
                    .card(padding: 0, cornerRadius: 18)

                    if valid {
                        Text("\(Fmt.sleep(max(0, length - Double(awakeMinutes) * 60))) asleep, including time to fall asleep.")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink2)
                    } else {
                        Text("Wake-up has to be after bedtime, within 20 hours.")
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.danger)
                    }

                    CheckInFields(checkIn: $checkIn, autoTags: sleep.autoTags(bedtime: bedtime))
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(entry == nil ? "Log sleep" : "Edit sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        var log = entry ?? ManualSleep(bedtime: bedtime, wake: wake)
                        log.bedtime = bedtime
                        log.wake = wake
                        log.awakeMinutes = awakeMinutes
                        // Edited by hand now, so it's no longer a tapped estimate.
                        log.tapped = false
                        sleep.log(log)
                        sleep.setCheckIn(checkIn, for: SleepAnalysis.day(for: bedtime))
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear { checkIn = sleep.checkIn(for: SleepAnalysis.day(for: bedtime)) }
        }
        .presentationDetents([.large])
    }
}

/// One night: summary, check-in, and edit or delete for hand-logged nights.
struct NightSheet: View {
    @Environment(SleepStore.self) private var sleep
    @Environment(\.dismiss) private var dismiss
    let night: SleepNight
    let onEdit: (ManualSleep) -> Void

    @State private var checkIn = SleepCheckIn()
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.sleep(night.asleep)).font(Typo.display(40)).monospacedDigit()
                        Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wake.formatted(date: .omitted, time: .shortened)) · \(night.isManual ? "logged by you" : "Apple Health")")
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink2)
                    }
                    if !night.segments.isEmpty {
                        StageBar(night: night)
                    }

                    CheckInFields(checkIn: $checkIn, autoTags: sleep.autoTags(for: night))

                    if let log = sleep.log(for: night) {
                        HStack(spacing: 8) {
                            Button("Edit times", systemImage: "pencil") {
                                save()
                                onEdit(log)
                            }
                            .buttonStyle(OOButtonStyle(kind: .outline, fullWidth: true))
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                                .buttonStyle(OOButtonStyle(kind: .danger, fullWidth: true))
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(night.day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this night?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    sleep.deleteLog(for: night)
                    dismiss()
                }
            }
            .onAppear { checkIn = sleep.checkIn(for: night.day) }
        }
        .presentationDetents([.large])
    }

    private func save() {
        // The automatic wind-down tag isn't stored; it's worked out from the routine.
        var stored = checkIn
        stored.tags.removeAll { $0 == SleepStore.windDownTag }
        sleep.setCheckIn(stored, for: night.day)
    }
}

/// Sleep goal, alarm time, reminders and the wind-down routine.
struct SleepSettingsSheet: View {
    @Environment(SleepStore.self) private var sleep
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var newStep = ""

    private static let goals = stride(from: 6.0, through: 10.0, by: 0.25).map { $0 }
    private static let windDowns = [15, 30, 45, 60, 90]

    var body: some View {
        @Bindable var sleep = sleep

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule").eyebrow(11.5)
                        VStack(spacing: 0) {
                            HStack {
                                Text("Sleep goal")
                                Spacer()
                                Picker("Sleep goal", selection: $sleep.goalHours) {
                                    ForEach(Self.goals, id: \.self) { Text(Fmt.sleep($0 * 3600)).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            Rectangle().fill(Theme.line).frame(height: 1)
                            DatePicker("Alarm", selection: wakeBinding, displayedComponents: .hourAndMinute)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            Rectangle().fill(Theme.line).frame(height: 1)
                            HStack {
                                Text("Bedtime")
                                Spacer()
                                Text(SleepStore.clock(sleep.bedtimeMinutes)).foregroundStyle(Theme.ink2)
                            }
                            .padding(14)
                        }
                        .font(Typo.body(15, .semibold))
                        .card(padding: 0, cornerRadius: 18)
                        Text("Bedtime is your alarm minus the goal and 15 minutes to fall asleep. Most adults need 7 to 9 hours. Keep the same alarm on weekends.")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reminders").eyebrow(11.5)
                        VStack(spacing: 0) {
                            Toggle("Wind-down and bedtime", isOn: $sleep.remindersOn)
                                .padding(14)
                            Rectangle().fill(Theme.line).frame(height: 1)
                            HStack {
                                Text("Wind down")
                                Spacer()
                                Picker("Wind down", selection: $sleep.windDownMinutes) {
                                    ForEach(Self.windDowns, id: \.self) { Text("\($0) min before").tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            Rectangle().fill(Theme.line).frame(height: 1)
                            Toggle("Morning check-in", isOn: $sleep.morningCheckInOn)
                                .padding(14)
                            Rectangle().fill(Theme.line).frame(height: 1)
                            Toggle("Caffeine cut-off", isOn: $sleep.caffeineReminderOn)
                                .padding(14)
                        }
                        .font(Typo.body(15, .semibold))
                        .card(padding: 0, cornerRadius: 18)
                        Text("Morning check-in asks how you slept 30 minutes after your alarm. Caffeine cut-off comes at \(SleepStore.clock(sleep.bedtimeMinutes - 8 * 60)), 8 hours before bed.")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wind-down routine").eyebrow(11.5)
                        VStack(spacing: 0) {
                            ForEach(sleep.steps) { step in
                                HStack {
                                    Text(step.title).font(Typo.body(15))
                                    Spacer()
                                    Button("Remove", systemImage: "minus.circle.fill") { sleep.deleteStep(step) }
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(Theme.danger)
                                        .buttonStyle(.plain)
                                }
                                .padding(14)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                            HStack {
                                TextField("Add a step", text: $newStep)
                                    .font(Typo.body(15))
                                    .onSubmit(addStep)
                                Button("Add", systemImage: "plus.circle.fill", action: addStep)
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(Theme.accent)
                                    .buttonStyle(.plain)
                                    .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(14)
                        }
                        .card(padding: 0, cornerRadius: 18)
                    }

                    if health.isAvailable {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Apple Health").eyebrow(11.5)
                            if health.isConnected {
                                Text("Sleep comes from Health: an Apple Watch worn to bed records stages, and an iPhone sleep schedule records time in bed. Check access in Health › Profile › Apps › Overload.")
                                    .font(Typo.body(13))
                                    .foregroundStyle(Theme.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Button("Connect Apple Health") { Task { await health.connect() } }
                                    .buttonStyle(OOButtonStyle(kind: .outline, fullWidth: true))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Sleep settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: {
                let time = SleepClock.timeOfDay(minutes: Double(sleep.wakeMinutes))
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                sleep.wakeMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func addStep() {
        sleep.addStep(newStep)
        newStep = ""
    }
}
