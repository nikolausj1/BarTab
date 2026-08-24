// AppModel.swift
//
// Drives the bar/flyout from DiskResource + AppSettings, on the PRD §6.6
// cadence: a 30-second timer, plus an immediate refresh whenever the flyout
// opens. Phase 2 adds the Settings window, so barResources can now reach
// .claude and .both — but ClaudeUsageResource itself doesn't exist until
// Phase 4, so Claude is wired to always vote `.unavailable` for now (see
// recomputeBarState below): its number renders "—" and it never drives the
// bar's color, exactly per PRD §6.1's "shown resource that is unavailable
// ... does not vote". Phase 4 only needs to replace that `.unavailable`
// with a real ClaudeUsageResource read.

import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var diskSnapshot = ResourceSnapshot(gauges: [], status: .unavailable(reason: "not yet loaded"))
    @Published private(set) var diskVolumes: [DiskVolumeState] = []
    @Published private(set) var barState: BarState = .normal

    let settings = AppSettings.shared

    private let diskResource = DiskResource()
    private var timer: Timer?
    private var didPrintStartupReading = false

    init() {
        // stdout is fully block-buffered when not attached to a TTY (e.g.
        // launched via `open` or piped to a log file), which would delay
        // the startup BOOT_FREE_GB line until the buffer filled or the
        // process exited. Force line buffering so it's visible immediately
        // — needed for the Phase 1 df cross-check.
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    /// Called on the 30s timer and again immediately whenever the flyout
    /// opens (PRD §6.6).
    func refresh() async {
        let snapshot = await diskResource.refresh()
        diskSnapshot = snapshot
        diskVolumes = diskResource.lastVolumes
        recomputeBarState()
        printStartupReadingIfNeeded()
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

    /// Recomputes `barState` from the current settings and last-read
    /// resource data. Called after every refresh, and also called directly
    /// by the Settings window (via `SettingsViewModel`'s `onChange`) after
    /// any successful settings edit, so the bar updates immediately without
    /// waiting for the next 30s timer tick or a relaunch (PRD §10 phase 2
    /// exit criterion).
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
            // ClaudeUsageResource doesn't exist until Phase 4. Claude always
            // votes .unavailable this phase: it never drives the bar color,
            // and its number always renders "—" (MenuBarIconView). This
            // means Claude-only renders the Unreadable state, and Both's
            // color is driven by disk alone — both exactly per PRD §6.1.
            states.append(.unavailable)
        }

        barState = aggregateBarState(states)
    }
}
