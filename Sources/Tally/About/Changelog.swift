import SwiftUI
import TallyKit

enum AppVersion {
    /// Release stage shown after the version number.
    static let stage = "Beta"
    static var number: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–" }
    /// "0.5 Beta"
    static var display: String { "\(number) \(stage)" }
}

struct ChangelogEntry: Identifiable {
    var id: String { version }
    let version: String
    let date: DateComponents
    let changes: [String]
}

/// What changed in each build. Add an entry, and bump the version in both Info.plists, for every release.
enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "0.8", date: DateComponents(year: 2026, month: 10, day: 27), changes: [
            "Sleep: naps are kept apart from the night, so a nap on the sofa no longer spoils the score.",
            "Nights are tagged for you from late workouts, big late meals and late coffee in the food diary.",
            "See how much more you lift after a good night than after a short one.",
            "Spots weekend lie-ins that throw your body clock off on Mondays.",
            "Optional morning check-in and caffeine cut-off reminders.",
        ]),
        ChangelogEntry(version: "0.7", date: DateComponents(year: 2026, month: 10, day: 26), changes: [
            "Food tracker: log breakfast, lunch, dinner and snacks, with calories and macros left for the day.",
            "Search millions of foods from Open Food Facts, or scan a barcode.",
            "Calorie and macro goals worked out from your body, activity and goal. Exercise from Apple Health adds to the day.",
            "Quick add, your own foods, copy a meal from yesterday, a water tracker and the last 7 days.",
            "Sleep: nights from Apple Health with stages and a sleep score, or tap Good night and I'm up, or log them yourself.",
            "A sleep goal and alarm time set your bedtime, with wind-down and bedtime reminders and a wind-down checklist.",
            "Tag nights (late caffeine, late workout…) to see what helps you sleep, and get tips from the last two weeks.",
            "Last night's sleep tells you whether to train as planned or go lighter, and the AI coach can review your sleep.",
        ]),
        ChangelogEntry(version: "0.6", date: DateComponents(year: 2026, month: 10, day: 16), changes: [
            "Supersets: link exercises so the rest timer starts after the last one.",
            "New exercise types: weighted and assisted bodyweight, and distance with time and pace.",
            "Time is entered like a timer: type 2500 for 25:00.",
            "Workouts from Apple Watch and other apps show in History and the calendar.",
            "A Watch workout recorded during a Tally workout is merged into it instead of being saved twice.",
            "Weekly recap on Home each Monday, and for past weeks in Progress.",
        ]),
        ChangelogEntry(version: "0.5", date: DateComponents(year: 2026, month: 10, day: 15), changes: [
            "Plans have their own tab.",
            "Reps moved to a card on Home. Tap it for the counter.",
            "126 exercises, up from 54, with machine, cable and Smith machine versions.",
            "Each exercise shows the muscles it works on a front and back figure.",
            "Create, edit and delete your own exercises. Pick their muscles on the figure.",
            "Filter exercises by muscle group and equipment.",
            "Progress shows which muscles you trained in the last 30 days.",
            "Version number and changelog in Settings.",
            "Less text on Home, plans and exercises. Exercise notes are added from the menu.",
        ]),
        ChangelogEntry(version: "0.4", date: DateComponents(year: 2026, month: 10, day: 15), changes: [
            "Plans: saved workouts that compare each set with the last session.",
            "Suggested weight based on last time.",
            "Interval timer and plate calculator.",
            "Month calendar in History.",
        ]),
        ChangelogEntry(version: "0.3", date: DateComponents(year: 2026, month: 10, day: 15), changes: [
            "New name and icon.",
            "Apple Health: steps, energy and body weight. Workouts are saved to Health.",
            "Share workouts, weeks and reps as Instagram stories.",
        ]),
        ChangelogEntry(version: "0.2", date: DateComponents(year: 2026, month: 10, day: 15), changes: [
            "Workout logging with sets, rest timer, records, history and progress charts.",
            "New design with accent colours and dark mode.",
            "Live Activity and training widget.",
        ]),
        ChangelogEntry(version: "0.1", date: DateComponents(year: 2026, month: 10, day: 15), changes: [
            "Rep counter with home and lock screen widgets.",
        ]),
    ]
}

struct ChangelogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Changelog.entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(entry.version) \(AppVersion.stage)").display(26)
                            if entry.version == AppVersion.number {
                                StatusPill(text: "Installed")
                            }
                            Spacer()
                            if let date = Calendar.current.date(from: entry.date) {
                                Text(date.formatted(.dateTime.day().month(.abbreviated).year())).eyebrow(10.5)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entry.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 8)
                                    Text(change)
                                        .font(Typo.body(15))
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The changelog on its own, opened from the update banner on Home.
struct ChangelogSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChangelogView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                }
        }
    }
}

/// Version and changelog link in Settings.
struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About").eyebrow(11.5)
            VStack(spacing: 0) {
                HStack {
                    Text("Version").font(Typo.body(15, .semibold))
                    Spacer()
                    Text("\(AppVersion.display) (\(AppVersion.build))")
                        .font(Typo.body(15))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(14)
                Rectangle().fill(Theme.line).frame(height: 1)
                NavigationLink {
                    ChangelogView()
                } label: {
                    HStack {
                        Text("Changelog").font(Typo.body(15, .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}
