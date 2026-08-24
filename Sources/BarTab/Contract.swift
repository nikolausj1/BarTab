// Contract.swift
//
// The locked shared interface for BarTab's resource model (PRD §8).
// Pure Foundation only — no SwiftUI, no AppKit — so this file alone can be
// compiled and smoke-tested with plain `swiftc`.
//
// Later phases add new `Resource` conformers (e.g. ClaudeUsageResource) and
// new call sites for `resourceState` / `aggregateBarState`. They must not
// need to edit this file to do so.

import Foundation

// MARK: - Resource protocol (extension point, PRD §8)

/// Something BarTab can show "how much is left" of. v1 ships exactly two
/// conformers (Disk, Claude); the protocol exists so v2+ can add more
/// without touching bar/flyout rendering code.
protocol Resource {
    var id: String { get }
    var displayName: String { get }
    func refresh() async -> ResourceSnapshot
}

// MARK: - ResourceStatus / ResourceSnapshot / Gauge (PRD §8, exact shape)

enum ResourceStatus: Equatable {
    case ok
    case stale
    case unavailable(reason: String)
}

struct Gauge: Equatable {
    let label: String
    let fractionUsed: Double // 0...1
    let detailText: String
    let resetDate: Date? // nil for disk gauges; set for Claude meters

    init(label: String, fractionUsed: Double, detailText: String, resetDate: Date? = nil) {
        self.label = label
        self.fractionUsed = fractionUsed
        self.detailText = detailText
        self.resetDate = resetDate
    }
}

struct ResourceSnapshot: Equatable {
    let gauges: [Gauge]
    let status: ResourceStatus
}

// MARK: - Bar-state mapping (PRD §6.1, worst-of rule)

/// Per-resource state, before aggregation. `.unavailable` means the
/// resource does not vote in the worst-of computation.
enum ResourceState: Equatable {
    case normal
    case warning
    case critical
    case unavailable
}

/// The menu bar icon's rendered state (PRD §6.1's table).
enum BarState: Equatable {
    case normal
    case warning
    case critical
    case unreadable
}

/// Maps a single scalar metric to a `ResourceState` against warning/critical
/// thresholds where **lower is worse** — true for both disk's strict free GB
/// and Claude's weekly percent remaining (PRD §6.1), so both resources share
/// this one mapping function.
///
/// Boundary rule: a value exactly at a threshold counts as having crossed it
/// (`<=`), matching PRD §11's "flips exactly at the configured thresholds".
func resourceState(value: Double, warningThreshold: Double, criticalThreshold: Double) -> ResourceState {
    if value <= criticalThreshold { return .critical }
    if value <= warningThreshold { return .warning }
    return .normal
}

/// Combines the states of every resource currently shown in the bar
/// (`barResources`) into the bar's single rendered state. Severity order is
/// critical > warning > normal. `.unavailable` resources don't vote; if
/// nothing shown is available, the bar is Unreadable (PRD §6.1).
func aggregateBarState(_ states: [ResourceState]) -> BarState {
    let voting = states.filter { $0 != .unavailable }
    if voting.isEmpty { return .unreadable }
    if voting.contains(.critical) { return .critical }
    if voting.contains(.warning) { return .warning }
    return .normal
}

// MARK: - AppSettings (PRD §8, UserDefaults-backed)

/// UserDefaults-backed app settings. All six fields from the PRD §8 table,
/// with their defaults. Takes an injectable `UserDefaults` instance so it
/// can be smoke-tested against an isolated suite instead of the real
/// `com.levelup.bartab` domain.
final class AppSettings {
    enum BarResources: String {
        case disk
        case claude
        case both
    }

    enum BarFormat: String {
        case iconOnly
        case numberOnly
        case iconAndNumber
    }

    static let shared = AppSettings()

    private enum Keys {
        static let barResources = "barResources"
        static let barFormat = "barFormat"
        static let warningThresholdGB = "warningThresholdGB"
        static let criticalThresholdGB = "criticalThresholdGB"
        static let claudeWarningPercent = "claudeWarningPercent"
        static let claudeCriticalPercent = "claudeCriticalPercent"
    }

    private static let defaultValues: [String: Any] = [
        Keys.barResources: BarResources.disk.rawValue,
        Keys.barFormat: BarFormat.iconOnly.rawValue,
        Keys.warningThresholdGB: 50,
        Keys.criticalThresholdGB: 20,
        Keys.claudeWarningPercent: 25,
        Keys.claudeCriticalPercent: 10,
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultValues)
    }

    var barResources: BarResources {
        get { BarResources(rawValue: defaults.string(forKey: Keys.barResources) ?? "") ?? .disk }
        set { defaults.set(newValue.rawValue, forKey: Keys.barResources) }
    }

    var barFormat: BarFormat {
        get { BarFormat(rawValue: defaults.string(forKey: Keys.barFormat) ?? "") ?? .iconOnly }
        set { defaults.set(newValue.rawValue, forKey: Keys.barFormat) }
    }

    var warningThresholdGB: Int {
        get { defaults.integer(forKey: Keys.warningThresholdGB) }
        set { defaults.set(newValue, forKey: Keys.warningThresholdGB) }
    }

    var criticalThresholdGB: Int {
        get { defaults.integer(forKey: Keys.criticalThresholdGB) }
        set { defaults.set(newValue, forKey: Keys.criticalThresholdGB) }
    }

    var claudeWarningPercent: Int {
        get { defaults.integer(forKey: Keys.claudeWarningPercent) }
        set { defaults.set(newValue, forKey: Keys.claudeWarningPercent) }
    }

    var claudeCriticalPercent: Int {
        get { defaults.integer(forKey: Keys.claudeCriticalPercent) }
        set { defaults.set(newValue, forKey: Keys.claudeCriticalPercent) }
    }
}
