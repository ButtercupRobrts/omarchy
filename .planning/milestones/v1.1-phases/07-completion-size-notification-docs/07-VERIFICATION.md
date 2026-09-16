---
phase: 07-completion-size-notification-docs
verified: 2026-09-16T14:36:31Z
status: passed
score: 9/9 must-haves verified
covered_files:

  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/07-completion-size-notification-docs/07-01-PLAN.md
  - .planning/phases/07-completion-size-notification-docs/07-01-SUMMARY.md
  - .planning/phases/07-completion-size-notification-docs/07-VALIDATION.md
  - .planning/phases/07-completion-size-notification-docs/07-REVIEW.md
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
  - manual/12-screenshots-recording.md

covered_digest: "v1:sha256:70df99c1bfa3c84b47f7e4fe23e41544b3bb4a5cdc3036a7107a2cd39e21d477"
behavior_unverified: 0
overrides_applied: 0
human_verification:

  - test: "Transcode a real video in the running UI (`omarchy transcode <clip> mp4 1080p`); read the done toast"
    expected: "The completion toast body shows `Saved and copied to clipboard (N MB).` legibly — PUA glyph intact, no truncation"
    why_human: "Toast rendering is a running-UI property per agents/skills/visual-verification.md; the dev shell loads the packaged /usr/share/omarchy tree, and the stub harness captures argv, not pixels (VALIDATION.md Manual-Only table; SUMMARY UAT item a)"
  - test: "Estimate→actual calibration on one real clip: note the `~N MB` shown in the quality menu, compare against the `N MB` in the done toast"
    expected: "The reported actual size lands within ~2× of the menu estimate (CRF variance expected — same MiB scale under the same `MB` label)"
    why_human: "Requires a real ffprobe/ffmpeg encode on real media; the stub harness pins the stat+awk chain against `truncate -s` fixtures, not real-clip bitrate behavior (SUMMARY UAT item b)"
  - test: "Read the edited Transcoding paragraph in `manual/12-screenshots-recording.md:68-74` aloud"
    expected: "Reads naturally to an end user; no CRF/codec jargon"
    why_human: "Doc-prose tone is human judgment (VALIDATION.md Manual-Only table; SUMMARY UAT item c). Minor known looseness: :72 invites an estimate check that only applies to videos — REVIEW IN-05, advisory"
---

# Phase 7: Completion-size notification + docs Verification Report

