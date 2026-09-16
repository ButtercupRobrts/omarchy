---
phase: 07-completion-size-notification-docs
plan: 01
subsystem: cli
tags: [bash, stat, awk, notification-send, stub-e2e, transcode, docs]

# Dependency graph
requires:
  - phase: 05-non-interactive-quality-in-omarchy-transcode
    provides: "done-notification call sites, `output_path` dedupe resolved pre-notification, and the stub-e2e harness (`notification:` argv capture, per-invocation FAKE_* knobs)"
  - phase: 06-interactive-quality-prompt-size-estimates
    provides: "`select_quality`/`estimate_label` helpers in the PR #6698-safe slot, the `~N MB` MiB-scale estimate convention the actual size matches, and the probe-guard idiom (`|| true` + `^[0-9]+$` gate)"
provides:
  - "SIZE-02: both done-notification arms send `Saved and copied to clipboard${size:+ ($size)}.` — `Saved and copied to clipboard (38 MB).` on the happy path, measured by `stat -c %s` of the deduped `$output` after `copy_to_clipboard`"
  - "`output_size_label()` between `select_quality` and `main` — `stat` → `^[0-9]+$` regex gate → awk `%.0f MB` on the MiB scale; failure returns 1 and the body degrades to the plain sentence, never lies, never aborts under `set -euo pipefail`"
  - "Encoder-stub opt-in knobs `FAKE_OUT_BYTES` (`truncate -s` the `${!#}` output path) and `FAKE_ENCODE_RC` (stub exits that status); unset is byte-identical to the old never-create-output behavior"
  - "WR-01 resolved: `estimate_label` prints `~%.0f MB` — sub-10 MiB estimates round instead of flooring (`1.9` → `~2 MB`), pinned `~6`/`~4`/`~2 MB` at dur=18/720p"
  - "IN-06 resolved: `notify_line`/`ffmpeg_line` empty-grep guard — `|| true` on both assignments plus a non-empty check before the arithmetic compare, so a missing line fails descriptively instead of false-passing on 0"
  - "`manual/12-screenshots-recording.md` Transcoding section now names the video quality step, the per-choice rough estimate, and the actual size in the completion notification"
affects: [verify-work, uat]

# Actuals
actuals:
  tasks: 3
  commits: 3
  plan_head_before: 7da33934

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Actual-size capture: `bytes=$(stat -c %s \"$1\" 2>/dev/null || true)` → `[[ $bytes =~ ^[0-9]+$ ]] || return 1` → `awk -v b 'BEGIN{printf \"%.0f MB\", b/1048576}'` — the two-step form is required because a `stat|numfmt` pipeline aborts under pipefail when stat fails"
    - "Conditional notification body suffix via `${size:+ ($size)}` — one expansion, no if tree, degrade-to-plain-body on helper failure"
    - "Opt-in stub output knob `FAKE_OUT_BYTES` + `truncate -s \"${!#}\"` so the real stat+awk chain is exercised; rows that set it own the file and `rm -f` it (fixture-ownership convention)"
    - "`FAKE_ENCODE_RC` stub exit knob pins the ordering contract: encode failure → zero `Transcoded to` notification lines"

key-files:
  created: []
  modified:
    - bin/omarchy-transcode
    - test/shell.d/transcode-quality-test.sh
    - manual/12-screenshots-recording.md

key-decisions:
  - "MiB-scale `N MB` label locked for the actual size (research §7b option a): matches the ROADMAP `38 MB` example verbatim and keeps estimate→actual comparison same-scale; no GB rollover (`1400 MB`); numfmt verified incapable of the spaced shape — awk is the tool"
  - "Three atomic commits as planned: `test(07)` IN-06 guard first (test file only, committed before any other test edit so the staged diff is exactly that hunk), `feat(07-01)` script+test+manual, `fix(07)` WR-01 rounding + pin"
  - "Per-arm minimal diff in main()'s tail (inside the PR #6698 conflict zone): `size=$(output_size_label \"$output\" || true)` inserted between `copy_to_clipboard` and each done send; the start notification and notification count are byte-unchanged"
  - "Docs criterion satisfied by verification, not churn: `docs/` has zero transcode mentions, `# omarchy:*`/`usage()`/`capture.md`/`bin/omarchy` already in sync — `manual/12` :70-72 was the only stale surface and the only doc edited"

