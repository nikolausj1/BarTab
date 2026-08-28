---
title: "BarTab - Product Requirements Document"
created: 2026-08-24
modified: 2026-08-24
version: 1.2
author: Claude Fable 5 (claude-fable-5)
tags:
---

# BarTab - Product Requirements Document

| | |
|---|---|
| **Product** | BarTab - a menu bar readout of how much he has left, disk first |
| **Platform** | macOS (menu bar only, no Dock icon, no main window) |
| **Status** | v1.2 PRD - agreed 2026-08-24, corrected 2026-08-28 |
| **Companion docs** | `Project Build Guide.md` (accounts, stack, deployment - follow it, do not restate it) |

## Revision Notes

**v1.2 (2026-08-28):** Corrects §6.6, which was wrong in a way that broke the product in the field. It claimed timers could simply "rely on system timer coalescing." The app ran four days and displayed 12 GB against a real 21 GB. The true cause was not the timer at all — `URL.resourceValues` caches onto the URL instance, so a stored volume URL returns its first reading forever. §6.6 and §9 now state the requirement directly.

**v1.1 (2026-08-24):** Bar contents made resource-selectable (Disk/Claude/Both × three formats) so BarTab stays useful if disk stops being the scarce resource. Bar color now follows the shown resource(s), worst-of when both are shown. Claude weekly thresholds added. Replaces v1.0's four display modes and its disk-only color invariant.

## 1. Overview and Vision

Justin's MacBook has repeatedly run critically low on disk space — as low as 1.6 GB free of 460 GB, with weeks spent in the teens. Dropbox syncing 320,000+ files, Xcode simulator runtimes (~86 GB), `~/Library/Developer` (~34 GB), and caches (~7.9 GB) are the known culprits. He has no passive way to see trouble coming; he finds out when a build fails or a sync storm stalls the filesystem.

BarTab is a macOS menu bar app that shows, at a glance, how much of things Justin has left — disk space first, Claude usage second — so he catches the problem before it becomes another incident.

This beats the alternatives available to him: doing nothing means discovering the problem only after something breaks; checking Finder or `df` manually means remembering to look; a general system-monitor app means noise he doesn't want and clicking he'd rather avoid. BarTab lives exactly where he already looks, conveys its state without any interaction (icon color), and is native — no Electron overhead, no dependency on a host scripting app like xbar or SwiftBar.

## 2. Users

Justin only. A developer who runs Claude Code heavily and has lived through the 1.6 GB-free incidents firsthand. This is a single-user personal tool — no other personas, no multi-user considerations.

## 3. Goals and Success Criteria

**Goals:**

- Make free disk space visible passively, at all times, without requiring a click.
- Warn him before space gets critical, through color alone — never an interruption.
- Add Claude usage as a second resource in v1, best-effort, without letting it affect the disk signal.
- Lay the architecture (a `Resource` extension point) for future resources without over-building v1 to accommodate them.

**Success criteria:**

- Displayed boot-volume free space matches `df -H /System/Volumes/Data` strict free within 1 GB.
- The bar icon changes color within one refresh cycle (30 seconds) of the boot volume's free space crossing a configured threshold.
- The Claude usage tile, when available, matches the values shown on Claude Code's `/usage` screen.
- With the bar set to Claude-only, the bar's color state matches the weekly meter against the configured Claude thresholds.
- Zero notifications, alerts, or any interruption originates from BarTab in v1.
- The app is running and visible immediately after every login, with no manual step.

**The one-sentence test:** Mid-build, Justin glances at the menu bar, sees the BarTab icon has gone yellow, and cleans up before it becomes another 1.6 GB incident — without clicking anything.

## 4. Scope

**In scope (v1):**

