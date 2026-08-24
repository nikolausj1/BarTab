// ClaudeTileView.swift
//
// PRD §6.3's Claude usage tile: renders every gauge-shaped field the
// endpoint returned (whatever's in `model.claudeSnapshot.gauges`,
// generically -- mirrors DiskResource/VolumeRow's pattern of a per-item
// `ForEach` over already-shaped data) plus one of the six tile states.
//
// Per-gauge coloring uses the Claude thresholds against that gauge's own
// percent REMAINING, `(1 - fractionUsed) * 100` -- exactly parallel to
// VolumeRow's per-volume disk-threshold coloring. `Gauge` doesn't need a
// Claude-specific shape for this: it already carries `fractionUsed`, which
// is enough to invert back to percent remaining, matching Contract.swift's
// intent that `Gauge` serve any future resource generically.
//
// This tile always renders in full regardless of `barResources`/
// `barFormat` (PRD §6.3) -- those settings gate the bar only.

import SwiftUI

struct ClaudeTileView: View {
    @ObservedObject var model: AppModel

    private var warningPercent: Int { model.settings.claudeWarningPercent }
    private var criticalPercent: Int { model.settings.claudeCriticalPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Usage")
                .font(.subheadline)

            switch model.claudeTileState {
            case .loading:
                Text("Loading Claude usage…")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .ok:
                gaugesList

            case .stale(let asOf):
                gaugesList
                Text("as of \(Self.timeFormatter.string(from: asOf))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            case .unavailableNoCredentials:
                unavailableText(ClaudeUsageResource.ReasonText.noCredentials)

            case .unavailableExpiredToken:
                unavailableText("open Claude Code to refresh sign-in")

            case .unavailableEndpointDead:
                unavailableText(ClaudeUsageResource.ReasonText.endpointDead)
            }
        }
    }

    @ViewBuilder
    private var gaugesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.claudeSnapshot.gauges, id: \.label) { gauge in
                ClaudeGaugeRow(gauge: gauge, warningPercent: warningPercent, criticalPercent: criticalPercent)
            }
        }
    }

    private func unavailableText(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude usage unavailable")
                .font(.caption)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

private struct ClaudeGaugeRow: View {
    let gauge: Gauge
    let warningPercent: Int
    let criticalPercent: Int

    private var remainingPercent: Double { (1 - gauge.fractionUsed) * 100 }

    private var state: ResourceState {
        resourceState(
            value: remainingPercent,
            warningThreshold: Double(warningPercent),
            criticalThreshold: Double(criticalPercent)
        )
    }

    private var gaugeColor: Color {
        switch state {
        case .critical: return .red
        case .warning: return .yellow
        case .normal: return .green
        case .unavailable: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(gauge.label)
                .font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * gauge.fractionUsed)
                }
            }
            .frame(height: 6)
            Text(gauge.detailText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
