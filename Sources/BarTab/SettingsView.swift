// SettingsView.swift
//
// PRD §6.4 Settings window, opened via the flyout's gear menu "Settings…"
// item (FlyoutView, using SwiftUI's `openSettings` environment action —
// available even though this is an LSUIElement app with no App menu/Cmd-,
// since `openSettings()` doesn't depend on either). A single small pane:
// bar-resources and bar-format pickers, then disk and Claude threshold
// fields. All controls bind live to SettingsViewModel, which validates on
// every edit and writes through to AppSettings only when valid.

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var model: AppModel
    @StateObject private var viewModel: SettingsViewModel

    init(model: AppModel) {
        self.model = model
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settings: model.settings) { [weak model] in
            model?.recomputeBarState()
        })
    }

    var body: some View {
        Form {
            Section("Bar Contents") {
                Picker("Bar shows", selection: Binding(
                    get: { viewModel.barResources },
                    set: { viewModel.barResources = $0 }
                )) {
                    Text("Disk").tag(AppSettings.BarResources.disk)
                    Text("Claude").tag(AppSettings.BarResources.claude)
                    Text("Both").tag(AppSettings.BarResources.both)
                }
                .pickerStyle(.segmented)

                Picker("Format", selection: Binding(
                    get: { viewModel.barFormat },
                    set: { viewModel.barFormat = $0 }
                )) {
                    Text("Icon only").tag(AppSettings.BarFormat.iconOnly)
                    Text("Number only").tag(AppSettings.BarFormat.numberOnly)
                    Text("Icon + number").tag(AppSettings.BarFormat.iconAndNumber)
                }
                .pickerStyle(.segmented)
            }

            Section("Disk Thresholds (GB free)") {
                thresholdField(
                    "Warning", text: $viewModel.warningGBText, error: viewModel.warningGBError,
                    onCommit: viewModel.diskFieldsChanged
                )
                thresholdField(
                    "Critical", text: $viewModel.criticalGBText, error: viewModel.criticalGBError,
                    onCommit: viewModel.diskFieldsChanged
                )
            }

            Section("Claude Thresholds (% remaining)") {
                thresholdField(
                    "Warning", text: $viewModel.claudeWarningText, error: viewModel.claudeWarningError,
                    onCommit: viewModel.claudeFieldsChanged
                )
                thresholdField(
                    "Critical", text: $viewModel.claudeCriticalText, error: viewModel.claudeCriticalError,
                    onCommit: viewModel.claudeFieldsChanged
                )
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func thresholdField(
        _ label: String, text: Binding<String>, error: String?, onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: text)
                .onChange(of: text.wrappedValue) { _, _ in onCommit() }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}
