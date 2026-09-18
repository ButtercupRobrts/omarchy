# Omarchy Fork

## What This Is

A personal fork of Omarchy (`omacom/omarchy` → `ButtercupRobrts/omarchy`) used for developing fixes against the live system and potentially upstreaming them. Shipped: per-monitor display scaling (v1.0, phases 1–3), transcode quality selection + size feedback in `omarchy-transcode` (v1.1, phases 4–7), and target-size transcoding (v1.2, phases 8–9).

## Current State

**v1.2 shipped 2026-09-18** — `omarchy-transcode` now accepts `--target <size>` (free-text: `25M`, `1.5G`, `500K`, `25MB`, bare `25` = MB) for video: bitrate derived from probed duration minus 192k audio, resolution auto-step-down across locked floors, two-pass encode, one overshoot retry, honest refusal naming the achievable minimum — plus a `Custom size…` row on the mp4 quality menu routing through the identical pipeline (interactive ≡ CLI byte-identical). All user-facing sizes are decimal MB, matching file managers and upload limits.

**v1.1 shipped 2026-09-16** — quality tiers (mp4 CRF, gif fps) interactively with `~N MB` estimates and as a 4th positional arg; completion notification reports actual output size. Milestone audit: 7/7 requirements, `.planning/v1.1-MILESTONE-AUDIT.md`.

## Next Milestone Goals

Remaining candidates tracked in `.planning/milestones/v1.2-REQUIREMENTS.md`: intent presets (SIZE-11), gif estimates (SIZE-12), picture quality arg (QUAL-10), Nautilus batch-answer memory (QUAL-11), sub-720p rungs (SIZE-16), deeper overshoot convergence (SIZE-17). Upstream: PR #12135 (v1.1 change set) is open; the stacked v1.2 branch `feat/transcode-target-size-upstream` is carved and ready — it goes upstream once #12135 resolves.

## Requirements

### Validated

- ✓ Hyprland accepts arbitrary "clean" per-output scales — existing
- ✓ `omarchy-hyprland-monitor-scaling` applies scale live via `hyprctl eval` — existing
- ✓ Display panel (`omarchy.monitor`) already has a SCALE section with preset pills — existing
- ✓ Shell runs one bar instance per screen (`Variants { model: Quickshell.screens }`) — existing
- ✓ `SUPER + /` / `SUPER + ALT + /` scaling keybindings exist — existing
- ✓ REQ-01..05 — v1.0 per-monitor scaling requirements — shipped in phases 1–3 (see REQUIREMENTS.md traceability)
- ✓ TRANSC-05 — `omarchy-menu-select` `--default-index` pre-highlight — Phase 4
- ✓ TRANSC-02 — 4th positional `[quality]` arg; `medium`/omitted byte-identical argv — Phase 5
- ✓ TRANSC-06 — Pictures skip quality; non-default `-high`/`-low` suffix — Phase 5
- ✓ TRANSC-01 — Interactive `Select quality` step (mp4 CRF tiers, gif fps tiers) — Phase 6
- ✓ TRANSC-03 — `~N MB` estimate subtexts on mp4 rows (approximate, degrade honestly) — Phase 6
- ✓ TRANSC-04 — Completion notification reports the actual output file size — Phase 7

### Out of Scope

- GDK_SCALE / activation-environment sync — upstream issue #10555 / PR #10570; separate layer, separate change
- SDDM greeter monitor scale — issue #7312; greeter config, unrelated to the shell panel
- Screensaver scale/art issues — #9027, #7307; unrelated visuals
- Brightness controls — already functional in the panel
- Building on open PR #11414's branch — independent implementation chosen instead

## Context

- Live setup under development: `eDP-1` laptop at scale 1.5, `HDMI-A-1` Samsung at scale 1.6 positioned `-1200x0` (left). `monitors.lua` has explicit per-monitor `hl.monitor()` lines after the generic catch-all.
- Bug chain: `omarchy-hyprland-monitor-scaling` applies live via `hyprctl eval` with hardcoded `position = "auto"` (clobbers configured layout until reload), then persists by rewriting the shared `omarchy_monitor_scale` variable — which explicit per-monitor lines override on every reload → silent revert (upstream issue #9950, also #7242, #8103, #6673, #10922).
- ~9 competing open upstream PRs attack the persistence half (#11414 most recent); none merged. Independent implementation keeps our change reviewable and standalone.
- Panel plumbing verified: `KeyboardPanel` exposes `screen` (from `anchorWindow.screen`), so a per-bar-monitor target is reachable in QML. `omarchy-monitor-state`'s displays JSON lacks per-display scale — panel must read `hyprctl monitors -j` itself or the state contract must be extended.
- Repo conventions: atomic single-concern commits, `test/shell.d/*-test.sh` suites (existing `monitor-scaling-test.sh` only covers persistence branch 1), visual verification required for UI changes, Nerd Font glyph care when editing QML.

## Constraints

- **Compatibility**: must handle all existing `monitors.lua` shapes — `omarchy_monitor_scale` variable, literal catch-all, explicit per-monitor lines, multi-line entries, `desc:` selectors
- **Style**: Omarchy AGENTS.md rules — atomic commits, `[[ ]]`/`(( ))` bash, `# omarchy:*` metadata headers, `#!/bin/bash` shebangs
- **Testing**: iterate via `~/.config/omarchy/plugins/` clone (hot-reload); final verification via `omarchy dev link`
- **Safety**: never edit `/usr/share/omarchy` on the live system — changes ship through the repo
- **Regression**: `monitor-clamshell-scale-test.sh` and related suites must stay green

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GSD project lives in the fork repo | The code under change lives here; `.planning/` alongside keeps plan and code together | — Pending |
| Two-phase split (CLI fix, then panel UI) | Omarchy requires atomic single-concern changes; maps to two clean potential upstream PRs | — Pending |
| Independent implementation, not building on PR #11414 | ~9 competing unmerged PRs for the same bug; a standalone change is more reviewable | — Pending |
| Test via plugin clone AND dev link | Hot-reload iteration plus real end-to-end verification | — Pending |
| `--default-index` as post-`--` menu arg → `defaultIndex` payload field | Reuses menu arg-forwarding; index is initial-only (filter typing resets to row 0) — accepted | Shipped Phase 4 |
| Locked tier tables: x264 18/23/28, x265 20/24/28, gif 15/10/5 fps; `medium` byte-identical to prior flags | Backward compat is the default path's contract | Shipped Phase 5 |
| Quality menu wire format `\t<tier>\t<subtext>` + strip-at-first-tab re-validation | Menu contract returns `label⇥subtext`; re-validation keeps foreign labels from reaching ffmpeg | Shipped Phase 6 |
| Estimate honesty: `CRF N · ~N MB` (1–2 sig figs), `larger than source` when estimate > src, all-qualitative on probe failure | Never show a misleading number; uniform row heights | Shipped Phase 6 |
| Actual size in done notification, MiB arithmetic labeled `MB`, `<1 MB` band, stat-failure degrades to plain body | Closes the estimate→actual calibration loop; never fabricates a size | Shipped Phase 7 |
| Format/resolution validation hoisted into `main()` ahead of menus and the start notification | Orphan `Transcoding video…` toast on bad positionals removed at milestone close | Shipped v1.1 close |
| Non-finite `--width`/`--maxheight` guarded like `defaultIndex` | `Inf`/`NaN` JSON tokens discarded the payload → menu hang | Shipped v1.1 close |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-16 after milestone v1.1 close*
