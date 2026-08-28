// DiskResource.swift
//
// The Phase 1 `Resource` conformer for local disk volumes (PRD §6.3, §8).
//
// `Gauge` (Contract.swift) is deliberately generic — label/fraction/detail
// text/reset date — because it has to serve every future resource too. The
// flyout's per-volume gauge coloring needs each volume's own raw free-GB
// number against the disk thresholds (PRD §6.3: "colored by the same
// warning/critical thresholds applied to that volume's own free space"),
// which the generic Gauge shape doesn't carry. Rather than smuggle a number
// into Gauge's detailText via string parsing, DiskResource exposes the raw
// per-volume data (`lastVolumes`) alongside the protocol-required
// `ResourceSnapshot`, so callers that need real numbers (the flyout, the
// bar-state computation) can use them directly, and callers that only want
// the generic shape (a future "all resources" summary view) still can.

import Foundation

struct DiskVolumeState: Equatable {
    let name: String
    let freeGB: Int
    let totalGB: Int
    let fractionUsed: Double // 0...1, used space
}

enum DiskReadError: Error {
    case volumeUnavailable
}

final class DiskResource: Resource {
    let id = "disk"
    let displayName = "Disk"

    /// Boot volume first, then qualifying externals, alphabetical by name
    /// (PRD §6.3). Empty when the last refresh's boot read failed.
    private(set) var lastVolumes: [DiskVolumeState] = []

    /// The number that actually drives the bar's disk state (PRD §8: "disk:
    /// boot-volume strict free GB"). nil when the last refresh's boot read
    /// failed.
    private(set) var lastBootFreeGB: Int?

    /// Deliberately a fresh URL per access, never a stored one.
    /// `URL.resourceValues(forKeys:)` CACHES what it reads onto the URL
    /// instance, so a long-lived URL returns its first reading forever. That
    /// froze the menu bar on its launch value while the timer fired correctly
    /// every 30 seconds underneath — the app reported 12 GB for four days
    /// against a real 21 GB. Any volume URL used for a repeated measurement
    /// must be constructed fresh at the point of reading.
    private var bootURL: URL { URL(fileURLWithPath: "/") }

    func refresh() async -> ResourceSnapshot {
        do {
            let boot = try Self.readVolume(at: bootURL, fallbackName: "Macintosh HD")
            var volumes = [boot]
            volumes.append(contentsOf: Self.qualifyingExternalVolumes(excludingBoot: bootURL))

            lastVolumes = volumes
            lastBootFreeGB = boot.freeGB

            let gauges = volumes.map {
                Gauge(label: $0.name, fractionUsed: $0.fractionUsed, detailText: "\($0.freeGB) GB free of \($0.totalGB) GB")
            }
            return ResourceSnapshot(gauges: gauges, status: .ok)
        } catch {
            lastVolumes = []
            lastBootFreeGB = nil
            return ResourceSnapshot(gauges: [], status: .unavailable(reason: "boot volume free space unreadable"))
        }
    }

    // MARK: - Volume reading

    /// Strict free (PRD §9: `volumeAvailableCapacityKey`, NOT
    /// ...ForImportantUsage) and total capacity for one volume URL.
    static func readVolume(at url: URL, fallbackName: String) throws -> DiskVolumeState {
        let values = try url.resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        guard let free = values.volumeAvailableCapacity, let total = values.volumeTotalCapacity, total > 0 else {
            throw DiskReadError.volumeUnavailable
        }
        let name = values.volumeName ?? fallbackName
        return DiskVolumeState(
            name: name,
            freeGB: gbValue(Int64(free)),
            totalGB: gbValue(Int64(total)),
            fractionUsed: fractionUsed(free: Int64(free), total: Int64(total))
        )
    }

    /// Other local, writable, browsable mounted volumes (PRD §6.3's
    /// three-key filter), excluding the boot volume, sorted alphabetically.
    static func qualifyingExternalVolumes(excludingBoot bootURL: URL) -> [DiskVolumeState] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
            .volumeIsReadOnlyKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }

        let standardizedBoot = bootURL.standardizedFileURL
        var results: [DiskVolumeState] = []

        for url in urls {
            if url.standardizedFileURL == standardizedBoot { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsLocal == true,
                  values.volumeIsBrowsable == true,
                  values.volumeIsReadOnly == false else { continue }
            guard let free = values.volumeAvailableCapacity, let total = values.volumeTotalCapacity, total > 0 else { continue }

            let name = values.volumeName ?? url.lastPathComponent
            results.append(DiskVolumeState(
                name: name,
                freeGB: gbValue(Int64(free)),
                totalGB: gbValue(Int64(total)),
                fractionUsed: fractionUsed(free: Int64(free), total: Int64(total))
            ))
        }

        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// SI gigabytes (10^9 bytes), integer, matching `df -H` — locked in the
    /// Phase 1 brief.
    static func gbValue(_ bytes: Int64) -> Int {
        Int(bytes / 1_000_000_000)
    }

    static func fractionUsed(free: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let fraction = 1.0 - (Double(free) / Double(total))
        return max(0, min(1, fraction))
    }
}
