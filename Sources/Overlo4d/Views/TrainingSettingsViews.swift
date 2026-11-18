import SwiftUI
import Overlo4dCore
import Overlo4dKit
import UIKit
import WidgetKit

/// Kilograms or pounds for every weight in the app.
struct UnitsSettingsSection: View {
    @AppStorage(Units.key, store: SharedStorage.defaults) private var unit = WeightUnit.kg.rawValue
    @AppStorage("progression.step") private var step = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Units").eyebrow(11.5)
            HStack(spacing: 4) {
                ForEach(WeightUnit.allCases) { option in
                    let selected = unit == option.rawValue
                    Button("\(option.name) (\(option.label))") {
                        guard unit != option.rawValue else { return }
                        unit = option.rawValue
                        // A custom jump of 2.5 kg makes no sense in pounds: back to "by equipment".
                        step = 0
                        WidgetCenter.shared.reloadAllTimelines()
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
            Text("Your log is kept as it is and shown in the unit you pick. Body weight stays in kilograms.")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
        }
    }
}

/// Training-day reminders, a nudge after a break and the weekly report notification.
struct ReminderSettingsSection: View {
    @Environment(GymStore.self) private var gym
    @AppStorage(TrainingReminders.Keys.enabled) private var enabled = false
    @AppStorage(TrainingReminders.Keys.days) private var daysRaw = ""
    @AppStorage(TrainingReminders.Keys.minutes) private var minutes = TrainingReminders.defaultMinutes
    @AppStorage(TrainingReminders.Keys.nudgeDays) private var nudgeDays = 0
    @AppStorage(TrainingReminders.Keys.weeklyReport) private var weeklyReport = false

    private static let nudgeOptions = [0, 2, 3, 4, 5, 7]

    /// Weekdays in the calendar's order, as (weekday number, short name).
    private var weekdays: [(day: Int, name: String)] {
        let calendar = Calendar.current
        return (0..<7).map { offset in
            let day = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return (day, calendar.veryShortWeekdaySymbols[day - 1])
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
            set: { minutes = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
        )
    }

    var body: some View {
        let days = WorkoutReminders.decode(daysRaw)
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminders").eyebrow(11.5)
            VStack(spacing: 0) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training days").font(Typo.body(15, .semibold))
                        Text(enabled ? WorkoutReminders.summary(days) : "A reminder on the days you plan to train.")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .padding(14)
                if enabled {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack(spacing: 6) {
                        ForEach(weekdays, id: \.day) { weekday in
                            let selected = days.contains(weekday.day)
                            Button(weekday.name) {
                                var next = days
                                if selected { next.remove(weekday.day) } else { next.insert(weekday.day) }
                                daysRaw = WorkoutReminders.encode(next)
                            }
                            .font(Typo.body(14, .bold))
                            .foregroundStyle(selected ? Theme.accentInk : Theme.ink2)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(selected ? Theme.accent : Theme.fill, in: .circle)
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[weekday.day - 1])
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .font(Typo.body(15, .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack {
                    Text("After a break").font(Typo.body(15, .semibold))
                    Spacer()
                    Picker("After a break", selection: $nudgeDays) {
                        ForEach(Self.nudgeOptions, id: \.self) { value in
                            Text(value == 0 ? "Off" : "\(value) days without training").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $weeklyReport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly report").font(Typo.body(15, .semibold))
                        Text("A note when last week's report is ready.")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .padding(14)
            }
            .card(padding: 0, cornerRadius: 18)
        }
        .onChange(of: enabled) { _, isOn in
            if isOn {
                // Start with Monday, Wednesday and Friday rather than nothing.
                if WorkoutReminders.decode(daysRaw).isEmpty { daysRaw = "2,4,6" }
                TrainingReminders.requestPermission()
            }
            TrainingReminders.reschedule(gym: gym)
        }
        .onChange(of: daysRaw) { TrainingReminders.reschedule(gym: gym) }
        .onChange(of: minutes) { TrainingReminders.reschedule(gym: gym) }
        .onChange(of: nudgeDays) { _, value in
            if value > 0 { TrainingReminders.requestPermission() }
            TrainingReminders.reschedule(gym: gym)
        }
        .onChange(of: weeklyReport) { _, isOn in
            if isOn { TrainingReminders.requestPermission() }
            TrainingReminders.reschedule(gym: gym)
        }
    }
}

/// Links that start things from the Shortcuts app, and so from Siri.
struct ShortcutsSettingsSection: View {
    @Environment(GymStore.self) private var gym
    @Environment(RepModel.self) private var reps
    @State private var copied: String?

    private var screens: [(title: String, link: AppLink)] {
        var links: [(String, AppLink)] = [
            ("Start an empty workout", .start(plan: nil)),
            ("Open the running workout", .activeWorkout),
            ("Log cardio", .cardio),
            ("Rep counter", .reps),
            ("Food diary", .food),
            ("Plate calculator", .plates),
            ("Timer", .timer),
            ("Weekly report", .report),
        ]
        links.insert(contentsOf: gym.plans.prefix(6).map { ("Start \($0.name)", AppLink.start(plan: $0.name)) }, at: 1)
        return links
    }

    /// Links that do the thing and leave the app as it was: good for automations and the Action Button.
    private var actions: [(title: String, link: AppLink, hint: String?)] {
        let exercise = reps.exercises.first?.name
        return [
            ("Drink a glass of water", .water(glasses: 1), nil),
            ("Log body weight", .weight(kg: 80), "Swap 80 for an Ask for Input number."),
            ("Start a 90 s rest", .rest(seconds: 90), "Shows on the Lock Screen if a workout is running."),
            ("Add 10 reps\(exercise.map { " of \($0)" } ?? "")", .addReps(count: 10, exercise: exercise), nil),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Siri and Shortcuts").eyebrow(11.5)
            VStack(alignment: .leading, spacing: 0) {
                Text("In the Shortcuts app, add the action Open URLs and paste one of these links. Name the shortcut, for example Start workout, and Siri runs it when you say its name. It also works from the Action Button, the Lock Screen and automations.")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                    .padding(14)
                ForEach(screens, id: \.title) { item in
                    row(item.title, item.link, hint: nil)
                }
            }
            .card(padding: 0, cornerRadius: 18)

            Text("Log without opening a screen").eyebrow(11.5)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                Text("These log straight away and show a short note. Use Open X-Callback URL instead of Open URLs and the shortcut goes on afterwards, with what was logged as its result.")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                    .padding(14)
                ForEach(actions, id: \.title) { item in
                    row(item.title, item.link, hint: item.hint)
                }
            }
            .card(padding: 0, cornerRadius: 18)

            Text("Hold the app icon on the Home Screen for Start workout, Log cardio and Rep counter.")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    private func row(_ title: String, _ link: AppLink, hint: String?) -> some View {
        let url = link.url?.absoluteString ?? ""
        let isCopied = copied == url
        return VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Button {
                UIPasteboard.general.string = url
                Motion.animate(Motion.tap) { copied = url }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                        Text(url)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let hint {
                            Text(hint)
                                .font(Typo.body(12))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    Spacer(minLength: 8)
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(Typo.body(13, .bold))
                        .foregroundStyle(isCopied ? Theme.good : Theme.accent)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
