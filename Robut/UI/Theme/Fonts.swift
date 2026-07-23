// Fonts.swift — Robut's self-hosted typefaces (Geist + Geist Mono).
//
// The design system splits type into two voices: Geist for UI, Geist Mono
// for numeric readouts (so ticking numbers don't jitter). Both ship as a
// single VARIABLE file each, so exact weights are selected through the
// `wght` axis via CoreText — SwiftUI's `.weight()` doesn't drive a variable
// axis reliably. Registration happens once, at runtime, from the bundle; if
// it ever fails the helpers fall back to the system font rather than crash.

import CoreText
import SwiftUI
import os

enum RobutFont {
    static let uiFamily = "Geist"
    static let monoFamily = "Geist Mono"

    /// Design weights (typography.css): 400 / 500 / 600 / 700.
    enum Weight {
        case regular, medium, semibold, bold

        var axisValue: Double {
            switch self {
            case .regular: 400
            case .medium: 500
            case .semibold: 600
            case .bold: 700
            }
        }
    }

    /// UI voice — Geist.
    static func ui(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        _ = registered
        return Font(variableFont(uiFamily, size: size, weight: weight))
    }

    /// Numeric / readout voice — Geist Mono.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        _ = registered
        return Font(variableFont(monoFamily, size: size, weight: weight))
    }

    // MARK: - Registration

    /// Registered exactly once per process — the first time a font is asked
    /// for, and eagerly from `AppDelegate`. Idempotent by construction.
    static let registered: Bool = registerBundledFonts()

    private static func registerBundledFonts() -> Bool {
        guard let urls = Bundle.main.urls(
            forResourcesWithExtension: "ttf", subdirectory: nil
        ) else { return false }

        var ok = true
        for url in urls where url.lastPathComponent.contains("Geist") {
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
                ok = false
                Log.app.error("font register failed for a bundled Geist file")
            }
        }
        return ok
    }

    // MARK: - Variable-axis selection

    /// 'wght' as a CoreText variation-axis identifier (four-char code).
    private static let wghtAxis = NSNumber(value: 0x7767_6874)

    private static func variableFont(
        _ family: String, size: CGFloat, weight: Weight
    ) -> CTFont {
        let variation = [wghtAxis: NSNumber(value: weight.axisValue)]
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: variation,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
