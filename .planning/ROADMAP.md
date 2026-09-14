# Roadmap: Omarchy Fork — Transcode Quality & Size Feedback

## Overview

Milestone v1.1 adds a quality step and size feedback to `omarchy-transcode` in four atomic phases. First, `omarchy-menu-select` learns a `--default-index` flag so a menu row can be pre-highlighted — additive payload plumbing that unblocks "Enter = medium". Then `omarchy-transcode` gains a non-interactive 4th positional quality arg with locked per-codec tier tables (x264 CRF 18/23/28, x265 CRF 20/24/28, gif 15/10/5 fps) where `medium` reproduces today's flags byte-for-byte. The interactive quality prompt follows, showing `~N MB` estimates as row subtext for mp4 and fps for gif, and the milestone closes with the actual output size in the completion notification plus a docs sweep. The ordering isolates the cross-component contract change first and proves the encoder tables before any UI depends on them — each phase is one reviewable change and a candidate upstream PR.

## Phases

**Phase Numbering:**

- Integer phases (4, 5, 6, 7): Planned milestone work
- Decimal phases (4.1, 4.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 4: Menu `defaultIndex` plumbing** - `omarchy-menu-select` accepts `--default-index N` (post-`--` menu arg) → `defaultIndex` in the JSON payload → `Menu.qml` `openDmenu` pre-highlights that row
- [ ] **Phase 5: Non-interactive quality in `omarchy-transcode`** - Optional 4th positional arg with validation, locked CRF/fps tier tables, non-default quality filename suffix, deliberate output-collision policy
- [ ] **Phase 6: Interactive quality prompt + size estimates** - Quality menu step after format+resolution for video, `~N MB` subtexts for mp4, fps subtexts for gif, `medium` pre-highlighted via Phase 4 plumbing
- [ ] **Phase 7: Completion-size notification + docs** - Actual output size appended to the done notification; usage/metadata/manual sync

## Phase Details

### Phase 4: Menu `defaultIndex` plumbing

**Goal**: `omarchy-menu-select` accepts `--default-index N` after `--`, emits `defaultIndex` in the select-mode JSON payload, and `Menu.qml`'s `openDmenu` initializes `selectedIndex` from it — with every existing caller byte-identical in behavior

**Depends on**: Nothing (first milestone phase)

**Requirements**: MENU-01

**Success Criteria** (what must be TRUE):

  1. `omarchy-menu-select "Prompt" a b c -- --default-index 1` opens the menu with row `b` pre-highlighted; Enter selects it
  2. All 16 existing `omarchy-menu-select` callers — including stdin-fed ones (timezone, keybindings, plugin menus) — behave exactly as before; the payload field is simply absent
  3. Out-of-range `defaultIndex` values clamp safely via the existing `rebuildDmenuDisplay` bounds check
  4. Typing in the filter still resets the highlight to row 0 (initial-only semantics, per `setFilter` behavior)

**Canonical refs:** `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md` (pitfall 2), `bin/omarchy-menu-select`, `shell/plugins/menu/Menu.qml`

**Plans**: 1 plan

- [ ] 04-01-PLAN.md — `--default-index` post-`--` flag → `defaultIndex` payload field → `openDmenu` pre-highlight via `MenuModel.dmenuDefaultIndex`, with stub e2e + node coverage and docs

### Phase 5: Non-interactive quality in `omarchy-transcode`

**Goal**: `omarchy transcode INPUT FORMAT RESOLUTION [QUALITY]` accepts an optional quality arg that selects locked per-codec tiers — x264 CRF 18/23/28, x265 CRF 20/24/28, gif 15/10/5 fps — where `medium` or omitted reproduces today's encoder flags byte-for-byte, non-default quality appends a suffix to the output filename, and output collisions follow a deliberate non-interactive-safe policy

**Depends on**: Nothing (can run parallel to Phase 4)

**Requirements**: QUAL-02, QUAL-03, SAFE-01

**Success Criteria** (what must be TRUE):

  1. `omarchy transcode in.mov mp4 1080p medium` and `omarchy transcode in.mov mp4 1080p` invoke ffmpeg with exactly today's flags (x264 `-preset fast -crf 23`, aac 192k) and produce `in-1080p.mp4`
  2. `high`/`low` map to the locked tier tables (x264 18/28, x265 20/28 at 4k, gif 15/5 fps) and produce `in-1080p-high.mp4` / `in-1080p-low.mp4`
  3. A 4th positional arg on a picture input exits non-zero with a clear error; picture flow is otherwise untouched
  4. An existing output file never hangs (ffmpeg stdin prompt) or silently fails on a detached launch — the collision policy is explicit in code and covered by test
  5. `usage()`, `# omarchy:args=`, and relevant docs reflect the new arg

**Canonical refs:** `.planning/research/STACK.md` (tier tables), `.planning/research/PITFALLS.md` (pitfalls 3–7), `bin/omarchy-transcode`

**Plans**: 0 plans

### Phase 6: Interactive quality prompt + size estimates

**Goal**: The video transcode flow gains a "Select quality" step after format+resolution whose rows carry `~N MB` estimate subtexts for mp4 (ffprobe duration × tier bitrate table + 192k audio) and fps subtexts for gif, with `medium` pre-highlighted via `--default-index 1` — pictures see no new prompt

**Depends on**: Phase 4 (needs `--default-index`), Phase 5 (needs the tier tables)

**Requirements**: QUAL-01, SIZE-01

**Success Criteria** (what must be TRUE):

  1. Transcoding a video interactively shows file → format → resolution → quality; the quality rows read `high/medium/low` with subtexts (`CRF 18 · ~110 MB` for mp4, `15 fps` for gif)
  2. The estimate is duration × per-resolution/tier bitrate midpoint + fixed audio term, rendered as `~N MB` with 1–2 sig figs; when it would exceed the source size or duration probe fails, the subtext degrades gracefully rather than lying
  3. `medium` is pre-highlighted; pressing Enter on defaults reproduces Phase 5's `medium` behavior
  4. The `label⇥subtext` return value is stripped (`${sel%%$'\t'*}`) before tier matching — no silent `set -e` aborts
  5. Picture inputs still stop after the resolution prompt
  6. ffprobe runs only inside the interactive video branch — non-interactive callers never pay for it

**Canonical refs:** `.planning/research/ARCHITECTURE.md` (integration points, tab contract), `.planning/research/FEATURES.md` (estimate placement), `.planning/research/PITFALLS.md` (pitfalls 1, 8, 10)

**Plans**: 0 plans

### Phase 7: Completion-size notification + docs

**Goal**: The transcode completion notification reports the actual output file size, closing the estimate→actual loop, and all user-facing docs/metadata are in sync

**Depends on**: Phase 6

**Requirements**: SIZE-02

**Success Criteria** (what must be TRUE):

  1. The completion notification includes the actual output size (e.g. `38 MB`), for both video and picture transcodes
  2. `usage()`, `# omarchy:*` metadata, `docs/`, and `manual/` entries are consistent with the shipped behavior (test/cli metadata shape stays green)

**Canonical refs:** `.planning/research/ARCHITECTURE.md`, `bin/omarchy-transcode`

**Plans**: 0 plans

## Progress

**Execution Order:**
Phases execute in numeric order: 4 → 5 → 6 → 7 (4 and 5 are independent; 6 gates on both)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Menu `defaultIndex` plumbing | 0/1 | Pending |  |
| 5. Non-interactive quality in `omarchy-transcode` | 0/0 | Pending |  |
| 6. Interactive quality prompt + size estimates | 0/0 | Pending |  |
| 7. Completion-size notification + docs | 0/0 | Pending |  |
