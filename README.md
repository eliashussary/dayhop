<div align="center">

<img src=".github/assets/icon.png" width="128" height="128" alt="Dayhop icon">

# Dayhop

**Your day, one click away.**

A tiny, native macOS menu bar calendar. The date and time in your menu bar, your month and upcoming events in a popover, a countdown to your next meeting, and clocks for the cities your team works in.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## Features

- **Your format in the menu bar.** Any [date format](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table) with a live preview, or presets. Optionally a calendar icon that shows today's date, or the icon alone.
- **Month calendar.** Click the menu bar to see the month, with dots on busy days and optional week numbers. Click any day to see its events.
- **Upcoming events.** Events from the Calendar app (iCloud, Google, Exchange, anything it syncs), opening on what's next. Click one to open it in Calendar.
- **One-click join.** Zoom, Google Meet, Teams, Webex, Whereby, Jitsi, Chime and FaceTime links get a **Join** button.
- **Next-meeting countdown.** For 30 minutes before an event, the menu bar shows `Standup in 12m`.
- **World clocks.** Add cities or abbreviations (`Tokyo`, `PST`) and see their time, offset and day.
- **Choose calendars.** Hide holidays, birthdays or anything else you don't want to see.
- **Native and small.** Swift, AppKit and SwiftUI. No Dock icon, no network access, no analytics, no account.

## Install

Build from source (needs the Xcode Command Line Tools, macOS 14 or later):

```sh
git clone https://github.com/eliashussary/dayhop
cd dayhop
make install   # builds, copies to /Applications and starts Dayhop
```

Open the popover and click **Allow Calendar Access** to see your events. Right-click the menu bar item for **Settings** and **Quit**.

## Usage

| Do this | To |
| --- | --- |
| Click the menu bar item | Open the calendar |
| Right-click or ⌃-click it | Settings, Open Calendar, Quit |
| `‹` `Today` `›` | Change month |
| Click a day | See that day's events and the days after it |
| Click an event | Open it in Calendar |
| **Join** | Open the meeting link |

Settings are stored in the app's preferences (`defaults read com.eliashussary.dayhop`).

## Development

```sh
make bundle   # build/Dayhop.app (ad-hoc signed)
make install  # bundle, copy to /Applications, restart
make check    # self-check for the date, countdown, time zone and meeting-link logic
make icon     # re-render Resources/AppIcon.icns from scripts/make-icon.swift
make dmg      # build/Dayhop-<version>.dmg; set SIGN_ID="Developer ID Application: …" to sign
```

Sources live in `Sources/Dayhop`:

| File | What |
| --- | --- |
| `AppDelegate.swift` | Menu bar item, clock tick, popover, menus |
| `PopoverView.swift` | Month grid, agenda, world clocks |
| `Settings.swift` | Settings window |
| `Events.swift` | Preferences and EventKit access |
| `Logic.swift` | Pure date and text helpers covered by `make check` |
| `MenuBarIcon.swift` | Template icon with today's date |

## License

[MIT](LICENSE)
