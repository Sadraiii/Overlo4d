import CoreText
import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// A colour that follows light/dark mode.
    public init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Colours from the Outdoor Office design system.
public enum Theme {
    public static let paper = Color(light: 0xEEF0EB, dark: 0x0F120F)
    public static let card = Color(light: 0xFAFBF8, dark: 0x191D19)
    public static let ink = Color(light: 0x151815, dark: 0xECEFE8)
    public static let ink2 = Color(light: 0x4A504A, dark: 0xB4BAB1)
    public static let ink3 = Color(light: 0x737A72, dark: 0x8A9288)
    public static let line = Color(light: 0xDADED6, dark: 0x2A302A)
    public static let line2 = Color(light: 0xC5CBC2, dark: 0x3A413A)
    public static let good = Color(light: 0x2C7748, dark: 0x6CCB8C)
    public static let goodSoft = Color(light: 0xD8EEDF, dark: 0x16301F)
    public static let danger = Color(light: 0xB0382C, dark: 0xF0897D)
    public static let hot = Color(light: 0xC4561A, dark: 0xF5A167)
    public static let band = Color(light: 0x2E332E, dark: 0x262B26)
    public static let bandInk = Color(light: 0xF3F4F0, dark: 0xECEFE8)

    public static var accentChoice: Accent {
        Accent(rawValue: SharedStorage.defaults.string(forKey: Accent.storageKey) ?? "") ?? .violet
    }

    public static var accent: Color { accentChoice.color }
    public static var accentInk: Color { accentChoice.ink }
    public static var accentSoft: Color { accentChoice.soft }
}

/// Accent colours, the same set as Outdoor Office.
public enum Accent: String, CaseIterable, Identifiable, Sendable {
    case violet, blue, teal, green, lime, gold, orange, red, pink, graphite

    public static let storageKey = "accent"

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    // (light, light ink, light soft, dark, dark ink, dark soft, swatch)
    private var hex: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .violet: (0x5A3E8A, 0xFFFFFF, 0xE8E1F2, 0xB9A0E6, 0x1B1229, 0x2A2240, 0x6B4E9B)
        case .blue: (0x2557A6, 0xFFFFFF, 0xDCE6F5, 0x8DB4F5, 0x0D1A30, 0x1B2740, 0x2E62B5)
        case .teal: (0x00707F, 0xFFFFFF, 0xD2EAEC, 0x6FD3DF, 0x032A30, 0x133136, 0x0A7F8F)
        case .green: (0x1F6B5C, 0xFFFFFF, 0xD6EBE5, 0x7FD1BC, 0x0B241E, 0x15302A, 0x237563)
        case .lime: (0x4A7212, 0xFFFFFF, 0xE2EDCF, 0xA9DB62, 0x172606, 0x233114, 0x5C8A1A)
        case .gold: (0x8A6200, 0xFFFFFF, 0xF3E7C6, 0xF2C14E, 0x2A1F00, 0x3A3012, 0xB98A10)
        case .orange: (0xA84A0C, 0xFFFFFF, 0xF6E3D6, 0xF2A66B, 0x2B1505, 0x3A2416, 0xC0590F)
        case .red: (0xB3261E, 0xFFFFFF, 0xF6DCDA, 0xF28B82, 0x3A0B07, 0x3D1C1A, 0xC0322A)
        case .pink: (0xA8295F, 0xFFFFFF, 0xF5DDE8, 0xF48FBF, 0x3A0A22, 0x3C1C2B, 0xC23C7A)
        case .graphite: (0x33393F, 0xFFFFFF, 0xDFE2E5, 0xC9CED6, 0x15181C, 0x2A2E33, 0x3D444B)
        }
    }

    public var color: Color { Color(light: hex.0, dark: hex.3) }
    public var ink: Color { Color(light: hex.1, dark: hex.4) }
    public var soft: Color { Color(light: hex.2, dark: hex.5) }
    public var swatch: Color { Color(uiColor: UIColor(hex: hex.6)) }
}

/// Light / dark / follow the phone.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let storageKey = "appearance"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Outdoor Office type: Big Shoulders Display for headings and numbers, Schibsted Grotesk for text.
public enum Typo {
    public enum Weight {
        case regular, medium, semibold, bold

        var fontName: String {
            switch self {
            case .regular: "SchibstedGrotesk-Regular"
            case .medium: "SchibstedGrotesk-Medium"
            case .semibold: "SchibstedGrotesk-SemiBold"
            case .bold: "SchibstedGrotesk-Bold"
            }
        }
    }

    /// Condensed display face. Use with uppercase text.
    public static func display(_ size: CGFloat, black: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(black ? "BigShouldersDisplayThin-Black" : "BigShouldersDisplayThin-ExtraBold", size: size, relativeTo: style)
    }

    public static func body(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }

    private static let fontFiles = [
        "BigShouldersDisplayThin-ExtraBold", "BigShouldersDisplayThin-Black",
        "SchibstedGrotesk-Regular", "SchibstedGrotesk-Medium", "SchibstedGrotesk-SemiBold", "SchibstedGrotesk-Bold",
    ]

    private static let registration: Void = {
        for name in fontFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the bundled fonts. Call once at launch in the app and in the widget extension.
    public static func registerFonts() {
        _ = registration
    }
}
