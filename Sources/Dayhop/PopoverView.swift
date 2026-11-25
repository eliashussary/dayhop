import SwiftUI

/// Stand-in for @State, whose macro plugin isn't in the Command Line Tools toolchain.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

struct PopoverView: View {
    @ObservedObject var events: Events
    var openSettings: () -> Void

    @AppStorage(Prefs.weekNumbers) private var weekNumbers = false
    @AppStorage(Prefs.agendaDays) private var agendaDays = 3
    @AppStorage(Prefs.clocks) private var clocks = ""
    @StateObject private var month = Box(Date())
    @StateObject private var selected = Box(Calendar.autoupdatingCurrent.startOfDay(for: Date()))
    private let cal = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            MonthGrid(events: events, month: $month.value, selected: $selected.value, weekNumbers: weekNumbers)
            Divider()
            agenda
            let zones = Prefs.zones(clocks)
            if !zones.isEmpty {
                Divider()
                WorldClocks(zones: zones)
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(month.value, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Button("Today") {
                month.value = Date()
                selected.value = cal.startOfDay(for: Date())
            }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
        }
        .buttonStyle(.borderless)
    }

    private func shift(_ n: Int) {
        month.value = cal.date(byAdding: .month, value: n, to: month.value) ?? month.value
    }

    // MARK: Agenda

    private var agenda: some View {
        let days = (0..<max(agendaDays, 1)).compactMap { cal.date(byAdding: .day, value: $0, to: selected.value) }
        let byDay = events.hasAccess ? itemsByDay(days) : [:]
        // Today's first event that hasn't ended, so the list opens on what's next rather than this morning.
        let now = Date()
        let next = byDay[cal.startOfDay(for: now)]?.first { !$0.allDay && now < $0.end }?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if events.hasAccess {
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayTitle(day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                let items = byDay[day] ?? []
                                if items.isEmpty {
                                    Text("No events").font(.callout).foregroundStyle(.tertiary)
                                }
                                ForEach(items) { EventRow(item: $0, day: day).id($0.id) }
                            }
                        }
                    } else {
                        AccessPrompt(events: events)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .onAppear {
                if let next { proxy.scrollTo(next, anchor: .top) }
            }
        }
    }

    private func itemsByDay(_ days: [Date]) -> [Date: [Item]] {
        guard let first = days.first, let end = cal.date(byAdding: .day, value: days.count, to: first) else { return [:] }
        var out: [Date: [Item]] = [:]
        for item in events.items(from: first, to: end) {
            for day in Logic.days(from: item.start, to: item.end, calendar: cal) where !(day < first) && day < end { // no Date >=, see Logic.swift
                out[day, default: []].append(item)
            }
        }
        return out
    }

    private func dayTitle(_ day: Date) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if cal.isDateInToday(day) { return "Today · \(date)" }
        if cal.isDateInTomorrow(day) { return "Tomorrow · \(date)" }
        if cal.isDateInYesterday(day) { return "Yesterday · \(date)" }
        return date
    }

    private var footer: some View {
        HStack {
            Button("Open Calendar") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
            Spacer()
            Menu {
                Button("Settings…", action: openSettings)
                Divider()
                Button("Quit Dayhop") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Month grid

struct MonthGrid: View {
    @ObservedObject var events: Events
    @Binding var month: Date
    @Binding var selected: Date
    var weekNumbers: Bool
    private let cal = Calendar.autoupdatingCurrent

    var body: some View {
        let days = Logic.monthGrid(for: month, calendar: cal)
        let busy = busyDays(days)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        Grid(horizontalSpacing: 0, verticalSpacing: 2) {
            GridRow {
                if weekNumbers { Color.clear.frame(width: 22, height: 1) }
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[(i + cal.firstWeekday - 1) % 7])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { row in
                GridRow {
                    if weekNumbers {
                        Text("\(cal.component(.weekOfYear, from: days[row * 7]))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 22)
                    }
                    ForEach(0..<7, id: \.self) { col in
                        cell(days[row * 7 + col], busy: busy.contains(days[row * 7 + col]))
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, busy: Bool) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = day == selected
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        return Button {
            selected = day
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isToday ? Color.accentColor : isSelected ? Color.primary.opacity(0.12) : .clear))
                Circle()
                    .fill(busy ? Color.secondary : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func busyDays(_ days: [Date]) -> Set<Date> {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return [] }
        return Set(events.items(from: first, to: end).flatMap { Logic.days(from: $0.start, to: $0.end, calendar: cal) })
    }
}

// MARK: - Rows

struct EventRow: View {
    let item: Item
    let day: Date
    private let cal = Calendar.autoupdatingCurrent

    var body: some View {
        let past = item.end < Date()
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(timeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url = item.meeting, !past {
                Button("Join") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
                    .help(url.absoluteString)
            }
        }
        .opacity(past ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { item.reveal() }
        .help("Show in Calendar")
    }

    private var timeText: String {
        let startsBefore = item.start < day
        let endsAfter = cal.date(byAdding: .day, value: 1, to: day).map { item.end > $0 } ?? false
        if item.allDay || (startsBefore && endsAfter) { return "All day" }
        if startsBefore { return "Until \(item.end.formatted(date: .omitted, time: .shortened))" }
        if endsAfter { return "From \(item.start.formatted(date: .omitted, time: .shortened))" }
        // Range(uncheckedBounds:) skips the bounds check, which would call Date <=.
        let end = item.end < item.start ? item.start : item.end
        return Range(uncheckedBounds: (item.start, end)).formatted(.interval.hour().minute())
    }
}

struct WorldClocks: View {
    let zones: [TimeZone]

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 5) {
                ForEach(zones, id: \.identifier) { zone in
                    HStack(spacing: 6) {
                        Text(Logic.cityName(zone.identifier))
                        Text(Logic.offset(of: zone, from: .autoupdatingCurrent, at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let hint = Logic.dayHint(for: zone, from: .autoupdatingCurrent, at: context.date) {
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

struct AccessPrompt: View {
    @ObservedObject var events: Events

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dayhop can show your upcoming events and meeting links from the Calendar app.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if events.status == .notDetermined {
                Button("Allow Calendar Access") { events.requestAccess() }
            } else {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
    }
}
