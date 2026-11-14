# Overlo4d: project guide for Claude

Read this first. It replaces re-exploring the repo. Facts here were checked against `main` at v0.11 (build 11), 2026-11-14. If code disagrees, trust the code and fix this file.

## What it is
A gym tracker for iPhone (iOS 26.1+, Liquid Glass), built by one person (mahmud, GitHub `Sadraiii`). It grew from a workout logger into a training + food + sleep + body app with an AI coach. Everything is stored on the phone; there is no account and no backend of its own (the optional coach server is the user's own Cloudflare Worker).

## Naming (important)
- Shown to the user as **Overlo4d** (4, not a). History: Tally → Overload → Overlo4d.
- Display name only. Code names stay: targets/modules `Tally`, `TallyKit`, `TallyCore`, `TallyWidget`; bundle ID `com.mahmud.plusultra`; App Group `group.com.mahmud.plusultra`; URL scheme `tally://`; widget kinds `PlusUltraReps`, `PlusUltraTraining`, `OverloadFood`. Changing them breaks installed data, widgets, deep links and old backups. Don't, unless asked.
- Backups are named `Overlo4d Backup …json`; `BackupName.legacyPrefixes` still accepts `Overload Backup `.
- Repo: `github.com/Sadraiii/Overlo4d` (old `RepCounter` URL redirects; both clones in the cloud container are the same repo). The shipped app still links the setup guide at the old RepCounter path.

## Tech stack
- Swift 6 (tools 6.0), SwiftUI, Observation (`@Observable` stores), iOS 26.1 only. No third-party Swift packages. No Swift Anthropic SDK: the Claude API is called by raw HTTP.
- `Package.swift` (root) defines products `Tally` (app) and `TallyWidget` (extension) plus target `TallyKit`; dependency `Packages/TallyCore` (path).
- Built and installed with **xtool** (`xtool.yml`), not Xcode. The user runs it in WSL (Ubuntu 24.04) on a Windows PC: `xtool dev` at the repo root with the iPhone plugged in (usbipd-win passthrough, admin PowerShell). No Mac.
- xtool consequences: no App Intents metadata → **no interactive widgets / Live Activity buttons**; App Group ID is rewritten at signing (read it from `embedded.mobileprovision`, see `SharedStorage.appGroupID`); no iCloud entitlement (backup uses a user-picked folder bookmark instead); the widget needs `-u _main` linker flag (see Package.swift).
- Fonts: Big Shoulders Display (numbers only) and Schibsted Grotesk (headings/body), in `Resources/Fonts`, registered at runtime by `Theme.swift`.
- Free Exercise DB photos (public domain, 239 files) bundled in `Resources/ExercisePhotos`.

## Layout
```
Package.swift, xtool.yml, Support/ (Info plists + entitlements, version lives here)
Sources/Tally/         app (SwiftUI), ~19k lines, one folder per feature (below)
Sources/TallyKit/      shared by app + widget: Theme, SharedStorage, snapshots, Live Activity attributes, SharedViews
Sources/TallyWidget/   Training/Food/Reps widgets + workout Live Activity
Packages/TallyCore/    pure-Swift logic + tests, builds and tests on Linux (7.5k lines, ~24 test files)
cloudflare/coach-mcp/  Cloudflare Worker (JS) = remote MCP server for the Claude connector; has npm tests
scripts/               anatomy.py (figure geometry), mockups/*.html + render.js (README screenshots), render-icons.sh
docs/images/           README mockup PNGs
.github/workflows/tests.yml   CI: `swift test` for TallyCore in swift:6.1-noble
```
**Rule of thumb:** anything with logic goes in TallyCore (testable, `public`, `Sendable`, Codable, no UIKit/SwiftUI/HealthKit); stores, views, HealthKit, Keychain, notifications go in `Sources/Tally`.

## Tabs and app shell
`TallyApp.swift`: `RootView` TabView with Home, Plans, Start (opens `WorkoutFlowView`; becomes a play icon while a workout is active), History, Progress. A `WorkoutAccessory` mini-bar shows the active workout. Stores are `@State` in `TallyApp` and injected via environment: `GymStore`, `CoachStore`, `FoodStore`, `SleepStore`, `BodyStore`, `ProgramStore`, `BackupStore`, `CoachCloudStore`. Deep links (`onOpenURL`): `tally://reps`, `tally://food`, `tally://train`. Accent colour (10 choices) and light/dark/system are user settings (`Accent`, `AppearanceMode` in TallyKit/Theme.swift, also in shared defaults for widgets).

## Data and storage
All JSON in the app's Documents folder unless noted. Every store loads at init and writes atomically; `StoreFile` (TallyCore) keeps safety copies.
| File | Owner | Holds |
|---|---|---|
| `gym.json` | `GymStore` | `GymData`: exercises (`ExerciseDef`), finished `workouts`, `plans`, `activeWorkout`, `exerciseNotes` (pinned notes by exercise UUID string) |
| `food.json` | `FoodStore` | food log, own foods, water, goals, fasting, weights, recipes |
| `sleep.json` | `SleepStore` | hand-logged nights, tags, feelings |
| `body.json` | `BodyStore` | measurements (one `BodyEntry` per day) + photo metadata; photos are JPEGs (2048 px, file protection on) in `Documents/ProgressPhotos`, never in the photo library |
| `programs.json` | `ProgramStore` | strength programs and progress |
| `coach.json`, `coach-chat.json` | `CoachStore` / chat | saved feedback, chat transcripts |
| `reps.json`, `activity.json`, `food-widget.json` | App Group container (`SharedStorage`) | quick-rep counters and snapshots the widgets read |
| `exercises.json` + GIF/photo cache | `ExerciseMediaStore` (Caches-like folder) | Workout API catalogue and downloaded demos, fetched once |

Core model (`Gym/Models.swift`): `Workout` → `[WorkoutExercise]` (`exerciseID`, `restSeconds`, `notes`, `supersetID`) → `[WorkoutSet]` (`type` normal/warm-up/drop/failure, `weight`, `reps`, `seconds`, `assistance`, `meters`, `isDone`, `rpe`). `ExerciseDef` has `kind`, `equipment`, `primary/secondary/tertiaryMuscles`, `grip`, `force`. Weights are **kg only** (no lb support yet). `Workout.programDay` links to a program day; `linkedHealthID/savedHealthID` link Apple Health.

**Adding a field to a Codable model: make it optional or defaulted** so old `gym.json` and backups still decode.

UserDefaults settings (those that belong to the user are in `BackupStore.settingsKeys` and are backed up; add new ones there): `defaultRestSeconds`, `rest.autoStart`, `rest.endDate/total/pausedRemaining` (timer survives restarts), `training.weeklyGoal`, `progression.enabled`, `progression.step`, `home.layout`, `coach.goal`, `coach.model`, `sleep.*`, `clock.*`, `exerciseDemo.style`, `workoutapi.overrides/thumbnails/variant`, `coachCloud.*`, `backup.*`, `progress.range` (not backed up), `food.*`. Secrets (Anthropic key, Workout API key, USDA/Spoonacular keys, coach token) live in the **Keychain** (`Coach/Keychain.swift`), are never committed and are not backed up.

## Features and where they live
**Workouts** (`Views/ActiveWorkoutView`, `ExerciseEditorSection`, `SetRow`, `StartWorkoutSheet`, `ExercisePicker`; `Gym/GymStore`, `RestTimer`, `LiveActivityManager`)
- Active workout edits a local copy, pushed via `GymStore.updateActive`; typing is debounced (`saveSoon`, 0.8 s), ticks save at once, `flush()` when scenePhase leaves active.
- Supersets/giant sets/circuits (`TallyCore/Supersets`), "Up next" scroll, jump menu, drop sets, RPE per set, pinned notes (`Views/PinnedNote`), replace exercise (only when no set done), keyboard −/+ steppers (`FocusedValues.fieldStepper` in SetRow, the most compile-risky code), Previous column (`PreviousSets.match`), finish summary (`WorkoutSummaryView`, compares with last same-plan session).
- Rest timer: pause/resume, ±15/+30, persisted end time, local notification, Live Activity switches to a rest countdown (`TallyWidget/WorkoutLiveActivity`, `TallyKit/WorkoutActivity`).
- Progression assistant (`TallyCore/Progression`): increase / add reps / hold / deload (−10% after 3 stuck sessions); step by equipment (2.5 kg bars, 2 kg dumbbells, 5 kg machines), overridable in Settings › Training.

**Plans and programs** (`Views/PlansTab`, `PlanDetailView`, `PlanTemplateViews`; `Program/*`; `TallyCore/Program`, `ProgramCoach`, `PlanTemplates`, `UpNext`)
- Plans = saved workout templates. Ready-made routines (full body, upper/lower, PPL, dumbbells, bodyweight; names must exist in `ExerciseLibrary`). "Up next" = plan waited longest with rested muscles.
- Strength programs: Juggernaut, block, or coach-written; percentages of a training max (90% of 1RM), Squat/Bench/Deadlift/Press names in `Program.swift`; edited in `ProgramEditor`.

**History / Progress** (`HistoryView`, `MonthCalendar`, `RecordsView`, `ProgressTabView`, `TrendsViews`, `RecapView`, `MilestoneViews`, `RecoveryViews`; TallyCore `Trends`, `Recap`, `Milestones`, `Recovery`, `Strength`)
- PRs (`RecordKind`), weekly recap, Trends (4w/12w/6m/1y vs previous period, est. 1RM per lift, push/pull/legs/core balance, per-month counts), milestones with tiers + longest streak + six-month consistency grid, muscle recovery (24 h + 6 h per hard set, clamp 24–72 h, sessions <12 h apart merge).

**Exercises and muscles** (`Exercises/*`, `Gym/ExerciseLibrary`, `TallyCore/Motion`, `MotionLibrary`, `FreeExerciseDB`, `WorkoutAPI`; `scripts/anatomy.py`)
- `AnatomyFigure` draws front/back muscle figure from point lists generated by `scripts/anatomy.py` into `AnatomyShapes.swift`; roles primary/secondary/tertiary, per-muscle `shades:`, volume heat, animated contraction (off with Reduce Motion).
- Demos, in the user's chosen order (`ExerciseDemoStyle`): own animated jointed figure (`MotionFigureView`, `MotionMove`/`MotionLoad`), Workout API GIFs (needs key; name matcher in `ExerciseMediaStore`, cached), or Free Exercise DB photos (bundled + remote).
- Custom exercises via `ExerciseEditor` (muscles picked by tapping the figure).

**Food** (`Food/*`; TallyCore `FoodDiary`, `Nutrition*`, `Fasting`, `CommonFoods`, `OpenFoodFacts`, `OnlineFoodSources`): Lifesum-style diary, calorie/macro goals from body+activity, barcode scan (`BarcodeScanner`), search Open Food Facts (no key), USDA FoodData Central and Spoonacular recipes (user's free keys), offline common foods, water, fasting timer, nutrition rating, weight log.

**Sleep** (`Sleep/*`; TallyCore `Sleep`, `SleepInsights`, `SleepLinks`): Health stages + manual logging, sleep score, wind-down/bedtime reminders, caffeine cutoff, "Good night" buttons, tags linked to workouts/food, AI sleep review.

**Body** (`Body/*`; TallyCore `Body`): measurements (body fat and waist also read from Health), progress photos front/side/back, side-by-side and slider compare. Photos are not in the iCloud backup.

**Health** (`Health/*`): HealthKit read (steps, energy, exercise minutes, sleep, weight, body fat, waist, workouts) and write (finished workouts); imports other apps' / Watch workouts, merges overlapping sessions (`TallyCore/Overlap`, `HealthLinking`). Health access is re-granted on a new phone.

**Tools and extras**: `Tools/` plate calculator, 1RM calculator, stopwatch/countdown/intervals/EMOM; `QuickCount/` rep counter (Outdoor Office style, shared with the Reps widget); `Share/` story-style share cards (PNG), export to CSV/text/JSON (`TallyCore/Export`); `About/Changelog.swift`; Edit Home sheet (`HomeLayout`, hide/reorder cards); Home is `Views/HomeTab` (greeting, week card with weekly goal, tool tiles, Today and Training sections).

**Widgets** (`TallyWidget/*`): Training, Food, Reps; small/medium/large + lock-screen accessory + StandBy; tint-safe colours (`WidgetColors`). They read App Group JSON snapshots written by the app; app reloads timelines on going to background.

**Backup** (`Backup/*`, `TallyCore/Backup`): one JSON of all data files + settings written to a user-picked folder (iCloud Drive) via security-scoped bookmark; automatic when leaving the app if data changed; restore on a new phone. Add any new data file to `BackupStore.documentFiles`.

## Integrations
| Service | Where | Notes |
|---|---|---|
| Anthropic Messages API | `TallyCore/Coach`, `CoachChat`; `Coach/*` | user's own key in Keychain; default model `claude-haiku-5-5`, Sonnet/Opus selectable; feedback on workouts/overall/sleep, chat with tools (`CoachToolbox`), training-load overtraining check (`TrainingLoad`), program writing (`ProgramCoach`) |
| Cloudflare Worker MCP connector | `cloudflare/coach-mcp`, `Coach/CoachCloudStore`, `TallyCore/CoachCloud` | no-API-key coaching via the user's Claude plan; app uploads its log to the user's Worker (KV); Claude reads it via a custom connector at `…/mcp/<token>`. Tools: `get_overview`, `get_workouts`, `get_exercise_history`, `search_exercises`, `get_weekly_sets`, `get_sleep/food/body`, `get_plans/programs`, `propose_plan_change`, `propose_program` (applied only on user tap). Cloudflare Root directory must be `cloudflare/coach-mcp`. First phone to connect claims the token |
| Open Food Facts | `TallyCore/OpenFoodFacts` | barcode + search, no key |
| USDA FDC / Spoonacular | `TallyCore/OnlineFoodSources` | user keys |
| Workout API (workoutapi.com) | `TallyCore/WorkoutAPI`, `ExerciseMediaStore` | exercise GIFs, key in Settings, cached |
| Free Exercise DB | `TallyCore/FreeExerciseDB` | public-domain photos |
| Apple Health / HealthKit | `Health/*` | entitlement in `Support/Tally.entitlements` |
| iCloud Drive folder | `Backup/*` | no iCloud entitlement |

## Testing
- Only **TallyCore builds on Linux**. The iOS targets (SwiftUI, HealthKit, ActivityKit, WidgetKit) cannot be compiled in the cloud container, so app-layer changes are checked by careful review only; flag that in your hand-off. Compile errors the user reports from `xtool dev` are most likely in recently added app-layer code.
- Run: `cd Packages/TallyCore && swift test` (swift-testing; ~264+ tests). CI does the same.
- Cloud container has no `swift` and github/download.swift.org are blocked. Pull the toolchain from Docker Hub's registry API without docker: token from `auth.docker.io` (scope `repository:library/swift:pull`), manifest list for `library/swift:6.1-noble` → amd64 manifest → the ~900 MB layer, `tar -xzf` into a scratch dir, put `usr/bin` on PATH, then `swift test --scratch-path <scratch>/build` (Swift 6.1.3). If rate-limited (TOOMANYREQUESTS) use `https://mirror.gcr.io/v2/library/swift/...` (no token, same paths). Re-read the manifest each time; digests change. Don't run this from several threads at once.
- Re-run only failing tests while fixing, then the full suite once.
- Worker: `cd cloudflare/coach-mcp && npm test`.
- README mockups are HTML rendered with Playwright: `scripts/mockups/render.js` (screens.html, widgets.html, muscle-gifs.js). Screenshots in README/docs are mockups, not simulator captures. Project files copies go under `/mnt/project-files/<topic>/`.

## Conventions
- **UI**: `.card()` (white, radius 22, faint edge, soft shadow), `Theme.fill` for wells/badges, `.eyebrow()` for small sentence-case labels, headings Schibsted Grotesk bold in sentence case (`Typo.title`, `.display()` renders Grotesk). **Big Shoulders condensed only for numbers** (`Typo.display`). No all-caps headings, no ticket/bib styling. Colours via `Theme`/`Accent` tokens (light + dark), never hard-coded.
- User-facing copy says "Overlo4d". Plain, short sentences.
- Every release: bump version in **both** `Support/Tally-Info.plist` and `Support/TallyWidget-Info.plist` (version + build) and add a `Changelog.entries` item at the top (`About/Changelog.swift`). Currently 0.11 / 11, stage "Beta".
- New data file → add to `BackupStore.documentFiles`; new user setting → add to `BackupStore.settingsKeys`; new widget-visible data → App Group file via `SharedStorage`.
- Pure logic + tests in TallyCore first, then wire UI. Keep structs `Sendable`; mind Swift 6 strict concurrency (stores are `@MainActor`).
- Don't add dependencies. Don't commit keys or tokens.
- Known gaps / ideas: kg only (no lb), no confirm/undo on swipe-delete of a workout, widgets don't show the weekly goal, no watchOS app, no interactive widget buttons (xtool), progress photos not in backup.

## Git rules (the user's standing rules)
- **Commit straight to `main`. No branches, no PRs.** Always `git pull --rebase origin main` first: other Claude threads commit to main concurrently (e.g. muscle GIFs, new features).
- Commit messages are 1 to 5 lines. **No** Claude Code, Co-Authored-By or session attribution lines, no model names.
- Push with `git push origin main`; retry network errors with backoff.
- Pushes to main on GitHub trigger Cloudflare deploy of the Worker and the TallyCore CI.

## Working with the user
mahmud is on a Windows PC only (no Mac). They can't see cloud-container output, so deliver previews as images/files in `/mnt/project-files/`. Verify claims before stating them; say plainly when app-layer code is uncompiled. Release notes the user reads are the `Changelog` entries.