patterns-established:
  - "Honesty-matrix test rows: happy-path size pin (per arm), degrade-never-lies pin (no ` MB)` on a missing output), encode-failure pin (zero `Transcoded to` lines), deduped-path pin (stat measures `-2`, not the collision fixture)"

requirements-completed: [SIZE-02]

coverage:
  - id: T-07-size-video
    description: "Video done-notification body carries the real output size — `FAKE_OUT_BYTES=39845888` (38.00 MiB) renders `Saved and copied to clipboard (38 MB).` on the `Transcoded to 1080p mp4` line"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#the video done notification reports the output size"
        status: pass
    human_judgment: false
  - id: T-07-size-picture
    description: "Picture arm carries the size via the same code path — `Transcoded to medium jpg` notification contains `(38 MB)`"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#the picture done notification reports the output size"
        status: pass
    human_judgment: false
  - id: T-07-size-gif
    description: "gif arm shares main()'s video tail — `Transcoded to 720p gif` notification contains `(38 MB)`"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#the gif done notification reports the output size"
        status: pass
    human_judgment: false
  - id: T-07-degrade
    description: "No `FAKE_OUT_BYTES` → stub creates nothing → stat fails inside `output_size_label` → body degrades to `Saved and copied to clipboard.` with no ` MB)` parenthetical and the run still exits 0"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a missing output degrades to the plain body without lying"
        status: pass
    human_judgment: false
  - id: T-07-failure
    description: "`FAKE_ENCODE_RC=1` → run exits non-zero, the `Transcoding video` start notification is recorded (pre-existing orphan, pinned), and zero `Transcoded to` lines appear — the notification can never claim a size for an output that does not exist"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a failed encode sends zero done notifications"
        status: pass
    human_judgment: false
  - id: T-07-dedupe-size
    description: "Pre-created `in-1080p.mp4` + `FAKE_OUT_BYTES` dedupes to `in-1080p-2.mp4` (`out=` pinned) and the notification still reports `(38 MB)` — stat measured the file actually written"
    requirement: SIZE-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#a deduped output reports the size of the file actually written"
        status: pass
    human_judgment: false
  - id: T-07-wr01
    description: "Sub-10 MiB estimates round instead of flooring — dur=18/720p pins `~6`/`~4`/`~2 MB` (unfixed `%d` renders `~5`/`~3`/`~1`); all nine pre-existing ≥10 MiB pins unchanged"
    requirement: SIZE-01 (advisory WR-01)
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#sub-10 MiB estimates round instead of flooring"
        status: pass
    human_judgment: false
  - id: T-07-docs
    description: "Docs consistency — `manual/12` names the quality step + actual-size notification; `docs/` grep-verified zero transcode mentions; `# omarchy:*`/`usage()`/`capture.md`/`bin/omarchy` verified in sync, untouched; `test/cli` metadata shape green"
    requirement: ROADMAP SC2
    verification:
      - kind: suite
        ref: "./test/cli (exit 0)"
        status: pass
      - kind: e2e
        ref: "grep -rli transcode docs/ → empty; grep -n estimate manual/12 → :70,:72"
        status: pass
    human_judgment: false
  - id: T-07-uat
    description: "Running-UI rendering and dogfood calibration — done toast shows `N MB` legibly with the glyph intact; `~N MB` menu estimate vs reported `N MB` on one real clip; `manual/12` paragraph reads naturally to an end user"
    requirement: SIZE-02
    verification: []
    human_judgment: true
    rationale: "Toast rendering and real-encode calibration are running-UI properties per agents/skills/visual-verification.md; the dev shell loads the packaged /usr/share/omarchy tree — recorded for end-of-phase UAT, not executed (STATE.md precedent)"

