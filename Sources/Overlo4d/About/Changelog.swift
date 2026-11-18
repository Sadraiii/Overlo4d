import SwiftUI
import Overlo4dKit

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
        ChangelogEntry(version: "0.15", date: DateComponents(year: 2026, month: 11, day: 18), changes: [
            "Fixed: a workout opened from Home could not be closed. Workouts and plans open like other screens again, with a back button and a swipe from the edge.",
            "Empty workout: start one straight from Home, under Start workout. The start sheet says \"Start empty workout\" when that is picked.",
            "History › + › Past workout adds a workout you did without the app: set the time, add exercises and sets, and save.",
        ]),
        ChangelogEntry(version: "0.14", date: DateComponents(year: 2026, month: 11, day: 18), changes: [
            "Shortcuts can now log for you: a glass of water, your body weight, reps on the rep counter, or a rest timer, without opening a screen. A short note confirms it. Links are in Settings › Siri and Shortcuts.",
            "With Open X-Callback URL in Shortcuts, the shortcut waits for Overlo4d and carries on afterwards, with what was logged as its result. Starting a plan by name works the same way.",
            "The workout bar above the tabs turns into the rest timer between sets, with a draining ring, the next exercise and the countdown, then a green \"Go\".",
            "The tab bar shrinks while you scroll down, so lists get more room.",
            "Dynamic Island tidied up: only small text sits beside the camera, and the set ring, exercise and time fit underneath.",
        ]),
        ChangelogEntry(version: "0.13", date: DateComponents(year: 2026, month: 11, day: 18), changes: [
            "Dynamic Island and Lock Screen: a ring drains around the rest timer, a paused rest shows the time left, and a saved workout leaves a short summary on the Lock Screen for 15 minutes. Tapping it opens the workout you're doing, not Home.",
            "Switch the Lock Screen and Dynamic Island off in Settings › Training if you'd rather not see them.",
            "Rest timer: a ring shows the time left, and when it runs out it turns green and says \"Rest over\" before sliding away. Its sound can be turned off in Settings; the phone still vibrates.",
            "Finishing a workout fades into the summary: the numbers count up, new records are called out at the top, and a firmer tap tells you it's saved.",
            "Sets, drop sets, warm-ups and exercises slide in and out, and \"Up next\" moves to the next exercise smoothly.",
            "Workout and plan cards grow into their screens and press in when touched. Buttons fade when they can't be used, and the number you're typing in is outlined.",
            "With Reduce Motion on, all of this fades instead of moving.",
        ]),
        ChangelogEntry(version: "0.12", date: DateComponents(year: 2026, month: 11, day: 14), changes: [
            "Kilograms or pounds: pick your unit in Settings › Units. Every weight, the suggestions, the plate calculator (45 lb bar and plates), the 1RM table and programs follow it. Your log stays as it is.",
            "Cardio: log a run, walk, ride, row, swim and more from Home or History with time, distance, effort and a note. Pace or speed and calories are worked out for you, and sessions count towards your week and streak.",
            "Cardio is saved to Apple Health as the right kind of workout, with its distance. Health asks once for permission to write distance.",
            "Undo in History: swipe a workout or cardio session away and you get a few seconds to put it back.",
            "Prediction on every lift: where your estimated 1RM is heading in 4 and 12 weeks, when you reach the next round number, and which sets would beat your record today.",
            "Deload weeks: Home tells you when one is due, after many hard weeks in a row, lifts slipping back or very high effort. Start it and for seven days workouts begin with fewer sets and suggest about 10% less weight.",
            "Coach report: each weekly recap opens with a score, what went well, what to keep an eye on and up to three things to do next week. It needs no AI key and works offline.",
            "Reminders in Settings: choose your training days and a time, get a nudge after a break of your choosing, and a note when the weekly report is ready. Today's reminder is skipped once you have trained.",
            "Import from Strong, Hevy or an Overlo4d spreadsheet in Settings › Your data. You see what will be added first, workouts already in your log are skipped, and unknown exercises become your own.",
            "Siri and Shortcuts: links in Settings start a workout, a plan by name, the cardio log, the rep counter and more from the Shortcuts app, the Action Button or by voice.",
            "Hold the app icon on the Home Screen for Start workout, Log cardio and Rep counter.",
            "The exercise figure moves more naturally. Knees, hips and elbows bend in one smooth line with no seams, and each rep starts and stops gently with a short pause at both ends.",
        ]),
        ChangelogEntry(version: "0.11", date: DateComponents(year: 2026, month: 11, day: 12), changes: [
            "Progression: each exercise shows what to aim for today from your last sessions. More weight once every set hit its reps, the same weight while reps are missing, one more go after a max-effort set, and 10% lighter after three stuck sessions. Tap Use to fill the sets.",
            "The step follows the equipment (2.5 kg on bars, 2 kg on dumbbells, 5 kg on heavy machines), or pick your own in Settings › Training, where suggestions can also be switched off.",
            "The Previous column now pairs warm-ups with warm-ups and working sets with working sets, so an extra warm-up no longer shifts every row.",
            "Minus and plus buttons above the keyboard change the weight or reps one step at a time, starting from last time's value.",
            "Rest timer: pause and resume, +15 and +30, a bar for the time left and what comes next. It keeps its end time, so it is right again after the app was closed, and it ends on any screen.",
            "Supersets of three are called giant sets and four or more circuits, each with a letter (Superset A). After every set the next exercise is marked Up next and scrolled into view.",
            "Jump to any exercise from the list button at the top of a workout, with the sets done for each.",
            "Add a drop set from the set number menu: it lands right after the set, about 20% lighter.",
            "Finish no longer asks when every set is ticked off, and says how many sets are left when some aren't.",
            "Typing in a workout no longer rewrites the whole log on every key; ticked sets are still saved at once.",
            "Add set copies assistance and distance too.",
            "Up next on Home and in the start sheet: the plan that has waited longest and whose muscles are rested.",
            "Ready-made routines in Plans: full body, upper / lower, push / pull / legs, dumbbells only and bodyweight. Each adds one plan per day, starting from the weights you last lifted.",
            "Weekly goal: set how many workouts you aim for in Settings › Training and see it on the week card.",
            "Progress › Trends: pick 4 weeks, 12 weeks, 6 months or a year and see workouts, volume, sets, records and session length against the same time before, the estimated 1RM of your most trained lifts, how your sets split over push, pull, legs and core, and workouts per month.",
            "The workout summary compares volume, sets and time with the last session of the same plan.",
            "Edit Home: hide cards you don't use and drag the rest into your order.",
            "The body figure is redrawn: a smooth outline with separate heads for the quads, hamstrings, calves, forearms and triceps, plus collarbones, kneecaps and spine.",
            "Worked muscles pulse on the exercise screen and when you pick a muscle on the workout card, the primary ones hardest. Still when Reduce Motion is on.",
            "The animated exercise figure is now a muscled body instead of a stick figure. It shows the primary, secondary and tertiary muscles in colour, glowing as the lift gets heavy, and moves the way the lift is done: bar over the midfoot in squats and deadlifts, a straight bar path in presses and rows, elbows tucked on the bench.",
            "Peptides, in Settings › Private: a reconstitution calculator for U-100 syringes (concentration, amount per unit, units to draw, portions per vial) with a syringe gauge, a log with site rotation, vial countdown and its own JSON export and import. It stays out of widgets, the coach and the iCloud backup.",
        ]),
        ChangelogEntry(version: "0.10", date: DateComponents(year: 2026, month: 11, day: 7), changes: [
            "Recovery: Home shows which muscles are still recovering and what's ready to train, on the body figure. Tap it for every muscle with the time it's ready again.",
            "Milestones for workouts, weight lifted, time trained, best streak and records, each with levels and how far you are from the next. New ones show on the workout summary.",
            "Consistency: the last six months of training days on one grid in Progress.",
            "Pin a note to an exercise (seat height, grip, cues) and see it every time you do it.",
            "Replace an exercise during a workout when the machine is taken, keeping the sets.",
            "Log effort as RPE on any set from the set number menu. It shows on the set and in History.",
            "The workout screen shows your totals on a card with a bar for how many sets are ticked off.",
            "New exercise demo style: an animated figure drawn in your accent colour, with the worked body parts lit up. Every built-in exercise has one, it works offline and in dark mode, and exercises you make get one when their name says what they are (squat, row, curl…).",
            "Switch between Figure, Photos and Drawings on the exercise screen, or pick your favourite in Settings › Exercise demos.",
            "Photos now fade smoothly between the start and end position, with a Start / End label.",
            "Exercise lists show a zoomed-in body figure with the trained muscles lit up, and name the primary muscles first and the secondary ones after.",
            "The exercise screen opens with What it trains: a large front and back figure with the muscles as coloured chips, then How to do it.",
            "Demos keep one size while loading or switching style, use less memory, and show a Try again button when a download fails.",
        ]),
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
            "Every built-in exercise (except burpees) now shows how it's done even without a key: start and end photos from the public-domain Free Exercise DB, flipping back and forth. The photos ship with the app, so they work offline.",
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
            "A Watch workout recorded during an Overlo4d workout is merged into it instead of being saved twice.",
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
