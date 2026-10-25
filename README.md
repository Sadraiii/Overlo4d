# Overload

A gym tracker built around progressive overload: log every set, see what you trained, and keep getting stronger week over week.

- Plans, supersets and a rest timer for training sessions
- A quick rep counter with a daily goal
- Muscle maps for each exercise and for the last 30 days
- Weekly recap, history and progress charts
- Apple Health sync, home screen widgets and a workout Live Activity
- Share cards for workouts and weeks

## Naming

The app was previously called Tally. The display name is now Overload. Code-level names (the `Tally`, `TallyKit`, `TallyCore` and `TallyWidget` targets), the bundle ID and the `tally://` URL scheme are unchanged, so installed data, widgets and deep links keep working.

## Building

The app is built with [xtool](https://github.com/xtool-org/xtool) from `xtool.yml` and targets iOS 26.1. Plain-Swift logic lives in `Packages/TallyCore` and has unit tests that run on Linux:

```sh
cd Packages/TallyCore && swift test
```
