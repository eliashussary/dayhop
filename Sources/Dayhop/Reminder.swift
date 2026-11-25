import AppKit
import SwiftUI

/// Full-screen "your meeting is starting" overlay with a Join button.
@MainActor
final class Reminders {
    private var shown = Set<String>()
    private var queue: [Item] = []
    private var window: NSWindow?

    /// Called every clock tick with the events starting soon; shows each due one once.
    func check(_ items: [Item], now: Date) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.reminders) else { return }
        let lead = TimeInterval(defaults.integer(forKey: Prefs.reminderLead))
        let linkOnly = defaults.bool(forKey: Prefs.reminderLinkOnly)
        for item in items where !item.allDay && !shown.contains(item.id)
            && (item.meeting != nil || !linkOnly)
            && Logic.reminderDue(start: item.start, now: now, lead: lead) {
            shown.insert(item.id)
            show(item)
        }
    }

    /// A sample reminder for the Settings preview. Its Join opens Zoom's test meeting page.
    func preview() {
        let now = Date()
        show(Item(id: "preview-\(now.timeIntervalSince1970)", eventID: "", title: "Design review",
                  start: now.addingTimeInterval(60), end: now.addingTimeInterval(31 * 60), allDay: false,
                  color: .accentColor, meeting: URL(string: "https://zoom.us/test"), calendar: "Work"))
    }

    func show(_ item: Item) {
        guard window == nil else {
            queue.append(item)
            return
        }
        // The screen you're looking at, judged by the pointer.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }

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
            Text(details)
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

    private var details: String {
        let time = Range(uncheckedBounds: (item.start, item.end < item.start ? item.start : item.end))
            .formatted(.interval.hour().minute()) // uncheckedBounds: no Date <=, see Logic.swift
        return [time, item.calendar, item.location].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "  ·  ")
    }
}