- Menu bar icon with three-state coloring (normal / warning / critical) driven by the selected resource(s)' state, worst-of when both are shown.
- Bar contents made resource-selectable via two orthogonal settings: which resource(s) show (Disk / Claude / Both, default Disk) and format (icon-only / number-only / icon + number, default icon-only).
- Flyout listing boot volume plus other local, writable, browsable, mounted volumes, each with a gauge.
- Claude usage tile rendering whatever the unofficial usage endpoint returns, best-effort.
- Settings window: bar resources, bar format, disk thresholds, Claude thresholds.
- Always-on launch at login.
- Personal, unsigned, local build from a public GitHub repo.

**Out of scope (non-goals):**

- **No notifications or interruptions, ever, in v1** — glance-only, by decision.
- **No per-folder culprit analysis** — deferred to v2. Note for whoever builds that: `du` lies about dehydrated Dropbox directories (cloud-only files report zero blocks on disk), so v2 must size by logical file size / file count, never `du` disk-block output.
- **No cleanup actions** — v1 is read-only information, not a remediation tool.
- **No sandboxing** — required tradeoff to read Claude Code's Keychain item.
- **No signed or notarized distribution** — personal local build; the public repo is safe because the code reads the token at runtime and no secret is ever committed.
- **No resources beyond disk and Claude in v1** — the `Resource` protocol is ready for more, but v1 ships exactly two.
- **No launch-at-login toggle** — always on by decision, not a setting.
- **No network volumes or read-only disk images in the flyout** — placeholder rule pending real-world testing (see Open Questions).

**Deferred (v2+ candidates):**

- Culprit watchlist surfacing the known heavy consumers (CoreSimulator runtimes ~86 GB at `/Library/Developer/CoreSimulator/Cryptex/`, `~/Library/Developer` ~34 GB, caches ~7.9 GB).
- Free-space history sparkline.
- Additional resources via the `Resource` protocol extension point.
- Notifications at thresholds.

## 5. Product Principles

- **Glance, never interrupt.** State is conveyed by color alone. No badge, no sound, no notification, ever.
- **Color follows the watched resource.** The bar's color reflects only the resource(s) selected for it; when both are shown, the worst state wins. (Disk still gates v1's ship — Claude remains best-effort data.)
- **Strict free, always.** Every number shown is the conservative, purgeable-excluded figure, even when it reads lower than Finder's.
- **Degrade, don't crash.** An unofficial, shape-shifting data source (the Claude endpoint) fails soft into "unavailable." It never breaks the app.

## 6. Functional Requirements

### 6.1 Menu bar icon

State is computed from the resource(s) selected for the bar (`barResources`, see §6.2) against each shown resource's own thresholds:

- **Disk** maps strict free GB against the disk warning/critical GB thresholds (as today).
- **Claude** maps the **weekly** percent remaining (locked: the weekly meter votes, never the 5-hour session meter — session caps recur routinely and would make red meaningless) against the Claude warning/critical percent-remaining thresholds (default 25% / 10%, see §6.4).

Bar state is the **worst** state among the shown resources, severity ordered critical > warning > normal. A shown resource that is unavailable or unreadable does not vote, and its number renders "—"; if **no** shown resource is available, the bar renders the Unreadable state below.

| State | Icon rendering | Number rendering |
|---|---|---|
| Normal | SF Symbol ("internaldrive"-style glyph), **template** image — inherits system menu bar color, adapts to light/dark automatically | Default menu bar text color |
| Warning | Same glyph, filled **yellow**, rendered as a **non-template** image (macOS forces template images to monochrome, so color requires original rendering mode) | Yellow text |
| Critical | Same glyph, filled **red**, non-template | Red text |
| Unreadable (no shown resource available) | Same glyph, template image, using the system's standard "?" question-mark variant (or the glyph at reduced opacity if no question variant exists) — never colored | "—" |

This coloring rule must be verified in both light and dark menu bar appearance during Phase 1 (see Build Phases). On cold launch, the icon renders in Normal template state until the first disk read completes (the read is near-instant; no dedicated loading state).

### 6.2 Bar contents (Settings-selectable)

