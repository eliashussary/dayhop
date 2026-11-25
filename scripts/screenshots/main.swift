// Renders the README images. The popover, reminder and settings are the app's real SwiftUI views
// fed sample events; the scenes around them (wallpaper, menu bar, windows) are mock-ups.
// Run via `make screenshots`. Output: .github/assets/{hero,reminder,settings}-{light,dark}.jpg
import AppKit
import CoreImage
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".github/assets")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Offscreen rendering

/// Lays out `view` in an offscreen window with the given appearance and snapshots it at `scale`×.
@MainActor
func snapshot<V: View>(_ view: V, dark: Bool, scale: CGFloat = 2) -> NSImage {
    let host = NSHostingView(rootView: view)
    let size = host.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

/// A canvas in points with a top-left origin, rendered at 2×.
final class Canvas {
    let size: NSSize
    let rep: NSBitmapImageRep

    init(_ w: CGFloat, _ h: CGFloat) {
        size = NSSize(width: w, height: h)
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
    }

    func draw(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Converts a top-left rect to AppKit's bottom-left coordinates.
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: size.height - y - h, width: w, height: h)
    }

    func place(_ image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat? = nil, shadow: CGFloat = 0, dark: Bool = false) {
        let w = width ?? image.size.width
        let h = image.size.height * w / image.size.width
        NSGraphicsContext.saveGraphicsState()
        if shadow > 0 {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.28)
            s.shadowBlurRadius = shadow
            s.shadowOffset = NSSize(width: 0, height: -shadow * 0.4)
            s.set()
        }
        image.draw(in: rect(x, y, w, h))
        NSGraphicsContext.restoreGraphicsState()
    }

    func save(_ name: String) {
        let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        try! data.write(to: outDir.appending(path: "\(name).jpg"))
        print("wrote \(name).jpg (\(rep.pixelsWide)×\(rep.pixelsHigh), \(data.count / 1024) KB)")
    }
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

extension Canvas {
    /// The canvas so far as an image, e.g. to blur it.
    var image: NSImage {
        let image = NSImage(size: size)
        image.addRepresentation(rep.copy() as! NSBitmapImageRep)
        return image
    }
}

func blurred(_ image: NSImage, radius: CGFloat) -> NSImage {
    let input = CIImage(data: image.tiffRepresentation!)!
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    let rep = NSCIImageRep(ciImage: output)
    let result = NSImage(size: image.size)
    result.addRepresentation(rep)
    return result
}

// MARK: - Scene pieces

/// Warm wallpaper in the app icon's coral, with soft color blobs.
func wallpaper(_ c: Canvas, dark: Bool) {
    let full = NSRect(origin: .zero, size: c.size)
    let base = dark ? [hex(0x1A0D16), hex(0x3A1424), hex(0x1C1030)] : [hex(0xFFF1EA), hex(0xFFE7EC), hex(0xF3EDFF)]
    NSGradient(colors: base)!.draw(in: full, angle: -35)
    let blobs: [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] = dark
        ? [(0xFF6B5B, 0.45, 0.20, 0.30, 0.55), (0xE23B6A, 0.40, 0.88, 0.85, 0.50), (0x7C5CFF, 0.30, 0.85, 0.10, 0.40)]
        : [(0xFFB199, 0.70, 0.20, 0.30, 0.55), (0xF9A8C8, 0.55, 0.90, 0.85, 0.50), (0xC4B5FD, 0.45, 0.85, 0.08, 0.40)]
    for (color, alpha, fx, fy, fr) in blobs {
        let center = NSPoint(x: c.size.width * fx, y: c.size.height * (1 - fy))
        NSGradient(colors: [hex(color, alpha), hex(color, 0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: c.size.width * fr, options: [])
    }
}

/// Menu bar with Dayhop's item highlighted on the right. Returns the item's frame (top-left coordinates).
@discardableResult
func menuBar(_ c: Canvas, dark: Bool, app: String, dayhop: String) -> NSRect {
    let h: CGFloat = 26
    (dark ? NSColor.black.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.5)).setFill()
    c.rect(0, 0, c.size.width, h).fill()
    let ink = dark ? NSColor.white : NSColor.black
    let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink]
    let regular: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(0.9)]
    var x: CGFloat = 18
    for (i, word) in ([app] + ["File", "Edit", "View", "Window", "Help"]).enumerated() {
        let s = NSAttributedString(string: word, attributes: i == 0 ? bold : regular)
        s.draw(at: NSPoint(x: x, y: c.size.height - h + 5))
        x += s.size().width + 20
    }

    let mono: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: ink]
    let title = NSAttributedString(string: dayhop, attributes: mono)
    let itemX = c.size.width - title.size().width - 24
    let item = NSRect(x: itemX - 8, y: 3, width: title.size().width + 16, height: 20)
    NSColor(white: dark ? 1 : 0, alpha: dark ? 0.18 : 0.10).setFill()
    NSBezierPath(roundedRect: c.rect(item.minX, item.minY, item.width, item.height), xRadius: 6, yRadius: 6).fill()
    title.draw(at: NSPoint(x: itemX, y: c.size.height - h + 5))

    for (i, symbol) in ["wifi", "battery.75percent", "magnifyingglass"].enumerated() {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r)
                ink.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(at: NSPoint(x: item.minX - 110 + CGFloat(i) * 34, y: c.size.height - h + (h - img.size.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    return item
}

/// The classic macOS arrow pointer with its tip at `tip` (top-left coordinates).
func cursor(_ c: Canvas, tip: NSPoint, scale k: CGFloat = 1) {
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.1, 13.1), (6.9, 19.4), (9.6, 18.2), (6.9, 12.1), (12.4, 12.1)]
    let path = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: tip.x + p.0 * k, y: c.size.height - tip.y - p.1 * k)
        i == 0 ? path.move(to: pt) : path.line(to: pt)
    }
    path.close()
    path.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.35)
    s.shadowBlurRadius = 3 * k
    s.shadowOffset = NSSize(width: 0, height: -1.5 * k)
    s.set()
    path.lineWidth = 2.6 * k
    NSColor.white.setStroke()
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.setFill()
    path.fill()
}

