---
phase: 06-interactive-quality-prompt-size-estimates
plan: 01
subsystem: cli
tags: [bash, ffmpeg, ffprobe, awk, menu-select, default-index, stub-e2e, transcode]

# Dependency graph
requires:
  - phase: 04-menu-defaultindex-plumbing
    provides: "`omarchy-menu-select -- --default-index N` → payload `defaultIndex` → Menu.qml `selectedIndex` (pre-highlight plumbing)"
  - phase: 05-non-interactive-quality-in-omarchy-transcode
    provides: "4th-positional `quality` + locked tier case in `transcode_video`, `output_path` suffix/dedupe, and the stub-e2e harness this phase extends"
provides:
  - "Interactive `Select quality` menu on the video path (after format+resolution, before `output_path`), rows passed as `\\t<tier>\\t<subtext>` argv with `medium` pre-highlighted via `-- --default-index 1`"
  - "mp4 estimate subtexts `CRF N · ~N MB`: ffprobe duration × locked resolution/tier bitrate midpoints (720p 2500/1500/700, 1080p 5500/3000/1400, 4k 16000/9000/4500 kbps) + audio term, rendered at 1–2 sig figs with no decimals"
  - "Honest degradation: per-row `larger than source` past `stat -c %s`, uniform `Best quality`/`Balanced`/`Smallest file` fallback on probe `N/A`/failure; gif rows carry `N fps` and never probe"
  - "Six helpers in `bin/omarchy-transcode` (`video_duration`, `video_audio_kbps`, `quality_token`, `quality_kbps`, `estimate_label`, `select_quality`) between `copy_to_clipboard` and `main` — the PR #6698-safe slot"
  - "Post-pick strip (`${selection%%$'\\t'*}`) + `high|medium|low` re-validation inside `select_quality`, before the notification boundary (T-06-02)"
  - "Extended stub harness: dual-mode `omarchy-menu-select` (FAKE_PICK), arg-dispatched `ffprobe` (FAKE_DURATION/FAKE_AUDIO/FAKE_PROBE_RC), `truncate -s` sized fixtures — 43 assertions"
affects: [phase-7-completion-notification, verify-work, uat]

# Actuals (#2632)
actuals:
  tokens: 6063
  tasks: 3
  commits: 2
  plan_head_before: a7bf1a1bd6aa3887e0e05c5759ba6b7b95d1e39d

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tab-row wire protocol: `\\t<label>\\t<subtext>` argv rows (leading tab = empty glyph field) into `omarchy-menu-select ... -- --default-index 1`; `label[\\tsubtext]` return stripped at the first tab and re-validated before use"
    - "Probe guards under `set -euo pipefail`: every ffprobe/stat call is `|| true`- or `if`-guarded and regex-gated (`^[0-9.]+$`/`^[0-9]+$`) before reaching `awk -v` — a probe hiccup degrades cosmetically, never aborts"
    - "Sig-fig rendering in awk: `d = int(log(mb)/log(10)) - 1; r = int(mb/(10^d)+0.5)*(10^d)` → `~N MB` at 1–2 significant figures"
    - "Dual-mode test stubs: `${FAKE_PICK+x}` distinguishes unset (tripwire, exit 1) from set (answer the menu), so one stub guards non-interactive rows and answers interactive ones"

key-files:
  created: []
  modified:
    - bin/omarchy-transcode
    - test/shell.d/transcode-quality-test.sh
    - test/shell.d/menu-select-test.sh

key-decisions:
  - "One atomic `feat(06-01)` commit carries script + harness (plan-mandated, Phase-4/5 precedent — one reviewable, independently revertible unit); the stale Phase-4 `--default-index` caller pin was re-scoped to omarchy-transcode in a preceding `test(06-01)` commit so every commit stays green"
  - "Audio-aware estimate adopted (discretion): `video_audio_kbps` returns 0 only on a successful probe reporting no `audio` line; probe failure keeps 192 — conservative over-estimate, never under"
  - "gif never spawns ffprobe (probes gated `format == mp4` inside `select_quality`); upscale flag deferred; helpers placed below `copy_to_clipboard` to stay clear of upstream PR #6698's insertion zone"
  - "Fallback wording pinned: `larger than source` (per-row D-02 degrade) and `Best quality`/`Balanced`/`Smallest file` (D-03 whole-menu fallback) — any rewording must update the test rows in the same commit"

