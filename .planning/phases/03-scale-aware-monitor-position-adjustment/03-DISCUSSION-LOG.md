# Phase 3: Scale-aware monitor position adjustment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-14
**Phase:** 3-scale-aware-monitor-position-adjustment
**Areas discussed:** Adjacency rules, Non-adjacent monitors, Applied-scale read-back, GDK_SCALE policy

---

## Adjacency rules

### What counts as edge-adjacent?

| Option | Description | Selected |
|--------|-------------|----------|
| Exact edge match only | Recompute only when edges coincide within float rounding — predictable but misses off-by-one hand-tuned configs | |
| Small tolerance (~5px), symmetric | Near-touching edges — tiny gap OR tiny overlap — count as adjacent and normalize to touching | ✓ |
| Exact + snap on any touch | Most aggressive — any touch normalizes | |

**User's choice:** Tolerance rule (adopted after designer/engineer analysis: near-touching is never a deliberate layout; dead zones are always cursor traps; "never create a broken state" principle)

### Which axes?

| Option | Description | Selected |
|--------|-------------|----------|
| Both X and Y | Horizontal neighbors and vertical stacks alike | ✓ |
| Horizontal only | Simpler, covers common case | |

### Sandwiched monitor — which edge wins?

| Option | Description | Selected |
|--------|-------------|----------|
| Largest shared edge | Keep adjacency to the most-attached neighbor; ties → left/top; broken side logged | ✓ |
| Left/top edge wins | Simplest deterministic rule | |
| Don't recompute | Sandwiched monitors keep exact position | |
| Cascade (rejected for v1) | Push downstream neighbors — correct UX, rewrites untouched monitors | deferred |

### Fail-safe on new third-monitor overlap?

| Option | Description | Selected |
|--------|-------------|----------|
| Warn + apply anyway | Trust rarity | |
| Abort to preserve | Never produce a worse state than doing nothing | ✓ |

---

## Non-adjacent monitors

### Floating monitor newly overlaps after growth?

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal clamp | Shift just enough to eliminate the new overlap | ✓ |
| Preserve + warn | Keep position, log overlap | |
| Refuse the change | Don't apply scale | |

### Gap semantics across scale changes?

| Option | Description | Selected |
|--------|-------------|----------|
| Logical px (as stored) | Coordinate preserved exactly | ✓ |
| Physical px (proportional) | Rescale offset so physical gap is constant | |

---

## Applied-scale read-back

| Option | Description | Selected |
|--------|-------------|----------|
| Single-pass + verify | Compute position from clean_scale output, atomic eval, post-check warns on divergence — no visible jiggle | ✓ |
| Two-pass measure | Apply scale, measure real size, eval position — visible intermediate broken state | |
| Trust clean_scale | No verification | |

**Notes:** clean_scale output is provably Hyprland-stable (k | gcd(120w,120h) ⇒ integer logical dims). The 1.4→1.5 vs 1.3333 divergence seen live came from bypassing clean_scale via raw `hyprctl eval`.

---

## GDK_SCALE policy

| Option | Description | Selected |
|--------|-------------|----------|
| In scope — fix it | Same function, same bug class (per-monitor change corrupting a global) | ✓ |
| Defer to v2 | Would have become SCALE-23 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Max scale | round(max of all monitor scales) — deterministic, no 'primary' fiction, sharpest XWayland result | ✓ |
| Focused monitor | Last-writer-wins — the current bug | |
| Origin monitor | Track 0x0 monitor — assumes a primary Hyprland doesn't have | |

**Notes:** round-vs-ceil flagged for research (ceil keeps sub-1.5 setups sharp but departs from upstream nearest-integer semantics).

---

## the Agent's Discretion

- Tolerance constant (~5px) tunable if research shows coordinate rounding needs more headroom
- Audit-log wording; whether divergence warnings also surface a desktop notification
- GDK_SCALE round-vs-ceil final choice (research-flagged)

## Deferred Ideas

- Cascading position shifts (constraint-graph propagation) — future phase/upstream v2
- `auto-left`/`auto-right`/etc. declarative positions — investigate in research; can't express per-monitor adjacency, but may inform future config-format work
