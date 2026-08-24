# BarTab

A macOS menu bar app that shows how much of things you have left. Disk space first,
Claude plan usage second.

Built for one person's Mac. It is public because there is nothing secret in it, not
because it is a product — there is no installer, no signing, and no support.

## What it does

A small icon sits in the menu bar and changes color as free space gets tight: normal,
yellow below a warning threshold, red below a critical one. Clicking it opens a flyout
with a gauge for the boot volume and for every mounted external drive, plus a tile for
Claude plan usage.

It never notifies, badges, or interrupts. The color is the whole alert system — you come
to it, it does not come to you.

## Configuring it

Settings let you choose **what** the bar shows (disk, Claude, or both) and **how** (icon,
number, or both together), so the app stays useful if disk stops being the thing you worry
about. Thresholds are configurable: absolute GB for disk, percent remaining for Claude.

The bar's color follows whatever you chose to watch. When both are shown, the worse state
wins.

## Two things worth knowing

**Free space is reported strictly.** BarTab uses `volumeAvailableCapacityKey`, which
excludes purgeable space, so its number can read lower than Finder's. That is deliberate —
purgeable space is not what stops a build from failing.

**Claude usage is best-effort.** There is no official API for subscription plan limits, so
the tile reads Claude Code's own OAuth token from the Keychain (read-only — BarTab never
refreshes or writes it) and calls the endpoint behind Claude Code's `/usage` screen. When
that token is expired or the endpoint changes, the tile says so and everything else keeps
working. Disk is the feature that has to work; Claude is the one that is allowed to fail.

## Building it

Requires XcodeGen.

```bash
xcodegen generate
xcodebuild -project BarTab.xcodeproj -scheme BarTab -configuration Debug -derivedDataPath /tmp/bartab-dd build
```

Build products go to `/tmp` deliberately, never inside the repo.

## If the icon seems to be missing

If you run a menu bar manager such as Ice or Bartender, a newly launched status item lands
in its hidden section, where it is clickable but invisible. Drag it out, or quit the
manager briefly to confirm the icon is there.

## Layout

- `PRD.md` — the full spec this was built from
- `Sources/BarTab/Contract.swift` — the resource model everything else builds on
- `scripts/claude-usage-spike.sh` — the read-only probe used to prove the usage endpoint
