// Theme.swift — Robut's design tokens, ported from the Robut Design System
// (the claude.ai design project). ONE place owns colour, metrics, radius,
// and motion, so every surface reads like Robut.
//
// The four STATUS colours are deliberately NOT duplicated here: their single
// source of truth is `RobotMood.nsTint` (RobotFace.swift), so the pane and
// the menubar icon can never drift. `Theme.status(_:)` surfaces them.

import SwiftUI

enum Theme {

    // MARK: - Colour

    enum Colors {
        // Surfaces — dark-native, cool near-black.
        static let void = Color(hex: 0x0A0B0D)
        static let panel = Color(hex: 0x16171A)        // the popover surface
        static let raised = Color(hex: 0x1C1E22)
        static let track = Color.white.opacity(0.10)   // meter track
        static let hover = Color.white.opacity(0.055)

        // Text ramp.
        static let textPrimary = Color(hex: 0xF3F4F6)
        static let textSecondary = Color(hex: 0x9CA0A8)
        static let textTertiary = Color(hex: 0x6A6E77)

        // macOS-style hairline separators.
        static let hairline = Color.white.opacity(0.08)

        // The one non-status accent: macOS system-blue links.
        static let link = Color(hex: 0x3B9DFF)

        // Brand.
        static let brandGreen = Color(hex: 0x29C980)
        static let paper = Color(hex: 0xF3ECDB)
    }

    /// Status colour for a mood — sourced from `RobotMood` so the pane and
    /// the menubar icon share one definition.
    static func status(_ mood: RobotMood) -> Color { mood.tint }

    // MARK: - Metrics (app-exact pane geometry)

    enum Metrics {
        static let paneWidth: CGFloat = 312
        static let padX: CGFloat = 14
        static let padY: CGFloat = 12
        static let headerTop: CGFloat = 12
        static let headerBottom: CGFloat = 4
        static let footerPad: CGFloat = 8
        static let rowGap: CGFloat = 14
    }

    // MARK: - Radius

    enum Radius {
        static let card: CGFloat = 8
        static let panel: CGFloat = 11
        static let block: CGFloat = 1   // segment-meter blocks
    }

    // MARK: - Motion

    enum Motion {
        /// Meters ease up to their value.
        static let bar = Animation.easeOut(duration: 0.6)
        /// Status colour cross-fades rather than popping.
        static let status = Animation.easeInOut(duration: 0.32)
    }
}
