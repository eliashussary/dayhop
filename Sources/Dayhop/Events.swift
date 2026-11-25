import EventKit
import SwiftUI

/// UserDefaults keys. Views read them with @AppStorage; the menu bar re-reads on every change.
enum Prefs {
    static let format = "format"
    static let showIcon = "showIcon"
    static let nextEvent = "nextEvent"
    static let weekNumbers = "weekNumbers"
    static let agendaDays = "agendaDays"
    static let clocks = "clocks"                   // comma-separated time zone ids
    static let hiddenCalendars = "hiddenCalendars" // comma-separated calendar ids
    static let reminders = "reminders"             // full-screen overlay when a meeting starts
    static let reminderLead = "reminderLead"       // seconds before the start to show it
    static let reminderLinkOnly = "reminderLinkOnly"

    /// The locale's own short date and time, e.g. "Wed, Nov 25  9:41 AM" or "Mi., 25. Nov.  09:41".
    /// Built from two templates, since a combined one adds an " at " that's noisy in a menu bar.
    static let autoFormat = [
        DateFormatter.dateFormat(fromTemplate: "EEEMMMd", options: 0, locale: .current) ?? "EEE MMM d",
        DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm a",
    ].joined(separator: "  ")

    static func register() {
        UserDefaults.standard.register(defaults: [
            format: autoFormat, showIcon: false, nextEvent: true, weekNumbers: false,
            agendaDays: 3, clocks: "", hiddenCalendars: "",
            reminders: true, reminderLead: 60, reminderLinkOnly: true,
        ])
    }

    static func split(_ list: String) -> [String] {
        list.split(separator: ",").map(String.init)
    }

    static func zones(_ list: String) -> [TimeZone] {
        split(list).compactMap(TimeZone.init(identifier:))
    }
}

/// One occurrence of a calendar event, copied out of EventKit.
struct Item: Identifiable {
    let id: String
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let meeting: URL?
    var calendar = ""
    var location: String?
}

extension Item {
    init(_ e: EKEvent) {
        eventID = e.eventIdentifier ?? ""
        id = eventID + "@\(e.startDate.timeIntervalSince1970)"
        let t = e.title ?? ""
        title = t.isEmpty ? "Untitled" : t
        start = e.startDate
        end = e.endDate
        allDay = e.isAllDay
        color = Color(nsColor: e.calendar?.color ?? .secondaryLabelColor)
        meeting = Logic.meetingURL(in: [e.url?.absoluteString, e.location, e.notes])
        calendar = e.calendar?.title ?? ""
        // Locations that are just a call link are already covered by Join.
        location = e.location.flatMap { $0.isEmpty || $0.contains("://") ? nil : $0 }
    }

    /// Shows the event in Calendar.app.
    func reveal() {
        let url = URL(string: "ical://ekevent/\(eventID)?method=show&options=more")
            ?? URL(fileURLWithPath: "/System/Applications/Calendar.app")
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class Events: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    /// Bumped whenever the calendar database changes, so views and caches refresh.
    @Published private(set) var revision = 0

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            refreshStatus()
        }
    }

    /// Picks up access granted or revoked in System Settings while Dayhop was running.
    func refreshStatus() {
        let now = EKEventStore.authorizationStatus(for: .event)
        guard now != status else { return }
        status = now
        store.reset()
        revision += 1
    }

    var calendars: [EKCalendar] {
        hasAccess ? store.calendars(for: .event) : []
    }

    /// Events overlapping [start, end) on visible calendars, all-day first, skipping ones you declined.
    func items(from start: Date, to end: Date) -> [Item] {
        guard hasAccess else { return [] }
        let hidden = Set(Prefs.split(UserDefaults.standard.string(forKey: Prefs.hiddenCalendars) ?? ""))
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] } // nil calendars would mean "all"
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: visible))
            .filter { e in
                e.status != .canceled
                    && e.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .map(Item.init)
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }
}
