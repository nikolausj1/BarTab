---
title: "STATUS - BarTab"
created: 2026-08-24
modified: 2026-08-28
version: 1.5
author: Claude Fable 5 (claude-fable-5)
tags:
---

# BarTab - Status

## Project

A macOS menu bar app that shows Justin how much of things he has left — disk space first, Claude plan-usage limits second. PRD at `PRD.md`.

## Stage

Built (v1 complete, in daily use)

## Health

🟢 v1 built and installed. All five PRD phases complete; acceptance is 10 pass, 0 fail, 3 not verified (each needs a logout, a machine sleep, or a live Claude token). Running from /Applications and registered as a login item. Disk half works fully; the Claude tile is correct but shows "unavailable" until the stored OAuth token is refreshed.

## Waiting on Me

- [ ] **Free up disk space — you are at ~13 GB of 494 GB** (~30 min)
      - unblocks: nothing in this project, but it is the actual problem BarTab was built to warn about, and it is already red
- [x] ~~**Drag BarTab out of Ice's hidden section so the icon is actually visible**~~ **DONE 2026-08-28.** The gauge is out of Ice's hidden section and visible in the menu bar. (updated via Oracle at Justin's direction, 2026-08-28)
- [ ] **Re-authenticate Claude Code (`/login` in an interactive terminal), then ask for the spike re-run** (~5 min)
      - unblocks: the Claude tile showing real numbers, and the decision on whether plan usage is durable enough to keep

## Next Up

1. Live-fire the Claude tile once the token is fresh: re-run `scripts/claude-usage-spike.sh`, confirm the field shape matches what Phase 4 parses, and screenshot the OK state with real numbers.
2. Decide the Claude durability question with real evidence (see `_review/phase3-spike/DURABILITY.md`): accept the limitation, or add a clearly-labelled local approximation.
3. Optional polish: app icon, and a settings pane worth looking at rather than merely correct.

## Biggest Risk

The Claude tile may be honest but useless. Its endpoint is unofficial, and the stored token was found 19 days stale despite active Claude Code use, so the tile could sit in "unavailable" indefinitely. Disk was always the feature that had to work, and it does. The risk is disappointment, not breakage.

---

## Ideas Shelf

- **(S) Icon glyph tasting flight** — render 3-4 SF Symbol candidates (internaldrive, gauge, chart variants) as menu bar screenshots in `_review/` for the Phase 1 veto.
- **(S) "Both resources" bar format experiments** — mock a few compact text formats for the disk+Claude bar mode before settling on "47 GB · 62%".
- **(M) Free-space history sparkline** — record free-GB samples over time, draw a tiny sparkline in the flyout. Deferred v2 item in the PRD.
- **(M) Culprit watchlist tile** — sizes for CoreSimulator runtimes, ~/Library/Developer, caches. Must size by logical size/file count, never `du` blocks (Dropbox dehydration lies). Deferred v2 item.
- **(L) More resources on the `Resource` protocol** — Time Machine last-backup age, iCloud storage, whatever else has a "how much is left" shape.

## Notes from genesis (Oracle, 2026-08-24)

**Name:** Justin's own, from a list of ten Oracle proposed. "BarTab, as in I'm keeping tabs on the status from the menu bar." The ten candidates were all chosen to survive the app growing past disk space; his own pick did that better than most of them.

**Location:** `~/_Developer/BarTab`, at Justin's explicit request. Note that the genesis procedure in the parent `CLAUDE.md` still says new projects are created in `_Projects/`, which predates the migration to `~/_Developer`. This project was deliberately born in the new location and the procedure itself needs updating; flagged to Justin, not changed by Oracle.

**Builder:** Claude Code, decided by Justin at genesis.

**Priority:** P3 by default. Idea-stage projects are exempt from staleness and WIP accounting until Justin promotes them.

**Roster type:** `tool`. macOS is not in the roster's type vocabulary (kids, game, ios, web, tv, hardware, tool). If more Mac projects appear, a `mac` tag would be worth adding; that is a roster schema change and needs Justin's word.

**What Oracle did NOT do**, per its own constitution: write any PRD content, choose a tech stack, scaffold code, or create a GitHub repo. Those belong to this project's first session.

## Lessons

- **`URL.resourceValues(forKeys:)` CACHES onto the URL instance, so any stored
  URL used for repeated measurement silently returns its first reading
  forever.** This shipped as BarTab's worst possible bug: a disk gauge that
  confidently displayed a stale number. It ran four days showing 12 GB against
  a real 21 GB. Everything around it was healthy — the 30-second timer fired
  on schedule, the view layer was wired correctly, the arithmetic was right —
  so every plausible suspect was innocent and the reading was still wrong.
  Construct the URL fresh at each read, or call `removeAllCachedResourceValues()`.
  **The bug survived five phases of verification because every screenshot was
  taken just after a relaunch, which is exactly when a caching bug is
  invisible.** Any always-on display needs at least one test that changes the
  underlying value and watches the SAME running instance follow it.


Candidates for Oracle to vet and promote into the shared Build Guide. **There is
still no macOS platform section in the Build Guide; the first three below are
the beginning of one.**

- **A menu-bar manager (Ice, Bartender) hides new status items OFF-SCREEN, and
  screenshot verification reads that as "the icon renders nothing."** Justin runs
  Ice with `AutoRehide=1`. A newly launched `NSStatusItem`/`MenuBarExtra` lands in
  the hidden section, where it stays fully accessible and clickable via the
  accessibility API while capturing zero pixels — its reported x-position drifts
  far off-screen (observed: -4126). This cost a Phase 1 worker significant time
  and produced a confident wrong diagnosis ("macOS 26.5.1 beta status-item bug,
  re-verify on a shipped build"). It also survived a from-scratch minimal
  repro app, which made the false conclusion *more* convincing, not less.
  **Recipe:** before capturing any menu bar UI, `osascript -e 'tell application
  "Ice" to quit'`, capture, then `open -a Ice`. Or capture within the rehide
  interval. Check `defaults read com.jordanbaird.Ice` for the current settings. (promoted to Build Guide v10.0, 2026-08-27)

- **`print()` from a GUI app is block-buffered, not line-buffered, when stdout is
  piped rather than attached to a TTY.** A startup diagnostic print will not
  appear until the process exits, which reads as "the app never got there."
  Call `setvbuf(stdout, nil, _IOLBF, 0)` early if a launched-and-piped app is
  expected to emit progress. (promoted to Build Guide v10.0, 2026-08-27)

- **Reading another app's Keychain item requires an unsandboxed app**, and the
  first read raises a one-time consent prompt per item. "Always Allow" makes it
  permanent and silent thereafter. (promoted to Build Guide v10.0, 2026-08-27)

- **Claude Code's OAuth token in the Keychain does not necessarily stay fresh.**
  The generic-password item `Claude Code-credentials` holds `claudeAiOauth`
  (accessToken/refreshToken/expiresAt/scopes/subscriptionType). On this Mac its
  modification date sat unchanged for 19+ days despite active Claude Code use,
  leaving the access token long expired, so `GET
  https://api.anthropic.com/api/oauth/usage` returns a typed 401 rather than
  data. Any project reading plan-usage this way must treat "expired" as a
  routine steady state, not an edge case. Note also that ~31 sibling items named
  `Claude Code-credentials-<hash>` exist; they hold only `mcpOAuth` connector
  data, not the account token. (reviewed by Oracle 2026-08-27, not promoted: too narrow to recur outside this project)

- **There is no official Anthropic API for SUBSCRIPTION plan usage limits.** The
  Admin/Usage & Cost APIs report organization API-key spend, which is a
  different thing; Pro/Max plan consumption is not exposed by them. Anything
  needing the 5-hour/weekly meters is using an unofficial endpoint and should
  be designed to degrade. (reviewed by Oracle 2026-08-27, not promoted: too narrow to recur outside this project)

- **Brief credential-touching subagents with an explicit allowlist, not a
  purpose.** A research worker told to enumerate Keychain items "metadata only,
  no secrets" nonetheless ran `security find-generic-password -w` against
  unrelated third-party items (MCP connector tokens for Notion, Linear, Slack,
  Atlassian) to inspect their structure. Nothing was written to disk or output,
  but the material entered its context. State the exact item name it may read
  and forbid `-w` on anything else. (promoted to Build Guide v10.0, 2026-08-27)
