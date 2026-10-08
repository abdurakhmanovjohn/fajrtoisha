# Fajr to Isha

A native iOS app for prayer times, reminders and prayer tracking. It is a standalone port of the
[Halal Bot](https://github.com/abdurakhmanovjohn/myhalalbot) Telegram bot. It does the same job,
but as a native app instead of a chat.

Everything stays on the device. There is no backend and no account. The only network call is to the
[Aladhan API](https://aladhan.com/prayer-times-api) to download prayer times.

## Features

- **Location-based prayer times**: Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha, from your location or
  a city you type in. The timezone is resolved automatically.
- **Works offline**: timings are downloaded a month at a time and cached, and the next month is
  fetched before the current one runs out. If a download fails, the app uses the last good data.
- **Two-stage reminders**: a heads-up before each prayer ("make Wudu"), then an alert at the adhan with a
  **Mark as Prayed** action that logs the prayer without opening the app.
- **Fajr-end reminders**: a warning N minutes before sunrise and an alert when Fajr time ends.
- **End-of-day summary** at 21:00, which mentions the weekly recap on Sundays and the monthly recap
  on the last day of the month. Tapping it opens Reports.
- **Today**: today's timings, the next prayer highlighted with a live countdown, and one-tap logging.
- **Log**: log any past day with Prev / Today / Next or a date picker. Future dates are locked.
  Today's prayers can't be marked before their adhan. Includes Nafl prayers (Tahajjud, Duha, Ishraq,
  Awwabin, Tarawih).
- **Stats**:
  - **Reports**: Today, 7-day and 30-day reports with completion rate, perfect days, a per-prayer
    chart and the most-missed prayer(s).
  - **Overview**: a 30-day activity grid.
  - **Profile**: current and longest streaks. An unfinished today never breaks your streak.
- **Qaza**: track missed prayers (including Witr) and record make-ups.
- **Settings**:
  - Reminder lead time (5–30 min).
  - Asr school (Hanafi or Standard).
  - Calculation method.
  - Change location.
  - Notification status and a test notification.
  - A Danger Zone to reset logs or delete all data.

## Requirements

- Xcode 26 or later (the project was created with Xcode 27)
- iOS 17.0+
- No third-party dependencies

## Getting started

1. Open `FajrToIsha.xcodeproj`.
2. Under **Signing & Capabilities**, choose your development team for the `FajrToIsha` and
   `FajrToIshaTests` targets. If you fork the project, also change the bundle identifier.
3. Optionally, add the **Time Sensitive Notifications** capability so adhan alerts can break through
   Focus modes. Without it they arrive as normal notifications.
4. Build and run the `FajrToIsha` scheme.

From the command line:

```bash
xcodebuild -scheme FajrToIsha -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

```bash
xcodebuild -scheme FajrToIsha -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

To see which simulators you have, run `xcrun simctl list devices available`.

## Project structure

```
FajrToIsha/
├── App/
│   ├── FajrToIshaApp.swift         # Entry point, scene phase refresh, background task
│   ├── AppDelegate.swift           # Notification delegate ("Mark as Prayed", tap routing)
│   ├── AppModel.swift              # Shared state; ties services together, refresh pipeline
│   └── SettingsStore.swift         # Settings persisted in UserDefaults
├── Models/
│   ├── Day.swift                   # Timezone-free calendar day ("yyyy-MM-dd")
│   ├── PersistentModels.swift      # SwiftData: PrayerLog, Qaza, CachedTimings
│   └── Prayer.swift                # Constants (AppConfig), prayer names, methods, DayTimings
├── Services/
│   ├── PrayerTimesService.swift    # Aladhan client + per-day SwiftData cache
│   ├── NotificationPlanner.swift   # Pure planner: which alerts to schedule, never > 64
│   ├── NotificationScheduler.swift # Applies the plan to UNUserNotificationCenter
│   ├── StatsEngine.swift           # Pure functions: streaks, reports, overview, profile
│   ├── LogStore.swift              # Prayer log and qaza reads/writes, time-gating
│   └── LocationManager.swift       # One-shot when-in-use CoreLocation lookup
└── Views/                          # Onboarding, Today, Log, Stats, Qaza, Settings
FajrToIshaTests/                    # Swift Testing tests for StatsEngine and NotificationPlanner
Design/AppIcon.svg                  # Source for the app icon
FajrToIsha-Info.plist               # Background modes and BGTask identifiers
```

App logic is kept separate from the UI. `StatsEngine` and `NotificationPlanner` take plain values
and have no SwiftData or UIKit dependencies, so they can be unit-tested directly.

## How it works

### Data

| Store                       | Contents                                                                 |
| --------------------------- | ------------------------------------------------------------------------ |
| `UserDefaults`              | Latitude/longitude or city, timezone, reminder offset, Asr school, method |
| SwiftData `PrayerLog`       | Prayer name, day, completed flag, category (`fard`/`nafl`); unique per (name, day, category) |
| SwiftData `Qaza`            | Prayer name and remaining count (never below 0)                          |
| SwiftData `CachedTimings`   | One row per day per location/method/school, plus Aladhan's timezone     |

Days are stored as `"yyyy-MM-dd"` strings, calculated in the location's timezone. Changing location
or timezone therefore never moves past logs to a different day.

### Prayer times

Timings come from Aladhan's monthly calendar endpoints. `/v1/calendar/{year}/{month}` is used for
coordinates and `/v1/calendarByCity/{year}/{month}` for a manually entered city. The `method` and
`school` parameters come from Settings. The timezone comes from `meta.timezone`. Suffixes such as
`" (+05)"` are removed from timing strings.

### Notifications

iOS keeps at most **64** pending local notifications per app. A full day needs 13 of them (5 heads-ups,
5 adhan alerts, 2 Fajr-end alerts and the summary). So the app schedules a rolling window of the next
**5 days**, sorted by time and capped at 63, which leaves one slot for the test notification.

The queue is rebuilt when the app launches or comes to the foreground, when a setting or the location
changes, and from a `BGAppRefreshTask`. Identifiers are stable (for example `2026-10-08_Asr_exact`),
so a rebuild only changes what is actually different. Prayers that are already logged get no adhan
alert, and logging a prayer removes its pending alert.

Because notification text is fixed when it's scheduled, the 21:00 summary invites you to open the app
rather than containing the numbers.

### Statistics

`StatsEngine` is a line-by-line port of the bot's `compute_streaks`, `build_daily_report`,
`build_range_report` and `build_overview`. It keeps the bot's behaviour, including:

- Reports start at the later of the range start and your first logged day, so new users aren't
  penalised.
- Ties for the most-missed prayer are all listed.
- Percentages are rounded the way Python's `round()` does it (half to even).

## Configuration

Most defaults are in `AppConfig` in [`FajrToIsha/Models/Prayer.swift`](FajrToIsha/Models/Prayer.swift):

| Constant              | Default    | Notes                                     |
| --------------------- | ---------- | ----------------------------------------- |
| `timeFormat`          | `"HH:mm"`  | Use `"h:mm a"` for 12-hour time           |
| `defaultOffset`       | `15`       | Reminder lead time in minutes             |
| `defaultAsrSchool`    | `1`        | 1 = Hanafi, 0 = Standard (Shafi'i)        |
| `defaultCalcMethod`   | `14`       | Aladhan method id                         |
| `summaryHour`         | `21`       | End-of-day summary time                   |
| `firstWeekday`        | `2`        | Monday                                    |

The notification window size (`windowDays = 5`) is set in `NotificationPlanner`.

## Differences from the Telegram bot

- The calculation method in Settings is sent to Aladhan. The bot always used method 14.
- **Mark as Prayed** logs the prayer for the day the alert was for, not the day you tap it.
- The bot's *View Schedule* command is the "Upcoming alerts today" section on the Today screen.
- The "Fajr ends soon" warning is skipped once Fajr has been logged.
- There are no accounts and no sync with the bot. The two keep separate data.

## Testing background refresh

Background refresh doesn't run in the Simulator. On a device, pause the app in the debugger and run:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.abdurakhmanovjohn.fajrtoisha.refresh"]
```

## Credits

Prayer times are provided by the [Aladhan API](https://aladhan.com/prayer-times-api).
