---
phase: 05-non-interactive-quality-in-omarchy-transcode
plan: 01
subsystem: cli
tags: [bash, ffmpeg, imagemagick, stub-e2e, cli-args, transcode]

# Dependency graph
requires: []
provides:
  - "`omarchy transcode INPUT FORMAT RESOLUTION [QUALITY]` — optional 4th positional ∈ high|medium|low selecting locked tiers (x264 crf 18/23/28, x265 crf 20/24/28, gif fps 15/10/5); medium/omitted byte-identical to prior argv"
  - "`output_path` quality suffix (stem-<res>-<quality>) + `[[ -e || -L ]]` dedupe to -2/-3 resolved before the Transcoding notification; no -y/-n anywhere"
  - "`main()` whitelist validation: pictures reject a 4th positional and non-tier values fail with `Invalid video quality:` — both pre-notification"
  - "Empty `quality` stays empty in main() (Phase 6 `-z` prompt signal intact); `${5:-medium}` owns the default inside `transcode_video`"
  - "test/shell.d/transcode-quality-test.sh — stub-bin e2e covering the whole non-interactive contract (28 assertions)"
affects: [phase-6-quality-prompt, phase-7, verify-work, uat]

# Actuals (#2632)
actuals:
  tokens: 7190
  tasks: 3
  commits: 1
  plan_head_before: bf7e8927e97ff0f3b5f5278ac35049c4b3c71f19

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tier tables as `case \"$quality\"` → variable mapping (crf_x264/crf_x265/gif_fps) between the resolution case and the format dispatch — medium arm holds the pre-change literals verbatim so byte-identity is reviewable by eye"
    - "Stub-encoder e2e: ffmpeg/magick stubs append `%q`-joined argv + an `out=%q` line to $CALLS and deliberately never create the output file, so dedupe rows use row-owned touch/ln -s fixtures rm -f'd after asserting"
    - "Exit-1 menu tripwires (omarchy-menu-file/omarchy-menu-select) make every green run a non-interactivity proof"

key-files:
  created:
    - test/shell.d/transcode-quality-test.sh
  modified:
    - bin/omarchy-transcode
    - default/agents/skills/omarchy/capture.md
    - manual/12-screenshots-recording.md

key-decisions:
  - "One atomic commit carries script + test + both docs (plan-mandated, Phase-4 precedent — the change is one reviewable, independently revertible unit; a candidate upstream PR)"
  - "Dedupe applies to pictures too — output_path is shared, so magick's silent-overwrite is upgraded to the same deliberate collision policy (SAFE-01 uniform; RESEARCH §1c)"
  - "Encoder stubs never create the output file (plan-locked spec): realpath tolerates a missing final component, and a stub touch would leak fixtures into shared $TMPDIR making identical-output rows self-collide"

patterns-established:
  - "Dedupe loop `while [[ -e $candidate || -L $candidate ]]` with `(( n += 1 ))` — the -L arm is load-bearing against symlink write-through; counter appends to the whole computed name"
  - "Byte-identity asserted three ways: explicit-medium vs omitted cmp, each vs a `%q`-built literal expected line (diff -u on fail) — catches shared regressions and path divergence"

requirements-completed: [QUAL-02, QUAL-03, SAFE-01]

coverage:
  - id: D1
    description: "`omarchy transcode in.mov mp4 1080p medium` and the omitted form invoke ffmpeg with byte-identical argv equal to the literal `-preset fast -crf 23 -c:a aac -b:a 192k -movflags +faststart` line and write `in-1080p.mp4`"
    requirement: QUAL-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#explicit medium and omitted quality produce identical ffmpeg argv"
        status: pass
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#medium quality produces the literal default ffmpeg argv"
        status: pass
    human_judgment: false
  - id: D2
    description: "high/low select the locked tiers — x264 -crf 18/28, x265 (4k) -crf 20/24/28, gif fps=15/10/5 — and produce `-high`/`-low` suffixed outputs"
    requirement: QUAL-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#tier rows (x264 high/low, 4k x265 20/24/28, gif fps 15/10/5, suffix names)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A 4th positional on a picture exits non-zero with an Invalid stderr line and an empty call log — before any notification, ffmpeg, magick, or menu; `img.png jpg low` still reads low as resolution (-resize 1080x>)"
    requirement: QUAL-03
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#picture rejection rows + positive control"
        status: pass
    human_judgment: false
  - id: D4
    description: "An existing output dedupes to -2/-3 (incl. `in-1080p-low-2.mp4` and the dangling-symlink -L case) resolved before the Transcoding notification; no overwrite flag ever reaches ffmpeg"
    requirement: SAFE-01
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#dedupe chain, symlink, picture dedupe, notification ordering, no-overwrite-flag rows"
        status: pass
    human_judgment: false
  - id: D5
    description: "Empty quality behaves as omitted (medium argv, unsuffixed name); whitespace and other non-tier values exit non-zero with `Invalid video quality:` naming the valid set"
    requirement: QUAL-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#empty/whitespace/bogus quality rows"
        status: pass
    human_judgment: false
  - id: D6
    description: "A 4th positional after `--` reaches positional[3] identically to the bare form; spaced filenames survive as single argv elements end-to-end"
    requirement: QUAL-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#-- passthrough and spaced-filename rows"
        status: pass
    human_judgment: false
  - id: D7
    description: "usage() shows [quality] and a Videos-only `high, medium, low` Qualities block; `# omarchy:args=` keeps every token bracketed so bare `omarchy transcode` stays interactive"
    requirement: QUAL-02
    verification:
      - kind: e2e
        ref: "test/shell.d/transcode-quality-test.sh#usage documents [quality] and the video tiers"
        status: pass
      - kind: other
        ref: "./test/cli (metadata lint)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Detached/keybind re-run of an identical transcode produces the -2 output with no overwrite prompt and no hang; optional real-encode smoke produces a playable file"
    requirement: SAFE-01
    verification: []
    human_judgment: true
    rationale: "No-tty no-hang is a property of the real launch environment (Util.execDetached); the stub proves the path is collision-free before ffmpeg runs but cannot exercise a real detached launch — recorded as UAT checklist below"