Two independent settings control the bar: **`barResources`** — which resource(s) are shown (Disk / Claude / Both, default Disk) — and **`barFormat`** — how they're rendered (icon-only / number-only / icon + number, default icon-only). Disk's number is strict free GB; Claude's number is weekly percent remaining. Bar color follows §6.1's worst-of rule across whichever resource(s) `barResources` selects.

| barResources | barFormat | Bar contents | Example |
|---|---|---|---|
| Disk | Icon-only (**default**) | Drive glyph, colored by disk state | (drive icon, yellow) |
| Claude | Number-only | Weekly percent remaining as text, colored by Claude state | `62%` |
| Both | Icon + number | Drive glyph + free GB + Claude weekly percent, colored worst-of | (icon) `47 GB · 62%` |

Claude's glyph for icon modes is an SF Symbol chosen during Phase 2 and presented at that phase's screenshot review — a delegated choice with a review gate, the same convention as the disk glyph in §7. When `barResources` is Both and `barFormat` is icon-only, the bar shows the disk glyph only, colored worst-of across both resources.

### 6.3 Flyout

Opened by clicking the menu bar item. Refreshes both resources immediately on open (see 6.6 for cadence).

**Title row:** "BarTab" with a gear icon on the right. The gear opens a menu with two items: **Settings…** and **Quit BarTab**. Because the app has no Dock icon (`LSUIElement` true), this is the only quit affordance in the app.

**Volumes section:** boot volume always listed first. Below it, one row for every other mounted volume that is local, writable, and browsable (determined via `URLResourceValues`: `volumeIsLocalKey` true, `volumeIsBrowsableKey` true, `volumeIsReadOnlyKey` false), ordered alphabetically by volume name. Network mounts and read-only disk images are excluded.

Each volume row shows: volume name, a gauge bar colored by the same warning/critical thresholds applied to that volume's own free space, and the text "X GB free of Y GB" (strict free).

| Case | Behavior |
|---|---|
| No external volumes mounted | Only the boot row is shown. No placeholder text. |
| An external volume (e.g. the Samsung T5) mounts | Its row appears within one refresh cycle. |
| An external volume unmounts | Its row disappears within one refresh cycle. |
| A network volume is mounted | Excluded — never listed. |
| A read-only disk image is mounted | Excluded — never listed. |
| Boot volume's free-space read fails | Boot row shows the volume name with "free space unreadable" in place of the gauge; bar icon follows the §6.1 Unreadable state. |

**Claude usage tile:** rendered below the volumes section. It renders every gauge-shaped field the unofficial usage endpoint returns for the signed-in account — session (5-hour) meter, weekly meter, and per-model weekly meters if present — each as label + gauge bar + percent used + reset time. Fields the endpoint doesn't return simply don't render; the tile never assumes a fixed shape and never crashes on a shape change.

| Tile state | Trigger | Rendering |
|---|---|---|
| Loading | First fetch since launch, no cached snapshot yet | "Loading Claude usage…" |
| OK | Most recent fetch succeeded | Live gauges as described above |
| Stale | Most recent fetch failed, but a prior snapshot exists | The cached gauges, labeled "as of \<time of last successful fetch\>" |
| Unavailable — no credentials | Keychain item missing or unreadable | "Claude usage unavailable" + one-line reason |
| Unavailable — expired token | Token present but the endpoint rejects it | "Claude usage unavailable" + "open Claude Code to refresh sign-in" |
| Unavailable — endpoint dead | Endpoint unreachable or erroring, no cached snapshot to fall back to | "Claude usage unavailable" + one-line reason |

The flyout's Claude tile always renders in full regardless of `barResources`/`barFormat` — those settings control the bar only. Whether the Claude tile's data also drives the bar's color depends on `barResources` (see §6.1/§6.2).

### 6.4 Settings window

A single small pane, opened via the gear menu's "Settings…" item:

- **Bar resources picker** — `barResources`: Disk / Claude / Both, from §6.2.
- **Bar format picker** — `barFormat`: icon-only / number-only / icon + number, from §6.2.
- **Disk warning threshold** — integer GB field.
- **Disk critical threshold** — integer GB field.
- **Claude warning percent** — integer percent-remaining field, default 25.
- **Claude critical percent** — integer percent-remaining field, default 10.

