# Roadmap: Omarchy Fork

## Milestones

- [x] **v1.0: Per-Monitor Display Scaling** — shipped; phases 1–3 archived under `.planning/milestones/archived-20260914-phases/`
- [x] **v1.1: Transcode Quality & Size Feedback** — shipped 2026-09-16; phases 4–7. See `.planning/milestones/v1.1-ROADMAP.md`
- [ ] **v1.2: Target-Size Transcode** — active; phases 8–9

## Overview

Milestone v1.2 inverts v1.1's estimate→actual loop: the user names a target output size and `omarchy-transcode` derives the best parameters that fit. Phase 8 ships the non-interactive `--target <size>` path end to end — free-text size parsing into bytes, video bitrate derived from probed duration minus the audio term, resolution auto-step-down across locked floor rungs, two-pass encoding, a single overshoot retry, and honest refusal below every floor — all validated before menus and the start notification per the v1.1 hoisted-validation convention. Phase 9 layers a `Custom size…` row onto the mp4 quality menu that routes through the already-shipped `omarchy-menu-input` into the same parser and planner. The CLI path is the tracer — fully exercisable without the menu row — and each phase stays one atomic, upstream-reviewable change confined to `bin/omarchy-transcode` plus its test harness, honoring the additive-diff constraint while v1.1 sits under upstream review.

## Phases

**Phase Numbering:**

