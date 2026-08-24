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

                // Phase 5 polish fix: this picker's own `Picker("Format",
                // ...)` label rendered nothing -- not merely hidden, but a
                // genuinely zero-width AXStaticText (confirmed via the
                // accessibility tree: `Format pos=(196,547) size=(0,96)`,
                // vs. "Bar shows"' correctly sized `size=(62,16)`).
                // Root cause, isolated by swapping the two Pickers' order
                // and re-measuring both times: it tracks the "Format"
                // picker specifically, not row position -- its three
                // segment labels ("Icon only" / "Number only" / "Icon +
                // number") are long enough that, at this window's 360pt
                // width, Form's automatic label-column sizing has no room
                // left for an inline label and silently collapses it to
                // zero rather than wrapping or overflowing. Rather than
                // widen the window or shorten those segment labels (both
                // reviewed and screenshotted in Phase 2), this stacks an
                // explicit, plain `Text("Format")` caption above the
                // picker instead of asking Form to fit it beside the
                // picker -- same row height budget, no competition for
                // horizontal space, and it's guaranteed to render because
                // it's a real, independently-sized view, not a value Form
                // computes and can collapse.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Format")
                    Picker("Format", selection: Binding(
                        get: { viewModel.barFormat },
                        set: { viewModel.barFormat = $0 }
                    )) {
                        Text("Icon only").tag(AppSettings.BarFormat.iconOnly)
                        Text("Number only").tag(AppSettings.BarFormat.numberOnly)
                        Text("Icon + number").tag(AppSettings.BarFormat.iconAndNumber)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
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
