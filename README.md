<div align="center">

<img src=".github/assets/icon.png" width="128" height="128" alt="Dayhop icon">

# Dayhop

**Your day, one click away.**

A tiny, native macOS menu bar calendar. The date and time in your menu bar, your month and upcoming events one click away, warnings that count you into every meeting, and clocks for everywhere your team works.

[![Latest release](https://img.shields.io/github/v/release/eliashussary/dayhop?label=download&color=e83a54)](https://github.com/eliashussary/dayhop/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/hero-dark.jpg">
  <img src=".github/assets/hero-light.jpg" alt="Dayhop's menu bar item reads 'Design review in 9m · Wed Nov 25 12:26 PM'. Below it, the calendar popover shows November with today highlighted, today's and tomorrow's events with Join buttons, and clocks for London, Tokyo and Los Angeles" width="880">
</picture>

</div>

---

## Features

- **Your format in the menu bar.** Any [date format](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), with a live preview and presets. Add a calendar icon that shows today's date, or use the icon alone.
- **Month at a glance.** Click the menu bar for the month, with dots on busy days and optional week numbers. Click any day to see what's on.
- **Upcoming events.** Everything in the Calendar app (iCloud, Google, Exchange, anything it syncs), opening on what's next. Declined and canceled events stay out of the way.
- **Warnings before every meeting.** A notification 5 minutes before, a glass countdown for the last 60 seconds, then a full-screen reminder when it starts, each with a **Join** button.
- **One-click join.** Zoom, Google Meet, Teams, Webex, Whereby, Jitsi, Chime and FaceTime links are found in the event's URL, location or notes.
- **Next-meeting countdown.** For the 30 minutes before an event, the menu bar reads `Design review in 9m`, then counts seconds in the last minute.
- **World clocks.** Add a city or an abbreviation (`Tokyo`, `PST`) to see its time, its offset from yours and whether it's already tomorrow there.
- **Native and small.** Written in Swift with AppKit and SwiftUI. It runs as a menu bar app with no Dock icon, and has no network access, analytics or account.

## Install

1. Download the latest **`Dayhop-x.y.z.dmg`** from [Releases](https://github.com/eliashussary/dayhop/releases/latest).
2. Open it and drag **Dayhop** into **Applications**.
3. Open Dayhop, then click **Allow Calendar Access** in its menu bar calendar.

> [!NOTE]
> Releases aren't notarized by Apple yet, so macOS blocks Dayhop the first time you open it. Go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Dayhop.app
> ```

To uninstall, quit Dayhop from its menu and delete it from Applications.

## Using it

### Calendar

| Do this | To |
| --- | --- |
| Click the menu bar item | Open the calendar |
| Right-click or `⌃`-click it | Open Calendar, Settings, Quit |
| `‹` `Today` `›` | Change month |
| Click a day | See that day's events and the days after it |
| Click an event | Open it in Calendar |
| **Join** | Open the meeting link |

### Before a meeting

Dayhop warns you three times, and each stage has a **Join** button. Joining from any of them skips the ones still to come.

1. **5 minutes before:** a notification with the time, calendar and location. Click **Join**, or click the notification to open the event in Calendar.
2. **60 seconds before:** a glass countdown panel under the menu bar, with a ring that drains to the start. It never takes focus from what you're typing.

   <picture>
     <source media="(prefers-color-scheme: dark)" srcset=".github/assets/countdown-dark.jpg">
     <img src=".github/assets/countdown-light.jpg" alt="A glass panel under the menu bar: a countdown ring with the seconds left, 'Design review', 'Starting in 0:35', a Join button and a close button. The menu bar counts down in seconds too" width="880">
   </picture>

3. **When it starts:** a full-screen reminder on the screen your pointer is on, over full-screen apps too.

   <picture>
     <source media="(prefers-color-scheme: dark)" srcset=".github/assets/reminder-dark.jpg">
     <img src=".github/assets/reminder-light.jpg" alt="A full-screen reminder over a blurred desktop: 'Starting in 0:57', 'Design review', '12:26 – 1:11 PM · Work', with Dismiss and Join on Zoom buttons" width="880">
   </picture>

   | Key | Action |
   | --- | --- |
   | `↩` | Join the meeting (or open the event in Calendar if it has no link) |
   | `esc` | Dismiss |

In **Settings → General → Before a meeting** you can move the notification (1–10 minutes before) or turn it off, turn off the countdown, show the full-screen reminder up to 5 minutes early or not at all, and choose whether events without a video call link get warnings too. **Preview** plays all three for a sample meeting 15 seconds away.

The first notification asks for permission. If you missed it, turn on Dayhop in **System Settings → Notifications**.

### Settings

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/settings-dark.jpg">
  <img src=".github/assets/settings-light.jpg" alt="Dayhop Settings: the General tab with the menu bar format, meeting reminder and calendar options, and the Clocks tab listing London, Tokyo and Los Angeles" width="880">
</picture>

Open Settings from the gear in the calendar, or by right-clicking the menu bar item.

- **General:** the menu bar format and icon, the next-meeting countdown, the warnings before a meeting, week numbers, how many days of events to list, and launch at login.
- **Clocks:** add, reorder and remove world clocks.
- **Calendars:** choose which calendars to show, such as hiding holidays or birthdays.

Settings are stored in the app's preferences (`defaults read com.eliashussary.dayhop`).

## Building from source

You need macOS 14 or later and the Xcode command line tools (`xcode-select --install`); Xcode itself isn't required.

```sh
git clone https://github.com/eliashussary/dayhop && cd dayhop
make install            # build, copy to /Applications and launch
make check              # self-check for the date, countdown, reminder, time zone and meeting-link logic
make dmg UNIVERSAL=1    # build a universal disk image in build/
```

| Path | What's there |
| --- | --- |
| `Sources/Dayhop/AppDelegate.swift` | Menu bar item, clock tick, popover and menus |
| `Sources/Dayhop/PopoverView.swift` | Month grid, agenda and world clocks |
| `Sources/Dayhop/Reminder.swift` | Meeting notifications, the countdown panel and the full-screen reminder |
| `Sources/Dayhop/Settings.swift` | The Settings window |
| `Sources/Dayhop/Events.swift` | Preferences and Calendar (EventKit) access |
| `Sources/Dayhop/Logic.swift` | Pure date and text helpers covered by `make check` |
| `scripts/make-icon.swift` | Draws the app icon (`make icon`) |
| `scripts/screenshots/` | Renders the README images from the real views with sample events (`make screenshots`) |

## Releasing

Pushing a version tag builds a universal `.dmg` and publishes it to GitHub Releases:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

For signed and notarized builds, add these repository secrets. The release workflow uses them automatically when they're present.

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your Apple Developer team ID |
| `APPLE_APP_PASSWORD` | An app-specific password for `notarytool` |

## License

[MIT](LICENSE) © Elias Hussary
