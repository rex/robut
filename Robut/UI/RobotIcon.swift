// RobotIcon.swift — the robot as a real NSImage, for the menubar.
//
// WHY THIS EXISTS, so nobody "simplifies" it back into a SwiftUI view:
//
// `MenuBarExtra`'s label is not a normal view. SwiftUI measures and
// rasterizes it to build an NSStatusItem, and a `Canvas` — which draws
// lazily into a GraphicsContext at display time and has no intrinsic
// size — comes out empty and ZERO WIDTH. The app runs, no crash, no log,
// and absolutely nothing appears in the menubar.
//
// It was caught by screenshotting the menubar with Robut running and
// again after quitting it: the two images were pixel-identical, so the
// status item was occupying no width at all.
//
// An `Image(nsImage:)` is the supported, reliable label content. The
// SwiftUI `RobotFace` is still used inside the pane, where Canvas works.

import AppKit

@MainActor
enum RobotIcon {
    /// Menubar icons are measured in points against a ~22pt bar; 18 sits
    /// right without crowding its neighbours.
    static let menuBarSize: CGFloat = 18

    private static var cache: [RobotMood: NSImage] = [:]

    static func image(for mood: RobotMood, size: CGFloat = menuBarSize) -> NSImage {
        if size == menuBarSize, let cached = cache[mood] { return cached }

        let image = NSImage(size: NSSize(width: size, height: size))
        if let rep = rasterize(mood: mood, size: size) {
            image.addRepresentation(rep)
        }

        // Not a template image: the colour IS the signal. A template
        // would be recoloured to the menubar's monochrome tint and the
        // whole at-a-glance design would be lost.
        image.isTemplate = false
        image.accessibilityDescription = mood.accessibilityDescription

        if size == menuBarSize { cache[mood] = image }
        return image
    }

    /// Draw the grid into a CONCRETE bitmap representation.
    ///
    /// This must not use `NSImage(size:flipped:drawingHandler:)`. That
    /// initializer is lazy — the handler doesn't run until AppKit draws
    /// the image, so the NSImage has no representation yet. AppKit copes;
    /// SwiftUI's `Image(nsImage:)` does not, and renders nothing at zero
    /// width. Same invisible-menubar symptom as the Canvas version, one
    /// layer down. Rasterizing up front fixes it for good.
    private static func rasterize(mood: RobotMood, size: CGFloat) -> NSBitmapImageRep? {
        let scale = 2  // Retina; the rep is tagged with its point size below.
        let pixels = Int(size) * scale

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: size, height: size)

        let grid = mood.pixels
        let columns = grid.map(\.count).max() ?? 8
        let rows = grid.count
        let pixel = (size / CGFloat(max(columns, rows))).rounded(.down)
        let originX = (size - pixel * CGFloat(columns)) / 2
        let originY = (size - pixel * CGFloat(rows)) / 2

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        mood.nsTint.setFill()
        for (row, line) in grid.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                // Origin is bottom-left here, so row 0 (the antenna)
                // has to be drawn at the TOP.
                NSRect(
                    x: originX + CGFloat(column) * pixel,
                    y: originY + CGFloat(rows - 1 - row) * pixel,
                    width: pixel,
                    height: pixel
                ).fill()
            }
        }
        return rep
    }
}
