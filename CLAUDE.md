---
title: "CLAUDE - BarTab"
created: 2026-08-24
modified: 2026-08-24
version: 1.0
author: Claude Opus 5 (claude-opus-5)
tags:
---

# BarTab

A macOS menu bar app showing how much of things Justin has left. Disk space first. The name is his: "keeping tabs on the status from the menu bar."

**This project is at Idea stage. No code exists and none should until the PRD is written.**

## Your first job

1. Read `_inbox/idea-dump.md`. It carries Justin's own words, the future scope he named, and portfolio context he did not have to supply.
2. Interrogate him per the protocol in `_Projects/_Templates/PRD Template.md`: **one question at a time**, challenging rather than transcribing, until the PRD quality checklist is answerable.
3. Draft the PRD.
4. Only then, the kickoff checklist in `_Projects/_Templates/Project Build Guide.md`.

The idea dump lists open questions deliberately left unanswered. They are starting points, not a script, and they are not requirements.

## The two shared documents

Both live in Dropbox and are **referenced, never copied**:

- `~/Library/CloudStorage/Dropbox/_Projects/_Templates/Project Build Guide.md` - accounts, tooling, platform conventions, hard-won gotchas. Read its Changelog at session start.
- `~/Library/CloudStorage/Dropbox/_Projects/_Templates/PRD Template.md` - the interrogation protocol and PRD structure.

**Never edit either one.** Justin's standing rule since 2026-08-12, and it holds even when you find a genuine error in them. Your channel is a `## Lessons` entry in this project's `STATUS.md`; Oracle vets those and folds the good ones in. A direct edit skips vetting, produces no run-summary entry, and loses the record of which project found it. This rule has been broken twice; do not make it three.

## Things the Build Guide already settles

Do not rediscover these:

- **Build to `/tmp`.** Never point `-derivedDataPath` inside the repo or any cloud-synced folder.
- This project lives in `~/_Developer`, outside Dropbox, on purpose. Keep it there.
- API keys live in `~/.secrets/api-keys.env`. Read them from the file; never echo a value into chat, and never commit one.
- There is no macOS platform section in the Build Guide yet. **You will likely be the first to write one**, via `## Lessons`. Menu bar apps, `NSStatusItem`, sandboxing and disk-access permissions are all currently undocumented here.

## Worth knowing before you design

The problem is real and measured. The MacBook has been as low as **1.6 GB free** of 460 GB. The largest consumers found during the DropBox Migration work were Xcode simulator runtimes at `/Library/Developer/CoreSimulator/Cryptex/` (~86 GB), `~/Library/Developer` (~34 GB) and caches (~7.9 GB).

One trap that directly affects this app: **`du` lies about Dropbox directories.** Dehydrated cloud-only files report zero blocks on disk, so `du -sm` can return 0 MB for a directory holding hundreds. If BarTab ever reports per-folder usage, this is the first thing that will make it wrong. Details in the Build Guide's Dropbox rule.

## Oracle Reporting Contract

This project is tracked by Oracle, the portfolio agent at the `_Projects` root, which rolls every project's status into `_Oracle/PORTFOLIO.md` and a dashboard. Parent standards and the Oracle Status Format are defined in `~/Library/CloudStorage/Dropbox/_Projects/CLAUDE.md` (inherited; read it). Your obligations:

1. **Keep `STATUS.md` current.** Refresh it at the end of any session with meaningful progress, decisions, or new blockers.
2. **Follow the Oracle Status Format exactly**: Project, Stage, Health, Waiting on Me, Next Up, Biggest Risk, in that order. Anything project-specific goes below a `---` divider. Bump `version` and update `modified` on every edit.
3. **Keep the Ideas Shelf stocked** with 2 to 5 self-contained items sized S/M/L that Justin could pick up for fun.
4. **Never delete `STATUS.md`.** If parking the project, set Stage to Paused and say why.
5. **Oracle trusts this file completely.** It never inspects code or git. An inaccurate status gives Justin a wrong portfolio picture.
6. Edits marked "updated via Oracle at Justin's direction" are authoritative. Reconcile them at session start; do not revert them.
7. **Share what you learn, and only through `STATUS.md`.** Reusable environment-level findings go in an optional `## Lessons` section at the bottom, below the divider. Oracle promotes vetted ones into the shared Build Guide.

## Waiting on Me items

Every item under `## Waiting on Me` needs a bolded concrete action, an effort estimate in parentheses, and an indented `- unblocks:` line. Items without effort estimates get flagged as a data-quality warning on every run.
