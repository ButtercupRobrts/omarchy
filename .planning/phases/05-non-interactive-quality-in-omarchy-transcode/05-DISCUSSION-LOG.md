# Phase 5: Non-interactive quality in `omarchy-transcode` - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-15
**Phase:** 5-non-interactive-quality-in-omarchy-transcode
**Areas discussed:** Collision policy, Invalid value handling, Tier scope (4K encode speed), GIF tier mechanics

---

## Collision policy

| Option | Description | Selected |
|--------|-------------|----------|
| Dedupe | Auto-rename to `stem-1080p-2.mp4` — always succeeds, never destroys data, never hangs | ✓ |
| Hard-fail (`-n`) | ffmpeg `-n`; error notification; user deletes the old file manually | |
| Overwrite (`-y`) | Silently replaces the previous transcode; output path always predictable | |

**User's choice:** Dedupe (recommended)
**Notes:** User asked for full pros/cons + reasoned recommendation on all areas before choosing. Recommendation rationale: dedupe only fires on exact re-runs since tier suffixes already distinguish quality-compare outputs; `-y` assumes transcodes are disposable; `-n` adds friction to a fire-and-forget action.

---

## Invalid value handling

| Option | Description | Selected |
|--------|-------------|----------|
| Strict error | `exit 1` + `unknown quality` message; only `high\|medium\|low` accepted | ✓ |
| Fallback to medium | Unknown values silently encode as medium | |
| Allow aliases/CRF | Also accept `h`/`m`/`l` or raw CRF ints like `21` | |

**User's choice:** Strict error (recommended)
**Notes:** Raw-CRF rejected for codec-conditional semantics (`21` is meaningless for gif) and for locking the model to CRF forever. Aliases save nothing — the interactive flow types for the user.

---

## Tier scope (4K encode speed)

| Option | Description | Selected |
|--------|-------------|----------|
| CRF/fps only | Presets stay as today (x264 fast, x265 slow at 4K); medium byte-identical by construction | ✓ |
| Vary preset too | e.g. low → `-preset veryfast`; muddies the quality axis but speeds up low-tier encodes | |

**User's choice:** CRF/fps only (recommended)
**Notes:** Preset is a second-order size lever; a faster preset on `high` would make it *less* size-efficient at fixed CRF — backwards. Slow-4K is pre-existing; the fix is notification UX, not tier reshaping.

---

## GIF tier mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| fps only | 15/10/5 fps; palette pipeline unchanged; low = choppy but not broken-looking | ✓ |
| fps + palette | low also reduces colors/dither — smaller but visible banding artifacts | |

**User's choice:** fps only (recommended)
**Notes:** Banding reads as a bug, not a tradeoff; fps is the lever every gif tool exposes. Palette knobs deferred to a possible v2 pass.

---

## the agent's Discretion

- Dedupe counter shape and error-message wording (follow existing `Invalid …` style)
- Test file naming/structure — avoid add/add collision with upstream PR #6698's `transcode-test.sh`

## Deferred Ideas

- 4K+slow encode time → notification/elapsed-time improvement (separate phase)
- gif palette/dither for `low` → v2 tier refinement
- Raw CRF passthrough / aliases → revisit only on user demand
- Nautilus batch quality, `--target SIZE`, intent presets, sample encodes → milestone v2 list