// MARK: - Mock windows (SwiftUI)

struct MockWindow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { c in
                        Circle().fill(Color(nsColor: hex(UInt32(c)))).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// NSPopover's rounded panel and arrow around the real popover content.
struct MockPopover<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: -1) {
            Triangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 22, height: 10)
            content
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// A document window, to have something on screen behind the reminder.
struct DocMock: View {
    var body: some View {
        MockWindow(title: "Q1 Roadmap.md") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Q1 Roadmap").font(.system(size: 28, weight: .bold))
                ForEach([0.92, 0.85, 0.97, 0.6, 0.0, 0.9, 0.8, 0.95, 0.4, 0.0, 0.88, 0.7], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(w == 0 ? 0 : 0.12))
                        .frame(width: 640 * w, height: 11)
                }
                Spacer()
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 760, height: 520)
    }
}

struct SettingsMock<Content: View>: View {
    let tab: String
    @ViewBuilder let content: Content

    var body: some View {
        MockWindow(title: "Dayhop Settings") {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(["General", "Clocks", "Calendars"], id: \.self) { item in
                        let on = item == tab
                        Text(item)
                            .font(.system(size: 13, weight: on ? .medium : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 3)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlColor))
                                        .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
                                }
                            }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                .padding(.top, 4)
                content
            }
        }
    }
}

// MARK: - Sample data

@MainActor func sampleEvents() -> [Item] {
    let cal = Calendar.autoupdatingCurrent
    let now = Date()
    let today = cal.startOfDay(for: now)
    func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: today)!)!
    }
    let work = Color(nsColor: .systemBlue), personal = Color(nsColor: .systemGreen), family = Color(nsColor: .systemPurple)
    func event(_ title: String, _ start: Date, minutes: Int, _ color: Color, link: String? = nil,
               calendar: String = "Work", location: String? = nil, allDay: Bool = false) -> Item {
        Item(id: "\(title)@\(start.timeIntervalSince1970)", eventID: "", title: title, start: start,
             end: start.addingTimeInterval(TimeInterval(minutes * 60)), allDay: allDay, color: color,
             meeting: link.flatMap(URL.init(string:)), calendar: calendar, location: location)
    }
    // The next meeting starts a few minutes from now, so the menu bar countdown and reminder have something to show.
    let next = Date(timeIntervalSince1970: ((now.timeIntervalSince1970 / 300).rounded(.up) + 1) * 300)

    var items = [
        event("Mia's birthday 🎂", today, minutes: 24 * 60, family, calendar: "Family", allDay: true),
        event("Standup", at(0, 9), minutes: 15, work, link: "https://meet.google.com/abc-defg-hij"),
        event("1:1 with Sam", at(0, 10, 30), minutes: 30, work, link: "https://zoom.us/j/1"),
        event("Design review", next, minutes: 45, work, link: "https://us02web.zoom.us/j/123456789"),
        event("Roadmap planning", next.addingTimeInterval(2 * 3600), minutes: 60, work, link: "https://teams.microsoft.com/l/meetup-join/1"),
        event("Climbing 🧗", at(0, 18, 30), minutes: 90, personal, calendar: "Personal", location: "Basecamp Gym"),
        event("Standup", at(1, 9), minutes: 15, work, link: "https://meet.google.com/abc-defg-hij"),
        event("Lunch with Ari", at(1, 12, 30), minutes: 60, personal, calendar: "Personal", location: "Pai"),
        event("Interview: iOS engineer", at(1, 15), minutes: 60, work, link: "https://zoom.us/j/2"),
    ]
    // A sprinkle across the month for the busy-day dots.
    for offset in [-12, -9, -8, -5, -2, 2, 3, 6, 9, 13, 16, 20] {
        items.append(event("Focus time", at(offset, 14), minutes: 120, work))
    }
    return items
}