**Phase Goal:** The transcode completion notification reports the actual output file size, closing the estimate→actual loop, and all user-facing docs/metadata are in sync
**Verified:** 2026-09-16T14:36:31Z
**Status:** human_needed — all 9 must-have truths verified against disk and independently re-run tests; the running-UI toast render, real-clip estimate→actual calibration, and manual-prose read-aloud genuinely require the live environment
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | Both done-notification call sites send `Saved and copied to clipboard${size:+ ($size)}.` where `size` is `$(output_size_label "$output" || true)` computed after `copy_to_clipboard` — happy path reads `Saved and copied to clipboard (38 MB).` (SIZE-02, ROADMAP SC1) | ✓ VERIFIED | Video arm `bin/omarchy-transcode:386-388` and picture arm `:391-393`: `size=$(output_size_label "$output" || true)` sits between `copy_to_clipboard "$output"` and the send in both arms; `grep -F 'size:+ ($size)'` matches exactly :388/:393. Diff of `22c28a7d` confirms only the done bodies changed. e2e re-ran green: `FAKE_OUT_BYTES=39845888` (exactly 38.00 MiB) rows assert `Saved and copied to clipboard (38 MB).` on the `Transcoded to 1080p mp4` and `Transcoded to medium jpg` notification lines (test :580-592) |
| 2 | `output_size_label()` lives between `select_quality` and `main` — still inside the proven `copy_to_clipboard`→`main` slot that dodges PR #6698's insertion zone — as `stat -c %s "$1" || true` → `^[0-9]+$` gate → awk `%.0f MB` on `/1048576` (MiB scale, same as the Phase-6 `~N MB` estimates) | ✓ VERIFIED | Definition at :289-297 — after `select_quality` close (:285), before `main` (:299); `copy_to_clipboard` ends :156 so the helper is clear of the `transcode_video`↔`copy_to_clipboard` PR #6698 zone. Body verbatim: `bytes=$(stat -c %s "$1" 2>/dev/null || true)` → `[[ $bytes =~ ^[0-9]+$ ]] || return 1` → `awk -v b … printf "%.0f MB", b / 1048576`. Post-review commit `972a1bba` adds a `0 < b < 1 MiB → "<1 MB"` band (:294) — strictly additive, same scale |
| 3 | A stat failure (missing/vanished output, non-numeric stat output) degrades the body to `Saved and copied to clipboard.` via `${size:+ ($size)}` — run still exits 0, no fabricated/partial size, `set -euo pipefail` never tripped (T-07-01) | ✓ VERIFIED | `|| true` inside the `$(…)` (status can't escape), `local` split from the substitution, `|| true` on the caller's command substitution (:387/:392), colon-form `${size:+}` expands empty. awk is the helper's last statement so it can never emit a partial label. e2e degrade row (:597-604) green: no `FAKE_OUT_BYTES` → body ends `clipboard.$` and contains no ` MB)`, run exits 0 |
| 4 | An encode failure produces zero `Transcoded to` notification lines — `set -e` aborts inside `transcode_video`/`transcode_picture` before the done notification; harness pins via `FAKE_ENCODE_RC` (T-07-failure) | ✓ VERIFIED | Ordering in `main()`: `transcode_video` :385 / `transcode_picture` :390 run before the done sends :388/:393 under `set -euo pipefail` (:9). e2e row (:610-618) green: `FAKE_ENCODE_RC=1` → non-zero exit, `Transcoding video` start notification present (pre-existing orphan, pinned not fixed), zero `Transcoded to` lines |
| 5 | A deduped output (`-2`/`-3`) reports the size of the file actually written — `stat` runs on `$output` resolved by `output_path` before the notifications (SIZE-02 + SAFE-01) | ✓ VERIFIED | `output=$(output_path …)` resolves the deduped path at :381 before the notification block; `output_size_label "$output"` stats that path. e2e row (:632-640) green: pre-created `in-1080p.mp4` (0 bytes) + `FAKE_OUT_BYTES=39845888` → `out=…/in-1080p-2.mp4` pinned AND `(38 MB)` reported — measuring the collision fixture would have printed `(0 MB)` |
| 6 | The start notification (`Transcoding video…` :384) is byte-unchanged and the notification count is unchanged — two sends on the video path, one on the picture path | ✓ VERIFIED | `git show 22c28a7d -- bin/omarchy-transcode`: the start-notification line appears only as unchanged context; exactly two `omarchy-notification-send` lines in the video arm, one in the picture arm (same as before). PUA glyphs byte-verified: `EF 80 BD` (U+F03D) on :384 and :388, `EF 80 BE` (U+F03E) on :393. Note (REVIEW IN-02, advisory): count/start-body are diff-verified but not pinned by a dedicated test row |
| 7 | Encoder stubs gained opt-in `FAKE_OUT_BYTES` (`truncate -s` the `${!#}` output path) and `FAKE_ENCODE_RC` (`exit` that status) knobs — unset is byte-identical to the old never-create-output behavior | ✓ VERIFIED | Stub body test :43-46: `if [[ -n ${FAKE_OUT_BYTES:-} ]]; then truncate -s "$FAKE_OUT_BYTES" "${!#}"; fi; exit "${FAKE_ENCODE_RC:-0}"`. `${!#}` is the last positional — the output path for both `ffmpeg` and `magick` argv shapes. Comments updated (:26-33, :118-122). Unset knobs leave dedupe rows non-self-colliding (proven by the :190-197 dedupe row still passing) |
| 8 | WR-01 folded in as a separate `fix(07)` commit: `estimate_label`'s `printf "~%d MB", r` became `%.0f` — sub-10 MiB estimates round instead of flooring; all nine pre-existing ≥10 MiB pins unchanged; dur=18/720p row pins `~6`/`~4`/`~2 MB` | ✓ VERIFIED | `bin/omarchy-transcode:238` now `printf "~%.0f MB", r` (`git show 8d52171b`: one-character change); `grep -n '~%d MB'` has no match. e2e pin (:655-661) green: `FAKE_DURATION=18` at 720p asserts `~6`/`~4`/`~2 MB` (unfixed code renders `~5`/`~3`/`~1`); all 44 pre-existing rows still green |
| 9 | `manual/12-screenshots-recording.md` names the video quality step and the actual size in the completion notification, user-voiced, no CRF jargon; every other doc surface (`# omarchy:*` header, `usage()`, `docs/`, `capture.md`, `bin/omarchy` GROUP_DESCRIPTIONS) verified-unchanged because already in sync (ROADMAP SC2) | ✓ VERIFIED | manual :70 now reads "asks for a format and a size — and a quality too, for videos, with a rough estimate of how big each choice will come out"; :72 adds "the notification tells you the actual size of the file it wrote, so you can check it against the estimate". `grep -rli transcode docs/` → empty (exit 1). `# omarchy:*` :3-7 includes `[quality]` in args + a `low` example — accurate; `usage()` :14/:30-31 documents `[quality]` and video-only tiers — accurate; `default/agents/skills/omarchy/capture.md:59` already lists `[quality]`; `bin/omarchy:89` GROUP_DESCRIPTIONS entry present. `./test/cli` re-ran → exit 0 |

**Score:** 9/9 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `bin/omarchy-transcode` | `output_size_label()` after `select_quality`/before `main`; `size` in main()'s `local` line; both done arms carry `size=$(… || true)` + `${size:+ ($size)}`; `estimate_label` `~%.0f` | ✓ VERIFIED | Helper :289-297 (with `972a1bba`'s `<1 MB` band :294); `local type output quality size positional=()` :301; arm wiring :387-388/:392-393; `~%.0f MB` :238; `bash -n` clean. Substantive (not a stub), wired from `main` |
| `test/shell.d/transcode-quality-test.sh` | `FAKE_OUT_BYTES`/`FAKE_ENCODE_RC` stub knobs, IN-06 `notify_line`/`ffmpeg_line` empty-guard, SIZE-02/WR-01 assertion rows — all existing rows keep passing | ✓ VERIFIED | Knobs :43-46; IN-06 guard :201-206 (`|| true` inside `$(…)` on both assignments + `[[ -n && -n ]]` before `(( ))`); 7 new rows :574-661 (video/picture/gif size, degrade, encode-failure, dedupe, `<1 MB`, WR-01 rounding). Re-ran: **52 `ok -`, 0 `not ok`, exit 0** (52 = 51 from SUMMARY + 1 `<1 MB` row added by `972a1bba`) |
| `manual/12-screenshots-recording.md` | Transcoding paragraph names the video quality step, rough per-choice estimate, and actual size in the completion notification | ✓ VERIFIED | :70 quality-step + estimate sentence; :72 actual-size notification sentence; `grep -n 'estimate'` hits :70/:72 inside the Transcoding section |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `main()` tail (:383-394) | `output_size_label()` | `size=$(output_size_label "$output" || true)` between `copy_to_clipboard "$output"` and each done `omarchy-notification-send` (:387, :392) — `$output` holds the deduped path resolved at :381 | ✓ WIRED | Verified in code and by e2e: happy-path `(38 MB)`, dedupe `-2` reports its own size, missing output degrades |
| Done-notification body | `omarchy-notification-send` positional contract | `"Saved and copied to clipboard${size:+ ($size)}."` — one typed argv element; missing size expands to nothing, no `if` tree | ✓ WIRED | Colon-form `+` expansion verified; label is digits + literal ` MB` (or `<1 MB`) by construction — nothing reinterpretable as options/hints into the busctl `susssasa{sv}i` call (T-07-04 sealed) |
| `output_size_label()` | coreutils `stat` + `awk` | `stat -c %s` (same incantation as input-side :254) → `^[0-9]+$` gate → `awk -v b 'BEGIN{… b/1048576}'` (:291-296) | ✓ WIRED | `awk -v` C-escape surface sealed by the digit gate (T-07-01); `|| true` inside `$(…)` so pipefail can't abort; MiB scale matches `estimate_label`'s `/1048576` (:233) — estimate→actual same-scale under one `MB` label |
| Encoder stub (:34-48) | real `stat`/`awk` chain | `truncate -s "$FAKE_OUT_BYTES" "${!#}"` makes the stub write a real sized file the script's own `stat` measures; `FAKE_ENCODE_RC` exits non-zero to pin no-done-notification-on-failure | ✓ WIRED | e2e rows exercise the real chain end-to-end — no mocked size value reaches the assertion |

