// ClaudeSmokeTest.swift
//
// Plain-swiftc smoke test for ClaudeUsageResource's pure parsing/mapping
// logic (Contract.swift's `Gauge`/`resourceState`, plus
// ClaudeUsageResource.swift's `parse`). Not an XCTest target — compiled
// standalone alongside Contract.swift and ClaudeUsageResource.swift, same
// pattern as Tests/ContractSmokeTest.swift:
//
//   T=$(mktemp -d) && cp Tests/ClaudeSmokeTest.swift "$T/main.swift" && \
//     swiftc -O Sources/BarTab/Contract.swift Sources/BarTab/ClaudeUsageResource.swift \
//       "$T/main.swift" -o "$T/t" && "$T/t"; rm -rf "$T"
//
// No network calls, no Keychain access — pure function tests against
// synthetic JSON fixtures. Prints PASS/FAIL counts and exits nonzero on
// any failure.

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

// MARK: utilization -> percent-remaining conversion (the one that must not
// be gotten backwards — a high utilization means LOW remaining means a
// WORSE (more critical) resourceState).

do {
    let highUsage = ["seven_day": ["utilization": 92.0, "resets_at": "2026-08-31T00:00:00Z"]] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: highUsage)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("weeklyPercentRemaining is 100 - utilization, not utilization itself",
          parsed.weeklyPercentRemaining == 8)
    check("high utilization (92% used) maps to LOW remaining (8%)",
          parsed.weeklyPercentRemaining! < 10)

    let state = resourceState(value: parsed.weeklyPercentRemaining!, warningThreshold: 25, criticalThreshold: 10)
    check("high utilization -> low remaining -> critical state (not normal/warning — the inversion must not be backwards)",
          state == .critical)
}

do {
    let lowUsage = ["seven_day": ["utilization": 5.0, "resets_at": "2026-08-31T00:00:00Z"]] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: lowUsage)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("low utilization (5% used) maps to HIGH remaining (95%)",
          parsed.weeklyPercentRemaining == 95)
    let state = resourceState(value: parsed.weeklyPercentRemaining!, warningThreshold: 25, criticalThreshold: 10)
    check("low utilization -> high remaining -> normal state",
          state == .normal)
}

// MARK: Gauge.fractionUsed uses utilization directly (usage-shaped, NOT
// inverted — the gauge bar fills as usage is consumed, opposite sense from
// the remaining-percent bar-vote value above).

do {
    let payload = ["seven_day": ["utilization": 62.0, "resets_at": "2026-08-31T16:30:00Z"]] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("Gauge.fractionUsed == utilization / 100 (usage-shaped, not remaining-shaped)",
          abs(parsed.gauges[0].fractionUsed - 0.62) < 0.0001)
    check("Gauge.detailText mentions percent used",
          parsed.gauges[0].detailText.contains("62%"))
    check("Gauge.resetDate is parsed from resets_at",
          parsed.gauges[0].resetDate != nil)
}

// MARK: representative multi-meter response -> Gauges

