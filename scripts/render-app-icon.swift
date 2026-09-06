#!/usr/bin/env swift
// render-app-icon.swift — the app icon, rendered from Robut's pixel robot.
//
// The icon IS the menubar robot: the calm 16×16 "antenna boxhead" from
// RobotFace.swift. Two outputs from the one grid:
//
//   1. The classic asset catalog (flat PNGs on the panel colour, in the
//      standard macOS icon footprint) — what macOS 15 and earlier show,
//      and Xcode's fallback.
//   2. A Liquid Glass Icon Composer document (`AppIcon.icon`) — layered
//      SVGs on a dark gradient, rendered by macOS 26 with glass, specular,
//      and per-layer shadow. The body and the antenna are separate layers
//      so the antenna reads as its own nub of glass.
//
//   swift scripts/render-app-icon.swift Robut/Assets.xcassets/AppIcon.appiconset Robut/AppIcon.icon
//
// The document schema is the one Icon Composer writes (verified against
// real documents: Sparkle's `Resources/AppIcon.icon` and two of this
// maintainer's own). Re-run after changing the grid or colours; outputs
// are committed so a fresh clone builds without running this.

import AppKit
import Foundation

// RobotMood.calm — keep in sync with RobotFace.swift.
let grid = [
    ".......##.......",
    ".......##.......",
    "..############..",
    ".##############.",
    ".##############.",
    ".##..######..##.",
    ".##..######..##.",
    ".##############.",
    ".##############.",
    ".##.#.#..#.#.##.",
    ".##############.",
    "..############..",
    "......####......",
    "...##########...",
    "..############..",
    "................",
]
let columns = 16
let rows = grid.count
/// Rows that form the antenna — its own glass layer in the .icon.
let antennaRows = 0..<2

// Theme.Colors.panel / .raised / .void, and RobotMood.calm.nsTint.
let panel = NSColor(srgbRed: 0x16 / 255, green: 0x17 / 255, blue: 0x1A / 255, alpha: 1)
let robot = NSColor(srgbRed: 0.16, green: 0.79, blue: 0.50, alpha: 1)
let robotHex = "#29C980"
let gradientTop = "extended-srgb:0.10980,0.11765,0.13333,1.00000"    // raised 0x1C1E22
let gradientBottom = "extended-srgb:0.03922,0.04314,0.05098,1.00000" // void   0x0A0B0D

// MARK: - Flat catalog PNGs

/// Asset-catalog slot → pixel size. Same pixels serve the 1x/2x pairs.
let slots: [(file: String, pixels: Int)] = [
    ("AppIcon-16.png", 16), ("AppIcon-16@2x.png", 32),
    ("AppIcon-32.png", 32), ("AppIcon-32@2x.png", 64),
    ("AppIcon-128.png", 128), ("AppIcon-128@2x.png", 256),
    ("AppIcon-256.png", 256), ("AppIcon-256@2x.png", 512),
    ("AppIcon-512.png", 512), ("AppIcon-512@2x.png", 1024),
]

func renderPNG(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a \(pixels)px bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    // macOS icon grid: the tile leaves ~10% margin on every side.
    let inset = floor(size * 0.10)
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = tile.width * 0.2237  // Apple's squircle proportion
    panel.setFill()
    NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()

    // The robot fills ~72% of the tile; whole-pixel cells, no seams.
    let cell = max(1, floor(tile.width * 0.72 / CGFloat(columns)))
    let originX = floor(tile.midX - cell * CGFloat(columns) / 2)
    let originY = floor(tile.midY - cell * CGFloat(rows) / 2)
    robot.setFill()
    for (row, line) in grid.enumerated() {
        for (column, character) in line.enumerated() where character == "#" {
            // AppKit is bottom-up; row 0 of the grid is the antenna tip.
            NSRect(
                x: originX + CGFloat(column) * cell,
                y: originY + CGFloat(rows - 1 - row) * cell,
                width: cell, height: cell
            ).fill()
        }
    }

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(pixels)px PNG")
    }
    return png
}

// MARK: - Liquid Glass document

/// One SVG layer on Icon Composer's 1024pt canvas: the selected rows of
/// the grid as crisp rects, the robot spanning ~72% of the canvas.
func svgLayer(rowsIncluded: (Int) -> Bool) -> String {
    let canvas = 1024.0
    let cell = (canvas * 0.72 / Double(columns)).rounded(.down)
    let originX = ((canvas - cell * Double(columns)) / 2).rounded(.down)
    let originY = ((canvas - cell * Double(rows)) / 2).rounded(.down)
    var rects: [String] = []
    for (row, line) in grid.enumerated() where rowsIncluded(row) {
        for (column, character) in line.enumerated() where character == "#" {
            let x = originX + Double(column) * cell
            let y = originY + Double(row) * cell   // SVG is top-down, like the grid
            rects.append(
                "  <rect x=\"\(Int(x))\" y=\"\(Int(y))\" width=\"\(Int(cell))\" height=\"\(Int(cell))\"/>"
            )
        }
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
    <g fill="\(robotHex)" shape-rendering="crispEdges">
    \(rects.joined(separator: "\n"))
    </g>
    </svg>

    """
}

func iconDocument() -> String {
    let gradient = """
        {
          "linear-gradient" : [ "\(gradientTop)", "\(gradientBottom)" ],
          "orientation" : { "start" : { "x" : 0, "y" : 0 }, "stop" : { "x" : 1, "y" : 1 } }
        }
    """
    return """
    {
      "fill-specializations" : [
        { "value" : \(gradient.trimmingCharacters(in: .whitespacesAndNewlines)) },
        { "appearance" : "dark", "value" : \(gradient.trimmingCharacters(in: .whitespacesAndNewlines)) }
      ],
      "groups" : [
        {
          "blend-mode" : "normal",
          "blur-material" : null,
          "hidden" : false,
          "layers" : [
            { "glass" : true, "hidden" : false, "image-name" : "01-body.svg", "name" : "01-body" }
          ],
          "lighting" : "individual",
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "specular" : true,
          "translucency" : { "enabled" : true, "value" : 0.35 }
        },
        {
          "blend-mode" : "normal",
          "blur-material" : null,
          "hidden" : false,
          "layers" : [
            { "glass" : true, "hidden" : false, "image-name" : "02-antenna.svg", "name" : "02-antenna" }
          ],
          "lighting" : "individual",
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "specular" : true,
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
      ],
      "supported-platforms" : { "circles" : [ "watchOS" ], "squares" : "shared" }
    }

    """
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: render-app-icon.swift <AppIcon.appiconset dir> <AppIcon.icon dir>\n".utf8)
    )
    exit(2)
}
let catalogDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let iconDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let assetsDirectory = iconDirectory.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: catalogDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

var cache: [Int: Data] = [:]
for slot in slots {
    let png = cache[slot.pixels] ?? renderPNG(pixels: slot.pixels)
    cache[slot.pixels] = png
    try png.write(to: catalogDirectory.appendingPathComponent(slot.file))
    print("wrote \(slot.file) (\(slot.pixels)px)")
}

try svgLayer(rowsIncluded: { !antennaRows.contains($0) })
    .write(to: assetsDirectory.appendingPathComponent("01-body.svg"), atomically: true, encoding: .utf8)
try svgLayer(rowsIncluded: { antennaRows.contains($0) })
    .write(to: assetsDirectory.appendingPathComponent("02-antenna.svg"), atomically: true, encoding: .utf8)
try iconDocument()
    .write(to: iconDirectory.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("wrote \(iconDirectory.lastPathComponent) (icon.json + 2 glass layers)")
