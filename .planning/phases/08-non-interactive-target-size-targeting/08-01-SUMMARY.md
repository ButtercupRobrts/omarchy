---
phase: 08-non-interactive-target-size-targeting
plan: 01
subsystem: cli
tags: [bash, ffmpeg, ffprobe, awk, numfmt, two-pass, passlog, stub-e2e, transcode, notify]

# Dependency graph
requires:
  - phase: 05-non-interactive-quality-in-omarchy-transcode
    provides: "positional `quality` tier case in `transcode_video`, `output_path` suffix/dedupe, and the stub-e2e harness this phase extends"
  - phase: 06-interactive-quality-prompt-size-estimates
    provides: "`video_duration`/`video_audio_kbps` probes, `select_quality` menu, `estimate_label`, dual-mode `omarchy-menu-select`/`ffprobe` stubs"
  - phase: 07-completion-size-notification-docs
    provides: "`output_size_label` + the `Transcoded to … (N MB)` completion notification this phase reports the actual size through"
provides:
  - "`omarchy transcode <video> [mp4] [res] --target <size>` — free-text size (`25M`, `25m`, `25MB`, `1.5G`, `500K`, bare `25`=MB) parsed by `parse_target_size` into integer bytes via `numfmt --from=iec`, canonicalized to a `numfmt --to=iec` filename token"
  - "`plan_target`: duration/audio probes → `target×8 ÷ duration ÷ 1000 × 0.98 − audio_kbps` in awk `%d` truncation → highest rung whose floor fits (4k 2000 / 1080p 800 / 720p 400 kbps, inclusive) → effective rung written back into `resolution` before `output_path`"
  - "Honest refusals ahead of every side effect: parse rejects exit 2 before menus; `--target`+quality-tier, `--target`+gif (positional or menu-picked), `--target`+picture, target ≥ source, failed/`N/A`/zero duration, and below-every-floor (naming the `(400+audio)×dur×125` achievable minimum as `~N MB`) all exit 1 pre-notification"
  - "`transcode_video_target`: two-pass encode (`-pass 1 -an -f null /dev/null`, `-pass 2 -c:a aac -b:a 192k -movflags +faststart`), `-passlogfile` in a `mktemp -d` under `$TMPDIR` with a path-baked EXIT trap, one toast updated `-p` → `-r` across passes 1/2 → 2/2, and exactly one pass-2-only overshoot retry at `video_kbps×target÷actual` writing a passdir sibling `mv`'d onto `$output` only on success"
  - "Pass-aware harness: the ffmpeg stub branches on `-pass` (synthesizes `-0.log`/`.mbtree`, requires the pass-1 artifacts at pass-2's own `-passlogfile`, per-invocation `FAKE_PASS2_RC` list, `FAKE_OUT_BYTES`/`FAKE_OUT_BYTES2` size queue), the notification stub prints id `7` for `-p`, and `run_transcode` exports `TMPDIR`"
affects: [phase-9-custom-size-row, verify-work, uat]

# Actuals (#2632)
actuals:
  tokens: 10846
  tasks: 3
  commits: 1
  plan_head_before: dc2b4e8233f616c3ffda966afc4b34eddd651c11

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Budget math in awk only: `awk -v` vars with `%d` truncation toward zero and the `d <= 0` gate inside the awk program — floats never enter `(( ))`, and a negative/zero result rides the floor loop to the 720p refusal"
    - "Passdir lifecycle: `mktemp -d \"${TMPDIR:-/tmp}/transcode-2pass.XXXXXX\"` + `trap \"rm -rf -- $(printf '%q' \"$passdir\")\" EXIT` — the resolved path is baked into the trap string because a `local` is already unbound when the trap runs after an errexit unwind"
    - "Overshoot retry: stat-gate on any byte-over → one pass-2-only re-encode to a unique passdir sibling (no `-y`/`-n` anywhere) → `mv` onto `$output` only on success → the done toast reports the stat-measured actual size either way"
    - "Per-invocation stub queues: `grep -c ' -pass 2 ' \"$CALLS\"` is the pass-2 call index for a run, feeding `FAKE_OUT_BYTES`/`FAKE_OUT_BYTES2` sizing and the `FAKE_PASS2_RC` rc list"

