# Phase 8: Non-interactive `--target` size targeting - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-16
**Phase:** 8-non-interactive-target-size-targeting
**Areas discussed:** Overshoot retry semantics, Floor values & refusal text, Target ≥ source & degenerate targets, Notifications during 2-pass

User elected to discuss all four areas, asking for senior-engineer recommendations with reasoning and no assumptions — the same pattern as phases 5–6. Every recommendation was accepted as presented; one plain-English clarification was requested (floor table).

---

## Overshoot Retry Semantics

**Q1 — What triggers the one allowed retry?**

| Option | Description | Selected |
|--------|-------------|----------|
| Any byte-over | output_bytes > target_bytes → retry; target is usually a hard upload cap, spec-literal SIZE-15, zero extra constants | ✓ |
| Tolerance band (~2%) | Retry only when >102%; inside the band just report actual — avoids a wasted re-encode but adds a second magic threshold | |

**Q2 — How is the retry's tightened budget computed?**

| Option | Description | Selected |
|--------|-------------|----------|
| Scale video_kbps by target/actual | video_kbps₂ = video_kbps₁ × target/actual; resolution and 192k audio fixed; deepshrink's single-correction model | ✓ |
| Re-plan with deflated target | Feed target²/actual through plan_target — could silently change resolution after filename/toasts committed | |
| Drop a resolution rung | Far too coarse for a few-% overshoot; contradicts "tighten the budget" | |

**Q3 — How does the retry write output (first attempt's file already exists)?**

| Option | Description | Selected |
|--------|-------------|----------|
| Temp file + mv on success | No -y (v1.1 exclusion preserved); failed retry keeps the overshot-but-playable first output | ✓ |
| rm first output, re-encode | Simpler, but a failed retry leaves zero output | |
| -y on retry pass 2 | Introduces the flag Phase 5 D-01 excluded; still loses the file on mid-write failure | |

---

## Floor Values & Refusal Text

**Q1 — Floor table (min video kbps per rung)?**

| Option | Description | Selected |
|--------|-------------|----------|
| 2000/800/400 | Comparator-grounded middle band; stepping down only on genuinely tight budgets; test-pinned | ✓ |
| Higher (3000/1200/600) | Steps down/refuses sooner — safer pictures, more refusals | |
| Lower (1500/600/300) | Fewer refusals, occasionally ships broken-looking video | |

**Notes:** User asked "what does this mean in plain english?" — floors were explained as the "below this the picture turns to mush" bitrate line per resolution (4k needs ~2000k, 1080p ~800k, 720p ~400k of the size budget's data-per-second). Accepted 2000/800/400 after the explanation.

**Q2 — What does the below-every-floor refusal name as the achievable minimum?**

| Option | Description | Selected |
|--------|-------------|----------|
| Computed min at 720p floor | (400k + audio) × duration × 125 — "Cannot fit under 10M — smallest achievable is ~18M" | ✓ |
| Static refusal, no number | Cheaper, but the requirement says name the minimum | |

---

## Target ≥ Source & Degenerate Targets

**Q1 — `--target 25M` on a source already under 25M?**

| Option | Description | Selected |
|--------|-------------|----------|
| Refuse: "already under target" | Nonzero exit naming both sizes; pointless re-encode is pure quality loss; consistent refusal convention | ✓ |
| Exit 0, no-op | Friendlier interactively, but scripts see success with no output file | |
| Encode anyway | Bigger, worse file — silently wrong | |

**Notes:** Agent surfaced the format-conversion nuance after selection (mov→mp4 where source already fits) — the refusal text should point at dropping `--target` and using the tier path. No objection.

**Q2 — Degenerate duration/bitrate guarding?**

| Option | Description | Selected |
|--------|-------------|----------|
| Gate duration, let huge kbps ride | Positive-numeric duration gate kills -nan/inf; huge derived -b:v is safe (encoder caps, undershoot direction) | ✓ |
| Cap at a codec ceiling | Silently changes intent; unneeded constant | |
| Minimum duration floor | Extra policy nobody asked for | |

---

## Notifications During 2-Pass

**Q1 — Progress signaling during doubled encode time?**

| Option | Description | Selected |
|--------|-------------|----------|
| Pass-scoped, one ID replaced | "(pass 1/2)" → "-r" replace → "(pass 2/2)"; liveness without toast spam | ✓ |
| Single toast, expectation body | "two-pass, ~2× normal time" — sets expectations but still a frozen toast for 10 min | |
| Unchanged | Cheapest; reads as hung at 4k/x265 | |

**Q2 — Step-down disclosure in notifications?**

| Option | Description | Selected |
|--------|-------------|----------|
| Disclose the step + target | "(720p — stepped down from 4k, target ≤25M)" — the milestone's differentiator | ✓ |
| Effective res + target only | Filename/toast agree, user isn't told it wasn't their pick | |
| Effective res only | The silent step Pitfall 7 forbids | |

**Q3 — `--target` with unset positional resolution?**

| Option | Description | Selected |
|--------|-------------|----------|
| Prompt as usual | Resolution keeps "ceiling" meaning; planner may step below the pick; consistent with other unset positionals | ✓ |
| Skip prompt, ceiling = source | Fewer prompts, but removes the ceiling control and makes --target the only flag changing which menus appear | |

---

## the agent's Discretion

- Exact refusal/error wording (must name the computed achievable minimum; point at the tier path for conversion intent)
- Pass-scoped toast wording and placement of the pass-2 update call inside `transcode_video_target`
- Normalized filename token shape beyond "digits+unit, filename-safe"
- Optional earlier gif-refusal right after the interactive format menu
- Internal structure of the new helper block (`parse_target_size`, `plan_target`, floor table, `transcode_video_target`)

## Deferred Ideas

- `Custom size…` row → Phase 9 (this phase only shapes the shared parser/planner contract)
- Sub-720p rungs (SIZE-16), repeated overshoot loop (SIZE-17), intent presets (SIZE-11), gif target (SIZE-12)
- Audio step-down ladder — rejected in favor of fixed-192k + refusal
- Progress percentage, audio-drop flag, `--reduce %`, codec selection, upscaling — REQUIREMENTS out-of-scope
