// ContractSmokeTest.swift
//
// Plain-swiftc smoke test for Contract.swift's bar-state mapping. Not an
// XCTest target — compiled standalone alongside Contract.swift per the
// pattern in the Phase 1 brief:
//
//   T=$(mktemp -d) && cp Tests/ContractSmokeTest.swift "$T/main.swift" && \
//     swiftc -O Sources/BarTab/Contract.swift "$T/main.swift" -o "$T/t" && \
//     "$T/t"; rm -rf "$T"
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

// MARK: resourceState — normal / warning / critical, including boundaries

check("value well above warning threshold is normal",
      resourceState(value: 100, warningThreshold: 50, criticalThreshold: 20) == .normal)
check("value between thresholds is warning",
      resourceState(value: 35, warningThreshold: 50, criticalThreshold: 20) == .warning)
check("value exactly at warning threshold is warning (crossed, not normal)",
      resourceState(value: 50, warningThreshold: 50, criticalThreshold: 20) == .warning)
check("value exactly at critical threshold is critical (crossed, not warning)",
      resourceState(value: 20, warningThreshold: 50, criticalThreshold: 20) == .critical)
check("value well below critical threshold is critical",
      resourceState(value: 1, warningThreshold: 50, criticalThreshold: 20) == .critical)
check("resourceState also works for percent-remaining-shaped metrics (Claude, phase 4)",
      resourceState(value: 8, warningThreshold: 25, criticalThreshold: 10) == .critical)

// MARK: aggregateBarState — worst-of rule

check("worst-of: critical beats normal",
      aggregateBarState([.normal, .critical]) == .critical)
check("worst-of: warning beats normal",
      aggregateBarState([.normal, .warning]) == .warning)
check("worst-of: critical beats warning",
      aggregateBarState([.warning, .critical]) == .critical)
check("all normal stays normal",
      aggregateBarState([.normal, .normal]) == .normal)
check("unavailable resource does not vote; remaining normal wins",
      aggregateBarState([.unavailable, .normal]) == .normal)
check("unavailable resource does not vote; remaining critical wins",
      aggregateBarState([.unavailable, .critical]) == .critical)
check("all shown resources unavailable yields Unreadable",
      aggregateBarState([.unavailable, .unavailable]) == .unreadable)
check("no shown resources at all yields Unreadable",
      aggregateBarState([]) == .unreadable)
check("single normal resource stays normal",
      aggregateBarState([.normal]) == .normal)

// MARK: AppSettings — defaults from an isolated suite (never touches the
// real com.levelup.bartab domain)

let suiteName = "com.levelup.bartab.smoketest.\(UUID().uuidString)"
guard let testDefaults = UserDefaults(suiteName: suiteName) else {
    print("FAIL: could not create isolated UserDefaults suite for AppSettings test")
    failCount += 1
    print("PASS: \(passCount)  FAIL: \(failCount)")
    exit(1)
}
let settings = AppSettings(defaults: testDefaults)
check("default barResources is disk", settings.barResources == .disk)
check("default barFormat is iconOnly", settings.barFormat == .iconOnly)
check("default warningThresholdGB is 50", settings.warningThresholdGB == 50)
check("default criticalThresholdGB is 20", settings.criticalThresholdGB == 20)
check("default claudeWarningPercent is 25", settings.claudeWarningPercent == 25)
check("default claudeCriticalPercent is 10", settings.claudeCriticalPercent == 10)
settings.warningThresholdGB = 77
check("settings write round-trips", settings.warningThresholdGB == 77)
testDefaults.removePersistentDomain(forName: suiteName)

// MARK: report

print("PASS: \(passCount)  FAIL: \(failCount)")
exit(failCount > 0 ? 1 : 0)