do {
    let payload: [String: Any] = [
        "five_hour": ["utilization": 40.0, "resets_at": "2026-08-24T20:00:00Z"],
        "seven_day": ["utilization": 30.0, "resets_at": "2026-08-31T00:00:00Z"],
        "seven_day_opus": ["utilization": 55.0, "resets_at": "2026-08-31T00:00:00Z"],
        "seven_day_sonnet": NSNull(),
        "extra_usage": ["is_enabled": false, "monthly_limit": NSNull(), "used_credits": NSNull(), "utilization": NSNull()],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!

    check("representative response yields 3 gauges (five_hour, seven_day, seven_day_opus)",
          parsed.gauges.count == 3)
    check("null seven_day_sonnet doesn't render a gauge",
          !parsed.meters.contains(where: { $0.key == "seven_day_sonnet" }))
    check("extra_usage never renders as a gauge (not gauge-shaped per spike)",
          !parsed.meters.contains(where: { $0.key == "extra_usage" }))
    check("five_hour renders (session meter) even though it doesn't vote",
          parsed.meters.contains(where: { $0.key == "five_hour" }))
    check("seven_day_opus (per-model) renders when present",
          parsed.meters.contains(where: { $0.key == "seven_day_opus" }))
}

// MARK: defensive handling — missing fields, unknown fields, malformed shapes

do {
    // Missing weekly entirely.
    let payload = ["five_hour": ["utilization": 10.0, "resets_at": "2026-08-24T20:00:00Z"]] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("missing seven_day yields nil weeklyPercentRemaining (doesn't crash, doesn't fabricate)",
          parsed.weeklyPercentRemaining == nil)
    check("missing seven_day still renders the meters that are present (five_hour)",
          parsed.gauges.count == 1)
}

do {
    // Unknown future field, dict-shaped with utilization+resets_at — should
    // render defensively rather than being ignored or crashing.
    let payload: [String: Any] = [
        "seven_day": ["utilization": 20.0, "resets_at": "2026-08-31T00:00:00Z"],
        "some_future_meter": ["utilization": 15.0, "resets_at": "2026-09-01T00:00:00Z"],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("unknown but meter-shaped field renders instead of crashing",
          parsed.meters.contains(where: { $0.key == "some_future_meter" }))
    check("unknown field still yields correct utilization",
          parsed.meters.first(where: { $0.key == "some_future_meter" })?.utilization == 15.0)
}

do {
    // Unknown field that is NOT meter-shaped (a plain string) — must not crash.
    let payload: [String: Any] = [
        "seven_day": ["utilization": 20.0, "resets_at": "2026-08-31T00:00:00Z"],
        "some_string_field": "unexpected shape",
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)
    check("non-dict unknown field is skipped, not crashed on", parsed != nil)
    check("non-dict unknown field doesn't render as a meter",
          parsed?.meters.contains(where: { $0.key == "some_string_field" }) == false)
}

do {
    // Malformed top-level JSON (an array, not an object).
    let data = "[1,2,3]".data(using: .utf8)!
    let parsed = ClaudeUsageResource.parse(data: data)
    check("malformed top-level JSON returns nil instead of crashing", parsed == nil)
}

do {
    // Empty object — no meters at all.
    let data = "{}".data(using: .utf8)!
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("empty object yields zero gauges, not a crash", parsed.gauges.isEmpty)
    check("empty object yields nil weeklyPercentRemaining", parsed.weeklyPercentRemaining == nil)
}

// MARK: weekly-meter-only voting rule (PRD §6.1 locked) — session meter
// renders but never appears as the bar-voting value.

do {
    // Session meter present, weekly absent: bar-voting value must be nil,
    // even though a gauge did render for the session meter.
    let payload = ["five_hour": ["utilization": 95.0, "resets_at": "2026-08-24T20:00:00Z"]] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("session meter alone (even at 95% used) never produces a bar-voting weeklyPercentRemaining",
          parsed.weeklyPercentRemaining == nil)
    check("session meter still rendered as a gauge for the tile",
          parsed.gauges.count == 1)
}

do {
    // Both present with very different values — voting value must come
    // from seven_day, not five_hour, regardless of which is worse.
    let payload: [String: Any] = [
        "five_hour": ["utilization": 99.0, "resets_at": "2026-08-24T20:00:00Z"], // session nearly exhausted
        "seven_day": ["utilization": 10.0, "resets_at": "2026-08-31T00:00:00Z"], // weekly barely used
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let parsed = ClaudeUsageResource.parse(data: data)!
    check("bar-voting value tracks seven_day (90% remaining), ignoring five_hour's near-exhaustion",
          parsed.weeklyPercentRemaining == 90)
    let state = resourceState(value: parsed.weeklyPercentRemaining!, warningThreshold: 25, criticalThreshold: 10)
    check("weekly-only voting: bar state is normal despite session meter being nearly critical",
          state == .normal)
}

// MARK: report

print("PASS: \(passCount)  FAIL: \(failCount)")
exit(failCount > 0 ? 1 : 0)
