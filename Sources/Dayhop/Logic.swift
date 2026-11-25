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
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// First video-call link found in an event's URL, location or notes.
    static func meetingURL(in texts: [String?]) -> URL? {
        for case let text? in texts {
            for match in linkDetector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
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
