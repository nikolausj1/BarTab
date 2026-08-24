// MenuBarIconView.swift
//
// Phase 2: renders all nine `barResources` x `barFormat` combinations
// (PRD §6.2). Two independent settings decide what's shown:
//
//   - Icon, when `barFormat` is iconOnly/iconAndNumber. Which glyph: the
//     disk family ("internaldrive", Phase 1's pick) whenever disk is part
//     of `barResources` (disk or both) — including Both+iconOnly, which
//     per §6.2 shows the disk glyph only, colored worst-of. Claude-only
//     uses its own glyph ("message", Phase 2's pick, presented at this
//     phase's screenshot review same as disk's in Phase 1). Warning/
//     critical/unreadable render the same glyph family through
//     IconRenderer exactly as Phase 1 established (colored non-template
//     for warning/critical, template for normal/unreadable) — that
//     rendering path is proven working (see EVIDENCE-NOTES.txt's lead
//     correction) and Phase 2 doesn't touch it, only which glyph name
//     feeds it.
//   - Number, when `barFormat` is numberOnly/iconAndNumber. Disk's number
//     is strict free GB ("47 GB"); Claude's number is weekly percent
//     remaining ("62%", PRD §6.2), sourced from
//     `model.claudeWeeklyPercentRemaining` (Phase 4) and rendering "—"
//     whenever that's nil (weekly meter absent/unreadable — matches it not
//     voting on bar state either). Both shows "47 GB · 62%". Whenever the
//     bar's overall state is Unreadable, the number collapses to a single
//     "—" regardless of which resource(s) are shown (PRD §6.1's table),
//     never a per-resource breakdown.
//
// Text color: measured directly (Phase 2 screenshot review), a colored
// SwiftUI `Text(...).foregroundColor(...)` does NOT survive MenuBarExtra's
// label — it gets forced back to the default menu-bar text color, the same
// monochrome-forcing IconRenderer.swift documents for Image. So warning/
// critical numbers go through IconRenderer.coloredText (a non-template
// NSImage), exactly parallel to coloredIcon; normal/unreadable numbers use
// plain SwiftUI Text with no override, which does render correctly.
//
// Icon+number layout: also measured directly, two separately-built
// non-template NSImages side by side in this HStack do not both render
// (only the first shows) — see IconRenderer.swift's header. So
// warning/critical's icon+number combo renders as one composited image
// (`coloredIconWithText`); normal/unreadable keeps the icon and number as
// two views (a template NSImage next to a plain, uncolored Text — proven
// to render correctly together).

import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var model: AppModel

    private enum Glyph {
        static let disk = "internaldrive"
        static let diskFill = "internaldrive.fill"
        // Claude's glyph, chosen for Phase 2 (PRD §6.2's delegated pick,
        // review-gated same as disk's Phase 1 pick): a single message
        // bubble, since Claude is a chat assistant and disk already
        // claims the literal "gauge" visual language via the flyout's
        // gauge bars. "message"/"message.fill" is a real SF Symbol pair
        // on macOS 14+ (verified), mirroring internaldrive's
        // base/filled-variant shape exactly.
        static let claude = "message"
        static let claudeFill = "message.fill"
    }

    private var resources: AppSettings.BarResources { model.settings.barResources }
    private var format: AppSettings.BarFormat { model.settings.barFormat }

    private var showsIcon: Bool { format == .iconOnly || format == .iconAndNumber }
    private var showsNumber: Bool { format == .numberOnly || format == .iconAndNumber }

    /// Both always shows the disk glyph only (PRD §6.2, explicit rule for
    /// Both+iconOnly, and Both's icon+number example shows one glyph too).
    private var usesDiskGlyph: Bool { resources == .disk || resources == .both }

    private var baseGlyph: String { usesDiskGlyph ? Glyph.disk : Glyph.claude }
    private var filledGlyph: String { usesDiskGlyph ? Glyph.diskFill : Glyph.claudeFill }

    var body: some View {
        switch (showsIcon, showsNumber, model.barState) {
        case (true, true, .warning):
            Image(nsImage: IconRenderer.coloredIconWithText(systemName: filledGlyph, text: numberText, color: .systemYellow))
        case (true, true, .critical):
            Image(nsImage: IconRenderer.coloredIconWithText(systemName: filledGlyph, text: numberText, color: .systemRed))
        case (true, true, .normal), (true, true, .unreadable):
            HStack(spacing: 4) {
                iconView
                numberView
            }
        case (true, false, _):
            iconView
        case (false, true, _):
            numberView
        case (false, false, _):
            EmptyView()
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch model.barState {
        case .normal:
            Image(nsImage: IconRenderer.templateIcon(systemName: baseGlyph))
        case .warning:
            Image(nsImage: IconRenderer.coloredIcon(systemName: filledGlyph, color: .systemYellow))
        case .critical:
            Image(nsImage: IconRenderer.coloredIcon(systemName: filledGlyph, color: .systemRed))
        case .unreadable:
            Image(nsImage: IconRenderer.templateIcon(systemName: baseGlyph, opacity: 0.35))
        }
    }

    @ViewBuilder
    private var numberView: some View {
        switch model.barState {
        case .warning:
            Image(nsImage: IconRenderer.coloredText(numberText, color: .systemYellow))
        case .critical:
            Image(nsImage: IconRenderer.coloredText(numberText, color: .systemRed))
        case .normal, .unreadable:
            Text(numberText)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var numberText: String {
        // Whole-bar Unreadable collapses to a single "—" (PRD §6.1's
        // table), never a per-resource breakdown.
        guard model.barState != .unreadable else { return "—" }

        switch resources {
        case .disk:
            return diskFreeText
        case .claude:
            return claudePercentText
        case .both:
            return "\(diskFreeText) · \(claudePercentText)"
        }
    }

    private var diskFreeText: String {
        guard let freeGB = model.diskVolumes.first?.freeGB else { return "—" }
        return "\(freeGB) GB"
    }

    private var claudePercentText: String {
        guard let remaining = model.claudeWeeklyPercentRemaining else { return "—" }
        return "\(Int(remaining.rounded()))%"
    }
}
