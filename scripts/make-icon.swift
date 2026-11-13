import AppKit
import Foundation

// Draws Beady's mark and writes Resources/AppIcon.icns, docs/images/logo.svg and
// docs/images/logo-mono.svg. Run: swift scripts/make-icon.swift
//
// The mark is a caterpillar strung from beads, in fat pixels and one colour, like the mascots of
// the owner's other projects (CalcMark's lark, gh-velocity's tortoise). Every detail is a hole:
// each bead has the hole it's strung through, and the head is the bead with two — its beady
// eyes. One colour is what lets the same drawing be the app icon, a mark on a light or a dark
// page, a favicon and a template image.
//
// Every pixel of the drawing is a whole number of device pixels at every icon size, so the edges
// stay hard. The two smallest sizes show the head alone: the body is mush at 16pt.

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let staging = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let images = root.appendingPathComponent("docs/images")

// X is a pixel, '.' is nothing.
let mascot = [
    "..............X......X.",
    "...............X....X..",
    "...............X....X..",
    "...............XXXXXX..",
    "..............XXXXXXXX.",
    ".............XXXXXXXXXX",
    ".............XXX..XX..X",
    ".............XXX..XX..X",
    ".............XXXXXXXXXX",
    ".............XXXXXXXXXX",
    ".............XXXXXXXXXX",
    "........XXXX..XXXXXXXX.",
    ".......XXXXXX..XXXXXX..",
    ".......XX..XX...XX.....",
    ".XXXX..XX..XX..XXXX....",
    "XXXXXXXXXXXXXXXXXXXX...",
    "XX..XX..XXXX..XX..XX...",
    "XX..XX........XX..XX...",
    "XXXXXX........XXXXXX...",
    ".XXXX..........XXXX....",
    ".X..X..........X..X....",
]

let face = [
    "..X......X..",
    "...X....X...",
    "...XXXXXX...",
    "..XXXXXXXX..",
    ".XXXXXXXXXX.",
    ".XXX..X..XX.",
    ".XXX..X..XX.",
    ".XXX..X..XX.",
    ".XXXXXXXXXX.",
    ".XXXXXXXXXX.",
    "..XXXXXXXX..",
    "...XXXXXX...",
]

let brand: UInt32 = 0xFF3D7F // hot pink: the one colour of the mark, and none of the status colours
let ink: UInt32 = 0x161D22 // the mark on the app icon, where the plate is the brand colour
let plateTop: UInt32 = 0xFF5A92
let plateBottom: UInt32 = 0xE03670
let plateInset: CGFloat = 0.055
let plateCorner: CGFloat = 0.2237 // of the plate's width: the macOS icon shape, near enough

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The grid for an icon `pixels` wide, the size of one of its pixels, and where it starts.
func layout(_ pixels: Int) -> (grid: [String], cell: Int, x: Int, y: Int) {
    let grid = pixels <= 32 ? face : mascot
    let columns = grid[0].count
    let cell = max(1, Int(Double(pixels) * 0.75) / max(columns, grid.count))
    return (grid, cell, (pixels - columns * cell) / 2, (pixels - grid.count * cell) / 2)
}

/// Each row's runs of pixels, so a bead is a handful of rectangles rather than a pixel each.
func runs(_ grid: [String]) -> [(x: Int, y: Int, width: Int)] {
    var found: [(x: Int, y: Int, width: Int)] = []
    for (y, row) in grid.enumerated() {
        var start = 0
        let cells = Array(row)
        while start < cells.count {
            var end = start
            while end < cells.count, cells[end] == cells[start] { end += 1 }
            if cells[start] != "." { found.append((start, y, end - start)) }
            start = end
        }
    }
    return found
}

func draw(_ pixels: Int) {
    let s = CGFloat(pixels)
    let inset = s * plateInset
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * plateCorner, yRadius: rect.width * plateCorner)
    NSGradient(colors: [color(plateTop), color(plateBottom)])?.draw(in: plate, angle: -90)
    if pixels >= 64 {
        plate.lineWidth = s * 0.006
        color(0xFFFFFF, 0.22).setStroke()
        plate.stroke()
    }

    let (grid, cell, x, y) = layout(pixels)
    NSGraphicsContext.current?.shouldAntialias = false
    color(ink).setFill()
    for run in runs(grid) {
        // AppKit counts up from the bottom; the grid reads down from the top.
        NSRect(x: x + run.x * cell, y: pixels - y - (run.y + 1) * cell,
               width: run.width * cell, height: cell).fill()
    }
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(pixels)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The mark alone, on nothing, one unit to a pixel: for the README, the docs and anything that
/// tints it. `fill` is a colour, or `currentColor` to take the colour of the text around it.
func svg(fill: String) -> String {
    var lines = [
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(mascot[0].count) \(mascot.count)\" shape-rendering=\"crispEdges\">",
        "  <!-- Beady's mark. Written by scripts/make-icon.swift: edit the grid there. -->",
        "  <g id=\"mascot\" fill=\"\(fill)\">",
    ]
    for run in runs(mascot) {
        lines.append("    <rect x=\"\(run.x)\" y=\"\(run.y)\" width=\"\(run.width)\" height=\"1\"/>")
    }
    lines += ["  </g>", "</svg>", ""]
    return lines.joined(separator: "\n")
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

for (name, fill) in [("logo.svg", String(format: "#%06X", brand)), ("logo-mono.svg", "currentColor")] {
    let file = images.appendingPathComponent(name)
    try svg(fill: fill).write(to: file, atomically: true, encoding: .utf8)
    print("wrote \(file.path)")
}
