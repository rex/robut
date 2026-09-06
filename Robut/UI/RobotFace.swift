// RobotFace.swift — the menubar robot, and the app's entire at-a-glance UX.
//
// Colour carries the signal (it reads instantly, even peripherally); the
// expression reinforces it. Calm green means you'll comfortably make it to
// reset — and the point is that a glance is genuinely enough, so you only
// ever look closer when the robot stops looking calm.

import AppKit
import SwiftUI

/// Robot expressions, mapped from the worst-case pace across all windows.
enum RobotMood: Sendable, Hashable {
    case calm       // comfortable / idle
    case squint     // tight — you'll just make it
    case alarmed    // shortfall — you'll run dry early
    case dim        // unknown / nothing configured

    /// Colour follows the verdict's ALARM, not its outlook. The outlook is
    /// factual ("you will run dry"); the alarm asks whether that costs you
    /// anything. A spent session and a blown week are both `.shortfall`-ish
    /// facts, and only one of them is worth turning the menubar red — see
    /// `PaceAlarm` and `PaceEngine.alarmLevel`.
    init(verdict: PaceVerdict?) {
        guard let verdict else { self = .dim; return }
        switch verdict.outlook {
        case .unknown:
            self = .dim
        case .comfortable, .idle:
            self = .calm
        case .tight, .shortfall, .exhausted:
            self = verdict.alarm == .alert ? .alarmed : .squint
        }
    }

    /// Loudest-wins ordering, for folding many windows into one icon.
    var rank: Int {
        switch self {
        case .dim: 0
        case .calm: 1
        case .squint: 2
        case .alarmed: 3
        }
    }

    /// The single source of truth for mood colour. It's an `NSColor`
    /// because the menubar icon is drawn with AppKit — see `RobotIcon`.
    var nsTint: NSColor {
        switch self {
        case .calm: NSColor(srgbRed: 0.16, green: 0.79, blue: 0.50, alpha: 1)
        case .squint: NSColor(srgbRed: 0.96, green: 0.71, blue: 0.20, alpha: 1)
        case .alarmed: NSColor(srgbRed: 0.94, green: 0.33, blue: 0.31, alpha: 1)
        // A concrete grey, NOT .secondaryLabelColor: dynamic catalog
        // colours resolve against an NSAppearance, and there isn't one
        // when drawing into an offscreen bitmap — they come out black or
        // fail outright. This grey reads acceptably on light and dark.
        case .dim: NSColor(srgbRed: 0.55, green: 0.56, blue: 0.58, alpha: 1)
        }
    }

    var tint: Color { Color(nsColor: nsTint) }

    var accessibilityDescription: String {
        switch self {
        case .calm: "Usage comfortable"
        case .squint: "Usage tight"
        case .alarmed: "Projected to run out before reset"
        case .dim: "Usage unknown"
        }
    }

    /// 16×16 pixel grid — the "antenna boxhead" (2026-09-06). `#` draws,
    /// anything else is transparent; the dark gaps are the eyes and mouth.
    ///
    /// ONE source for the menubar icon, the pane face, and the app icon
    /// (`Scripts/render-app-icon.swift` copies the calm face — change it
    /// here, re-render there). Keep it 16 wide: `RobotIcon` floors the
    /// cell to whole points against an 18pt bar, so a LARGER grid draws a
    /// SMALLER robot.
    var pixels: [String] {
        Self.crown + eyes + Self.brow + mouth + Self.torso
    }

    // Shared anatomy, top to bottom. 4 + 3 + 2 + 2 + 5 = 16 rows.
    private static let crown = [
        ".......##.......",   // antenna tip
        ".......##.......",   // antenna stem
        "..############..",
        ".##############.",
    ]
    private static let brow = [
        ".##############.",
        ".##############.",
    ]
    private static let torso = [
        "..############..",
        "......####......",   // neck
        "...##########...",   // shoulders
        "..############..",
        "................",
    ]

    /// Three rows. The eyes are dark 2-wide holes at columns 3–4 / 11–12;
    /// how many rows they occupy is the expression.
    private var eyes: [String] {
        let open = ".##..######..##."
        let solid = ".##############."
        return switch self {
        case .calm: [solid, open, open]
        case .squint, .dim: [solid, solid, open]   // half-closed / closed
        case .alarmed: [open, open, open]           // wide
        }
    }

    /// Two rows under the brow.
    private var mouth: [String] {
        let solid = ".##############."
        let grille = ".##.#.#..#.#.##."
        let flat = ".####......####."
        return switch self {
        case .calm: [grille, solid]
        case .squint: [flat, solid]
        case .alarmed: [flat, flat]                 // open
        case .dim: [solid, solid]                   // closed
        }
    }
}

/// Renders a `RobotMood` as crisp pixel art at any size.
struct RobotFace: View {
    let mood: RobotMood
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let grid = mood.pixels
            let columns = grid.map(\.count).max() ?? 8
            let rows = grid.count
            // Floor to whole points so pixels stay sharp instead of blurring
            // across a fractional boundary.
            let pixel = max(1, floor(min(canvasSize.width / CGFloat(columns),
                                         canvasSize.height / CGFloat(rows))))
            let originX = (canvasSize.width - pixel * CGFloat(columns)) / 2
            let originY = (canvasSize.height - pixel * CGFloat(rows)) / 2

            for (row, line) in grid.enumerated() {
                for (column, character) in line.enumerated() where character == "#" {
                    let rect = CGRect(
                        x: originX + CGFloat(column) * pixel,
                        y: originY + CGFloat(row) * pixel,
                        width: pixel,
                        height: pixel
                    )
                    context.fill(Path(rect), with: .color(mood.tint))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(mood.accessibilityDescription)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach([RobotMood.calm, .squint, .alarmed, .dim], id: \.self) { mood in
            RobotFace(mood: mood, size: 48)
        }
    }
    .padding()
}