**Validation:** for each pair, the critical threshold must be less than the warning threshold. Disk thresholds must be ≥ 1 and clamp to an upper bound of 5000 GB. Claude thresholds clamp to 1–99 (percent). Fields bind live to `AppSettings` (see Data Model) and persist as the user edits them; while a field's value would violate its validation rule, the invalid value is shown with an inline error message and is not written to `AppSettings` — the last valid value remains in effect until the user corrects it.

Launch-at-login has no control in this window — it is always on (see 6.5), by decision.

### 6.5 Login item

BarTab registers itself via `SMAppService` on first run so it launches automatically at every login. There is no setting to disable this.

### 6.6 Refresh cadence (locked)

- Disk: every 30 seconds, plus immediately whenever the flyout opens.
- Claude usage: every 5 minutes, plus immediately whenever the flyout opens.
- Volume URLs must be constructed fresh at each reading. `URL.resourceValues(forKeys:)` caches its results onto the URL instance, so a stored URL silently reports its first measurement forever — the bar freezes while the timer keeps firing correctly underneath. This is a correctness requirement, not an optimisation.
- Timers are scheduled in the run loop's `.common` modes, and the app opts out of App Nap via `beginActivity(options: .userInitiatedAllowingIdleSystemSleep)` — deliberately still allowing the Mac itself to sleep. On `NSWorkspace.didWakeNotification` both resources refresh immediately and both timers are rebuilt, so no reading can outlive a sleep.

## 7. Visual and Design Spec

Native macOS throughout — no custom chrome, no third-party UI kit. `MenuBarExtra`'s window-style flyout uses the system's standard materials (vibrancy/blur) rather than a custom background. All icons are SF Symbols. Tone is utilitarian and information-dense, matching the feel of macOS's own menu bar extras (battery, clock) — no branding flourishes, no marketing copy.

