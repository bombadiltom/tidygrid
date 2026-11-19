// Draws the app icon: a blue rounded square with a white 2x2 grid, one cell filled.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let bg = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: bg, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.36, blue: 0.90, alpha: 1))!.draw(in: path, angle: -90)
    let inner = bg.insetBy(dx: s * 0.13, dy: s * 0.13)
    let gap = s * 0.035
    let cw = (inner.width - gap) / 2, ch = (inner.height - gap) / 2
    for r in 0..<2 { for c in 0..<2 {
        let cell = NSRect(x: inner.minX + CGFloat(c) * (cw + gap), y: inner.minY + CGFloat(r) * (ch + gap), width: cw, height: ch)
        let p = NSBezierPath(roundedRect: cell, xRadius: s * 0.03, yRadius: s * 0.03)
        NSColor.white.withAlphaComponent(r == 1 && c == 0 ? 1 : 0.35).setFill()
        p.fill()
    }}
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run(); task.waitUntilExit()
print("Wrote \(out)")