# Metrics
duration: 14min
completed: 2026-09-15
status: complete
---

# Phase 5 Plan 01: Non-interactive quality in `omarchy-transcode` Summary

**Optional `[quality]` 4th positional selects locked CRF/fps tiers (x264 18/23/28, x265 20/24/28, gif 15/10/5) with medium byte-identical, `-high`/`-low` filename suffixes, `[[ -e || -L ]]` dedupe to `-2`/`-3` before the Transcoding notification, and pre-notification rejection on pictures and non-tier values**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-09-15T14:41:12Z
- **Completed:** 2026-09-15T14:54:28Z
- **Tasks:** 3
- **Files modified:** 4 (1 created)

## Accomplishments

- `bin/omarchy-transcode` parses `quality="${positional[3]:-}"`, validates it in `main()` after `media_type` resolves (pictures → `Invalid argument: quality applies to videos only`; non-tiers → `Invalid video quality: <v> (expected high, medium, or low)`) — both fail before the "Transcoding video…" notification, so failure states are never orphaned. `quality` stays empty when omitted; `transcode_video`'s `${5:-medium}` owns the default so Phase 6's `-z` prompt signal survives.
- `output_path()` gained the 4th `quality` param: `stem-<res>-<quality>` suffix for non-default tiers and a `while [[ -e || -L ]]` dedupe loop producing `-2`/`-3` — covering dangling symlinks (T-05-01) and, because the function is shared, upgrading pictures from magick's silent-overwrite to the same deliberate policy. No `-y`/`-n` is ever passed to ffmpeg — dedupe is the whole collision policy (D-01), so detached/keybind launches can never hit ffmpeg's stdin overwrite prompt.
- `transcode_video()` maps `high|medium|low` → `crf_x264`/`crf_x265`/`gif_fps` in a `case` between the resolution and format dispatches; the medium arm holds today's literals (23/24/10) verbatim, presets/audio/`+faststart`/palette pipeline untouched (D-03, D-04).
- New `test/shell.d/transcode-quality-test.sh` (28 assertions): PATH-shadowing stubs for `file`, `ffmpeg`, `magick`, `wl-copy`, `omarchy-notification-send` plus exit-1 menu tripwires; `%q`-joined argv recording; byte-identical medium proven both directions against each other and against a literal expected line; the full dedupe surface including the dangling-symlink row; picture rejection with an empty call log; `--` passthrough, spaced filenames, `--help`, and the no-overwrite-flag pin.
- Metadata/usage/docs synced: `# omarchy:args=`/`usage()` gained bracketed `[quality]` (arg-optional preserved → interactive picker intact), a Videos-only `Qualities:` block, a `…mp4 1080p low` example, the `capture.md` signature line, and one user-voiced manual sentence on the quality word and `-high`/`-low` filenames.

## Task Commits

The plan mandates one atomic commit for all `files_modified` (Phase-4 precedent — script + test + docs are one reviewable, independently revertible unit), so tasks 1–3 executed and verified sequentially and landed together:

1. **Tasks 1–3: quality arg parse/validate + tier tables + suffix/dedupe + stub e2e + docs** - `59e97b01` (feat, 4 files)

**Plan metadata:** pending — committed after this file via `gsd_run query commit`

## Files Created/Modified