# Metrics
completed: 2026-09-16
status: complete
---

# Phase 7 Plan 1: Completion-size notification + docs Summary

**The `omarchy transcode` completion notification now reports the actual output file size — `Saved and copied to clipboard (38 MB).` — on the video (mp4 and gif) AND picture arms, measured by a new `output_size_label()` helper (`stat -c %s` → `^[0-9]+$` gate → awk `%.0f MB`, MiB scale) wired in via `${size:+ ($size)}` so a stat failure degrades to the plain body instead of lying or aborting; the Phase-6 WR-01 and IN-06 advisories folded in as their own `fix(07)`/`test(07)` commits, and `manual/12` was the only doc surface needing a sync.**

## Performance

- **Completed:** 2026-09-16
- **Tasks:** 3
- **Files modified:** 3 (`bin/omarchy-transcode`, `test/shell.d/transcode-quality-test.sh`, `manual/12-screenshots-recording.md`)

## Accomplishments

- `output_size_label()` added between `select_quality` and `main` — inside the proven PR #6698-safe helper slot — as `stat -c %s "$1" || true` → digit-only regex gate → awk `printf "%.0f MB"` on `/1048576`; `size` added to main()'s `local` line.
- Both done-notification arms now compute `size=$(output_size_label "$output" || true)` between `copy_to_clipboard` and the send call, with body `Saved and copied to clipboard${size:+ ($size)}.` — PUA glyph bytes (`EF 80 BD` video / `EF 80 BE` picture) and the `Transcoding video…` start notification byte-unchanged; notification count unchanged.
- Encoder stubs gained opt-in `FAKE_OUT_BYTES` (`truncate -s` the `${!#}` output path — correct for both ffmpeg and magick argv shapes) and `FAKE_ENCODE_RC` knobs; unset is byte-identical to the old never-create-output behavior so dedupe rows don't self-collide.
- Harness extended to 51 assertions: size pins on all three arms (mp4, picture, gif), degrade-never-lies, encode-failure-zero-`Transcoded`-lines, deduped-`-2`-reports-its-own-size, and the WR-01 `~6`/`~4`/`~2 MB` rounding pin at dur=18/720p — every pre-existing row still green.
- IN-06 false-pass fixed: `|| true` on the `notify_line`/`ffmpeg_line` grep assignments plus a `[[ -n … && -n … ]]` guard before the arithmetic compare — a missing line now fails descriptively instead of reading empty as 0.
- WR-01 fixed: `estimate_label`'s `printf "~%d MB"` → `"~%.0f MB"` — sub-10 MiB estimates round (`1.9` → `~2 MB`) instead of flooring; all nine existing pins are ≥10 so zero existing rows changed.
- `manual/12-screenshots-recording.md` Transcoding paragraph now names the video quality step with its rough per-choice estimate, and reports that the finish notification shows the actual size — user-voiced, no CRF jargon; every other doc surface verified in sync and untouched (`grep -rli transcode docs/` empty, `./test/cli` exit 0).

## Task Commits

Three atomic commits in the plan-mandated order, each with a clean `--stat`:

1. **`4e0e1f89` — `test(07)`**: IN-06 guard, `test/shell.d/transcode-quality-test.sh` only (committed FIRST, before any other test edit, so the staged diff was exactly that hunk).
2. **`22c28a7d` — `feat(07-01)`**: exactly the three `files_modified` paths — `bin/omarchy-transcode` (+17/−5: helper, `size` local, both arms), `test/shell.d/transcode-quality-test.sh` (stub knobs, comment sync, 7 new assertion blocks), `manual/12-screenshots-recording.md` (paragraph sync).
3. **`8d52171b` — `fix(07)`**: `estimate_label` `~%d`→`~%.0f` (one character) + the dur=18/720p rounding pin — exactly two files.

