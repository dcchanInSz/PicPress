//
//  Palette.swift
//  PicPress
//
//  Colours, byte formatting and small drawing helpers.
//

import AppKit

enum Palette {
    static var accent: NSColor { .controlAccentColor }

    static var positive: NSColor {
        NSColor(name: "positive") { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 0.36, green: 0.87, blue: 0.58, alpha: 1)
                : NSColor(srgbRed: 0.07, green: 0.58, blue: 0.33, alpha: 1)
        }
    }

    static var warning: NSColor {
        NSColor(name: "warning") { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 0.98, green: 0.70, blue: 0.33, alpha: 1)
                : NSColor(srgbRed: 0.75, green: 0.42, blue: 0.04, alpha: 1)
        }
    }

    static var hairline: NSColor { .separatorColor }

    static var rowHover: NSColor { NSColor.labelColor.withAlphaComponent(0.05) }

    /// Brand gradient used by the icon and the app icon.
    static var brandGradient: NSGradient {
        NSGradient(colors: [
            NSColor(srgbRed: 0.29, green: 0.62, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.47, green: 0.36, blue: 0.95, alpha: 1)
        ]) ?? NSGradient(colors: [accent, accent])!
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    /// Resolves a dynamic colour for the given appearance (AppKit has no
    /// `resolvedColor(with:)`, unlike UIKit).
    func cgColor(for appearance: NSAppearance) -> CGColor {
        var resolved = self.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.cgColor
        }
        return resolved
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// "-87%" when the file got smaller, "+12%" when it grew.
    static func savings(from source: Int, to output: Int) -> String {
        guard source > 0 else { return "—" }
        let ratio = (1 - Double(output) / Double(source)) * 100
        let rounded = Int(ratio.rounded())
        return rounded >= 0 ? "-\(rounded)%" : "+\(-rounded)%"
    }
}

enum Glyph {
    static func image(_ symbol: String,
                      pointSize: CGFloat,
                      weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}