key-files:
  created: []
  modified:
    - bin/omarchy-transcode
    - test/shell.d/transcode-quality-test.sh

key-decisions:
  - "One atomic `feat(08-01)` commit carries script + harness (plan-mandated — the flag without the encoder is dead code, the parser without the flag is unreachable); `transcode_video`, `output_path`, `select_quality`, and every v1.1 helper stay byte-identical for the PR #12135 additive-diff window"
  - "`--target` refuses rather than degrades everywhere: no qualitative fallback on probe failure, no tolerance band on overshoot, no audio step-down ladder — the honest refusal/toast IS the feature (D-05/D-06/D-07)"
  - "An omitted resolution still prompts under `--target`, and the pick is the planner's ceiling: a 4k pick on a 5M budget encodes 720p and the toast says so (`stepped down from 4k`)"
  - "Retry rows pin byte-exact boundaries (target, target+1, target−1) rather than the plan's illustrative 27M/25M example — same contract, sharper edge coverage; retry math verified at 6658k → 6657k"

patterns-established:
  - "The shared `parse_target_size`/`plan_target` contract is deliberately reusable — Phase 9's `Custom size…` menu row hands its typed input to the same two helpers and never re-parses"
  - "Refusal ordering as a map: parse rejects in the arg loop (exit 2), semantic conflicts after `media_type` (exit 1), budget refusals in `plan_target` after probing (exit 1) — every refusal dies before the start notification, and the call-log shape per refusal is pinned in tests"
  - "Notification id plumbing: `-p` captures the daemon id at the start toast, `-r <id>` replaces it in place for pass 2 — one toast per run, not one per pass"

