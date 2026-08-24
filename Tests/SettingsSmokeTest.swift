// SettingsSmokeTest.swift
//
// Plain-swiftc smoke test for SettingsViewModel's validation rules
// (PRD §6.4), against an isolated UserDefaults suite — never the real
// com.levelup.bartab domain. Same pattern as ContractSmokeTest.swift:
//
//   T=$(mktemp -d) && cp Tests/SettingsSmokeTest.swift "$T/main.swift" && \
//     swiftc -O Sources/BarTab/Contract.swift Sources/BarTab/SettingsViewModel.swift \
//       "$T/main.swift" -o "$T/t" && "$T/t"; rm -rf "$T"
//
// Prints PASS/FAIL counts and exits nonzero if anything failed.

import Foundation

var passCount = 0
var failCount = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        passCount += 1
    } else {
        failCount += 1
        print("FAIL: \(name)")
    }
}

var suiteNames: [String] = []

func freshSettings() -> AppSettings {
    let suiteName = "com.levelup.bartab.smoketest.\(UUID().uuidString)"
    suiteNames.append(suiteName)
    let defaults = UserDefaults(suiteName: suiteName)!
    return AppSettings(defaults: defaults)
}

@MainActor
func run() {
    // MARK: initial text fields mirror AppSettings' defaults

    let settings0 = freshSettings()
    let vm0 = SettingsViewModel(settings: settings0) {}
    check("warning GB text starts at default (50)", vm0.warningGBText == "50")
    check("critical GB text starts at default (20)", vm0.criticalGBText == "20")
    check("claude warning text starts at default (25)", vm0.claudeWarningText == "25")
    check("claude critical text starts at default (10)", vm0.claudeCriticalText == "10")

    // MARK: disk pair — critical < warning

    let settingsDiskPair = freshSettings()
    let vmDiskPair = SettingsViewModel(settings: settingsDiskPair) {}
    vmDiskPair.warningGBText = "30"
    vmDiskPair.criticalGBText = "40" // critical >= warning: invalid
    vmDiskPair.diskFieldsChanged()
    check("disk pair: critical >= warning is rejected (error shown)", vmDiskPair.criticalGBError != nil)
    check("disk pair: critical >= warning does not write warning", settingsDiskPair.warningThresholdGB == 50)
    check("disk pair: critical >= warning does not write critical", settingsDiskPair.criticalThresholdGB == 20)

    vmDiskPair.criticalGBText = "10" // now valid: 10 < 30
    vmDiskPair.diskFieldsChanged()
    check("disk pair: valid edit clears the error", vmDiskPair.criticalGBError == nil)
    check("disk pair: valid edit writes warning", settingsDiskPair.warningThresholdGB == 30)
    check("disk pair: valid edit writes critical", settingsDiskPair.criticalThresholdGB == 10)

    // MARK: disk bounds — clamp 1...5000

    let settingsDiskBounds = freshSettings()
    let vmDiskBounds = SettingsViewModel(settings: settingsDiskBounds) {}
    vmDiskBounds.warningGBText = "999999"
    vmDiskBounds.criticalGBText = "1"
    vmDiskBounds.diskFieldsChanged()
    check("disk bounds: value above 5000 clamps to 5000", settingsDiskBounds.warningThresholdGB == 5000)
    check("disk bounds: clamped value reflected back into the text field", vmDiskBounds.warningGBText == "5000")

    vmDiskBounds.warningGBText = "5000"
    vmDiskBounds.criticalGBText = "0" // below 1, clamps to 1
    vmDiskBounds.diskFieldsChanged()
    check("disk bounds: value below 1 clamps to 1", settingsDiskBounds.criticalThresholdGB == 1)

    // MARK: disk bounds — non-numeric is rejected, not clamped

    let settingsDiskInvalid = freshSettings()
    let vmDiskInvalid = SettingsViewModel(settings: settingsDiskInvalid) {}
    vmDiskInvalid.warningGBText = "abc"
    vmDiskInvalid.criticalGBText = "20"
    vmDiskInvalid.diskFieldsChanged()
    check("disk: non-numeric warning text shows an error", vmDiskInvalid.warningGBError != nil)
    check("disk: non-numeric warning text does not write", settingsDiskInvalid.warningThresholdGB == 50)
    check("disk: last-valid critical also untouched while warning invalid", settingsDiskInvalid.criticalThresholdGB == 20)

    // MARK: claude pair — critical < warning

    let settingsClaudePair = freshSettings()
    let vmClaudePair = SettingsViewModel(settings: settingsClaudePair) {}
    vmClaudePair.claudeWarningText = "15"
    vmClaudePair.claudeCriticalText = "15" // equal counts as violating "<"
    vmClaudePair.claudeFieldsChanged()
    check("claude pair: critical == warning is rejected", vmClaudePair.claudeCriticalError != nil)
    check("claude pair: rejected edit does not write", settingsClaudePair.claudeWarningPercent == 25)

    vmClaudePair.claudeCriticalText = "5"
    vmClaudePair.claudeFieldsChanged()
    check("claude pair: valid edit clears the error", vmClaudePair.claudeCriticalError == nil)
    check("claude pair: valid edit writes warning", settingsClaudePair.claudeWarningPercent == 15)
    check("claude pair: valid edit writes critical", settingsClaudePair.claudeCriticalPercent == 5)

    // MARK: claude bounds — clamp 1...99

    let settingsClaudeBounds = freshSettings()
    let vmClaudeBounds = SettingsViewModel(settings: settingsClaudeBounds) {}
    vmClaudeBounds.claudeWarningText = "150"
    vmClaudeBounds.claudeCriticalText = "1"
    vmClaudeBounds.claudeFieldsChanged()
    check("claude bounds: value above 99 clamps to 99", settingsClaudeBounds.claudeWarningPercent == 99)
    check("claude bounds: clamped value reflected back into text field", vmClaudeBounds.claudeWarningText == "99")

    vmClaudeBounds.claudeWarningText = "99"
    vmClaudeBounds.claudeCriticalText = "0"
    vmClaudeBounds.claudeFieldsChanged()
    check("claude bounds: value below 1 clamps to 1", settingsClaudeBounds.claudeCriticalPercent == 1)

    // MARK: onChange callback fires only on successful writes

    var changeCount = 0
    let settings6 = freshSettings()
    let vmCallback = SettingsViewModel(settings: settings6) { changeCount += 1 }
    vmCallback.warningGBText = "40"
    vmCallback.criticalGBText = "50" // invalid (critical >= warning)
    vmCallback.diskFieldsChanged()
    check("onChange does not fire for a rejected edit", changeCount == 0)
    vmCallback.criticalGBText = "10" // now valid
    vmCallback.diskFieldsChanged()
    check("onChange fires exactly once for a valid edit", changeCount == 1)

    // MARK: barResources / barFormat write straight through (no validation needed)

    let settingsPickers = freshSettings()
    let vmPickers = SettingsViewModel(settings: settingsPickers) {}
    vmPickers.barResources = .both
    check("barResources writes through", settingsPickers.barResources == .both)
    vmPickers.barFormat = .iconAndNumber
    check("barFormat writes through", settingsPickers.barFormat == .iconAndNumber)

    // Clean up every isolated suite this test created — never the real
    // com.levelup.bartab domain.
    for name in suiteNames {
        UserDefaults().removePersistentDomain(forName: name)
    }
}

// Plain top-level script code (this file, compiled as `main.swift`) isn't
// statically known to the compiler as MainActor-isolated even though it
// always runs on the main thread — `assumeIsolated` asserts that fact so
// `run()`'s MainActor-isolated SettingsViewModel calls can be made
// synchronously, matching how the real app runs (SwiftUI drives
// SettingsViewModel from the main thread too).
MainActor.assumeIsolated {
    run()
}

print("PASS: \(passCount)  FAIL: \(failCount)")
exit(failCount > 0 ? 1 : 0)
