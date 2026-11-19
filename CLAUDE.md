# Overlo4d: project guide for Claude

Read this first. It replaces re-exploring the repo. Facts here were checked against `main` at v0.11 (build 11), 2026-11-14. If code disagrees, trust the code and fix this file.

## What it is
A gym tracker for iPhone (iOS 26.1+, Liquid Glass), built by one person (mahmud, GitHub `Sadraiii`). It grew from a workout logger into a training + food + sleep + body app with an AI coach. Everything is stored on the phone; there is no account and no backend of its own (the optional coach server is the user's own Cloudflare Worker).

## Naming (important)
- Shown to the user as **Overlo4d** (4, not a). History: Tally → Overload → Overlo4d.
- Code names follow the app name since 2026-11-15: targets/modules `Overlo4d` (app), `Overlo4dKit`, `Overlo4dCore`, `Overlo4dWidget`; folders `Sources/Overlo4d*`, `Packages/Overlo4dCore`, `Support/Overlo4d*`. The tally-marks view is `TallyMarks` (it draws tally marks; not the old app name).
- **Kept on purpose, because changing them loses data on the phone. Don't rename unless asked:** bundle ID `com.mahmud.plusultra`; widget bundle ID `com.mahmud.plusultra.TallyWidget` (pinned with `bundleID:` in `xtool.yml`, otherwise xtool derives it from the product name and placed widgets vanish); App Group `group.com.mahmud.plusultra`; Keychain service `com.mahmud.tally.coach`; widget kinds `PlusUltraReps`, `PlusUltraTraining`, `OverloadFood`.
- URL scheme is `overlo4d://`; the old `tally://` is still registered and parsed (`AppLink.legacyScheme`) so old shortcuts keep working.
- Backups are named `Overlo4d Backup …json`; `BackupName.legacyPrefixes` still accepts `Overload Backup `.
- Repo: `github.com/Sadraiii/Overlo4d` (old `RepCounter` URL redirects; both clones in the cloud container are the same repo). The cloud clone folder may still be called `RepCounter`.

## Tech stack
- Swift 6 (tools 6.0), SwiftUI, Observation (`@Observable` stores), iOS 26.1 only. No third-party Swift packages. No Swift Anthropic SDK: the Claude API is called by raw HTTP.
- `Package.swift` (root) defines products `Overlo4d` (app) and `Overlo4dWidget` (extension) plus target `Overlo4dKit`; dependency `Packages/Overlo4dCore` (path).
- Built and installed with **xtool** (`xtool.yml`), not Xcode. The user runs it in WSL (Ubuntu 24.04) on a Windows PC: `xtool dev` at the repo root with the iPhone plugged in (usbipd-win passthrough, admin PowerShell). No Mac.
- xtool consequences: no App Intents metadata → **no interactive widgets / Live Activity buttons**; App Group ID is rewritten at signing (read it from `embedded.mobileprovision`, see `SharedStorage.appGroupID`); no iCloud entitlement (backup uses a user-picked folder bookmark instead); the widget needs `-u _main` linker flag (see Package.swift).
- Fonts: Big Shoulders Display (numbers only) and Schibsted Grotesk (headings/body), in `Resources/Fonts`, registered at runtime by `Theme.swift`.
- Free Exercise DB photos (public domain, 239 files) bundled in `Resources/ExercisePhotos`.

## Layout
```
Package.swift, xtool.yml, Support/ (Info plists + entitlements, version lives here)
Sources/Overlo4d/         app (SwiftUI), ~19k lines, one folder per feature (below)
Sources/Overlo4dKit/      shared by app + widget: Theme, SharedStorage, snapshots, Live Activity attributes, SharedViews
Sources/Overlo4dWidget/   Training/Food/Reps widgets + workout Live Activity
Packages/Overlo4dCore/    pure-Swift logic + tests, builds and tests on Linux (7.5k lines, ~24 test files)
cloudflare/coach-mcp/  Cloudflare Worker (JS) = remote MCP server for the Claude connector; has npm tests
scripts/               anatomy.py (muscle figure), motion_figure.py (exercise figure parts), motion/ (pose dump, figure preview), mockups/*.html + render.js (README screenshots, GIF recorders), render-icons.sh
docs/images/           README mockup PNGs
.github/workflows/tests.yml   CI: `swift test` for Overlo4dCore in swift:6.1-noble
```
**Rule of thumb:** anything with logic goes in Overlo4dCore (testable, `public`, `Sendable`, Codable, no UIKit/SwiftUI/HealthKit); stores, views, HealthKit, Keychain, notifications go in `Sources/Overlo4d`.

## Tabs and app shell
`Overlo4dApp.swift`: `RootView` TabView with Home, Plans, Start (opens `WorkoutFlowView`; becomes a play icon while a workout is active), History, Progress. A `WorkoutAccessory` mini-bar shows the active workout and, between sets, the rest ring and countdown (inline placement shows just the time); the tab bar minimizes on scroll. Stores are `@State` in `Overlo4dApp` and injected via environment: `GymStore`, `CoachStore`, `FoodStore`, `SleepStore`, `BodyStore`, `ProgramStore`, `BackupStore`, `CoachCloudStore`. Deep links (`onOpenURL`): `overlo4d://reps`, `overlo4d://food`, `overlo4d://train`, `overlo4d://active` (see `AppLink`). Accent colour (10 choices) and light/dark/system are user settings (`Accent`, `AppearanceMode` in Overlo4dKit/Theme.swift, also in shared defaults for widgets).

## Data and storage
All JSON in the app's Documents folder unless noted. Every store loads at init and writes atomically; `StoreFile` (Overlo4dCore) keeps safety copies.
| File | Owner | Holds |
|---|---|---|
| `gym.json` | `GymStore` | `GymData`: exercises (`ExerciseDef`), finished `workouts`, `plans`, `activeWorkout`, `exerciseNotes` (pinned notes by exercise UUID string) |
| `food.json` | `FoodStore` | food log, own foods, water, goals, fasting, weights, recipes |
| `sleep.json` | `SleepStore` | hand-logged nights, tags, feelings |
| `body.json` | `BodyStore` | measurements (one `BodyEntry` per day) + photo metadata; photos are JPEGs (2048 px, file protection on) in `Documents/ProgressPhotos`, never in the photo library |
| `programs.json` | `ProgramStore` | strength programs and progress |
| `coach.json`, `coach-chat.json` | `CoachStore` / chat | saved feedback, chat transcripts |
| `peptides.json` | `PeptideStore` (created only while the tracker is open) | peptide profiles + log; deliberately **not** in `BackupStore.documentFiles`, widgets, coach or `CoachToolbox`; own JSON export/import |
| `reps.json`, `activity.json`, `food-widget.json` | App Group container (`SharedStorage`) | quick-rep counters and snapshots the widgets read |
| `exercises.json` + GIF/photo cache | `ExerciseMediaStore` (Caches-like folder) | Workout API catalogue and downloaded demos, fetched once |

Core model (`Gym/Models.swift`): `Workout` → `[WorkoutExercise]` (`exerciseID`, `restSeconds`, `notes`, `supersetID`) → `[WorkoutSet]` (`type` normal/warm-up/drop/failure, `weight`, `reps`, `seconds`, `assistance`, `meters`, `isDone`, `rpe`). `ExerciseDef` has `kind`, `equipment`, `primary/secondary/tertiaryMuscles`, `grip`, `force`. Weights are **kg only** (no lb support yet). `Workout.programDay` links to a program day; `linkedHealthID/savedHealthID` link Apple Health.

**Adding a field to a Codable model: make it optional or defaulted** so old `gym.json` and backups still decode.

UserDefaults settings (those that belong to the user are in `BackupStore.settingsKeys` and are backed up; add new ones there): `defaultRestSeconds`, `rest.autoStart`, `rest.sound`, `liveActivity.enabled`, `rest.endDate/total/pausedRemaining` (timer survives restarts), `training.weeklyGoal`, `progression.enabled`, `progression.step`, `home.layout`, `coach.goal`, `coach.model`, `sleep.*`, `clock.*`, `exerciseDemo.style`, `workoutapi.overrides/thumbnails/variant`, `coachCloud.*`, `backup.*`, `progress.range` (not backed up), `food.*`. Secrets (Anthropic key, Workout API key, USDA/Spoonacular keys, coach token) live in the **Keychain** (`Coach/Keychain.swift`), are never committed and are not backed up.

## Features and where they live
**Workouts** (`Views/ActiveWorkoutView`, `ExerciseEditorSection`, `SetRow`, `StartWorkoutSheet`, `ExercisePicker`; `Gym/GymStore`, `RestTimer`, `LiveActivityManager`)
- Active workout edits a local copy, pushed via `GymStore.updateActive`; typing is debounced (`saveSoon`, 0.8 s), ticks save at once, `flush()` when scenePhase leaves active.
- Supersets/giant sets/circuits (`Overlo4dCore/Supersets`), "Up next" scroll, jump menu, drop sets, RPE per set, pinned notes (`Views/PinnedNote`), replace exercise (only when no set done), keyboard −/+ steppers (`FocusedValues.fieldStepper` in SetRow, read only by `KeyboardStepperBar`; `FieldStepper` is Equatable by field id + label because its closure changes every update: in 0.13–0.15 the whole workout screen read it, the likely cause of the hangs on Finish/Minimize), set number fields format/parse through `NumberInput` (Overlo4dCore, tested: locale decimal mark, no grouping, showing a value never writes it back), Previous column (`PreviousSets.match`), finish summary (`WorkoutSummaryView`, compares with last same-plan session).
- Rest timer: pause/resume, ±15/+30, persisted end time, local notification (sound optional, `rest.sound`), `RestDock` with a progress ring and a 2.5 s green "Rest over" (`RestTimer.justFinished`).
- Live Activity (`Gym/LiveActivityManager`, `Overlo4dWidget/WorkoutLiveActivity`, `Overlo4dKit/WorkoutActivity`): one activity per workout; `ContentState.phase(isStale:)` gives training / resting / restPaused / restOver / finished. Rest end is the stale date, so "Rest over" shows without the app; countdowns are system timer views, so updates are sent only on real changes. Finishing ends it with a summary kept 15 min on the Lock Screen (`.after`); discarding ends it at once; a relaunch re-attaches by start time (`resume`). Taps open `overlo4d://active` (the running workout, never starts one) or History once finished. Off switch: `liveActivity.enabled`. Layout: expanded island has only small text beside the camera (workout name left, `phase.label` right); the big row sits in the bottom region (`ExpandedIsland`: `SetsRing` "7/18" | exercise + set line | `BigTime`, sized per phase because timer text takes its longest width), plus `RestBar` while resting. Compact times are right-aligned in fixed widths; `ContentState.setLine` reads "Set 3 of 4 · 80 kg × 8" from `nextTarget` (filled by the manager via `Fmt.set` once the set has values). The manager takes `exercises: (UUID) -> ExerciseDef?` (pass `gym.exercise(_:)`). New `ContentState` fields must be optional. No buttons in it (xtool has no App Intents).
- Progression assistant (`Overlo4dCore/Progression`): increase / add reps / hold / deload (−10% after 3 stuck sessions); step by equipment (2.5 kg bars, 2 kg dumbbells, 5 kg machines), overridable in Settings › Training.

**Plans and programs** (`Views/PlansTab`, `PlanDetailView`, `PlanTemplateViews`; `Program/*`; `Overlo4dCore/Program`, `ProgramCoach`, `PlanTemplates`, `UpNext`)
- Plans = saved workout templates. Ready-made routines (full body, upper/lower, PPL, dumbbells, bodyweight; names must exist in `ExerciseLibrary`). "Up next" = plan waited longest with rested muscles.
- Strength programs: Juggernaut, block, or coach-written; percentages of a training max (90% of 1RM), Squat/Bench/Deadlift/Press names in `Program.swift`; edited in `ProgramEditor`.

**History / Progress** (`HistoryView`, `MonthCalendar`, `RecordsView`, `ProgressTabView`, `TrendsViews`, `RecapView`, `MilestoneViews`, `RecoveryViews`; Overlo4dCore `Trends`, `Recap`, `Milestones`, `Recovery`, `Strength`)
- PRs (`RecordKind`), weekly recap, Trends (4w/12w/6m/1y vs previous period, est. 1RM per lift, push/pull/legs/core balance, per-month counts), milestones with tiers + longest streak + six-month consistency grid, muscle recovery (24 h + 6 h per hard set, clamp 24–72 h, sessions <12 h apart merge).

**Exercises and muscles** (`Exercises/*`, `Gym/ExerciseLibrary`, `Overlo4dCore/Motion`, `MotionLibrary`, `FreeExerciseDB`, `WorkoutAPI`; `scripts/anatomy.py`)
- `AnatomyFigure` draws front/back muscle figure from point lists generated by `scripts/anatomy.py` into `AnatomyShapes.swift`; roles primary/secondary/tertiary, per-muscle `shades:`, volume heat, animated contraction (off with Reduce Motion).
- Demos, in the user's chosen order (`ExerciseDemoStyle`): own animated anatomical figure (below), Workout API GIFs (needs key; name matcher in `ExerciseMediaStore`, cached), or Free Exercise DB photos (bundled + remote).
- Exercise figure: `Overlo4dCore/Motion` + `MotionLibrary` hold 80 `MotionMove` patterns (two poses of absolute segment angles, 0 up, 90 forward; `faceUp` for lying on the back, `straightHands` moves the hands in a straight line with the elbows following, `elbowOut` foreshortens the upper arm) and the move + `MotionLoad` of every built-in exercise. `MotionFigureView` bends the body pieces (`MotionShapes.swift`, point runs generated by `scripts/motion_figure.py`; side arm and leg each drawn whole and cut at the elbow/knee, front parts cut from `anatomy.py`) along `MotionChain` (Overlo4dCore): near a joint every point follows a curve from one bone to the next and the inside of a bend creases, so there are no seams or joint discs (shoulder → hip → knee → ankle is one chain from the side). Muscles in role colours, glowing toward the end pose; 60 fps. `MotionPattern.phase` rests 6% of each half-rep at both ends and eases with the minimum-jerk curve; keep `motionPhase`/`motionChain` in `scripts/mockups/motion-figure.js` in step with the Swift. After pose changes run `scripts/motion/dump.sh` (rewrites `scripts/mockups/motion-data.js`); `node scripts/mockups/exercise-gifs.js <folder> [light|dark] [name filter]` records a GIF per exercise (33 fps, 3 cs frames, 128-colour palette per GIF, about 0.6 MB each).
- Custom exercises via `ExerciseEditor` (muscles picked by tapping the figure).

**Food** (`Food/*`; Overlo4dCore `FoodDiary`, `Nutrition*`, `Fasting`, `CommonFoods`, `OpenFoodFacts`, `OnlineFoodSources`): Lifesum-style diary, calorie/macro goals from body+activity, barcode scan (`BarcodeScanner`), search Open Food Facts (no key), USDA FoodData Central and Spoonacular recipes (user's free keys), offline common foods, water, fasting timer, nutrition rating, weight log.

**Sleep** (`Sleep/*`; Overlo4dCore `Sleep`, `SleepInsights`, `SleepLinks`): Health stages + manual logging, sleep score, wind-down/bedtime reminders, caffeine cutoff, "Good night" buttons, tags linked to workouts/food, AI sleep review.

**Body** (`Body/*`; Overlo4dCore `Body`): measurements (body fat and waist also read from Health), progress photos front/side/back, side-by-side and slider compare. Photos are not in the iCloud backup.

**Health** (`Health/*`): HealthKit read (steps, energy, exercise minutes, sleep, weight, body fat, waist, workouts) and write (finished workouts); imports other apps' / Watch workouts, merges overlapping sessions (`Overlo4dCore/Overlap`, `HealthLinking`). Health access is re-granted on a new phone.

**Peptides** (`Peptides/*`; Overlo4dCore `Peptides`): private tracker opened only from Settings › Private (full-screen cover, Hide button closes it and Settings). `Reconstitution` maths for U-100 syringes (mg/mL = vial mg ÷ water mL; mcg per unit = mcg/mL ÷ 100; units = target mcg ÷ mcg per unit, rounded to the nearest 1 or 0.5 unit mark), `SyringeGauge` (Canvas), schedules, site rotation, vial countdown; no PIN (removed at the user's request), the screen only blanks in the app switcher. Ships no suggested amounts; keep it that way and keep it isolated from the rest of the app.

**Tools and extras**: `Tools/` plate calculator, 1RM calculator, stopwatch/countdown/intervals/EMOM; `QuickCount/` rep counter (Outdoor Office style, shared with the Reps widget); `Share/` story-style share cards (PNG), export to CSV/text/JSON (`Overlo4dCore/Export`); `About/Changelog.swift`; Edit Home sheet (`HomeLayout`, hide/reorder cards); Home is `Views/HomeTab` (greeting, week card with weekly goal, tool tiles, Today and Training sections).

**Widgets** (`Overlo4dWidget/*`): Training, Food, Reps; small/medium/large + lock-screen accessory + StandBy; tint-safe colours (`WidgetColors`). They read App Group JSON snapshots written by the app; app reloads timelines on going to background. Training shows the weekly goal from `ActivitySnapshot.weeklyGoal` (rewritten when the goal changes).

**Backup** (`Backup/*`, `Overlo4dCore/Backup`): one JSON of all data files + settings written to a user-picked folder (iCloud Drive) via security-scoped bookmark; automatic when leaving the app if data changed; restore on a new phone. Add any new data file to `BackupStore.documentFiles`.

## Integrations
| Service | Where | Notes |
|---|---|---|
| Anthropic Messages API | `Overlo4dCore/Coach`, `CoachChat`; `Coach/*` | user's own key in Keychain; default model `claude-haiku-5-5`, Sonnet/Opus selectable; feedback on workouts/overall/sleep, chat with tools (`CoachToolbox`), training-load overtraining check (`TrainingLoad`), program writing (`ProgramCoach`) |
| Cloudflare Worker MCP connector | `cloudflare/coach-mcp`, `Coach/CoachCloudStore`, `Overlo4dCore/CoachCloud` | no-API-key coaching via the user's Claude plan; app uploads its log to the user's Worker (KV); Claude reads it via a custom connector at `…/mcp/<token>`. Tools: `get_overview`, `get_workouts`, `get_exercise_history`, `search_exercises`, `get_weekly_sets`, `get_sleep/food/body`, `get_plans/programs`, `propose_plan_change`, `propose_program` (applied only on user tap). Cloudflare Root directory must be `cloudflare/coach-mcp`. First phone to connect claims the token |
| Open Food Facts | `Overlo4dCore/OpenFoodFacts` | barcode + search, no key |
| USDA FDC / Spoonacular | `Overlo4dCore/OnlineFoodSources` | user keys |
| Workout API (workoutapi.com) | `Overlo4dCore/WorkoutAPI`, `ExerciseMediaStore` | exercise GIFs, key in Settings, cached |
| Free Exercise DB | `Overlo4dCore/FreeExerciseDB` | public-domain photos |
| Apple Health / HealthKit | `Health/*` | entitlement in `Support/Overlo4d.entitlements` |
| iCloud Drive folder | `Backup/*` | no iCloud entitlement |

## Testing
- iOS builds can be checked on the user's PC when it is connected (Desktop Commander, PowerShell): `git pull --ff-only origin main` in `C:\Users\mahmu\Desktop\GitRepo\Overlo4d`, then `wsl -d Ubuntu-24.04 --cd /mnt/c/Users/mahmu/Desktop/GitRepo/Overlo4d -- bash -lc "xtool dev build"` (builds without a phone; leave the untracked `graphify-out/` alone).
- Only **Overlo4dCore builds on Linux**. The iOS targets (SwiftUI, HealthKit, ActivityKit, WidgetKit) cannot be compiled in the cloud container, so app-layer changes are checked by careful review only; flag that in your hand-off. Compile errors the user reports from `xtool dev` are most likely in recently added app-layer code.
- Run: `cd Packages/Overlo4dCore && swift test` (swift-testing; ~264+ tests). CI does the same.
- Cloud container has no `swift` and github/download.swift.org are blocked. Pull the toolchain from Docker Hub's registry API without docker: token from `auth.docker.io` (scope `repository:library/swift:pull`), manifest list for `library/swift:6.1-noble` → amd64 manifest → the ~900 MB layer, `tar -xzf` into a scratch dir, put `usr/bin` on PATH, then `swift test --scratch-path <scratch>/build` (Swift 6.1.3). If rate-limited (TOOMANYREQUESTS) use `https://mirror.gcr.io/v2/library/swift/...` (no token, same paths). Re-read the manifest each time; digests change. Don't run this from several threads at once.
- `scripts/motion/preview.sh page.html [squat,curl]` compiles `MotionFigureView.swift` and `MotionShapes.swift` against a small stand-in for SwiftUI (`scripts/motion/preview/`) that records Canvas drawing as SVG. It is a real Swift 6 type check of that code on Linux and shows what it draws; add to the stand-in when the figure code uses a new SwiftUI call. Name a few moves: the page of all 80 is hundreds of MB and too big for a browser. The same trick can check other Canvas-only code.
- Re-run only failing tests while fixing, then the full suite once.
- Worker: `cd cloudflare/coach-mcp && npm test`.
- README mockups are HTML rendered with Playwright: `scripts/mockups/render.js` (screens.html, widgets.html, muscle-gifs.js). Screenshots in README/docs are mockups, not simulator captures. Project files copies go under `/mnt/project-files/<topic>/`.

## Conventions
- **Motion** (`Views/Motion.swift`): use `Motion.tap` (presses, ticks), `.standard` (content changing in place), `.arrive` (things that appear), via `Motion.animate {}` which fades instead under Reduce Motion; transitions `.rise(reduceMotion:)`/`.pop(reduceMotion:)`; `.reveal(isShown, delay:)` for staggered entrances; `.buttonStyle(.pressable)` for tappable cards. No zoom navigation transitions: in 0.13 a workout zoomed open from Home (whose nav bar is hidden) had no way back, so pushes use the standard slide. No repeating SwiftUI animations (use symbol effects); keep frequent interactions instant.
- **Haptics**: `.sensoryFeedback` at the call site: `.selection` for picking or nudging a value, `.setDone` (success) for a ticked set, `.workoutDone` (heavy impact) for a saved workout, `.success` for other completions; the rest end plays a notification haptic from `RestTimer`.
- **UI**: `.card()` (white, radius 22, faint edge, soft shadow), `Theme.fill` for wells/badges, `.eyebrow()` for small sentence-case labels, headings Schibsted Grotesk bold in sentence case (`Typo.title`, `.display()` renders Grotesk). **Big Shoulders condensed only for numbers** (`Typo.display`). No all-caps headings, no ticket/bib styling. Colours via `Theme`/`Accent` tokens (light + dark), never hard-coded.
- User-facing copy says "Overlo4d". Plain, short sentences.
- Every release: bump version in **both** `Support/Overlo4d-Info.plist` and `Support/Overlo4dWidget-Info.plist` (version + build) and add a `Changelog.entries` item at the top (`About/Changelog.swift`). Currently 0.18 / 18, stage "Beta".
- New data file → add to `BackupStore.documentFiles`; new user setting → add to `BackupStore.settingsKeys`; new widget-visible data → App Group file via `SharedStorage`.
- Pure logic + tests in Overlo4dCore first, then wire UI. Keep structs `Sendable`; mind Swift 6 strict concurrency (stores are `@MainActor`).
- Don't add dependencies. Don't commit keys or tokens.
- Known gaps / ideas: body weight kg only, no watchOS app, no interactive widget buttons (xtool), progress photos not in backup.

## Git rules (the user's standing rules)
- **Commit straight to `main`. No branches, no PRs.** Always `git pull --rebase origin main` first: other Claude threads commit to main concurrently (e.g. muscle GIFs, new features).
- Commit messages are 1 to 5 lines. **No** Claude Code, Co-Authored-By or session attribution lines, no model names.
- Push with `git push origin main`; retry network errors with backoff.
- Pushes to main on GitHub trigger Cloudflare deploy of the Worker and the Overlo4dCore CI.

## Working with the user
mahmud is on a Windows PC only (no Mac). They can't see cloud-container output, so deliver previews as images/files in `/mnt/project-files/`. Verify claims before stating them; say plainly when app-layer code is uncompiled. Release notes the user reads are the `Changelog` entries.

## Added in 0.12 (app layer uncompiled, Overlo4dCore tested)
- **Units**: `Units.weight` (kg/lb, key `units.weight` in the App Group defaults, `SharedUnit` for widgets). Weights are always stored in kg. Show them with `Fmt.load` / `Fmt.mass` / `Fmt.volume`; `Fmt.weight` is a plain number formatter. Body weight is still kg only.
- **Cardio**: `CardioSession` (Overlo4dCore) in `gym.json` under `cardio`; `Views/CardioViews.swift`; saved to Health by `HealthManager.save(_: CardioSession)`.
- **Deload**: `Deload.assess` + `GymStore.deloadAdvice/startDeload` (`deload.start`), `DeloadCard` on Home. **Forecast**: `StrengthForecast`, `ForecastCard` on the exercise screen. **Weekly report**: `WeeklyReport.build`, `CoachReportCard` in the recap.
- **Reminders**: `Gym/TrainingReminders.swift` (keys `reminders.*`), rescheduled when the app opens or closes.
- **Import**: `WorkoutImport` (Strong, Hevy, own CSV), `Share/ImportSheet.swift`, `GymStore.importWorkouts`.
- **Links**: `AppLink` parses every `overlo4d://` (and old `tally://`) link (widgets, Home Screen menu in Info.plist, Shortcuts "Open URLs"). App Intents are not used: xtool doesn't generate their metadata.
- **Shortcuts actions (0.14)**: `overlo4d://water?glasses=|ml=`, `weight?kg=|lb=`, `reps?add=&exercise=`, `rest?seconds=` log straight away (`RootView.open` returns a `LinkOutcome`, shown as a `LinkNote` capsule); `AppLinkRequest` reads `x-success`/`x-error` (also the `overlo4d://x-callback-url/<action>` form) so Shortcuts' Open X-Callback URL resumes with `result`/`errorMessage`. Links are listed in Settings › Siri and Shortcuts (`ShortcutsSettingsSection`). Real App Intents would need xtool's draft PR #397 (parameterless intents only), not in a release as of v1.24.0.