- **Bar glyph:** an SF Symbol in the "internaldrive" family (exact symbol chosen during Phase 1 and presented at the Phase 1 screenshot review — a delegated choice with a review gate, locked as such, not an open question). Normal state renders as a template image so it automatically matches the system's light/dark menu bar appearance. Warning and critical states render the same glyph as a non-template image filled yellow or red respectively (rationale in §6.1).
- **Gauge bars:** simple horizontal bars, fill proportional to `fractionUsed`, colored using the same warning/critical thresholds as the icon (per volume for disk rows; per meter for the Claude tile, using the endpoint's own reported fraction).
- **Typography:** system default fonts and sizes throughout — the flyout's text and the Settings window use standard SwiftUI `Form`/`Text` styling, no custom type.
- **Settings window:** small, single-pane, standard SwiftUI form controls (segmented picker or radio group for bar resources and bar format, numeric text fields for thresholds).

No mockup exists; this spec is the full visual reference. Where a rendering choice isn't pinned above (e.g. exact glyph), match native macOS conventions and flag the choice as reviewable rather than inventing a departure from them.

## 8. Data Model

**`AppSettings`** (persisted in `UserDefaults`):

| Field | Type | Default |
|---|---|---|
| `barResources` | String (raw value of an enum: `disk` \| `claude` \| `both`) | `disk` |
| `barFormat` | String (raw value of an enum: `iconOnly` \| `numberOnly` \| `iconAndNumber`) | `iconOnly` |
| `warningThresholdGB` | Int | 50 |
| `criticalThresholdGB` | Int | 20 |
| `claudeWarningPercent` | Int | 25 |
| `claudeCriticalPercent` | Int | 10 |

**`Resource` protocol** — the extension point that lets v2 add resources without touching the bar/flyout rendering code:

```swift
protocol Resource {
    var id: String { get }
    var displayName: String { get }
    func refresh() async -> ResourceSnapshot
}
```

**`ResourceSnapshot`** (value type):

| Field | Type |
|---|---|
| `gauges` | `[Gauge]` |
| `status` | `ResourceStatus` (`ok` \| `stale` \| `unavailable(reason: String)`) |

**`Gauge`** (value type):

| Field | Type |
|---|---|
| `label` | String |
| `fractionUsed` | Double, 0...1 |
| `detailText` | String (e.g. "47 GB free of 500 GB") |
| `resetDate` | Date? (optional — set for Claude meters, nil for disk) |

**Conformers:** `DiskResource` (one `Gauge` per qualifying volume — boot first, then externals, per §6.3's inclusion rule) and `ClaudeUsageResource` (one `Gauge` per meter the endpoint returns).

**Invariant:** the bar's color state derives only from the resources selected for the bar. Each shown resource maps to normal/warning/critical via its own thresholds (disk: boot-volume strict free GB; Claude: weekly percent remaining). When both are shown the worst state wins. Unavailable resources don't vote; if no shown resource is available the bar shows the Unreadable state.

**Claude usage caching:** the most recent successful `ClaudeUsageResource` snapshot is cached in `UserDefaults` as JSON, so the "stale" tile state (§6.3) can render a real last-known snapshot across relaunches, not just within a session.

**Content strategy:** not applicable — BarTab has no editable content. Every value it displays is live system state (`URLResourceValues`) or a live API response (the Claude usage endpoint); nothing is authored or maintained as data.

## 9. Tech Stack and Architecture

Swift + SwiftUI, using `MenuBarExtra` in window style as the entire UI surface (bar item + flyout). Deployment target macOS 14+ (`MenuBarExtra` requires only 13+, but the target is locked at 14+ deliberately — no Mac older than Justin's is in scope). Project scaffolded with XcodeGen (`project.yml`) per the Build Guide. Bundle ID `com.levelup.bartab`, team `6A4J2GTB6F`. `LSUIElement` set to true (no Dock icon, no app switcher entry). The app is **not sandboxed** — the one project-specific deviation from typical Build Guide conventions, required because reading another app's (Claude Code's) Keychain item is not compatible with the App Sandbox. Builds go to `/tmp` via `-derivedDataPath`, never in-repo, per the Build Guide's standing rule. Repo is public on GitHub as `nikolausj1/BarTab` — safe, since the code reads the OAuth token from the Keychain at runtime and no secret is ever committed.

**Free-space source:** `URLResourceValues.volumeAvailableCapacityKey` (strict free, excludes purgeable space) — deliberately **not** `volumeAvailableCapacityForImportantUsageKey`, which is what Finder uses and which includes purgeable space. Every number BarTab displays is the strict figure; the flyout labels it "free," and it may legitimately read lower than what Finder shows for the same volume. This is by design (Product Principle: "Strict free, always"), not a bug.

**Claude credentials:** BarTab reads Claude Code's OAuth token from the macOS Keychain — a generic password item with service `"Claude Code-credentials"` — at the time of each fetch. BarTab never writes to or refreshes this token; if it's expired, the tile goes to the "expired token" unavailable state (§6.3). The first Keychain read of a session triggers a macOS consent prompt; Justin clicks "Always Allow" once and it doesn't recur.

**Rejected alternatives** (noted so they aren't relitigated):

- **Electron, or a script under xbar/SwiftBar:** either heavier than necessary or dependent on a separate host app being installed. Native `MenuBarExtra` is less total code than either approach for this shape.
- **`NSStatusItem` + `NSPopover` manual wiring:** the traditional pre-SwiftUI approach. `MenuBarExtra` covers everything this app needs on a modern macOS target, so the manual approach adds complexity with no benefit here.

## 10. Build Phases

1. **Scaffold + disk core.** XcodeGen project, `LSUIElement` app, icon-only bar item with live state, flyout with volume gauges.
   *Exit:* app runs from a `/tmp` build; screenshot taken; displayed boot free GB matches `df -H /System/Volumes/Data` strict free within 1 GB; icon flips yellow/red when thresholds are temporarily raised above current free space.

2. **Settings + bar contents.** Settings window, `barResources` × `barFormat` picker pair, threshold editing (disk + Claude), persistence across relaunch.
   *Exit:* screenshots covering the mode matrix (all nine `barResources` × `barFormat` combinations); thresholds survive an app relaunch, Claude threshold fields verified persisting.

3. **Claude endpoint spike** (timeboxed, a standalone script — not app code, and not yet integrated). Read the Keychain item, call the usage endpoint, dump the JSON.
   *Exit:* JSON fields documented in a spike note in the repo, cross-checked against what Claude Code's `/usage` screen shows for the same account. **If the spike fails, the Claude tile ships as permanently "unavailable" and v1 remains disk-only — v1 is not blocked by this phase.**

4. **Claude tile.** Integrate the spike's findings, defensive rendering per §6.3, all four (six, counting sub-states) tile states.
   *Exit:* tile matches the `/usage` screenshot side-by-side; the "unavailable" state is verified by temporarily renaming the Keychain item; the "stale" state is verified by killing network access mid-session.

5. **Login item + acceptance pass.** `SMAppService` registration; a full run through every item in §11 Acceptance Criteria.
   *Exit:* app present in System Settings > Login Items; every acceptance criterion checked off.

## 11. Acceptance Criteria

- [ ] Bar item appears within 2 seconds of app launch (locked bar).
- [ ] Boot-volume free space matches `df -H /System/Volumes/Data` within 1 GB.
- [ ] Icon/text color flips between normal, warning, and critical exactly at the configured thresholds.
- [ ] All nine `barResources` × `barFormat` combinations render correctly.
- [ ] Claude-only bar color flips at the configured Claude thresholds.
- [ ] Both mode shows worst-of color (verify by forcing disk red while Claude green).
- [ ] Claude-only bar with the endpoint dead renders the Unreadable state with "—".
- [ ] Flyout lists boot volume plus the Samsung T5 (or any mounted local writable volume) when connected, and drops that row within one refresh cycle of it unmounting.
- [ ] Claude tile's values match Claude Code's `/usage` screen for the same account.
- [ ] Each of the Claude tile's states (loading, ok, stale, unavailable-no-credentials, unavailable-expired-token, unavailable-endpoint-dead) is individually reachable and renders correctly.
- [ ] Settings (`barResources`, `barFormat`, disk thresholds, Claude thresholds) persist across an app relaunch.
- [ ] The gear menu's "Quit BarTab" item quits the app.
- [ ] The app is registered as a login item in System Settings and launches automatically after a fresh login.
- [ ] After the Mac sleeps and wakes, both resources refresh within one cycle and show no stale numbers.

## 12. Risks and Open Questions

**Risks:**

| Risk | Mitigation |
|---|---|
| The unofficial Claude usage endpoint breaks or changes shape | Tile degrades to "stale" or "unavailable"; disk always continues to gate v1's core signal regardless |
| Keychain consent is denied, or the prompt reappears after a Claude Code update rewrites its Keychain item | Tile shows "unavailable" with a specific reason; Justin re-approves via the system prompt |
| Strict-free numbers read lower than Finder's, causing confusion | Every number is explicitly labeled "free," and this PRD documents the discrepancy as intentional |
| Colored (non-template) menu bar icon rendering behaves inconsistently across light/dark menu bar appearance | Verified explicitly in both appearances during Phase 1, before the phase is considered complete |
| Bar set to Claude-only while the unofficial endpoint is down leaves the bar uninformative | Unreadable bar state with "—"; the flyout states the reason; switching the bar back to Disk is one Settings change |

**Open questions (non-blocking):**

- Whether network volumes should ever appear in the flyout — excluded in v1 by the placeholder rule in §6.3; revisit if it turns out to matter in practice.
- The Claude usage endpoint's exact URL and response shape — undiscovered until the Phase 3 spike; the `/usage` screen in Claude Code is the ground truth to validate against.