### Prohibitions (negative checks — all empirically verified)

| Prohibition | Status | Evidence |
| ----------- | ------ | -------- |
| Never report a size the script did not itself just measure | ✓ HELD | `stat`→regex-gate→`return 1` (:291-292); degrade e2e row green (:597-604); no estimate/cached value can substitute |
| Never claim a size for a file the transcode didn't produce | ✓ HELD | `set -e` ordering (:385/:390 before :388/:393) + `FAKE_ENCODE_RC` row pins zero `Transcoded to` lines (:610-618); dedupe row proves the written `-2` is measured, not the fixture |
| Never let the size lookup delay, reorder, or replace the notification | ✓ HELD | One `stat`+`awk` between `copy_to_clipboard` and the send; `|| true`-guarded; no extra probing, no second notification |
| Never render the actual on a different scale than the estimate | ✓ HELD | `/1048576` + `%.0f` + literal ` MB` on both sides; no numfmt, no GB rollover, no decimals |
| Never touch the start notification or change notification cardinality | ✓ HELD | `22c28a7d` diff shows start line untouched; 2 video sends / 1 picture send preserved; glyphs byte-verified |
| Never place `output_size_label` between `transcode_video` and `copy_to_clipboard` (PR #6698 zone) | ✓ HELD | Helper at :289 — below `copy_to_clipboard` (:150-156) |
| Never churn in-sync doc surfaces | ✓ HELD | `22c28a7d` touches exactly the 3 `files_modified` paths; `docs/` grep empty; `usage()`/`# omarchy:*`/`capture.md`/`bin/omarchy` unchanged-and-accurate |
| Never mix the three commits' concerns | ✓ HELD | `4e0e1f89` test(07) → test file only; `22c28a7d` feat(07-01) → exactly 3 paths; `8d52171b` fix(07) → 2 files; review-fix `972a1bba` → 2 files, its own commit |
| Never let a stub-created output leak between rows | ✓ HELD | `rm -f` after asserting at :584, :591, :626, :639, :648 |
| Never weaken the harness for convenience | ✓ HELD | IN-06 guard made the ordering assertion stricter (`|| true` + non-empty guard before `(( ))`); all new rows add coverage; no existing assertion loosened |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full stub e2e | `bash test/shell.d/transcode-quality-test.sh` | **52 `ok -`, 0 `not ok`, exit 0** | ✓ PASS |
| Syntax | `bash -n bin/omarchy-transcode` | exit 0 | ✓ PASS |
| Metadata lint + routing | `./test/cli` | exit 0, zero `not ok` | ✓ PASS |
| Full shell suite | `./test/shell` | 7/240 files failed — exactly the documented environmental set (bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths per STATE.md:98); transcode-quality 52/52 green inside | ✓ PASS |
| Docs inventory | `grep -rli transcode docs/` | empty (exit 1) | ✓ PASS |
| Size-suffix presence | `grep -n 'size:+ ($size)' bin/omarchy-transcode` | exactly :388 and :393 | ✓ PASS |
| Helper placement | `grep -n 'output_size_label\|^main\|^select_quality\|^copy_to_clipboard'` | def :289 between select_quality (:247) and main (:299); calls :387/:392 | ✓ PASS |
| WR-01 fixes | `grep -n '~%d MB'` → none; `~%.0f MB` at :238; `<1 MB` band :294 | both fixes in place | ✓ PASS |
| Commit atomicity | `git show --stat` per commit | 4e0e1f89: 1 file; 22c28a7d: exactly 3 files_modified; 8d52171b + 972a1bba: 2 files each | ✓ PASS |
| Glyph bytes | `od -c` on :384/:388/:393 | `EF 80 BD` ×2 (video), `EF 80 BE` ×1 (picture) | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| SIZE-02 | 07-01 | The completion notification reports the actual output file size | ✓ SATISFIED | Truths 1-6 + artifacts; e2e pins `(38 MB)` on all three arms (mp4, picture, gif), degrade-never-lies, encode-failure-zero-lines, deduped-`-2`-size, and the `<1 MB` sub-MiB floor. REQUIREMENTS.md:19/:62 still shows the checkbox unchecked / "Pending" — bookkeeping for milestone close-out, not a behavior gap |

No orphaned requirements: REQUIREMENTS.md maps exactly SIZE-02 to Phase 7, and it is declared in the plan's `requirements` frontmatter (`requirements-completed: [SIZE-02]` in the SUMMARY).

### Flagged Assumptions — Disposition

| Assumption (07-01-PLAN.md :384-393) | Status |
| --------------------------------- | ------ |
| [SIZE-02, concurrency — UNRESOLVED probe] Two parallel transcodes resolving the same basename can both pick the same candidate; the notification reports whatever file sits at `$output` at stat time — a real file's real size, possibly the other run's | ✓ DOCUMENTED, not silently dropped — plan :388 records it with rationale (no cross-process locking, matches repo conventions; the notification still satisfies "reports the actual output file size" for the path it names). Out of scope for the phase goal |
| [unit label — locked] `38 MB` MiB-scale resolves MB-vs-MiB by same-scale consistency | ✓ Verified in code (`/1048576` both sides) |
| [WR-01 scope] folded in as `fix(07)` | ✓ Landed as `8d52171b` |
| [IN-06 scope] rides along as `test(07)` | ✓ Landed as `4e0e1f89`, committed first per the load-bearing order note |
| [body wording] minimal suffix form; filename-in-body rejected | ✓ Verified — `${size:+ ($size)}` suffix only |
| [start-notification orphan] pinned not fixed | ✓ Pinned at :613-614 |

### Anti-Patterns Found

None blocking. REVIEW WR-01 (`0 MB` for non-empty sub-1 MiB outputs) was fixed in `972a1bba` before this verification — the `<1 MB` band is in place at :294 with a `FAKE_OUT_BYTES=200000` pin (:644-649). Remaining REVIEW items are INFO/advisory: IN-01 (combined-knob partial-file semantics), IN-02 (notification count/start-body not pinned by a test row — diff-verified here instead), IN-03/IN-06 (stale/overclaiming comments — IN-04 comment was corrected in `972a1bba`), IN-05 (manual :72's estimate-check phrasing covers videos; pictures have no estimate — prose looseness, not a mechanism error).

### Manual-Only Items (VALIDATION.md)

The three running-UI items — done-toast legibility with glyph, real-clip estimate→actual sanity, and manual-prose read-aloud — are recorded in `human_verification` above. Everything automated passes; status is `human_needed` solely for these.

---

_Verified: 2026-09-16_
_Verifier: the agent (gsd-verifier)_
