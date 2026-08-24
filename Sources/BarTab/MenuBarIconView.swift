// MenuBarIconView.swift
//
// Phase 1 renders icon-only mode only (barFormat's other two modes are
// Phase 2). Glyph family is "internaldrive" (PRD §7's delegated pick,
// presented at the Phase 1 screenshot review): "internaldrive" for
// normal/unreadable (template, tracks system appearance), "internaldrive.fill"
// filled yellow/red for warning/critical (non-template, see IconRenderer.swift
// for why).

import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.barState {
        case .normal:
            Image(nsImage: IconRenderer.templateIcon(systemName: "internaldrive"))
        case .warning:
            Image(nsImage: IconRenderer.coloredIcon(systemName: "internaldrive.fill", color: .systemYellow))
        case .critical:
            Image(nsImage: IconRenderer.coloredIcon(systemName: "internaldrive.fill", color: .systemRed))
        case .unreadable:
            // PRD §6.1: template image, reduced opacity fallback — SF Symbols
            // has no built-in "internaldrive with question mark" variant.
            Image(nsImage: IconRenderer.templateIcon(systemName: "internaldrive", opacity: 0.35))
        }
    }
}
