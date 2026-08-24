// FlyoutView.swift
//
// PRD §6.3: title row + gear menu (Settings… opens the Settings window as
// of Phase 2, via the `openSettings` environment action; Quit BarTab is
// the only quit affordance since LSUIElement means no Dock icon), then one
// row per qualifying volume, then the Claude usage tile (Phase 4). Both
// resources refresh immediately on open, per §6.6.

import SwiftUI

struct FlyoutView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BarTab")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Settings…") {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Divider()
                    Button("Quit BarTab") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            volumesSection

            Divider()

            ClaudeTileView(model: model)
        }
        .padding(12)
        .frame(width: 280)
        .task {
            await model.refresh()
        }
    }

    @ViewBuilder
    private var volumesSection: some View {
        switch model.diskSnapshot.status {
        case .unavailable:
            VStack(alignment: .leading, spacing: 3) {
                Text("Boot Volume")
                    .font(.subheadline)
                Text("free space unreadable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .ok, .stale:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.diskVolumes, id: \.name) { volume in
                    VolumeRow(
                        volume: volume,
                        warningThresholdGB: model.settings.warningThresholdGB,
                        criticalThresholdGB: model.settings.criticalThresholdGB
                    )
                }
            }
        }
    }
}
