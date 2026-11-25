import AppKit
import SwiftUI
import UserNotifications

/// Warnings before a meeting, each shown once per event:
/// a notification minutes before, a glass countdown panel for the last minute, then a full-screen reminder.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    private var notified = Set<String>()
    private var counted = Set<String>()
    private var shown = Set<String>()
    private var queue: [Item] = []
    private var window: NSWindow?
    private var countdown: (item: Item, window: NSWindow)?
    /// Preview meetings, run through the same stages as real ones.
    private var extra: [Item] = []
    private var askedForNotifications = false

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: "join", title: "Join", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "meeting", actions: [join], intentIdentifiers: []),
            UNNotificationCategory(identifier: "event", actions: [], intentIdentifiers: []),
        ])
    }

    /// Asks once per launch; macOS only prompts the first time.
    func requestNotificationAccess() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Called every clock tick with the events starting soon.
    func check(_ items: [Item], now: Date) {
        extra.removeAll { !(now < $0.end) }
        let defaults = UserDefaults.standard
        let linkOnly = defaults.bool(forKey: Prefs.reminderLinkOnly)
        let notifyLead = TimeInterval(defaults.integer(forKey: Prefs.notifyLead)) // 0 = off
        let countdownOn = defaults.bool(forKey: Prefs.countdown)
        let fullOn = defaults.bool(forKey: Prefs.reminders)
        let fullLead = TimeInterval(defaults.integer(forKey: Prefs.reminderLead))

        for item in items + extra where !item.allDay && (item.meeting != nil || !linkOnly) {
            let left = item.start.timeIntervalSince(now)
            if notifyLead > 0, left <= notifyLead, left > 0, notified.insert(item.id).inserted {
                notify(item, left: left)
            }
            // The countdown hands over to the full-screen reminder; without one it runs to the start.
            if countdownOn, left <= 60, left > (fullOn ? fullLead : -120), counted.insert(item.id).inserted {
                showCountdown(item)
            }
            if fullOn, Logic.reminderDue(start: item.start, now: now, lead: fullLead), shown.insert(item.id).inserted {
                closeCountdown()
                show(item)
            }
        }
        if let c = countdown, !(now.timeIntervalSince(c.item.start) < 120) { closeCountdown() }
    }

    /// A sample meeting 15 seconds out, so the notification, countdown and full-screen reminder play in quick succession.
    /// Its Join opens Zoom's test meeting page.
    func preview() {
        let now = Date()
        extra.append(Item(id: "preview-\(now.timeIntervalSince1970)", eventID: "", title: "Design review",
                          start: now.addingTimeInterval(15), end: now.addingTimeInterval(31 * 60), allDay: false,
                          color: .accentColor, meeting: URL(string: "https://zoom.us/test"), calendar: "Work"))
    }

    /// Joining from any stage skips the stages still to come.
    private func join(_ id: String, _ url: URL) {
        NSWorkspace.shared.open(url)
        counted.insert(id)
        shown.insert(id)
        closeCountdown()
    }

    // MARK: Notification

    private func notify(_ item: Item, left: TimeInterval) {
        requestNotificationAccess()
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.subtitle = "In \(Int((left / 60).rounded(.up))) min"
        content.body = item.summary
        content.sound = .default
        content.categoryIdentifier = item.meeting == nil ? "event" : "meeting"
        content.userInfo = ["id": item.id, "url": item.meeting?.absoluteString ?? "", "event": item.eventID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
    }

    /// Show banners even though Dayhop counts as the active app while its menu bar item is in use.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Join joins; clicking the notification itself shows the event in Calendar.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["id"] as? String ?? ""
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        let eventID = info["event"] as? String ?? ""
        let joining = response.actionIdentifier == "join"
        let clicked = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if joining, let url { self.join(id, url) } else if clicked { Item.reveal(eventID: eventID) }
            }
        }
        completionHandler()
    }

    // MARK: Countdown

    private func showCountdown(_ item: Item) {
        closeCountdown()
        guard let screen = Self.screenUnderPointer() else { return }
        let size = NSSize(width: 360, height: 84)
        let area = screen.visibleFrame // below the menu bar
        let panel = OverlayWindow(contentRect: NSRect(x: area.maxX - size.width - 12, y: area.maxY - size.height - 12,
                                                      width: size.width, height: size.height),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let view = CountdownView(
            item: item,
            join: { [weak self] in if let url = item.meeting { self?.join(item.id, url) } },
            close: { [weak self] in self?.closeCountdown() }
        )
        panel.contentView = Self.glass(FirstClickHostingView(rootView: view), cornerRadius: 22)
        panel.alphaValue = 0
        panel.orderFrontRegardless() // never takes focus from what you're typing in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        countdown = (item, panel)
    }

    private func closeCountdown() {
        guard let panel = countdown?.window else { return }
        countdown = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Liquid Glass on macOS 26 and later, a HUD blur before that.
    private static func glass(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.addSubview(content)
        content.frame = blur.bounds
        return blur
    }

    /// The screen you're looking at, judged by the pointer.
    private static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Full screen

    func show(_ item: Item) {
        guard window == nil else {
            queue.append(item)
            return
        }
        guard let screen = Self.screenUnderPointer() else { return }

        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver // above full-screen apps and the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let host = NSHostingView(rootView: ReminderView(item: item, close: { [weak self] in self?.close() }))
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        window.contentView = blur
        host.frame = blur.bounds
        window.setFrame(screen.frame, display: true)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
        self.window = window
    }

    private func close() {
        guard let window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
        if !queue.isEmpty { show(queue.removeFirst()) }
    }
}

/// A non-activating panel takes keyboard focus (↩ and esc) without pulling Dayhop to the front,
/// which macOS may refuse while you're in another app. Borderless windows can't be key by default.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Buttons respond to the first click, even though the countdown panel never becomes key.
private final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A filled accent capsule. The system prominent style turns grey in windows that aren't key,
/// and the countdown panel never is.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

/// The last-minute countdown: a draining ring with the seconds left, the event, and Join.
struct CountdownView: View {
    let item: Item
    var join: () -> Void
    var close: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = max(0, item.start.timeIntervalSince(context.date))
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(item.color.opacity(0.25), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: min(1, left / 60))
                        .stroke(item.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: left)
                    Text("\(Int(left.rounded(.up)))")
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).lineLimit(1)
                    Text(Logic.startsText(start: item.start, now: context.date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if item.meeting != nil {
                    Button("Join", action: join)
                        .buttonStyle(PillButtonStyle())
                }
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
            }
            .padding(.horizontal, 16)
        }
        .frame(width: 360, height: 84)
    }
}

struct ReminderView: View {
    let item: Item
    var close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Logic.startsText(start: item.start, now: context.date))
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.color)
            }
            Text(item.title)
                .font(.system(size: 64, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(item.summary)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Button("Dismiss", action: close)
                    .keyboardShortcut(.cancelAction)
                if let url = item.meeting {
                    Button {
                        NSWorkspace.shared.open(url)
                        close()
                    } label: {
                        Label(Logic.serviceName(url).map { "Join on \($0)" } ?? "Join Meeting", systemImage: "video.fill")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        item.reveal()
                        close()
                    } label: {
                        Text("Open in Calendar").frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.extraLarge)
            .padding(.top, 16)
        }
        .padding(60)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
