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

import AppKit

enum IconRenderer {
    /// Builds a solid-color, non-template NSImage of an SF Symbol by
    /// filling a color and using the glyph as a `.destinationIn` mask. This
    /// survives MenuBarExtra's monochrome-forcing because the image is
    /// explicitly marked `isTemplate = false`.
    static func coloredIcon(systemName: String, color: NSColor, pointSize: CGFloat = 16) -> NSImage {
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
}
