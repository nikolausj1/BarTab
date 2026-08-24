// SettingsViewModel.swift
//
// Live-binding validation for the Settings window (PRD §6.4). AppSettings
// (Contract.swift, locked) has no validation of its own — its setters write
// whatever they're given. This view model is the validation layer that
// sits in front of it: text fields bind to @Published strings here, every
// edit is validated, and AppSettings is only written when the edit is
// fully valid. An invalid edit shows an inline error and leaves whatever
// was last written in AppSettings (and hence the bar) untouched.
//
// Two independent rules per PRD §6.4:
//   - Bounds: disk fields clamp to 1...5000, Claude fields to 1...99. A
//     non-numeric entry is rejected (error, nothing written); an in-range
//     but out-of-bounds number is clamped to the nearest bound and that
//     clamped value is what gets written (and reflected back into the
//     field, so clamping is visible, not silent).
//   - Pair rule: within each pair, critical must be < warning. Checked
//     after bounds-parsing both fields in the pair, since it's inherently
//     relational — if it fails, neither field's new value is written and
//     the critical field shows the error.

import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    private let settings: AppSettings
    private let onChange: () -> Void

    @Published var warningGBText: String
    @Published var criticalGBText: String
    @Published var claudeWarningText: String
    @Published var claudeCriticalText: String

    @Published private(set) var warningGBError: String?
    @Published private(set) var criticalGBError: String?
    @Published private(set) var claudeWarningError: String?
    @Published private(set) var claudeCriticalError: String?

    init(settings: AppSettings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        warningGBText = String(settings.warningThresholdGB)
        criticalGBText = String(settings.criticalThresholdGB)
        claudeWarningText = String(settings.claudeWarningPercent)
        claudeCriticalText = String(settings.claudeCriticalPercent)
    }

    var barResources: AppSettings.BarResources {
        get { settings.barResources }
        set {
            settings.barResources = newValue
            onChange()
        }
    }

    var barFormat: AppSettings.BarFormat {
        get { settings.barFormat }
        set {
            settings.barFormat = newValue
            onChange()
        }
    }

    /// Called whenever either disk threshold text field changes.
    func diskFieldsChanged() {
        let bounds = 1...5000
        let w = Self.parseClamped(warningGBText, bounds: bounds)
        let c = Self.parseClamped(criticalGBText, bounds: bounds)

        warningGBError = w == nil ? "Whole number, 1\u{2013}5000" : nil
        criticalGBError = c == nil ? "Whole number, 1\u{2013}5000" : nil
        guard let w = w, let c = c else { return }

        guard c < w else {
            criticalGBError = "Critical must be less than warning"
            return
        }

        settings.warningThresholdGB = w
        settings.criticalThresholdGB = c
        warningGBText = String(w)
        criticalGBText = String(c)
        onChange()
    }

    /// Called whenever either Claude threshold text field changes.
    func claudeFieldsChanged() {
        let bounds = 1...99
        let w = Self.parseClamped(claudeWarningText, bounds: bounds)
        let c = Self.parseClamped(claudeCriticalText, bounds: bounds)

        claudeWarningError = w == nil ? "Whole number, 1\u{2013}99" : nil
        claudeCriticalError = c == nil ? "Whole number, 1\u{2013}99" : nil
        guard let w = w, let c = c else { return }

        guard c < w else {
            claudeCriticalError = "Critical must be less than warning"
            return
        }

        settings.claudeWarningPercent = w
        settings.claudeCriticalPercent = c
        claudeWarningText = String(w)
        claudeCriticalText = String(c)
        onChange()
    }

    private static func parseClamped(_ text: String, bounds: ClosedRange<Int>) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Int(trimmed) else { return nil }
        return min(max(raw, bounds.lowerBound), bounds.upperBound)
    }
}