- `bin/omarchy-transcode` — `[quality]` metadata + usage + `Qualities:` block; `output_path` 4th param, suffix rule, `[[ -e || -L ]]` dedupe; `transcode_video` 5th param + tier `case` + interpolated CRF/fps; `main()` positional extract, pre-notification validation block, updated call sites
- `test/shell.d/transcode-quality-test.sh` — new stub-bin e2e (auto-discovered by `test/shell`; name avoids add/add collision with upstream PR #6698's `transcode-test.sh`)
- `default/agents/skills/omarchy/capture.md` — signature line gains `[quality]`
- `manual/12-screenshots-recording.md` — one user-voiced sentence on the quality word and `demo-1080p-high.mp4`/`demo-1080p-low.mp4` naming

## Decisions Made

- All locked decisions implemented verbatim — D-00a (tier tables), D-00b (medium byte-identical, asserted both directions + literal), D-00c (picture rejection pre-notification), D-00d (suffix naming), D-01 (dedupe-only collision policy, resolved pre-notification), D-02 (strict whitelist, no aliases/CRF), D-03 (CRF/fps only), D-04 (gif low = fps=5).
- Discretion used per plan: picture-rejection wording `Invalid argument: quality applies to videos only`; dedupe loop placed inside `output_path` (shared → uniform policy, pictures dedupe too — deliberate, RESEARCH §1c).
- Encoder stubs deliberately never create the output file (plan action 9 — deviates from RESEARCH §2's `touch` sketch on purpose): `realpath` exits 0 on a missing final component, and an unconditional stub `touch` would leak files into shared `$TMPDIR`, making the byte-identity pair and the empty-quality row self-collide. Collision fixtures are row-owned (`touch`/`ln -s` + immediate `rm -f`).

## Deviations from Plan

None - plan executed exactly as written. (The no-touch stub behavior is a plan-mandated spec, not an executor deviation.)

## Issues Encountered

- `printf '%q'` escapes `,` and `>` inside the recorded argv line (`fps=15\,`, `1080x\>`), so the gif-fps and picture-resize greps pin the escaped recorded forms. Fixed inline during task 2; verified green.
- No other issues — all plan line references matched the working tree.

## Threat Model Status

| Threat | Disposition | Status |
|--------|-------------|--------|
| T-05-01 dangling-symlink write-through | mitigate | Implemented — `[[ -e \|\| -L ]]` in `output_path`; pinned by the `ln -s /nonexistent` e2e row |
| T-05-02 quality → filename/argv injection | mitigate | Implemented — `high\|medium\|low` whitelist in `main()` before `output_path`; invalid/whitespace rows prove rejection |
| T-05-03 ffmpeg stdin overwrite prompt on detached launch | mitigate | Implemented — dedupe removes the only interactive surface; no `-y`/`-n`; cumulative-argv pin proves no overwrite flag |
| T-05-04 TOCTOU between check and open | accept | Residual degrades to today's prompt/refuse, never silent clobber |
| T-05-05 `file` MIME → glob | accept | Unchanged surface; stubbed in tests |
| T-05-06 `format` → extension | accept | Pre-existing, unchanged |

No new trust-boundary surface introduced beyond the plan's register — no Threat Flags.

## Verification Results

- `bash -n bin/omarchy-transcode` — exit 0
- `bash test/shell.d/transcode-quality-test.sh` — 28/28 `ok -` assertions, exit 0 (rerun after task-2 expansion; tracer gate: verified end-to-end before expansion, `end-of-phase` mode)
- `grep -c 'Invalid video quality' bin/omarchy-transcode` — exactly 2 (main() arm + transcode_video `*)` arm)
- `./test/cli` — exit 0 (metadata lint green; `[quality]` lint-neutral, args stays bracketed/non-empty)
- `./test/shell` — 7 of 240 files failed, all pre-existing environmental (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths — reproducing at base commit per STATE.md:92); `transcode-quality-test.sh` ran and passed inside the suite

## User Setup Required

None - no external service configuration required.

## Pending UAT (NON-GATING — recorded for end-of-phase, not executed)

The agent cannot exercise a real keybind/detached launch; the stub proves the collision-free path, not the launch environment:

1. **Detached-launch (SAFE-01):** transcode the same video at the same settings twice via the actual keybind/menu trigger (`Super + Ctrl + .`) — the second run produces the `-2` output with no overwrite prompt and no hang.
2. **Real-encode smoke (optional, QUAL-02):** `omarchy transcode <clip> mp4 720p high` produces a playable file — stubbing proves argv, not encoder acceptance.
3. **Nautilus regression:** `transcode.py` is untouched by design — path-only invocation still reaches the interactive flow unchanged until Phase 6.

## Next Phase Readiness

- Phase 6 contract intact: `quality` stays empty in `main()` when omitted — the `-z $quality` prompt trigger and the locked tier tables are ready to consume.
- `./test/cli` + stub e2e green; the public surface (`[quality]`, `high|medium|low`, `-high`/`-low` naming) is documented in both doc trees and independently revertible via the single commit.
- Known pre-existing issues left untouched per plan: `positional[4]` leniency, the avi-format notification orphan, 4K+slow encode time.

---
*Phase: 05-non-interactive-quality-in-omarchy-transcode*
*Completed: 2026-09-15*

## Self-Check: PASSED
