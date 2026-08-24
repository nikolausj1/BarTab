// ClaudeUsageResource.swift
//
// Phase 4's `Resource` conformer for Claude Code's usage endpoint (PRD
// §6.3, §6.6, §8, §9; mechanics confirmed by _review/phase3-spike/SPIKE.md).
//
// Keychain -> in-memory-only token read (never written to disk/log/stdout),
// one GET to the unofficial usage endpoint, defensive parsing of whatever
// meter-shaped fields are present, and a last-good-snapshot cache in
// UserDefaults (non-secret fields only) so the "stale" tile state survives
// relaunch (PRD §8).
//
// LOCKED CONVERSION (do not get this backwards): the endpoint's
// `utilization` is percent USED, 0-100. Contract.swift's `resourceState`
// wants "lower is worse" i.e. percent REMAINING, so any voting/threshold
// comparison uses `100 - utilization`. Only the weekly meter (`seven_day`)
// is exposed as `lastWeeklyPercentRemaining` for AppModel's bar vote (PRD
// §6.1: session/5h never colors the bar). Pinned explicitly in
// Tests/ClaudeSmokeTest.swift.
//
// PRD §6.3: "renders every gauge-shaped field... fields the endpoint
// doesn't return simply don't render... never assumes a fixed shape." So
// `parse` iterates whatever dict-shaped, utilization-bearing fields are
// present rather than hardcoding five_hour/seven_day/seven_day_opus/
// seven_day_sonnet -- those four plus `extra_usage` are simply what the
// spike documented as *currently* present. `extra_usage` is explicitly
// skipped (spike's recommendation: it isn't gauge-shaped -- no fixed 0...1
// fraction when the pay-as-you-go tier is disabled).

import Foundation
import Security

/// One rendered meter, generic over whatever JSON key produced it.
/// Codable so a non-secret subset (no token, ever) can round-trip through
/// the UserDefaults cache.
struct ClaudeMeter: Equatable, Codable {
    let key: String // raw JSON key, e.g. "seven_day" -- used to find the weekly vote
    let label: String // human label for the tile
    let utilization: Double // 0-100, percent USED, raw from the endpoint
    let resetsAt: Date?
}

/// Why the most recent fetch attempt failed, when it did. Distinguishes the
/// three PRD §6.3 "unavailable" sub-states. Not part of Contract.swift's
/// `ResourceStatus` (that only carries a free-text reason string) --
/// AppModel reads this alongside the `ResourceSnapshot` to pick tile copy.
enum ClaudeFailureReason: Equatable {
    case noCredentials
    case expiredToken
    case endpointDead
}

/// The flyout Claude tile's six states (PRD §6.3's table). Lives outside
/// Contract.swift (locked) since "loading" has no equivalent in
/// `ResourceStatus` -- it's a launch-time UI concern, not a fetch outcome.
enum ClaudeTileState: Equatable {
    case loading
    case ok
    case stale(asOf: Date)
    case unavailableNoCredentials
    case unavailableExpiredToken
    case unavailableEndpointDead
}

final class ClaudeUsageResource: Resource {
    let id = "claude"
    let displayName = "Claude"

    enum ReasonText {
        static let noCredentials = "Claude Code credentials not found in Keychain"
        static let expiredToken = "Claude Code's sign-in has expired"
        static let endpointDead = "Claude usage endpoint unreachable"
    }

