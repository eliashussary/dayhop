// Self-check for Sources/Dayhop/Logic.swift. Run via `make check`.
import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Toronto")!
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// Month grid: Nov 2026 starts on a Sunday.
cal.firstWeekday = 1
var grid = Logic.monthGrid(for: day(2026, 11, 15), calendar: cal)
assert(grid.count == 42 && grid[0] == day(2026, 11, 1) && grid[41] == day(2026, 12, 12))
cal.firstWeekday = 2 // Monday: lead with Oct 26.
grid = Logic.monthGrid(for: day(2026, 11, 15), calendar: cal)
assert(grid[0] == day(2026, 10, 26))
// Crosses the Nov 1 DST change and stays on midnights.
assert(grid.allSatisfy { cal.component(.hour, from: $0) == 0 })

// Days an event touches.
assert(Logic.days(from: day(2026, 11, 25, 9), to: day(2026, 11, 25, 10), calendar: cal) == [day(2026, 11, 25)])
assert(Logic.days(from: day(2026, 11, 25), to: day(2026, 11, 26), calendar: cal) == [day(2026, 11, 25)])
assert(Logic.days(from: day(2026, 11, 25, 22), to: day(2026, 11, 27, 1), calendar: cal).count == 3)
assert(Logic.days(from: day(2026, 11, 25, 9), to: day(2026, 11, 25, 9), calendar: cal).count == 1)

// Meeting links.
assert(Logic.meetingURL(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123?pwd=x"])?.host == "us02web.zoom.us")
assert(Logic.meetingURL(in: ["see https://example.com and <https://meet.google.com/abc-defg-hij>"])?.host == "meet.google.com")
assert(Logic.meetingURL(in: ["https://evilzoom.us/j/1", "https://docs.google.com/x"]) == nil)

// Countdown.
let now = day(2026, 11, 25, 9)
assert(Logic.countdown(title: "Standup", start: now.addingTimeInterval(11 * 60 + 1), now: now) == "Standup in 12m")
assert(Logic.countdown(title: "Standup", start: now.addingTimeInterval(-60), now: now) == "Standup now")
assert(Logic.countdown(title: "Standup", start: now.addingTimeInterval(31 * 60), now: now) == nil)
assert(Logic.countdown(title: "Standup", start: now.addingTimeInterval(-6 * 60), now: now) == nil)
assert(Logic.countdown(title: String(repeating: "x", count: 30), start: now, now: now) == String(repeating: "x", count: 23) + "… now")

// Meeting reminders.
assert(Logic.reminderDue(start: now.addingTimeInterval(60), now: now, lead: 60))
assert(!Logic.reminderDue(start: now.addingTimeInterval(61), now: now, lead: 60))
assert(Logic.reminderDue(start: now, now: now, lead: 0))
assert(Logic.reminderDue(start: now.addingTimeInterval(-119), now: now, lead: 0))
assert(!Logic.reminderDue(start: now.addingTimeInterval(-120), now: now, lead: 0))
assert(Logic.startsText(start: now.addingTimeInterval(44.2), now: now) == "Starting in 0:45")
assert(Logic.startsText(start: now.addingTimeInterval(125), now: now) == "Starting in 2:05")
assert(Logic.startsText(start: now.addingTimeInterval(-10), now: now) == "Starting now")
assert(Logic.startsText(start: now.addingTimeInterval(-185), now: now) == "Started 3 min ago")
assert(Logic.serviceName(URL(string: "https://us02web.zoom.us/j/1")!) == "Zoom")
assert(Logic.serviceName(URL(string: "https://meet.google.com/abc")!) == "Google Meet")
assert(Logic.serviceName(URL(string: "https://example.com")!) == nil)

// Time zones.
let toronto = TimeZone(identifier: "America/Toronto")!
assert(Logic.offset(of: TimeZone(identifier: "Europe/London")!, from: toronto, at: now) == "+5h")
assert(Logic.offset(of: TimeZone(identifier: "Asia/Kathmandu")!, from: toronto, at: now) == "+10h 45m")
assert(Logic.offset(of: TimeZone(identifier: "America/Los_Angeles")!, from: toronto, at: now) == "−3h")
assert(Logic.offset(of: toronto, from: toronto, at: now) == "Same time")
let lateEvening = day(2026, 11, 25, 22)
assert(Logic.dayHint(for: TimeZone(identifier: "Asia/Tokyo")!, from: toronto, at: lateEvening) == "Tomorrow")
assert(Logic.dayHint(for: TimeZone(identifier: "Pacific/Honolulu")!, from: toronto, at: day(2026, 11, 25, 1)) == "Yesterday")
assert(Logic.dayHint(for: TimeZone(identifier: "Europe/London")!, from: toronto, at: now) == nil)
assert(Logic.cityName("America/Argentina/Buenos_Aires") == "Buenos Aires")

print("ok")