// MARK: - Scenes

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    Prefs.register()
    let defaults = UserDefaults.standard
    defaults.set("Europe/London,Asia/Tokyo,America/Los_Angeles", forKey: Prefs.clocks)
    defaults.set(2, forKey: Prefs.agendaDays)
    defaults.set(true, forKey: Prefs.weekNumbers)
    defaults.set("EEE MMM d  h:mm a", forKey: Prefs.format)

    let events = Events()
    events.sample = sampleEvents()
    let now = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE MMM d  h:mm a"
    let upcoming = events.items(from: now, to: now.addingTimeInterval(31 * 60)).filter { !$0.allDay }
    let countdown = upcoming.lazy.compactMap { Logic.countdown(title: $0.title, start: $0.start, now: now) }.first
    let menuText = [countdown, formatter.string(from: now)].compactMap { $0 }.joined(separator: "  ·  ")

    for dark in [false, true] {
        let mode = dark ? "dark" : "light"

        // Hero: the popover open under the menu bar item, with the countdown in the menu bar.
        do {
            let c = Canvas(1100, 760)
            let popover = snapshot(MockPopover { PopoverView(events: events, openSettings: {}) }, dark: dark)
            let doc = snapshot(DocMock(), dark: dark)
            c.draw {
                wallpaper(c, dark: dark)
                let item = menuBar(c, dark: dark, app: "Notes", dayhop: menuText)
                c.place(doc, x: 50, y: 120, width: 640, shadow: 36, dark: dark)
                let x = min(item.midX - popover.size.width / 2, c.size.width - popover.size.width - 14)
                // Keep the arrow under the item even when the panel is pushed in from the edge.
                c.place(popover, x: x, y: 28, shadow: 36, dark: dark)
                cursor(c, tip: NSPoint(x: item.maxX - 40, y: item.maxY - 3))
            }
            c.save("hero-\(mode)")
        }

        // Reminder: a desktop blurred behind the real reminder view, as the overlay draws it.
        do {
            let c = Canvas(1100, 640)
            let doc = snapshot(DocMock(), dark: dark)
            let meeting = upcoming.first ?? events.sample![3]
            let soon = Item(id: "soon", eventID: "", title: meeting.title, start: now.addingTimeInterval(58),
                            end: now.addingTimeInterval(58 + meeting.end.timeIntervalSince(meeting.start)), allDay: false,
                            color: meeting.color, meeting: meeting.meeting, calendar: meeting.calendar)
            let reminder = snapshot(ReminderView(item: soon, close: {})
                .environment(\.controlActiveState, .key) // offscreen windows are never key; draw Join as it looks live
                .frame(width: 1000, height: 520), dark: dark)
            c.draw {
                wallpaper(c, dark: dark)
                menuBar(c, dark: dark, app: "Notes", dayhop: menuText)
                c.place(doc, x: 170, y: 70, shadow: 40, dark: dark)
            }
            let behind = blurred(c.image, radius: 28)
            c.draw {
                behind.draw(in: NSRect(origin: .zero, size: c.size))
                (dark ? NSColor.black.withAlphaComponent(0.42) : NSColor.white.withAlphaComponent(0.45)).setFill()
                NSRect(origin: .zero, size: c.size).fill(using: .sourceOver)
                c.place(reminder, x: (c.size.width - reminder.size.width) / 2, y: (c.size.height - reminder.size.height) / 2)
            }
            c.save("reminder-\(mode)")
        }

        // Settings: General behind, Clocks in front.
        do {
            let c = Canvas(1100, 760)
            let general = snapshot(SettingsMock(tab: "General") { GeneralTab(previewReminder: {}) }.frame(width: 500, height: 660), dark: dark)
            let clocks = snapshot(SettingsMock(tab: "Clocks") { ClocksTab() }.frame(width: 500, height: 420), dark: dark)
            c.draw {
                wallpaper(c, dark: dark)
                c.place(general, x: 50, y: 50, shadow: 34, dark: dark)
                c.place(clocks, x: 570, y: 290, shadow: 44, dark: dark)
            }
            c.save("settings-\(mode)")
        }
    }
}