requirements-completed: [SIZE-10, SIZE-13, SIZE-14, SIZE-15, SAFE-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "`omarchy transcode in.mov mp4 1080p --target 25M` runs exactly two ffmpeg calls — pass 1 with `-pass 1 -passlogfile <passdir>/2pass -an -f null /dev/null`, pass 2 with `-pass 2 -b:v 3233k -c:a aac -b:a 192k -movflags +faststart` — `-vf`/`-c:v`/`-preset`/`-b:v` byte-identical across passes, no `-crf` anywhere, output `in-1080p-25M.mp4`"
    requirement: SIZE-10
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a --target run two-passes at the derived bitrate with byte-identical shared flags"
        status: pass
    human_judgment: false
  - id: D2
    description: "Free-text size parsing: `25M`/`25m`/`25MB`/`1.5G`/`500K`/bare `25` accept into integer bytes and canonicalize to filename tokens (`-25M`, `-1.5G`, `-5.0M`); `abc`/`-5M`/`0`/`25.5.2M`/missing value reject with exit 2 and a completely empty call log"
    requirement: SIZE-10
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#size forms 25m/25MB/25/1.5G/500K parse and canonicalize"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#invalid --target values exit 2 before any side effect"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a missing --target value exits 2 with an empty call log"
        status: pass
    human_judgment: false
  - id: D3
    description: "Resolution step-down: the planner picks the highest rung whose floor fits (4k→1080p at 10M, →720p at 5M, exactly-at-floor stays 4k), writes the rung back before `output_path`, and both toasts + the filename name the effective resolution with a step-down disclosure; an unset resolution still prompts and its pick acts as the ceiling"
    requirement: SIZE-13
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a 4k request on a 10M budget steps down to 1080p and says so"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a 4k request on a 5M budget steps down to 720p"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a target at or above the 4k floor stays at 4k"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an unset resolution prompts as the planner ceiling under --target"
        status: pass
    human_judgment: false
  - id: D4
    description: "Honest refusals: below every floor and below the audio-only budget the run refuses naming the computed `~N MB` achievable minimum; target ≥ source refuses before probing naming both sizes and the tier path; failed/`N/A`/zero duration probes refuse pre-notification; no negative, zero, or `-nan` `-b:v` ever reaches ffmpeg argv"
    requirement: SIZE-14
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#targets below every floor refuse naming the achievable minimum"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a target too small for audio alone refuses; no bad -b:v reaches argv"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a target at or above the source refuses before probing"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#failed, N/A, and zero durations all refuse before any notification"
        status: pass
    human_judgment: false
  - id: D5
    description: "Overshoot retry: any byte-over triggers exactly one pass-2-only re-encode at `video_kbps×target÷actual` (6658k→6657k at 50M+1) writing a passdir sibling `mv`'d onto `$output` on success; a failed retry preserves the overshot first output; at/under target never retries; a still-over retry never loops; passlog artifacts never survive success or either pass failure; no `-y`/`-n` on any ffmpeg line"
    requirement: SIZE-15
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a byte-over target retries pass-2 once at the tightened bitrate"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an at-or-under target never retries"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an overshoot retries at most once"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a failed retry preserves the overshot first output"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a pass-1 failure aborts before pass 2 with a clean passdir"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a pass-2 failure aborts with no done toast and a clean passdir"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#no ffmpeg line carries -y or -n"
        status: pass
    human_judgment: false
  - id: D6
    description: "Safety/refusal matrix: `--target`+positional quality refuses naming both, `--target`+gif refuses (positional and menu-picked), `--target`+picture refuses before any menu, a fully-positional `--target` run skips the quality menu and probes exactly twice, ordinary tier runs still never probe"
    requirement: SAFE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#--target plus a quality tier refuses naming both"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#--target gif refuses pre-notification"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a menu-picked gif under --target refuses pre-notification"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#--target on a picture refuses before any menu or notification"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a fully-positional --target run skips the quality menu"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a --target run probes exactly twice"
        status: pass
    human_judgment: false
  - id: D7
    description: "Real-encode dogfood + notification UAT: `omarchy transcode <real-clip> mp4 1080p --target 10M` lands under 10M and plays; one toast updates pass 1/2 → 2/2 in place and the done toast reports the actual size; below-floor and ≥source refusals show no toast"
    requirement: SIZE-15
    verification: []
    human_judgment: true
    rationale: "Stubs prove argv and call ordering, not real encoder acceptance or a live notification daemon — the dev shell loads the packaged /usr/share/omarchy tree, so end-of-phase human UAT covers it (checklist recorded in ## Issues Encountered / UAT)"

# Metrics
duration: 46min
completed: 2026-09-17
status: complete
---

# Phase 8 Plan 01: Non-interactive `--target` size targeting Summary

**`omarchy transcode … --target <size>` parses a free-text size, derives bitrate from the probed duration, steps resolution down locked floor rungs, two-pass encodes to budget, retries once on any byte-over, and refuses honestly before every side effect**

## Performance

- **Duration:** ~46 min (task-1 tracer slice executed in the preceding session segment)
- **Started:** 2026-09-17T00:15:00Z (plan-head ledger recorded 00:14:55Z)
- **Completed:** 2026-09-17T01:00:30Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `--target <size>` lands end-to-end on the non-interactive path: `parse_target_size` normalizes `25M`/`25m`/`25MB`/`1.5G`/`500K`/bare-MB into bytes and canonicalizes a filename token; `plan_target` probes duration + audio, derives `target×8÷dur÷1000×0.98−audio` in awk, and steps the requested rung down the 2000/800/400 kbps floors; `transcode_video_target` two-passes with a tmpdir passlog and one `-p`→`-r` toast
- The refusal matrix holds ahead of every menu and notification — parse rejects exit 2 with an empty call log; quality-conflict, gif (positional or menu-picked), picture, ≥source, dead-probe, below-floor, and audio-only refusals each die with their own stderr wording and the achievable-minimum `~N MB` where the plan pins it
- The overshoot retry is exactly one pass-2-only re-encode at `video_kbps×target÷actual` into a unique passdir sibling, `mv`'d over `$output` only on success; the done toast reports the stat-measured actual size either way, and a failed retry keeps the overshot-but-playable first output
- The harness is pass-aware (per-pass RC knobs, synthesized passlog artifacts, per-invocation size queue, notification id `7`) and all 82 assertions pass — including every v1.1 pin (`medium` argv byte-identical, tier runs never probe)

## Task Commits

The plan mandates one atomic commit — "the flag without the encoder is dead code; the parser without the flag is unreachable" — so tasks 1–2 ran uncommitted and the whole phase ships in:

1. **Tasks 1–3 (tracer slice + refusal matrix + retry/hygiene + atomic commit)** — `ddea5f7d` (feat(08-01)): `bin/omarchy-transcode` + `test/shell.d/transcode-quality-test.sh`, +781/−14. Tracer feedback gate: end-of-phase mode with automated-only verify → re-ran the focused suite green before expansion, no checkpoint.

**Plan metadata:** `docs(08-01)` commits follow this file — the SUMMARY commit itself, then the STATE/ROADMAP/REQUIREMENTS sync.

## Files Created/Modified

- `bin/omarchy-transcode` — `--target` arm in the arg loop + `[--target size]`/`--target size` usage/docs (:6–:7, :12–:21); new helpers `parse_target_size` (:310), `plan_target` (:339), `transcode_video_target` (:398) between `output_size_label` and `main()`; target-aware quality-menu gate (`-z $target_bytes`); planner call + effective-rung writeback before `output_path`; `-p`/`-r` notification plumbing; refusal matrix at :522/:540/:547–:572
- `test/shell.d/transcode-quality-test.sh` — pass-aware ffmpeg stub (`-pass` arms, synthesized `2pass-0.log`/`.mbtree`, passlog-existence pin at pass 2, `FAKE_PASS1_RC`/`FAKE_PASS2_RC`/`FAKE_OUT_BYTES`/`FAKE_OUT_BYTES2` knobs), notification stub `-p`→id `7`, `TMPDIR` export in `run_transcode`, and ~40 new assertion rows across the happy path, parsing, refusal matrix, retry, and hygiene

## Decisions Made

- Kept the plan's one-atomic-commit mandate (script + harness as the reviewable unit); every v1.1 helper body is byte-identical — the diff's removed lines are confined to metadata, `usage()`, the menu gate, and the `output_path`/dispatch lines
- Retry rows use byte-exact boundaries (target−1, target, target+1) instead of the plan's illustrative 27M/25M example — identical contract, sharper edge pins; the tightened-bitrate math is asserted at 6658k→6657k
- The passlog dir is named `transcode-2pass.XXXXXX` under `$TMPDIR` so the cleanup rows can `find -name '*2pass*'` — a strictly stronger check than the plan's `*-0.log*` pattern (it also catches an empty leaked dir)
- Trap fix folded in (see Auto-fixed Issues): the EXIT trap bakes the resolved passdir path because errexit unwinds the function's locals before the trap runs

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — test wrongness] Sparse 2 GiB fixture for the `1.5G` accepted-size row**
- **Found during:** Task 1 (tracer slice)
- **Issue:** `--target 1.5G` on the 120 MiB fixture correctly refused ≥source before the naming assertion could run — the row exercised the wrong path
- **Fix:** `truncate -s 2G "$TMPDIR/big.mov"` sparse fixture for that case; removed after asserting
- **Files modified:** `test/shell.d/transcode-quality-test.sh`
- **Verification:** accepted-forms row green
- **Committed in:** `ddea5f7d` (part of the atomic commit)

