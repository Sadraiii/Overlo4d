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
        ChangelogEntry(version: "0.9", date: DateComponents(year: 2026, month: 10, day: 30), changes: [
            "Widgets: redrawn in the new look, with a large Training widget (last workout and 8 weeks of training) and a large Food widget (calories, macros, water and fast).",
            "Lock Screen: new Training inline and week-ring widgets, and all widgets stay readable when the Home Screen is tinted or clear and in StandBy.",
            "Widgets: the streak now ends on its own if you miss a week, and the Food widget no longer refreshes over and over.",
            "Body: log waist, chest, hips, arms, thighs, calves, neck, shoulders and body fat, with a chart and the change for each.",
            "Pick which measurements you track, with how-to-measure tips. Body fat and waist sync with Apple Health.",
            "Progress photos: front, side and back, from the camera or your library, with last time's photo shown to line up the pose. Kept in the app only.",
            "Compare two days side by side or with a slider, see how weight and measurements changed in between, and share the before and after.",
            "Ask the coach can read your measurements.",
            "Food: a Nutrition screen for the day or the last 7 days, with your macro split against the goal and fibre, sugar, saturated fat and salt against daily guidelines.",
            "Foods get a rating dot (great, good, OK now and then, best kept small) in search and on the food screen.",
            "Saturated fat and salt are read from Open Food Facts, USDA and Spoonacular, and can be typed in for your own foods.",
            "The week chart shows how far over or under your goal and maintenance you were, and the weight change that adds up to.",
            "Food goals show your daily deficit and the date you'd reach your goal weight.",
            "New look: cleaner white cards, sentence-case headings, a calmer Home with a greeting, a simpler week card, one row of tools and Today and Training sections.",
            "Exercise animations from Workout API: add your key in Settings to see how each exercise is done on its screen, as a still in exercise lists, and in a sheet from the badge during a workout. Switch between Movement and Muscles, or pick a different animation if the match is off. Each one is downloaded once and kept on the phone.",
            "Muscle view remade: the body is one soft figure, muscles are shaded in your accent colour (primary, secondary, tertiary), and the Muscles worked card has a bigger figure with sets bars. Tap a muscle on the figure or in the list to pick it out.",
        ]),
        ChangelogEntry(version: "0.8", date: DateComponents(year: 2026, month: 10, day: 27), changes: [
            "Sleep: naps are kept apart from the night, so a nap on the sofa no longer spoils the score.",
            "Nights are tagged for you from late workouts, big late meals and late coffee in the food diary.",
            "See how much more you lift after a good night than after a short one.",
            "Spots weekend lie-ins that throw your body clock off on Mondays.",
            "Optional morning check-in and caffeine cut-off reminders.",
            "Exercise details: primary, secondary and tertiary muscles each in their own colour on the body figure, plus grip and force type.",
            "Ask the coach: chat with the AI coach. It looks up your workouts, progress, plans, sleep and food itself, and can propose plan changes you apply with one tap.",
            "Food search adds everyday foods from USDA FoodData Central, with lab-measured nutrition.",
            "Recipes from Spoonacular with calories and macros per serving. Log a serving in one tap (needs a free key).",
            "Save a meal you eat often and log it again in one tap.",
            "Weight: log it or use Apple Health, set a goal weight, and see your trend and when you'll reach it.",
            "Food can be saved to Apple Health, and the AI coach now looks at your calories and protein.",
            "Optional reminders to log breakfast, lunch and dinner.",
            "Danish products: packaged-food search can show only products sold in Denmark, with Danish names.",
            "Fasting timer with 12:12 to 20:4 and one-meal-a-day plans. Logging food ends the fast.",
            "Food widget for the home and lock screen: calories left, macros, water and your fast.",
            "Strength programs: Juggernaut 16 weeks, a 4–8 week block, or one the AI coach writes for you, with phases, deloads and the weights filled in for every day.",
            "Rep-out sets in a program raise your training max for the next weeks automatically.",
            "Edit a program after making it: name, training maxes, day names and accessories.",
            "Ask the coach now knows your strength program and coaches within it.",
            "Workouts show the muscles they work on the body figure, with sets per muscle, while you train, on the summary and in History.",
            "Edit a workout's date, start, end and duration, during the workout (tap the start time) or later in History. Workouts past midnight are handled.",
            "Export: the training log shows sets per muscle group for each workout and the muscle group beside every exercise, marks edited times, and the export screen shows the muscles worked in the period.",
            "Rest timer on the lock screen and Dynamic Island: a big countdown with a bar that drains, the next exercise and set, and \"Rest over\" when it's time to lift, even with the app closed.",
            "Backup to iCloud Drive: pick a folder once and everything is backed up when you leave the app, so a new iPhone can restore it from Settings. Restores can be undone.",
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
            .card(padding: 0, cornerRadius: 18)
        }
    }
}
