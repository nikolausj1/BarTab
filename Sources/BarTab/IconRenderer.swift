// IconRenderer.swift
//
// PRD §6.1 known trap: the menu bar renders template images monochrome, and
// SwiftUI's MenuBarExtra label often forces template rendering even when
// asked not to. `Image(systemName:).foregroundColor(...)` does not survive
// this in the bar (it gets flattened to the system's monochrome menu bar
// color). Warning/critical states need real yellow/red, so those states are
// rendered as a non-template NSImage built with an offscreen tint pass,
// wrapped in `Image(nsImage:)`. Normal/Unreadable stay template images so
// they keep tracking the system's light/dark menu bar appearance for free.
//
// Phase 2 found a second trap the same way (direct pixel measurement of
// screenshots, not guesswork): two *separate* `Image(nsImage:)` views built
// from independently-drawn non-template NSImages, placed side by side in
// the MenuBarExtra label's HStack, do not both render — only the first
// shows. A template NSImage next to a plain (uncolored) SwiftUI `Text`
// renders fine side by side; it's specifically two custom-drawn
// non-template images together that collapses to one. So the
// icon-and-text warning/critical combo is built as a *single* composited
// NSImage (`coloredIconWithText`) instead of two images in an HStack.

import AppKit

enum IconRenderer {
    /// Builds a solid-color, non-template NSImage of an SF Symbol by
    /// filling a color and using the glyph as a `.destinationIn` mask. This
    /// survives MenuBarExtra's monochrome-forcing because the image is
    /// explicitly marked `isTemplate = false`.
    static func coloredIcon(systemName: String, color: NSColor, pointSize: CGFloat = 16) -> NSImage {
        let tinted = tintedGlyph(systemName: systemName, color: color, pointSize: pointSize)
        tinted.isTemplate = false
        return tinted
    }

    /// Builds an explicit **template** NSImage of an SF Symbol, at a given
    /// opacity. Used for Normal/Unreadable instead of a bare SwiftUI
    /// `Image(systemName:)`, because on this OS build a bare Image inside
    /// MenuBarExtra's label was observed to render with no visible content
    /// at all (not merely losing color — literally invisible against the
    /// menu bar background) rather than reliably becoming a template image.
    /// Setting `isTemplate = true` explicitly on a real NSImage sidesteps
    /// whatever heuristic SwiftUI was failing to apply.
    static func templateIcon(systemName: String, pointSize: CGFloat = 16, opacity: CGFloat = 1.0) -> NSImage {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return NSImage()
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let glyph = base.withSymbolConfiguration(config) ?? base

        guard opacity < 1.0 else {
            glyph.isTemplate = true
            return glyph
        }

        let size = glyph.size
        let faded = NSImage(size: size)
        faded.lockFocus()
        glyph.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: opacity)
        faded.unlockFocus()
        faded.isTemplate = true
        return faded
    }

    /// Builds a solid-color, non-template NSImage of a text string, for the
    /// same reason `coloredIcon` exists: MenuBarExtra's label was found (by
    /// direct pixel measurement, Phase 2) to force a colored SwiftUI
    /// `Text(...).foregroundColor(...)` back to the default menu-bar text
    /// color, exactly like it forces colored `Image`s to template
    /// rendering. Drawing the string into an explicitly non-template
    /// NSImage survives that the same way `coloredIcon` does. Only
    /// warning/critical numbers need this — normal/unreadable numbers use
    /// plain SwiftUI `Text` with no color override, which was confirmed (by
    /// the same measurement) to render correctly. Use this alone
    /// (numberOnly format); for icon+number together use
    /// `coloredIconWithText` instead (see file header).
    static func coloredText(_ string: String, color: NSColor, pointSize: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSImage {
        let image = NSImage(size: textSize(string, pointSize: pointSize, weight: weight))
        image.lockFocus()
        attributedString(string, color: color, pointSize: pointSize, weight: weight).draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Builds one composited non-template NSImage containing both the tinted
    /// glyph and the colored text, glyph first. Required for the
    /// icon+number warning/critical combo — see file header for why two
    /// separate non-template images doesn't work here.
    static func coloredIconWithText(
        systemName: String, text: String, color: NSColor,
        pointSize: CGFloat = 16, textPointSize: CGFloat = 12, textWeight: NSFont.Weight = .medium, spacing: CGFloat = 4
    ) -> NSImage {
        let glyph = tintedGlyph(systemName: systemName, color: color, pointSize: pointSize)
        let glyphSize = glyph.size
        let attributed = attributedString(text, color: color, pointSize: textPointSize, weight: textWeight)
        let textSize = attributed.size()

        let totalHeight = max(glyphSize.height, textSize.height)
        let totalWidth = glyphSize.width + spacing + textSize.width
        let canvas = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        canvas.lockFocus()
        glyph.draw(
            at: NSPoint(x: 0, y: (totalHeight - glyphSize.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        attributed.draw(at: NSPoint(x: glyphSize.width + spacing, y: (totalHeight - textSize.height) / 2))
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }

    // MARK: - Shared drawing helpers

    private static func tintedGlyph(systemName: String, color: NSColor, pointSize: CGFloat) -> NSImage {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return NSImage()
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let glyph = base.withSymbolConfiguration(config) ?? base

        let size = glyph.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill()
        glyph.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()
        return tinted
    }

    private static func attributedString(_ string: String, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func textSize(_ string: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSSize {
        attributedString(string, color: .black, pointSize: pointSize, weight: weight).size()
    }
}