**2. [Rule 1 — test wrongness] Canonical token expectation `5M` → `5.0M`**
- **Found during:** Task 1 (tracer slice)
- **Issue:** `numfmt --to=iec` renders exact MiB with `.0` (`5.0M`), which the plan's research already accepted; the row pinned `5M`
- **Fix:** Row asserts `in-720p-5.0M.mp4` with a comment noting `.0` is accepted
- **Files modified:** `test/shell.d/transcode-quality-test.sh`
- **Verification:** step-down rows green
- **Committed in:** `ddea5f7d`

**3. [Rule 1 — real bug] EXIT trap referenced a `local` that is unbound when it runs**
- **Found during:** Task 3 (passlog-hygiene rows) — the pass-1-failure row caught a leaked `transcode-2pass.*` dir
- **Issue:** `trap '… -d $passdir …' EXIT` set inside `transcode_video_target` fires after errexit tears the function's locals down, so `passdir` evaluated empty and `rm -rf` never ran — every mid-run failure would have leaked passlogs on the real system too
- **Fix:** bake the resolved path at trap-install time: `trap "rm -rf -- $(printf '%q' "$passdir")" EXIT`, with a comment naming the mechanism
- **Files modified:** `bin/omarchy-transcode`
- **Verification:** reproduced in an isolated script, then the pass-1/pass-2-failure hygiene rows go green — `find "$TMPDIR" -name '*2pass*'` empty on every path
- **Committed in:** `ddea5f7d`

