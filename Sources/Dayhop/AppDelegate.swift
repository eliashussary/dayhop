import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let events = Events()
    private let reminders = Reminders()
    private let popoverState = PopoverState()
    private let popover = NSPopover()
    private let formatter = DateFormatter()
    private let calendar = Calendar.autoupdatingCurrent
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?
    private var iconDay = 0
    private var popoverClosedAt = Date.distantPast
    // Events in the next half hour, for the countdown and reminders. Refetched each minute or on calendar changes.
    private var upcoming: [Item] = []
    private var fetchedAt = Date.distantPast
    private var fetchedRevision = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        setupMainMenu()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(events: events, state: popoverState,
                                                             openSettings: { [weak self] in self?.showSettings() }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(click(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown]) // like system menus: respond on press, not release
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        prefsChanged()
        startClock()

        // Opened from Finder/Launchpad/Spotlight: show the calendar so it's obvious where Dayhop lives.
        let launchedByUser = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? false
        if launchedByUser && !CommandLine.arguments.contains("--background") {
            // The status item has no frame until the menu bar lays it out, and a popover can't attach before then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }

    /// Opening Dayhop again while it's running shows the calendar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    // MARK: Menu bar clock

    /// Ticks on each whole second so a seconds field never lags.
    private func startClock() {
        let next = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) + 1)
        let timer = Timer(fire: next, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func prefsChanged() {
        formatter.dateFormat = UserDefaults.standard.string(forKey: Prefs.format) ?? Prefs.autoFormat
        fetchedAt = .distantPast
        tick()
    }

    private func tick() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let date = formatter.string(from: now)
        let soon = upcomingEvents(now)
        reminders.check(soon, now: now)
        let countdown = UserDefaults.standard.bool(forKey: Prefs.nextEvent)
            ? soon.lazy.compactMap { Logic.countdown(title: $0.title, start: $0.start, now: now) }.first
            : nil
        let title = [countdown, date.isEmpty ? nil : date].compactMap { $0 }.joined(separator: "  ·  ")
        if button.title != title { button.title = title }

        // Never leave an empty, unclickable status item: fall back to the icon.
        if UserDefaults.standard.bool(forKey: Prefs.showIcon) || title.isEmpty {
            let day = calendar.component(.day, from: now)
            if button.image == nil || day != iconDay {
                button.image = MenuBarIcon.image(day: day)
                iconDay = day
            }
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        } else if button.image != nil {
            button.image = nil
        }
    }

    private func upcomingEvents(_ now: Date) -> [Item] {
        guard events.hasAccess else { return [] }
        if now.timeIntervalSince(fetchedAt) >= 60 || fetchedRevision != events.revision {
            upcoming = events.items(from: now.addingTimeInterval(-5 * 60), to: now.addingTimeInterval(31 * 60))
                .filter { !$0.allDay }
            fetchedAt = now
            fetchedRevision = events.revision
        }
        return upcoming
    }

    // MARK: Popover and menus

    @objc private func click(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(popoverClosedAt) > 0.3 {
            showPopover()
        }
        // Otherwise this same press already closed the transient popover (it closes on any click outside it,
        // the menu bar item included, before this action runs), so leave it closed.
    }

    func popoverWillClose(_ notification: Notification) {
        popoverClosedAt = Date()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        events.refreshStatus()
        popoverState.reset()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Calendar", action: #selector(openCalendar), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dayhop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(events: events, previewReminder: { [weak self] in self?.reminders.preview() })))
            window.title = "Dayhop Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        events.refreshStatus()
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }

    /// Needed for ⌘Q/⌘W/⌘, and copy/paste in text fields while the settings window is open.
    private func setupMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Dayhop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Dayhop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Dayhop", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        NSApp.mainMenu = main
    }
}
