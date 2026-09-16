# Phase 6: Interactive quality prompt + size estimates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-15
**Phase:** 6-interactive-quality-prompt-size-estimates
**Areas discussed:** Subtext wording, Estimate vs source, Probe-failure fallback, Row icons

**Format note:** User requested all areas discussed in a single pass with senior-engineer recommendations and explanations, no assumptions. All four recommendations were accepted as presented.

---

## Subtext wording

| Option | Description | Selected |
|--------|-------------|----------|
| CRF 18 · ~110 MB | Matches the ROADMAP success criterion verbatim; CRF number is a calibration anchor, ~ keeps honesty. 16 chars, no elision. | ✓ |
| ~110 MB only | Cleanest; follows FEATURES.md's "named tiers hide raw CRF" guidance literally — but deviates from the roadmap's written example. | |
| ~110 MB · biggest | Size + qualitative tag. Redundant — tier order already implies ranking — and spends chars on noise. | |

**User's choice:** `CRF 18 · ~110 MB`
**Notes:** Recommendation grounded in the roadmap success criterion being the acceptance contract; FEATURES.md's CRF objection targets CRF as an input control, not informational subtext.

---

## Estimate vs source

| Option | Description | Selected |
|--------|-------------|----------|
| Show "larger than source" | Replace the number for that row — honest, actionable, cheap (stat -c %s + compare). The number would be fake anyway on efficient sources. | ✓ |
| Keep number, append marker | e.g. "CRF 18 · ~1.4 GB · grows file". Keeps a number but ~30-char budget gets tight and the number is still untrustworthy. | |
| Show raw estimate anyway | Simplest — but this is exactly the "estimate lies" case the success criterion says to degrade on. | |

**User's choice:** Show "larger than source" (replace the number on that row)
**Notes:** The estimate is least trustworthy exactly where it would mislead — efficient sources re-encode up at CRF 18.

---

## Probe-failure fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Qualitative subtexts | "Best quality" / "Balanced" / "Smallest file" on all rows — uniform heights AND the menu still explains the tiers. | ✓ |
| Plain labels, no subtext | high/medium/low with no subtext. Uniform and safe, but the quality step loses its payoff — looks like the resolution step. | |

**User's choice:** Qualitative subtexts on all rows
**Notes:** Mixed subtext/no-subtext rows render uneven detailRowHeight — ruled out either way (pitfall 10).

---

## Row icons

| Option | Description | Selected |
|--------|-------------|----------|
| Empty glyph | Consistent with the format and resolution prompts in the same flow — all plain rows. Icon-ing only this step breaks intra-flow consistency. | ✓ |
| Per-tier Nerd Font glyph | e.g. up/circle/down glyphs per tier. Prettier scanability, but a second visual dialect inside one prompt sequence. | |

**User's choice:** Empty glyph field
**Notes:** No existing omarchy-menu-select caller uses tab fields — this menu is the first subtext user. Glyphs do exist elsewhere (omarchy-menu-plugin uses icon⇥name⇥id).

---

## The agent's Discretion

- Exact qualitative wording for "larger than source" and fallback subtexts (≤~30 chars, no tabs)
- Audio-stream probe to drop the +192k term on silent sources (researcher flag)
- Upscale note in subtext when source < target resolution (optional-or-defer per research)
- Helper function placement/naming (adjacent to transcode_video or below copy_to_clipboard; PR #6698 conflict window)
- awk vs integer math (awk is repo convention)
- Test file name: transcode-quality-test.sh

## Deferred Ideas

- Upscale flag in subtext — possible v1.x refinement
- Audio-stream-aware estimates — researcher may fold in or defer
- Icons on all transcode prompts — scope creep, whole-flow visual pass
- gif size estimates — v2 (SIZE-12), needs sample-encode estimator
- Nautilus batch quality remembering — post-v1.1, interacts with PR #6698
- Completion-notification actual size — Phase 7
