// AppModel.swift
//
// Drives the bar/flyout from DiskResource + AppSettings, on the PRD §6.6
// cadence: a 30-second timer, plus an immediate refresh whenever the flyout
// opens. Phase 1 only wires up Disk; the Claude branch of the worst-of
// computation is left for Phase 4 (see recomputeBarState below) — there's
// no Settings picker yet to select barResources away from its .disk
// default, so it can't be reached in this phase.

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

    private func recomputeBarState() {
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
        // .claude / worst-of-with-claude: Phase 4. Unreachable in Phase 1
        // since barResources has no UI to leave its .disk default.

        barState = aggregateBarState(states)
    }
}
