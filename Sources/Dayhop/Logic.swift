import Foundation

/// Pure date and text helpers, kept free of AppKit/EventKit so `make check` can compile them alone.
///
/// Don't use `<=` or `>=` on Date (or anything that does, like `a...b`, `a..<b`, `max`, `min`):
/// the macOS 27.2 SDK links them to Foundation symbols that older macOS builds lack, and with a
/// macOS 14 deployment target that's a weak null that segfaults at runtime. `<`, `>` and `==` are fine.
enum Logic {
    /// 42 days (six full weeks) covering `month`, starting on the calendar's first weekday.
    static func monthGrid(for month: Date, calendar: Calendar) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Start of each day an event touches. An event ending exactly at midnight doesn't touch the next day.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        var day = calendar.startOfDay(for: start), out: [Date] = []
        repeat {
            out.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        } while day < end
        return out
    }

    static let meetingHosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "chime.aws", "facetime.apple.com", "around.co",
    ]
    /// http(s) URLs up to whitespace or the brackets and quotes invites wrap them in.
    /// A plain regex: NSDataDetector took ~2ms per event on long invite notes, which added up to half a second per popover.
    private static let linkPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'()\[\]]+"#, options: .caseInsensitive)

    /// First video-call link found in an event's URL, location or notes.
    static func meetingURL(in texts: [String?]) -> URL? {
        for case let text? in texts {
            for match in linkPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text),
                      let url = URL(string: String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))),
                      let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }

    /// Whether a meeting reminder is due: from `lead` seconds before the start until two minutes after
    /// (so one still shows if the Mac wakes just after the meeting began).
    static func reminderDue(start: Date, now: Date, lead: TimeInterval) -> Bool {
        let left = start.timeIntervalSince(now)
        return left <= lead && left > -120
    }

    /// The reminder's live headline: "Starting in 0:45", "Starting now", "Started 3 min ago".
    static func startsText(start: Date, now: Date) -> String {
        let left = start.timeIntervalSince(now)
        if left > 0 {
            let s = Int(left.rounded(.up))
            return String(format: "Starting in %d:%02d", s / 60, s % 60)
        }
        return left > -60 ? "Starting now" : "Started \(Int(-left / 60)) min ago"
    }

    /// "Zoom", "Google Meet", … for the Join button; nil for services without a nicer name.
    static func serviceName(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let names = [
            "zoom.us": "Zoom", "zoomgov.com": "Zoom", "meet.google.com": "Google Meet",
            "teams.microsoft.com": "Teams", "teams.live.com": "Teams", "webex.com": "Webex",
            "whereby.com": "Whereby", "meet.jit.si": "Jitsi", "chime.aws": "Chime", "facetime.apple.com": "FaceTime",
        ]
        return names.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value
    }

    /// Menu bar text for an event that starts soon ("Standup in 12m") or just started ("Standup now").
    static func countdown(title: String, start: Date, now: Date,
                          lead: TimeInterval = 30 * 60, grace: TimeInterval = 5 * 60) -> String? {
        let left = start.timeIntervalSince(now)
        guard left <= lead, left > -grace else { return nil }
        let name = title.count > 24 ? String(title.prefix(23)) + "…" : title
        return left <= 0 ? "\(name) now" : "\(name) in \(Int((left / 60).rounded(.up)))m"
    }

    /// "+5h", "−3h 30m" or "Same time", relative to `local`.
    static func offset(of zone: TimeZone, from local: TimeZone, at date: Date) -> String {
        let diff = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        if diff == 0 { return "Same time" }
        let minutes = abs(diff) / 60, sign = diff > 0 ? "+" : "−"
        return minutes % 60 == 0 ? "\(sign)\(minutes / 60)h" : "\(sign)\(minutes / 60)h \(minutes % 60)m"
    }

    /// "Tomorrow" / "Yesterday" when it's a different calendar day in `zone` than in `local`.
    static func dayHint(for zone: TimeZone, from local: TimeZone, at date: Date) -> String? {
        func dayIndex(_ tz: TimeZone) -> Int {
            Int(((date.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: date))) / 86400).rounded(.down))
        }
        switch dayIndex(zone) - dayIndex(local) {
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return nil
        }
    }

    /// "America/Argentina/Buenos_Aires" → "Buenos Aires".
    static func cityName(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }
}
