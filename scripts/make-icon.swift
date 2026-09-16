import AppKit
import Foundation

// Draws the app icon and writes Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
//
// The mark is bd's lifecycle at a glance: a ring segmented into closed (green), in flight
// (amber) and open (blue), around a single bead. Small sizes get a heavier ring and wider gaps,
// because at 16pt the segments merge into a doughnut otherwise.

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let staging = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let open = color(0x4C9BFF)
let wip = color(0xF2A03D)
let done = color(0x53C07A)

func draw(_ s: CGFloat) {
    let inset = s * 0.055
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
    NSGradient(colors: [color(0x25333D), color(0x0E1417)])?.draw(in: plate, angle: -90)
    if s >= 64 {
        plate.lineWidth = s * 0.006
        color(0xFFFFFF, 0.14).setStroke()
        plate.stroke()
    }

    // Heavier and simpler as the icon gets smaller.
    let tiny = s <= 48
    let centre = NSPoint(x: s * 0.5, y: s * 0.5)
    let radius = s * (tiny ? 0.28 : 0.27)
    let width = s * (tiny ? 0.15 : 0.115)
    let gap: CGFloat = tiny ? 14 : 8
    let spans: [(CGFloat, CGFloat, NSColor)] = [(90, 210, done), (210, 330, wip), (330, 90, open)]
    for (start, end, colour) in spans {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius, startAngle: start + gap / 2, endAngle: end - gap / 2)
        arc.lineWidth = width
        arc.lineCapStyle = .butt
        colour.setStroke()
        arc.stroke()
    }
    let bead = s * (tiny ? 0.10 : 0.085)
    color(0xF5F7FA).setFill()
    NSBezierPath(ovalIn: NSRect(x: centre.x - bead, y: centre.y - bead, width: bead * 2, height: bead * 2)).fill()
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: staging)
try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: staging.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: staging.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", staging.path, "--output", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("wrote \(output.path)")