---

**Total deviations:** 3 auto-fixed (2 test-correctness, 1 real cleanup bug)
**Impact on plan:** All necessary for correctness — the trap fix prevents real passlog leaks. No scope creep.

## Issues Encountered

- `./test/shell` baseline: the failing files are exactly a subset of STATE.md's 7 recorded environmental files (bar-icon-geometry, config, runtime-smoke, snapper, unowned-system-paths fail; locate and screenshot-sanity pass in this environment). Verified identical on the unmodified baseline via `git stash` — zero failures attributable to this change.
- Silent-abort diagnosis during task 1: a bare `run_transcode` in the accepted-size loop died under `set -e` with no `not ok` line; traced via `bash -x` to the ≥source refusal — resolved by deviation 1.

### UAT checklist (recorded, not executed — non-gating)

The dev shell loads the packaged `/usr/share/omarchy` tree and no real notification daemon is exercisable, so per the plan these are recorded for end-of-phase human UAT:

- (a) `omarchy transcode <real-clip> mp4 1080p --target 10M` → output lands under 10M, plays, both toasts name the effective resolution
- (b) ONE notification updates pass 1/2 → pass 2/2 in place, then the done toast reports the actual size
- (c) A below-floor target (e.g. `4M` on a 60 s clip) refuses naming the achievable minimum, with no toast at all
- (d) A target ≥ source names both sizes and points at dropping `--target` for format conversion

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 9 (`Custom size…` menu row) hands off to the shared `parse_target_size`/`plan_target` contract — the menu needs only to collect the string and route it through the same planner; the dispatch, retry, and refusal machinery are already proven
- The `-p`/`-r` notification-id pattern is established for any future multi-stage transcode toast
- No blockers

## Self-Check: PASSED

- `git log --oneline --all --grep="08-01"` → `ddea5f7d` (1 commit, matching the ledger `dc2b4e82..HEAD` count)
- `bash -n bin/omarchy-transcode` → clean
- `bash test/shell.d/transcode-quality-test.sh` → exit 0, 82 `ok` lines, 0 `not ok` — every task-1/2/3 row plus all v1.1 pins
- `./test/cli` → exit 0 (metadata lint + routing green)
- `./test/shell` → exit 1; failing files are a strict subset of the 7 recorded environmental files, byte-identical to the stashed baseline run
- Diff confinement: `git show` lists exactly the two `files_modified` paths; removed lines confined to metadata/`usage()`/menu-gate/`output_path`/dispatch sites; all v1.1 helper bodies byte-identical
- Acceptance greps: `-z $target_bytes` menu gate, `plan_target "$input"` before `output_path`, `-passlogfile` ×3, `retry_kbps`/`retry.mp4` inside `transcode_video_target`, `rm -rf "$passdir"` after the retry block — all present
- No stubs: the diff scan for TODO/FIXME/placeholder markers found only legitimate `STUB_DIR` harness references; no `## Known Stubs` needed

---
*Phase: 08-non-interactive-target-size-targeting*
*Completed: 2026-09-17*
