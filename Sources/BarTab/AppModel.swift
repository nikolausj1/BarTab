// AppModel.swift
//
// Drives the bar/flyout from DiskResource + ClaudeUsageResource +
// AppSettings, on the PRD §6.6 cadence: disk every 30 seconds, Claude every
// 5 minutes, both immediately whenever the flyout opens.
//
// Phase 4 replaces Phase 2's hardcoded Claude `.unavailable` vote with a
// real ClaudeUsageResource read. Per PRD §6.1 (locked), only the weekly
// meter votes on bar color -- `claudeResource.lastWeeklyPercentRemaining`
// is nil whenever the weekly meter is absent or unreadable, which is
// exactly the "doesn't vote" case, even if other meters (session, per-model)
// rendered fine in the flyout tile.

import Foundation
import Combine
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var diskSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: "not yet loaded"))
    @Published private(set) var diskVolumes: [DiskVolumeState] = []
    @Published private(set) var barState: BarState = .normal

    @Published private(set) var claudeSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: "not yet loaded"))
    @Published private(set) var claudeTileState: ClaudeTileState = .loading
    @Published private(set) var claudeWeeklyPercentRemaining: Double?

    let settings = AppSettings.shared

    private let diskResource = DiskResource()
    private let claudeResource = ClaudeUsageResource()
    private var diskTimer: Timer?
    private var claudeTimer: Timer?
    private var didPrintStartupReading = false

    /// Phase 4 evidence gathering only (PRD §10 phase 4 exit criterion:
    /// each of the six Claude tile states individually reachable). When
    /// set, a fixture state is applied once at launch and all real Claude
    /// fetches (initial, timer, and flyout-open refresh) are skipped
    /// entirely, so the injected state can't be clobbered by a live
    /// network/Keychain result. Inert unless the env var below is set.
    private let debugClaudeFixture: String? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["BARTAB_DEBUG_CLAUDE_STATE"]
        #else
        return nil
        #endif
    }()

    init() {
        // stdout is fully block-buffered when not attached to a TTY (e.g.
        // launched via `open` or piped to a log file), which would delay
        // the startup BOOT_FREE_GB line until the buffer filled or the
        // process exited. Force line buffering so it's visible immediately
        // — needed for the Phase 1 df cross-check.
        setvbuf(stdout, nil, _IOLBF, 0)

        // PRD §6.5 (locked): always-on login item, no setting. Best-effort,
        // idempotent, logs-only on failure -- see LoginItem.swift.
        LoginItem.registerIfNeeded()

        // A cache-restored snapshot (PRD §8) is a prior session's
        // successful fetch -- render it immediately as Stale rather than
        // Loading, so a relaunch doesn't lose the last-known numbers.
        if let initial = claudeResource.initialSnapshot, let fetchDate = claudeResource.lastGoodFetchDate {
            claudeSnapshot = initial
            claudeTileState = .stale(asOf: fetchDate)
            claudeWeeklyPercentRemaining = claudeResource.lastWeeklyPercentRemaining
        }

        Task { await refreshDisk() }

        startDiskTimer()
        preventAppNap()
        observeWake()

        #if DEBUG
        if let fixture = debugClaudeFixture {
            applyDebugClaudeFixture(named: fixture)
            return
        }
        #endif

        Task { await refreshClaude() }
        startClaudeTimer()
    }


    // MARK: - Staying current (PRD §6.6)
    //
    // A background LSUIElement app is a prime App Nap target, and a napped
    // process stops firing timers entirely. Left alone, the bar silently
    // freezes on whatever number it last read — observed in the field showing
    // 12 GB after four days when the disk actually had 21 GB. Three defences,
    // because any one of them alone has been seen to fail:
    //   1. schedule timers in .common modes rather than .default,
    //   2. tell the system this process must not be napped (while still
    //      allowing the Mac itself to sleep normally),
    //   3. refresh and rebuild the timers on every wake.

    private var activityToken: NSObjectProtocol?

    private func startDiskTimer() {
        diskTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshDisk() }
        }
        RunLoop.main.add(t, forMode: .common)
        diskTimer = t
    }

    private func startClaudeTimer() {
        claudeTimer?.invalidate()
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshClaude() }
        }
        RunLoop.main.add(t, forMode: .common)
        claudeTimer = t
    }

    /// Opt out of App Nap for the process lifetime. `.userInitiatedAllowingIdleSystemSleep`
    /// deliberately does NOT include `.idleSystemSleepDisabled` — this is a laptop, and a
    /// disk gauge has no business keeping it awake.
    private func preventAppNap() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep menu bar gauges current")
    }

    /// Refresh immediately on wake and rebuild both timers, so a stale reading
    /// can never outlive one sleep.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.startDiskTimer()
                    self.startClaudeTimer()
                    await self.refreshDisk()
                    await self.refreshClaude()
                }
        }
    }

    /// Called whenever the flyout opens (PRD §6.6: both resources refresh
    /// immediately on open, independent of their own timers). Skips the
    /// Claude half while a debug fixture is active, so opening the flyout
    /// during screenshot capture can't overwrite the injected state with a
    /// real fetch.
    func refresh() async {
        if debugClaudeFixture != nil {
            await refreshDisk()
        } else {
            async let d: () = refreshDisk()
            async let c: () = refreshClaude()
            _ = await (d, c)
        }
    }

    #if DEBUG
    /// Screenshot-verification only (Phase 4 evidence, PRD §6.3's six tile
    /// states). `name` is one of "loading", "ok", "stale",
    /// "no-credentials", "expired-token", "endpoint-dead" -- renders that
    /// state directly, without touching the Keychain or network. See
    /// `debugClaudeFixture` above for how this is gated and applied once.
    private func applyDebugClaudeFixture(named name: String) {
        let sampleGauges = [
            Gauge(label: "Session (5h)", fractionUsed: 0.40, detailText: "40% used · resets 6:00 PM", resetDate: Date().addingTimeInterval(3600)),
            Gauge(label: "Weekly (all models)", fractionUsed: 0.62, detailText: "62% used · resets Fri 4:30 PM", resetDate: Date().addingTimeInterval(86400 * 3)),
        ]
        switch name {
        case "loading":
            claudeSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: "not yet loaded"))
            claudeTileState = .loading
            claudeWeeklyPercentRemaining = nil
        case "ok":
            claudeSnapshot = ResourceSnapshot(gauges: sampleGauges, status: .ok)
            claudeTileState = .ok
            claudeWeeklyPercentRemaining = 38
        case "stale":
            claudeSnapshot = ResourceSnapshot(gauges: sampleGauges, status: .stale)
            claudeTileState = .stale(asOf: Date().addingTimeInterval(-1800))
            claudeWeeklyPercentRemaining = 38
        case "no-credentials":
            claudeSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: ClaudeUsageResource.ReasonText.noCredentials))
            claudeTileState = .unavailableNoCredentials
            claudeWeeklyPercentRemaining = nil
        case "expired-token":
            claudeSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: ClaudeUsageResource.ReasonText.expiredToken))
            claudeTileState = .unavailableExpiredToken
            claudeWeeklyPercentRemaining = nil
        case "endpoint-dead":
            claudeSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: ClaudeUsageResource.ReasonText.endpointDead))
            claudeTileState = .unavailableEndpointDead
            claudeWeeklyPercentRemaining = nil
        default:
            break
        }
        recomputeBarState()
    }
    #endif

    /// Called on the 30s disk timer and as part of `refresh()`.
    func refreshDisk() async {
        let snapshot = await diskResource.refresh()
        diskSnapshot = snapshot
        diskVolumes = diskResource.lastVolumes
        recomputeBarState()
        printStartupReadingIfNeeded()
    }

    /// Called on the 5-minute Claude timer and as part of `refresh()`.
    func refreshClaude() async {
        let snapshot = await claudeResource.refresh()
        claudeSnapshot = snapshot
        claudeWeeklyPercentRemaining = claudeResource.lastWeeklyPercentRemaining
        recomputeClaudeTileState()
        recomputeBarState()
    }

    /// Exit criterion #2 needs the app's own computed boot free GB printed
    /// to stdout at startup, to diff against `df -H` from outside the app.
    private func printStartupReadingIfNeeded() {
        guard !didPrintStartupReading else { return }
        didPrintStartupReading = true
        if let freeGB = diskResource.lastBootFreeGB {
            print("BOOT_FREE_GB=\(freeGB)")
        } else {
            print("BOOT_FREE_GB=unreadable")
        }
    }

    /// Maps the just-updated `claudeSnapshot` (plus `claudeResource`'s
    /// failure-reason detail, which `ResourceStatus.unavailable`'s single
    /// free-text string can't carry) into one of the flyout tile's six
    /// PRD §6.3 states.
    private func recomputeClaudeTileState() {
        switch claudeSnapshot.status {
        case .ok:
            claudeTileState = .ok
        case .stale:
            claudeTileState = .stale(asOf: claudeResource.lastGoodFetchDate ?? Date())
        case .unavailable:
            switch claudeResource.lastFailureReason {
            case .noCredentials:
                claudeTileState = .unavailableNoCredentials
            case .expiredToken:
                claudeTileState = .unavailableExpiredToken
            case .endpointDead, .none:
                claudeTileState = .unavailableEndpointDead
            }
        }
    }

    /// Recomputes `barState` from the current settings and last-read
    /// resource data. Called after every refresh, and also called directly
    /// by the Settings window (via `SettingsViewModel`'s `onChange`) after
    /// any successful settings edit, so the bar updates immediately without
    /// waiting for the next timer tick or a relaunch (PRD §10 phase 2 exit
    /// criterion).
    func recomputeBarState() {
        var states: [ResourceState] = []

        if settings.barResources == .disk || settings.barResources == .both {
            if let freeGB = diskResource.lastBootFreeGB {
                states.append(resourceState(
                    value: Double(freeGB),
                    warningThreshold: Double(settings.warningThresholdGB),
                    criticalThreshold: Double(settings.criticalThresholdGB)
                ))
            } else {
                states.append(.unavailable)
            }
        }

        if settings.barResources == .claude || settings.barResources == .both {
            // Locked (PRD §6.1): only the weekly meter votes, never the
            // 5-hour session meter. `claudeWeeklyPercentRemaining` (this
            // model's own @Published mirror of `claudeResource
            // .lastWeeklyPercentRemaining`, kept in sync by every real
            // `refreshClaude()`) is nil whenever `seven_day` is
            // absent/unreadable, which correctly makes Claude not-vote even
            // if other meters rendered in the tile.
            //
            // Phase 5 fix: this used to read `claudeResource
            // .lastWeeklyPercentRemaining` directly, which is
            // behavior-identical on every real fetch path but silently
            // couldn't be driven by the Phase 4 DEBUG fixture (which only
            // ever set the @Published mirror, not the private resource
            // object) -- so the bar's *color* vote for Claude was
            // impossible to exercise without a live, unexpired token, even
            // though the flyout tile's state and the bar's *number* text
            // both already read the mirror correctly. Reading the mirror
            // here too closes that gap with no change to any real-fetch
            // behavior.
            if let remaining = claudeWeeklyPercentRemaining {
                states.append(resourceState(
                    value: remaining,
                    warningThreshold: Double(settings.claudeWarningPercent),
                    criticalThreshold: Double(settings.claudeCriticalPercent)
                ))
            } else {
                states.append(.unavailable)
            }
        }

        barState = aggregateBarState(states)
    }
}
