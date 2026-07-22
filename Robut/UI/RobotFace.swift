// RobotFace.swift — the menubar robot, and the app's entire at-a-glance UX.
//
// Colour carries the signal (it reads instantly, even peripherally); the
// expression reinforces it. Calm green means you'll comfortably make it to
// reset — and the point is that a glance is genuinely enough, so you only
// ever look closer when the robot stops looking calm.

import SwiftUI

/// Robot expressions, mapped from the worst-case pace across all windows.
enum RobotMood: Sendable, Hashable {
    case calm       // comfortable / idle
    case squint     // tight — you'll just make it
    case alarmed    // shortfall — you'll run dry early
    case dim        // unknown / nothing configured

    init(outlook: PaceOutlook?) {
        switch outlook {
        case .comfortable, .idle: self = .calm
        case .tight: self = .squint
        case .shortfall, .exhausted: self = .alarmed
        case .unknown, nil: self = .dim
        }
    }

    var tint: Color {
        switch self {
        case .calm: Color(red: 0.16, green: 0.79, blue: 0.50)
        case .squint: Color(red: 0.96, green: 0.71, blue: 0.20)
        case .alarmed: Color(red: 0.94, green: 0.33, blue: 0.31)
        case .dim: Color.secondary
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .calm: "Usage comfortable"
        case .squint: "Usage tight"
        case .alarmed: "Projected to run out before reset"
        case .dim: "Usage unknown"
        }
    }

    /// 8×8 pixel grid. `#` draws, anything else is transparent — the gaps
    /// are what form the eyes and mouth, exactly like the logo.
    var pixels: [String] {
        switch self {
        case .calm:
            ["   ##   ",
             "   ##   ",
             " ###### ",
             "########",
             "## ## ##",
             "########",
             "#  ##  #",
             " ###### "]
        case .squint:
            ["   ##   ",
             "   ##   ",
             " ###### ",
             "########",
             "########",
             "## ## ##",
             "#      #",
             " ###### "]
        case .alarmed:
            ["   ##   ",
             "   ##   ",
             " ###### ",
             "########",
             "# #  # #",
             "########",
             "#  ##  #",
             " #    # "]
        case .dim:
            ["   ##   ",
             "   ##   ",
             " ###### ",
             "########",
             "## ## ##",
             "########",
             "########",
             " ###### "]
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