## Files Created/Modified

- `bin/omarchy-transcode` — `output_size_label()` :287-294; `size` in main()'s locals :298; `size=$(output_size_label "$output" || true)` + `${size:+ ($size)}` body at :384-385 (video) and :389-390 (picture); `~%.0f MB` at :238
- `test/shell.d/transcode-quality-test.sh` — IN-06 guard :192-198; `FAKE_OUT_BYTES`/`FAKE_ENCODE_RC` stub knobs :43-46 + comment updates :26-33/:118-122; new assertion blocks at :574-652
- `manual/12-screenshots-recording.md` — Transcoding paragraph :70-72 (quality step + rough estimate + actual-size notification)

## Decisions Made

- **MiB-scale `38 MB` label** (research §7b option a, locked by the plan): same scale as the `~N MB` estimates, matches the ROADMAP example; resolves the MB-vs-MiB advisory by consistency.
- **Per-arm minimal diff** in the PR #6698 conflict zone over hoisting a shared body — the restructure was the bigger-conflict alternative.
- **IN-06 guard committed alone first** so `git add test/…` staged exactly that hunk (load-bearing commit-order note honored).

## Deviations from Plan

None — all edits, knobs, rows, commit scopes, and ordering landed exactly as specified.

## Issues Encountered

None. All pinned values (`(38 MB)` from `FAKE_OUT_BYTES=39845888`; `~6`/`~4`/`~2 MB` at dur=18/720p) verified live through the real stat+awk chain.

## Verification Results

- `bash test/shell.d/transcode-quality-test.sh` → **51/51 `ok -`, zero `not ok`**
- `bash -n bin/omarchy-transcode` → exit 0
- `./test/cli` → exit 0, zero `not ok`
- `./test/shell` → **7 of 240 files failed — exactly the documented pre-existing environmental set** (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths); no new failures
- `git log --oneline -3` → `fix(07)`, `feat(07-01)`, `test(07)` in order; each `--stat` clean
- `grep -F 'size:+ ($size)' bin/omarchy-transcode` → 2 matches; `grep -n 'output_size_label'` → :289 def, :384/:389 calls; `grep -n '~%d MB'` → no match

## UAT Checklist (recorded, not executed — dev shell loads the packaged `/usr/share/omarchy` tree per STATE.md)

- [ ] (a) Transcode a real video and confirm the done toast shows `N MB` legibly with the glyph intact, no truncation (agents/skills/visual-verification.md).
- [ ] (b) Estimate→actual calibration: compare the `~N MB` shown in the quality menu against the reported `N MB` on one real clip (±2× CRF variance expected).
- [ ] (c) Read the edited `manual/12` paragraph aloud for end-user tone.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 7 complete: SIZE-02 proven end-to-end through the stub harness; both Phase-6 advisories (WR-01, IN-06) resolved; the MB-vs-MiB terminology advisory resolved by decision (MiB scale under the `MB` label, both estimate and actual).
- The `avi` unknown-format orphan and the `Transcoding`-on-failure start-notification orphan remain pinned-as-is (pre-existing, out of scope).
- Blockers/concerns: none new; the 7 pre-existing environmental `./test/shell` failures are unchanged.

## Self-Check: PASSED

- `bin/omarchy-transcode`, `test/shell.d/transcode-quality-test.sh`, `manual/12-screenshots-recording.md` — all committed; no stray working-tree changes (`git status` clean).
- Commits verified: `4e0e1f89` test(07) (one file), `22c28a7d` feat(07-01) (exactly the three files_modified), `8d52171b` fix(07) (two files).
- `bash test/shell.d/transcode-quality-test.sh` → 51/51 `ok -`; `bash -n` clean; `./test/cli` exit 0; `./test/shell` → only the 7 documented environmental failures.

---
*Phase: 07-completion-size-notification-docs*
*Completed: 2026-09-16*
