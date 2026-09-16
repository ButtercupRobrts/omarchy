# Project Research Summary — v1.2 Target-Size Transcode

**Synthesized:** 2026-09-16
**Sources:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md

## Key Findings

**The universal recipe is confirmed.** Every credible comparator converges on: `usable_kbps = target_bytes × 8 ÷ dur_s ÷ 1000 × (1 − ~0.02 container reserve) − audio_kbps`, then two-pass `-b:v`. Verified empirically on installed ffmpeg n9.0.1 — lands ~1–5% under target.

**Two-pass is non-negotiable.** Single-pass ABR drifts ~20% (what got HandBrake's target-size axed). Two-pass x264/x265 both verified working via `-pass 1/2` + `-passlogfile` (uniform flag covers both codecs; no `-x265-params stats=`).

**Input mode already ships.** `bin/omarchy-menu-input` exists, emits `mode:"input"`, Menu.qml routes it — the `Custom size…` row needs zero QML and zero menu-select changes. Quirk: empty submit returns exit 0 with empty text (≠ cancel); caller must treat empty as invalid.

**gif refuses `--target`.** Verified: palette encoder ignores `-b:v` entirely (byte-identical output at 100k vs 5000k).

**Audio is the real edge case.** Fixed `-b:a 192k` exceeds the entire budget on tight targets (10 MB over 10 min ≈ 137 kbps total). Needs a step-down decision: 192→96→64→refuse (comparator precedent: deepshrink).

## Implications for Roadmap

**Build order (dependency-strict):**
1. `parse_target_size` parser + `--target` flag + refusal matrix (×quality mutual exclusion, ×gif, ×picture, missing value) — dies pre-notification per v1.1 convention
2. `plan_target` helper (duration + audio probes → budget math → resolution floor table → step-down or refuse) + `transcode_video_target` sibling (two-pass, mktemp-d passlog + EXIT trap) + main() wiring
3. `Custom size…` row in `select_quality` (sentinel → `omarchy-menu-input` → parse loop)
4. Tests + docs

**Additive-diff rules:** `transcode_video` stays byte-identical (sibling function, not a parameter); tier case tables duplicated per the file's documented convention; step-down writes effective rung back into `resolution` so filename/toasts name the actual output for free.

## Watch Out For (fatal severity)

- **Passlog lifecycle** — no `trap` exists in the script today; `mktemp -d` + EXIT trap is mandatory or aborts leak stale passlogs that corrupt the next run's pass 2.
- **Free-text parse** — first unbounded input the script has ever taken; regex → integer bytes via awk; bare `25` policy (recommend MB); bounds refusal.
- **Test harness hang** — `omarchy-menu-input` is NOT stubbed today; a `Custom size…` test would invoke the real binary and spin forever on `done_file`. Also: ffmpeg stub's `truncate -s "${!#}"` fails on pass 1 (`/dev/null`); `run_transcode` doesn't export TMPDIR so script-side `mktemp -d` is unobservable.
- **Duration is a hard dependency** — probe failure must *refuse* (no qualitative fallback exists under `--target`); watch `local x=$(...)` status masking and awk `/0` → `-nan` reaching `-b:v`.
- **Step-down ordering** — resolution must be resolved in `main()` BEFORE `output_path`/`transcode_video`, or the filename and toasts lie about the resolution.

## Open Design Calls (for plan phase)

- Audio step-down ladder: 192→96→64→refuse (recommended) vs fixed 192k→refuse
- Bare-number unit: MB (recommended) vs bytes
- Resolution floors: ~2M/800k/400k video-kbps for 4k/1080p/720p (grounded in comparators)
- Sub-720p rungs: none recommended this milestone
- Overshoot: warn-and-report (recommended) vs retry loop (defer unless dogfooding shows real misses)
- Bad menu input: re-prompt vs reject (recommend one re-prompt then cancel)
- Codec under `--target` at 4k: keep the resolution-keyed x264/x265 split (consistency) vs x264-always (speed)