patterns-established:
  - "`select_quality` owns the entire tab⇥protocol — row build, menu call, strip, re-validation — so main() adds exactly 3 lines and the contract lives in one place"
  - "Env knobs as per-invocation prefixes (`FAKE_PICK=… FAKE_DURATION=60 run_transcode …`) propagate through the function to stub children and cannot leak between rows"

requirements-completed: [QUAL-01, SIZE-01]

coverage:
  - id: D1
    description: "`omarchy transcode in.mov mp4 1080p` (quality unset) fires `Select quality` after the resolution prompt with `\\t<tier>\\tCRF N · ~N MB` rows and `-- --default-index 1`; a `medium` pick produces ffmpeg argv byte-identical to positional `medium` and writes the unsuffixed `in-1080p.mp4`"
    requirement: QUAL-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#the quality menu fires with CRF N · ~N MB rows and medium pre-highlighted"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a medium menu pick equals positional medium byte-for-byte"
        status: pass
    human_judgment: false
  - id: D2
    description: "mp4 estimates are `dur × (kbps + audio) × 125` rendered `~N MB` at 1–2 sig figs with no decimal (60 s/1080p → ~41/~23/~11; 157 s → ~110/~60/~30); the 192k audio term drops only on a proven-audio-less source (~39/~21/~10)"
    requirement: SIZE-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#estimates render at 1-2 significant figures with no decimals"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a source with no audio stream drops the 192k estimate term"
        status: pass
    human_judgment: false
  - id: D3
    description: "Honest degradation: a 15 MiB source degrades only the exceeding rows to `larger than source`; a 1 KiB source degrades all three; `N/A` duration and probe hard-fail both render uniform `Best quality`/`Balanced`/`Smallest file` rows without aborting"
    requirement: SIZE-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#larger than source degrades per row, not per menu"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a tiny source degrades all three rows to larger than source"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an N/A duration falls back to qualitative rows and still transcodes"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a failed probe degrades to qualitative rows without aborting"
        status: pass
    human_judgment: false
  - id: D4
    description: "The pick's subtext is stripped at the first tab and re-validated `high|medium|low` inside `select_quality` — a `low\\t…` pick yields `-crf 28` + `in-1080p-low.mp4`, a `bogus\\tjunk` pick fails `Invalid video quality` before the notification, and an empty pick (Esc) aborts silently"
    requirement: QUAL-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a menu pick strips the subtext before tier matching"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a foreign-label menu pick is rejected before the notification"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an empty menu pick aborts before the notification"
        status: pass
    human_judgment: false
  - id: D5
    description: "Probe/menu scoping: the 4-positional path and picture inputs spawn zero `menu-select:`/`ffprobe:` calls; gif rows carry `15/10/5 fps` subtexts with zero `ffprobe:` lines; the `avi` unknown-format orphan (all-qualitative prompt then `Invalid video format`) is pinned, not fixed"
    requirement: SIZE-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a four-positional run never prompts or probes"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#gif rows carry fps subtexts and never probe the input"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a picture run never prompts for quality or probes"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#an unknown format prompts with qualitative rows then fails Invalid video format"
        status: pass
    human_judgment: false
  - id: D6
    description: "Running-UI rendering and dogfood calibration — cursor on `medium`, subtexts un-elided at ~300px card width, uniform `detailRowHeight`; `~N MB` estimates within ~2× of actual output on real clips; Nautilus per-file prompt; partial-positionals two-prompt chain"
    requirement: QUAL-01
    verification: []
    human_judgment: true
    rationale: "Rendering, elision, real-encode calibration, and the Nautilus/session flows are running-UI properties per agents/skills/visual-verification.md; the dev shell loads the packaged /usr/share/omarchy tree, so this checklist is recorded for end-of-phase UAT, not executed (STATE.md:96 precedent)"

# Metrics
duration: 22 min
completed: 2026-09-15
status: complete
---

# Phase 6 Plan 1: Interactive quality prompt + size estimates Summary

