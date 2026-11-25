import AppKit

/// A small calendar page showing today's date, drawn as a template image so it follows the menu bar's appearance.
enum MenuBarIcon {
    static func image(day: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let page = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 1.25, width: 14.5, height: 14.5), xRadius: 3, yRadius: 3)
            page.lineWidth = 1.3
            page.stroke()
            // Header band: rounded on top, square where it meets the page.
            NSBezierPath(roundedRect: NSRect(x: 1.75, y: 11.25, width: 14.5, height: 4.5), xRadius: 3, yRadius: 3).fill()
            NSRect(x: 1.75, y: 11.25, width: 14.5, height: 2).fill()

            let text = "\(day)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: 9 - size.width / 2, y: 6.25 - size.height / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dayhop"
        return image
    }
}