- Integer phases (8, 9): Planned milestone work
- Decimal phases (8.1, 8.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 8: Non-interactive `--target` size targeting** - `omarchy transcode INPUT mp4 RES --target 25M` → parse size → plan (duration probe → bitrate → resolution step-down) → two-pass encode → one overshoot retry → actual-size notification; every refusal dies before menus/notifications
- [ ] **Phase 9: Interactive `Custom size…` row** - mp4 quality menu gains a sentinel row → `omarchy-menu-input` free-text prompt → same parser/planner path → re-prompt once on bad input, clean cancel on Esc

## Phase Details

### Phase 8: Non-interactive `--target` size targeting

**Goal**: `omarchy transcode <video> [mp4] [res] --target <size>` accepts free-text sizes (`25M`, `1.5G`, `500K`, `25MB`; bare number = MB), derives video bitrate from probed duration (`target×8 ÷ duration × ~0.98 reserve − audio`), auto-steps resolution down the locked rungs (4k → 1080p → 720p) when the budget is tight, two-pass encodes to the budget, retries once on overshoot, and refuses honestly — naming the achievable minimum — below every floor

**Depends on**: Nothing (first milestone phase)

**Requirements**: SIZE-10, SIZE-13, SIZE-14, SIZE-15, SAFE-02

**Success Criteria** (what must be TRUE):

  1. `omarchy transcode in.mov mp4 1080p --target 25M` runs ffmpeg twice — pass 1 carrying `-pass 1 -an -f null /dev/null`, pass 2 carrying `-pass 2 -b:v <derived>k -c:a aac` and the deduped output path — with `-vf`/`-c:v` identical across passes, no `-crf` anywhere on either line, and output named `in-1080p-25M.mp4`
  2. The size parser accepts `25M`/`25m`/`25MB`/`1.5G`/`500K`/bare `25` (MB) into integer bytes and rejects `abc`, `-5M`, `0`, `25.5.2M`, and a missing value — each rejection on stderr before any menu and before the start notification
  3. A 4k request on a tight budget steps down to the highest rung whose video-bitrate floor fits; `output_path`, the start toast, and the done toast all name the *effective* resolution, because the planner runs before `output_path` and writes the rung back into `resolution`
  4. Below the 720p floor — or when fixed 192k audio alone exceeds the budget — the run refuses naming the achievable minimum size — no negative, zero, or `-nan` `-b:v` ever reaches argv; duration-probe failure refuses the same way (no qualitative fallback exists under `--target`)
  5. The refusal matrix holds pre-notification: `--target` + positional quality errors naming both; `--target` + gif refuses (palette output ignores `-b:v`); `--target` + picture refuses; `--target` skips `select_quality` entirely
  6. A completed encode landing over target triggers exactly one re-encode with a tightened budget scaled by the overshoot ratio; the done notification reports the actual size either way — never a silent loop
  7. Passlogs live in `mktemp -d` under `TMPDIR` with trap cleanup — a pass-1 or pass-2 failure leaves zero `*-0.log*` artifacts, and stale-passlog reuse is impossible by construction
  8. The test harness is pass-aware: the ffmpeg stub branches on `-pass` (per-pass RC knobs, synthesizes passlog artifacts, `truncate`s only the real output), `run_transcode` exports `TMPDIR`, and every v1.1 pin still passes — `medium` argv byte-identical, non-interactive tier runs never probe

**Canonical refs:** `.planning/research/ARCHITECTURE.md` (integration map, step-down ordering, additive-diff rules), `.planning/research/PITFALLS.md` (pitfalls 1–7, 9–11), `.planning/research/STACK.md` (verified two-pass/numfmt mechanics), `.planning/research/FEATURES.md` (budget math, floor grounding), `bin/omarchy-transcode`, `test/shell.d/transcode-quality-test.sh`

**Plans**: 1 plan

- [x] 08-01-PLAN.md — `--target` flag arm + `parse_target_size` + refusal matrix + `plan_target`/floor table + `transcode_video_target` two-pass sibling (`mktemp -d` passlog + trap) + `resolution`-overwrite wiring before `output_path` + overshoot retry + pass-aware stub harness — one atomic commit (the flag without the encoder is dead code; the parser without the flag is unreachable)

### Phase 9: Interactive `Custom size…` row

**Goal**: The mp4 `Select quality` menu gains a `Custom size…` row that opens `omarchy-menu-input`, feeds the typed answer through the same `parse_target_size` → `plan_target` path as `--target`, re-prompts once on empty or unparseable input, and cancels cleanly on Esc — with zero QML and zero `omarchy-menu-select` changes

**Depends on**: Phase 8 (the row hands off to its parser, planner, and dispatch)

**Requirements**: MENU-02

**Success Criteria** (what must be TRUE):

  1. Interactive mp4 transcodes show `Custom size…` as a fourth row with a subtext (uniform row heights); gif menus never contain it
  2. Picking the row opens `omarchy-menu-input "Target size (e.g. 25M)"`; a valid answer produces ffmpeg argv byte-identical to the equivalent `--target` run — one code path behind both entry points (e.g. a `target:<bytes>` prefix through `select_quality`'s return, branched before the tier whitelist)
  3. Empty submit (exit-0-with-empty, not a cancel) and unparseable input each re-prompt once, then cancel cleanly; Esc exits before the start notification like every sibling prompt
  4. The sentinel label can never reach the tier `case` or ffmpeg as a "quality"; the strip-at-first-tab re-validation stays the single chokepoint
  5. `omarchy-menu-input` is stubbed in the harness (`FAKE_INPUT` knob + call-log line) in the same commit — the suite cannot hang on the real binary's `done_file` spin-wait

**Canonical refs:** `.planning/research/ARCHITECTURE.md` (sentinel/prefix contract, input-mode quirks), `.planning/research/PITFALLS.md` (pitfalls 8, 11), `bin/omarchy-menu-input`, `bin/omarchy-transcode`, `shell/plugins/menu/Menu.qml` (input mode, already shipped)

**Plans**: 1 plan (anticipated)

- [ ] 09-01: mp4-only sentinel row + `omarchy-menu-input` handoff + `target:` return contract + re-prompt-once-then-cancel + `omarchy-menu-input` stub + interactive-parity assertions (Custom row ≡ `--target` argv)

## Progress

**Execution Order:**
Phases execute in numeric order: 8 → 9 (9 layers on 8's parser, planner, and dispatch)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 8. Non-interactive `--target` size targeting | 0/1 | Pending |  |
| 9. Interactive `Custom size…` row | 0/1 | Pending |  |

## Next

After v1.2: remaining candidates tracked in `.planning/milestones/v1.1-REQUIREMENTS.md` (SIZE-11 intent presets, SIZE-12 gif estimates, QUAL-10 picture quality arg, QUAL-11 Nautilus batch-answer memory) plus v3 deferrals added in REQUIREMENTS.md (SIZE-16 sub-720p rungs, SIZE-17 deeper overshoot convergence).
