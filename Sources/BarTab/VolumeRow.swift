// VolumeRow.swift
//
// One flyout row per volume (PRD §6.3): name, gauge bar colored by that
// volume's own free space against the disk thresholds, and
// "X GB free of Y GB" text.

import SwiftUI

struct VolumeRow: View {
    let volume: DiskVolumeState
    let warningThresholdGB: Int
    let criticalThresholdGB: Int

    private var state: ResourceState {
        resourceState(
            value: Double(volume.freeGB),
            warningThreshold: Double(warningThresholdGB),
            criticalThreshold: Double(criticalThresholdGB)
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
            Text(volume.name)
                .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * volume.fractionUsed)
                }
            }
            .frame(height: 6)
            Text("\(volume.freeGB) GB free of \(volume.totalGB) GB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
