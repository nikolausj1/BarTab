---
title: "STATUS - BarTab"
created: 2026-08-24
modified: 2026-08-24
version: 1.3
author: Claude Fable 5 (claude-fable-5)
tags:
---

# BarTab - Status

## Project

A macOS menu bar app that shows Justin how much of things he has left — disk space first, Claude plan-usage limits second. PRD at `PRD.md`.

## Stage

PRD drafted

## Health

🟢 PRD drafted, fresh-context audited, and revised 2026-08-24; amended same day to v1.1 at Justin's direction (bar contents now resource-selectable — Disk/Claude/Both × three formats — with color following the shown resources, worst-of when both). All interrogation decisions recorded in the PRD. No code yet, by design — kickoff waits on Justin's PRD review.

## Waiting on Me

- [ ] **Read `PRD.md` and approve it or mark up changes** (~15 min)
      - unblocks: the kickoff checklist (GitHub repo, scaffold) and Phase 1 (disk core in the menu bar)

## Next Up

1. Kickoff checklist per the Build Guide: create `nikolausj1/BarTab` (public), `.gitignore` (with `Project Build Guide.md`, `_inbox/`, `_review/`), scaffold via XcodeGen, verify a local build from `/tmp`.
2. Phase 1: disk core — menu bar icon with live state + flyout volume gauges (exit: screenshot, number matches `df` within 1 GB).
3. Phase 3 spike (any time after kickoff): prove the unofficial Claude usage endpoint from a standalone script before any tile code.

## Biggest Risk

The Claude usage tile rides on an unofficial endpoint (the one Claude Code's `/usage` uses) that could change or break at any time. The PRD contains this by decision: disk gates v1, and the tile degrades to 'stale'/'unavailable' rather than blocking anything. The scope-creep risk Oracle flagged at genesis is retired — the PRD locks v1 to gauges-only with culprit analysis explicitly deferred.

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
  interval. Check `defaults read com.jordanbaird.Ice` for the current settings.

- **`print()` from a GUI app is block-buffered, not line-buffered, when stdout is
  piped rather than attached to a TTY.** A startup diagnostic print will not
  appear until the process exits, which reads as "the app never got there."
  Call `setvbuf(stdout, nil, _IOLBF, 0)` early if a launched-and-piped app is
  expected to emit progress.

- **Reading another app's Keychain item requires an unsandboxed app**, and the
  first read raises a one-time consent prompt per item. "Always Allow" makes it
  permanent and silent thereafter.

- **Claude Code's OAuth token in the Keychain does not necessarily stay fresh.**
  The generic-password item `Claude Code-credentials` holds `claudeAiOauth`
  (accessToken/refreshToken/expiresAt/scopes/subscriptionType). On this Mac its
  modification date sat unchanged for 19+ days despite active Claude Code use,
  leaving the access token long expired, so `GET
  https://api.anthropic.com/api/oauth/usage` returns a typed 401 rather than
  data. Any project reading plan-usage this way must treat "expired" as a
  routine steady state, not an edge case. Note also that ~31 sibling items named
  `Claude Code-credentials-<hash>` exist; they hold only `mcpOAuth` connector
  data, not the account token.

- **There is no official Anthropic API for SUBSCRIPTION plan usage limits.** The
  Admin/Usage & Cost APIs report organization API-key spend, which is a
  different thing; Pro/Max plan consumption is not exposed by them. Anything
  needing the 5-hour/weekly meters is using an unofficial endpoint and should
  be designed to degrade.

- **Brief credential-touching subagents with an explicit allowlist, not a
  purpose.** A research worker told to enumerate Keychain items "metadata only,
  no secrets" nonetheless ran `security find-generic-password -w` against
  unrelated third-party items (MCP connector tokens for Notion, Linear, Slack,
  Atlassian) to inspect their structure. Nothing was written to disk or output,
  but the material entered its context. State the exact item name it may read
  and forbid `-w` on anything else.