    /// Gauges from the most recent successful fetch (live), or -- failing
    /// that -- the most recent successful fetch restored from the
    /// UserDefaults cache at launch (PRD §8). Empty only when neither
    /// exists yet.
    private(set) var lastGauges: [Gauge] = []
    private(set) var lastMeters: [ClaudeMeter] = []
    /// Weekly percent REMAINING, already inverted from utilization -- the
    /// sole bar-voting number (PRD §6.1). nil when the weekly meter is
    /// absent from the response, or no data exists at all.
    private(set) var lastWeeklyPercentRemaining: Double?
    /// When the last *successful* fetch happened (live this session, or --
    /// at launch, before any refresh() call -- restored from cache). Drives
    /// the Stale tile's "as of <time>" text.
    private(set) var lastGoodFetchDate: Date?
    /// Why the most recent fetch attempt failed; nil if it succeeded.
    private(set) var lastFailureReason: ClaudeFailureReason?

    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheKey: String

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, cacheKey: String = "claudeUsageCache") {
        self.session = session
        self.defaults = defaults
        self.cacheKey = cacheKey
        loadCacheIfPresent()
    }

    /// Best snapshot to show before any `refresh()` call completes this
    /// session. If a cache was restored at launch, that's an existing
    /// snapshot from a prior session's successful fetch -- per PRD §6.3's
    /// Stale trigger ("most recent fetch failed, but a prior snapshot
    /// exists" -- nothing has been fetched *this* session yet, so it
    /// trivially qualifies), render it as Stale immediately rather than
    /// Loading. nil (renders Loading) only when no cache exists at all.
    var initialSnapshot: ResourceSnapshot? {
        guard lastGoodFetchDate != nil, !lastGauges.isEmpty else { return nil }
        return ResourceSnapshot(gauges: lastGauges, status: .stale)
    }

    // MARK: - Resource

    func refresh() async -> ResourceSnapshot {
        guard let token = Self.readAccessToken() else {
            return fail(.noCredentials)
        }

        let request = Self.buildRequest(token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return fail(.endpointDead)
        }

        guard let http = response as? HTTPURLResponse else {
            return fail(.endpointDead)
        }

        if http.statusCode == 200 {
            guard let parsed = Self.parse(data: data) else {
                // Totally unparseable body -- degrade soft, don't crash.
                return fail(.endpointDead)
            }
            lastMeters = parsed.meters
            lastGauges = parsed.gauges
            lastWeeklyPercentRemaining = parsed.weeklyPercentRemaining
            lastGoodFetchDate = Date()
            lastFailureReason = nil
            persistCache()
            return ResourceSnapshot(gauges: parsed.gauges, status: .ok)
        }

        if http.statusCode == 401 {
            // Spike-documented typed body:
            // {"type":"error","error":{"type":"authentication_error","message":"OAuth access token has expired..."}}
            if Self.isAuthenticationError(data: data) {
                return fail(.expiredToken)
            }
            return fail(.endpointDead)
        }

        return fail(.endpointDead)
    }

    // MARK: - Failure handling (falls back to cache -> stale, else -> unavailable)

    private func fail(_ reason: ClaudeFailureReason) -> ResourceSnapshot {
        lastFailureReason = reason
        if lastGoodFetchDate != nil, !lastGauges.isEmpty {
            // PRD §6.3's Stale trigger is just "fetch failed, prior
            // snapshot exists" -- it doesn't distinguish *why* the fetch
            // failed, so any of the three failure reasons falls back to
            // Stale whenever a snapshot (live or cache-restored) exists.
            return ResourceSnapshot(gauges: lastGauges, status: .stale)
        }
        let text: String
        switch reason {
        case .noCredentials: text = ReasonText.noCredentials
        case .expiredToken: text = ReasonText.expiredToken
        case .endpointDead: text = ReasonText.endpointDead
        }
        return ResourceSnapshot(gauges: [], status: .unavailable(reason: text))
    }

    // MARK: - Keychain (in-memory only -- never written to disk, log, or stdout)

    /// Reads Claude Code's OAuth access token from the macOS Keychain.
    /// `SecItemCopyMatching` returns the secret `Data` directly into memory
    /// -- no temp file, unlike the Phase 3 spike script's shell approach
    /// (which this app deliberately does not repeat). The token is held
    /// only in local `let`/`var` bindings for the lifetime of this call and
    /// the subsequent HTTP request; it is never logged, printed, or
    /// persisted.
    private static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    // MARK: - HTTP

    private static func buildRequest(token: String) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func isAuthenticationError(data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        guard let error = obj["error"] as? [String: Any] else { return false }
        return (error["type"] as? String) == "authentication_error"
    }

    // MARK: - Parsing (defensive: renders whatever meter-shaped fields exist)

    struct ParsedUsage {
        let meters: [ClaudeMeter]
        let gauges: [Gauge]
        let weeklyPercentRemaining: Double?
    }

    private static let knownLabels: [String: String] = [
        "five_hour": "Session (5h)",
        "seven_day": "Weekly (all models)",
        "seven_day_opus": "Weekly (Opus)",
        "seven_day_sonnet": "Weekly (Sonnet)",
    ]

    /// Fields that are never treated as a meter even if dict-shaped --
    /// `extra_usage` doesn't have a fixed 0...1 fraction when the
    /// pay-as-you-go tier is disabled (spike's recommendation).
    private static let excludedKeys: Set<String> = ["extra_usage"]

    /// Known display order first (matches the spike's documented shape:
    /// session, then weekly, then per-model weekly), then any unrecognized
    /// meter-shaped keys alphabetically -- so an unknown future field still
    /// renders, deterministically, rather than being silently dropped.
    private static let knownKeyOrder = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]

    static func parse(data: Data) -> ParsedUsage? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var meters: [ClaudeMeter] = []
        var seen = Set<String>()

        func meter(forKey key: String, value: Any) -> ClaudeMeter? {
            guard !excludedKeys.contains(key) else { return nil }
            guard let dict = value as? [String: Any] else { return nil } // null, or not a meter -- skip, don't crash
            let utilization: Double?
            if let d = dict["utilization"] as? Double {
                utilization = d
            } else if let i = dict["utilization"] as? Int {
                utilization = Double(i)
            } else {
                utilization = nil
            }
            guard let utilization else { return nil }
            let resetsAt = parseDate(dict["resets_at"] as? String)
            let label = knownLabels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            return ClaudeMeter(key: key, label: label, utilization: utilization, resetsAt: resetsAt)
        }

        for key in knownKeyOrder {
            guard let value = top[key] else { continue }
            if let m = meter(forKey: key, value: value) {
                meters.append(m)
            }
            seen.insert(key)
        }
        for (key, value) in top.sorted(by: { $0.key < $1.key }) {
            guard !seen.contains(key) else { continue }
            if let m = meter(forKey: key, value: value) {
                meters.append(m)
            }
        }

        let weeklyRemaining = meters.first(where: { $0.key == "seven_day" }).map { 100 - $0.utilization }
        return ParsedUsage(meters: meters, gauges: gauges(from: meters), weeklyPercentRemaining: weeklyRemaining)
    }

    /// Meter -> Gauge mapping (PRD §6.3/§8): `fractionUsed` is
    /// utilization/100 (the gauge bar shows usage, filling as it's
    /// consumed -- NOT percent remaining), `detailText` is
    /// "NN% used · resets <time>" (or just "NN% used" when no reset time
    /// parsed), `resetDate` is the parsed `resets_at`.
    private static func gauges(from meters: [ClaudeMeter]) -> [Gauge] {
        meters.map { meter in
            let used = min(max(meter.utilization, 0), 100)
            let fraction = used / 100
            let usedText = "\(Int(used.rounded()))% used"
            let detail: String
            if let resetsAt = meter.resetsAt {
                detail = "\(usedText) · resets \(shortTimeFormatter.string(from: resetsAt))"
            } else {
                detail = usedText
            }
            return Gauge(label: meter.label, fractionUsed: fraction, detailText: detail, resetDate: meter.resetsAt)
        }
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain = ISO8601DateFormatter()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return iso8601Fractional.date(from: string) ?? iso8601Plain.date(from: string)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Cache (UserDefaults, non-secret only -- never the token)

    private struct Cache: Codable {
        let meters: [ClaudeMeter]
        let fetchDate: Date
    }

    private func persistCache() {
        guard let fetchDate = lastGoodFetchDate else { return }
        let cache = Cache(meters: lastMeters, fetchDate: fetchDate)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func loadCacheIfPresent() {
        guard let data = defaults.data(forKey: cacheKey) else { return }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        lastMeters = cache.meters
        lastGoodFetchDate = cache.fetchDate
        lastGauges = Self.gauges(from: cache.meters)
        lastWeeklyPercentRemaining = cache.meters.first(where: { $0.key == "seven_day" }).map { 100 - $0.utilization }
    }
}