**`omarchy transcode` now fires a `Select quality` menu after format+resolution on the interactive video path — `CRF N · ~N MB` estimate rows for mp4 (ffprobe duration × locked bitrate midpoints + audio term, 1–2 sig figs), `N fps` rows for gif, `medium` pre-highlighted via Phase-4 `--default-index`, with per-row `larger than source` degrade, all-qualitative probe-failure fallback, and strip+re-validation of the pick before the notification boundary.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-09-15T21:59:43Z
- **Completed:** 2026-09-15T22:21:21Z
- **Tasks:** 3
- **Files modified:** 3 (`bin/omarchy-transcode`, `test/shell.d/transcode-quality-test.sh`, `test/shell.d/menu-select-test.sh`)

## Accomplishments

- Six new helpers (`video_duration`, `video_audio_kbps`, `quality_token`, `quality_kbps`, `estimate_label`, `select_quality`) between `copy_to_clipboard` and `main` — outside upstream PR #6698's insertion zone — plus the 3-line `[[ $type == "video" && -z $quality ]]` prompt block in `main()` (D-00a..i, D-01..D-04 all implemented as locked).
- mp4 rows render `CRF N · ~N MB` via awk `dur × (kbps + audio) × 125` at 1–2 sig figs (verified: 60 s/1080p → `~41`/`~23`/`~11 MB`; 157 s → `~110`/`~60`/`~30 MB`; audio-less source → `~39`/`~21`/`~10 MB`); a tier estimate exceeding `stat -c %s` renders `larger than source` on that row only.
- Probe `N/A` or hard failure degrades all three rows to `Best quality`/`Balanced`/`Smallest file` without aborting; gif rows carry `15`/`10`/`5 fps` and never spawn ffprobe; pictures and 4-positional callers see zero menu/probe calls.
- The `label\tsubtext` pick is stripped at the first tab (`${selection%%$'\t'*}`) and re-validated `high|medium|low` inside `select_quality` — a foreign label dies with `Invalid video quality` before the notification (T-06-02); an empty pick (Esc) aborts silently, matching sibling prompts.
- Test harness extended to 43 assertions: dual-mode `omarchy-menu-select` stub (FAKE_PICK unset = tripwire / set = answer, empty = Esc), arg-dispatched `ffprobe` stub (` stream=codec_type ` token → audio arm, else duration arm honoring FAKE_DURATION/FAKE_PROBE_RC), `truncate -s` sized fixtures — every Phase-5 row still green, six of them now doubling as interactive-path proofs via `FAKE_PICK=$'medium\tBalanced'`.
- `usage()` now names the quality step; `./test/cli` exit 0; `./test/shell` shows only the 7 documented pre-existing environmental failures.

## Task Commits

Each task ran to its verified gate; per the plan's mandate (and Phase-4/5 precedent) the feature lands as ONE atomic commit — "Do not commit" on tasks 1–2, script + test together in task 3:

1. **Tasks 1–2 (tracer slice + matrix expansion)** — `11083223` (feat): `bin/omarchy-transcode` + `test/shell.d/transcode-quality-test.sh`, 392 insertions. Tracer feedback gate: re-ran the automated `<verify>` set end-to-end before expansion — all green (interactive + end-of-phase mode, automated-only verify → no checkpoint).
2. **Deviation fix (stale Phase-4 pin)** — `fbe56e4c` (test): `test/shell.d/menu-select-test.sh` caller sweep re-scoped to omarchy-transcode.
3. **Task 3 (usage touch + sweep + atomic commit)** — included in `11083223` (usage() line) and verified by the sweep.

**Plan metadata:** `docs(06-01)` commit follows this file (SUMMARY + STATE + ROADMAP + REQUIREMENTS).

## Files Created/Modified

- `bin/omarchy-transcode` — six helpers (:162–:285), the `main()` quality-prompt block (:365–:367), usage() quality mention (:17)
- `test/shell.d/transcode-quality-test.sh` — dual-mode menu-select stub, arg-dispatched ffprobe stub, `truncate -s 120M` fixture, six `FAKE_PICK` prefixes on unset-quality rows, 14 new assertion blocks
- `test/shell.d/menu-select-test.sh` — `--default-index` caller sweep re-scoped (deviation, below)

## Decisions Made

