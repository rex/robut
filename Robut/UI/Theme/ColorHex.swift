// ColorHex.swift — hex → Color, the one place raw hex literals live.
//
// Robut's palette is defined once, in Theme, from the design system's
// tokens. This initializer keeps those definitions readable (0x16171A, not
// three divisions by 255) instead of scattering hex maths through the UI.

import SwiftUI

extension Color {
    /// `Color(hex: 0x16171A)` — opaque sRGB from a 24-bit RGB literal.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
