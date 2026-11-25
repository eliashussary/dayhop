import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var events: Events

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ClocksTab()
                .tabItem { Label("Clocks", systemImage: "globe") }
            CalendarsTab(events: events)
                .tabItem { Label("Calendars", systemImage: "calendar") }
        }
        .frame(width: 480, height: 470)
    }
}

// MARK: - General

struct GeneralTab: View {
    @AppStorage(Prefs.format) private var format = Prefs.autoFormat
    @AppStorage(Prefs.showIcon) private var showIcon = false
    @AppStorage(Prefs.nextEvent) private var nextEvent = true
    @AppStorage(Prefs.weekNumbers) private var weekNumbers = false
    @AppStorage(Prefs.agendaDays) private var agendaDays = 3
    @StateObject private var launchAtLogin = Box(SMAppService.mainApp.status == .enabled)

    private static let presets = [
        Prefs.autoFormat, "EEE MMM d  h:mm a", "EEE d MMM  HH:mm", "EEEE, MMMM d", "h:mm a", "HH:mm:ss", "yyyy-MM-dd HH:mm",
    ]

    var body: some View {
        Form {
            Section("Menu bar") {
                LabeledContent("Format") {
                    TextField("Format", text: $format)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                LabeledContent("Preview") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(render(format, context.date).isEmpty ? "Icon only" : render(format, context.date))
                            .monospacedDigit()
                    }
                }
                HStack {
                    Menu("Presets") {
                        ForEach(Self.presets, id: \.self) { preset in
                            Button(render(preset, Date())) { format = preset }
                        }
                        Divider()
                        Button("Icon only") {
                            format = ""
                            showIcon = true
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Link("Format reference", destination: URL(string: "https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table")!)
                }
                Toggle("Show calendar icon", isOn: $showIcon)
                Toggle("Show the next event 30 minutes before it starts", isOn: $nextEvent)
            }
            Section("Calendar") {
                Toggle("Show week numbers", isOn: $weekNumbers)
                Stepper("Show events for \(agendaDays) \(agendaDays == 1 ? "day" : "days")", value: $agendaDays, in: 1...14)
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin.value)
                    .onChange(of: launchAtLogin.value) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin.value = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func render(_ format: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: date)
    }
}

// MARK: - Clocks

struct ClocksTab: View {
    @AppStorage(Prefs.clocks) private var clocks = ""
    @StateObject private var query = Box("")

    private var ids: [String] { Prefs.split(clocks) }

    /// Cities and zone ids containing the query, plus an abbreviation match ("PST", "CET").
    private var matches: [String] {
        let q = query.value.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var found = TimeZone(abbreviation: q.uppercased()).map { [$0.identifier] } ?? []
        found += TimeZone.knownTimeZoneIdentifiers.filter {
            $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(q)
        }
        var seen = Set(ids)
        return Array(found.filter { seen.insert($0).inserted }.prefix(8))
    }

    var body: some View {
        Form {
            Section("World clocks") {
                if ids.isEmpty {
                    Text("Add a city below to see its time in the calendar popover.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Text(Logic.cityName(id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(id == ids.first)
                        Button { move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(id == ids.last)
                        Button { clocks = ids.filter { $0 != id }.joined(separator: ",") } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .help("Remove")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section("Add a clock") {
                TextField("Search", text: $query.value, prompt: Text("City or zone, e.g. Tokyo, London, PST"))
                ForEach(matches, id: \.self) { id in
                    Button {
                        clocks = (ids + [id]).joined(separator: ",")
                        query.value = ""
                    } label: {
                        HStack {
                            Text(Logic.cityName(id))
                            Spacer()
                            Text(id).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ id: String, by delta: Int) {
        var list = ids
        guard let i = list.firstIndex(of: id), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        clocks = list.joined(separator: ",")
    }
}

// MARK: - Calendars

struct CalendarsTab: View {
    @ObservedObject var events: Events
    @AppStorage(Prefs.hiddenCalendars) private var hidden = ""

    var body: some View {
        Form {
            if events.hasAccess {
                let groups = Dictionary(grouping: events.calendars, by: { $0.source?.title ?? "Other" })
                    .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                ForEach(groups, id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.value, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: shown(calendar.calendarIdentifier)) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(nsColor: calendar.color)).frame(width: 9, height: 9)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                }
            } else {
                Section { AccessPrompt(events: events) }
            }
        }
        .formStyle(.grouped)
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !Prefs.split(hidden).contains(id) },
            set: { show in
                let rest = Prefs.split(hidden).filter { $0 != id }
                hidden = (show ? rest : rest + [id]).joined(separator: ",")
            }
        )
    }
}
