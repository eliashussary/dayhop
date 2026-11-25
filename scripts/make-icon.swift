// Renders Resources/AppIcon.icns. Run via `make icon`.
// Linkhop's hop, on a calendar page: a dotted arc from a faded day to today.
import AppKit

let canvas: CGFloat = 1024
let top = NSColor(srgbRed: 1.00, green: 0.50, blue: 0.36, alpha: 1)
let bottom = NSColor(srgbRed: 0.91, green: 0.23, blue: 0.33, alpha: 1)

func draw() {
    // macOS icon grid: 824pt tile centered on a 1024 canvas.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)

    // Calendar page with a soft shadow.
    let page = NSRect(x: 222, y: 230, width: 580, height: 560)
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    pageShadow.shadowBlurRadius = 30
    pageShadow.shadowOffset = NSSize(width: 0, height: -12)
    pageShadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: page, xRadius: 80, yRadius: 80).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Header band, clipped to the page's rounded top.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: page, xRadius: 80, yRadius: 80).addClip()
    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: page.minX, y: 650, width: page.width, height: 140), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    // Binder rings.
    NSColor.white.setFill()
    for x in [360.0, 664.0] {
        NSBezierPath(roundedRect: NSRect(x: x - 22, y: 690, width: 44, height: 64), xRadius: 22, yRadius: 22).fill()
    }

    // From-day (faded) and to-day (solid).
    bottom.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: NSRect(x: 292, y: 300, width: 120, height: 120), xRadius: 30, yRadius: 30).fill()
    bottom.setFill()
    NSBezierPath(roundedRect: NSRect(x: 612, y: 300, width: 120, height: 120), xRadius: 30, yRadius: 30).fill()

    // Dotted hop arc.
    let p0 = NSPoint(x: 352, y: 462), c1 = NSPoint(x: 362, y: 640)
    let c2 = NSPoint(x: 666, y: 640), p3 = NSPoint(x: 672, y: 480)
    let arc = NSBezierPath()
    arc.move(to: p0)
    arc.curve(to: p3, controlPoint1: c1, controlPoint2: c2)
    arc.lineWidth = 34
    arc.lineCapStyle = .round
    arc.setLineDash([0, 62], count: 2, phase: 0)
    bottom.setStroke()
    arc.stroke()

    // Arrowhead landing on today, aligned with the arc's end tangent.
    let dx = p3.x - c2.x, dy = p3.y - c2.y, len = (dx * dx + dy * dy).squareRoot()
    let d = NSPoint(x: dx / len, y: dy / len), n = NSPoint(x: -d.y, y: d.x)
    let tip = NSPoint(x: p3.x + d.x * 30, y: p3.y + d.y * 30)
    let base = NSPoint(x: p3.x - d.x * 48, y: p3.y - d.y * 48)
    let head = NSBezierPath()
    head.move(to: tip)
    head.line(to: NSPoint(x: base.x + n.x * 42, y: base.y + n.y * 42))
    head.line(to: NSPoint(x: base.x - n.x * 42, y: base.y - n.y * 42))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 16
    head.fill()
    head.stroke()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! png(size).write(to: out.appending(path: "icon_\(size)x\(size).png"))
    try! png(size * 2).write(to: out.appending(path: "icon_\(size)x\(size)@2x.png"))
}