- **Single atomic commit for script + harness** (plan-mandated prohibition: "Never split the change across multiple commits"); the menu-select pin fix rides separately as `test(06-01)` so the feat commit's `--stat` shows exactly the two `files_modified` paths and every commit is green.
- **Audio-aware estimate adopted** (discretion item): `video_audio_kbps` tests the substitution's exit status — a *successful* probe reporting no `audio` line returns 0, probe *failure* keeps 192 (conservative over-estimate).
- **gif never probes** (pinned discretion): `select_quality` only calls ffprobe/stat when `format == "mp4"`.
- **Upscale flag deferred**; helpers below `copy_to_clipboard`; awk math; fallback wording pinned (`larger than source`, `Best quality`/`Balanced`/`Smallest file`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Re-scoped the Phase-4 `--default-index` caller pin in `menu-select-test.sh`**
- **Found during:** Task 3 (suite sweep) — `./test/shell` reported 8 failures: the 7 documented environmental files plus `test/shell.d/menu-select-test.sh` (`not ok - no existing caller passes --default-index yet`).
- **Issue:** The Phase-4 sweep pinned "no shipped caller passes `--default-index`" — its own comment says "Phase 6 adopts it first." This plan is that adoption, so the pin's invariant is now intentionally false and the acceptance criterion ("no failures beyond the 7") could not be met with the stale pin.
- **Fix:** Re-scoped the sweep to exclude `bin/omarchy-transcode` and re-worded the assertion to "omarchy-transcode is the only caller passing --default-index" — preserving the tripwire's protective purpose (any *other* new caller still fails).
- **Files modified:** `test/shell.d/menu-select-test.sh`
- **Verification:** `bash test/shell.d/menu-select-test.sh` → 11/11 ok; full `./test/shell` re-run shows exactly the 7 documented environmental failures.
- **Committed in:** `fbe56e4c` (separate `test(06-01)` commit so the atomic feat commit keeps exactly the two `files_modified` paths)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Necessary for suite green; the pin was designed to be updated by this phase. No scope creep — no source contract changed.

## Issues Encountered

- `menu-select-test.sh` stale pin (handled as the deviation above). No other issues — all pinned assertion values (`~41`/`~23`/`~11`, `~110`/`~60`/`~30`, `~39`/`~21`/`~10`, per-row/all `larger than source`) verified live against the real script.

## UAT Checklist (recorded, not executed — dev shell loads the packaged `/usr/share/omarchy` tree per STATE.md)

- [ ] (a) Open the quality menu in the running UI: cursor sits on `medium`, subtexts un-elided at ~300px card width, all three rows same `detailRowHeight` (agents/skills/visual-verification.md; `wtype` Enter should pick medium).
- [ ] (b) Estimate-vs-actual dogfood: transcode 2–3 varied clips, compare the shown `~N MB` against real output size (±2× CRF variance expected — the check is that estimates land inside it, not that they're exact).
- [ ] (c) Nautilus multi-select: 2+ videos → Transcode → confirm the quality prompt appears per file (locked behavior — verify understood, not broken).
- [ ] (d) Partial-positionals chain: `omarchy transcode <clip> mp4` prompts resolution THEN quality (D-00i — the two-prompt chain can't be driven by the single-pick stub).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 6 complete: the quality prompt + estimate contract is proven end-to-end through the stub harness; the `avi` unknown-format orphan is pinned (documented, not fixed).
- Phase 7 (completion-notification actual size + docs sweep) can consume: `select_quality`'s estimate math, the `numfmt --to=iec` note from RESEARCH §2, and `manual/` + `capture.md` doc touches deliberately left untouched here.
- Blockers/concerns: none new; the 7 pre-existing environmental `./test/shell` failures are unchanged.

## Self-Check: PASSED

- `bin/omarchy-transcode`, `test/shell.d/transcode-quality-test.sh`, `test/shell.d/menu-select-test.sh` — all present on disk and committed.
- Commits verified: `fbe56e4c` (test pin), `11083223` (feat — exactly the two `files_modified` paths, no deletions).
- `bash test/shell.d/transcode-quality-test.sh` → 43/43 `ok -`; `bash -n bin/omarchy-transcode` clean; `./test/cli` exit 0; `./test/shell` → only the 7 documented environmental failures.

---
*Phase: 06-interactive-quality-prompt-size-estimates*
*Completed: 2026-09-15*
