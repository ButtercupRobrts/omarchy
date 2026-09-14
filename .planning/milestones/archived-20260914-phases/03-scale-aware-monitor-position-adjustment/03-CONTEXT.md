# Phase 3: Scale-aware monitor position adjustment - Context

**Gathered:** 2026-09-14
**Status:** Ready for planning

<domain>
## Phase Boundary

`omarchy-hyprland-monitor-scaling` must keep the monitor layout intact when a scale changes the target's logical size. Positions are stored in logical pixels that encode the old scale, so an edge-adjacent monitor's fixed offset becomes wrong: shrinking logical width creates dead gaps that trap the cursor; growing it creates overlaps that Hyprland warns about and that corrupt bar rendering/click regions. The tool must recompute the target monitor's position to preserve its adjacency relationships, apply scale+position atomically, and persist both to `monitors.lua`. Also in scope: `GDK_SCALE` currently follows whichever monitor was last scaled — a global corrupted by a per-monitor change; it must track the maximum monitor scale.

**Live evidence (Phase 2 UAT):** Samsung `HDMI-A-1` at `-1200x0` scale 1.6 → rescale to 1.5 overlapped `eDP-1` by 80px (dead clicks, "overlaps with other monitor(s)" warning, translucent bar); rescale toward 1.4 snapped to 1.5 via `clean_scale` but raw eval produced 1.3333 and left a ~165px dead gap that trapped the cursor. Upstream issue #10922 describes this class of problem; none of the ~9 open upstream scaling PRs handle it.

</domain>

<decisions>
## Implementation Decisions

### Adjacency detection and recompute
- **D-01:** Tolerance-based adjacency — monitor edges that touch or are within ~5 logical px of each other (in either direction: a tiny gap OR a tiny overlap) count as adjacent and are normalized to touching after rescale. Clear gaps (> ~5px) and large overlaps are not adjacency — the position is preserved exactly. Rationale: logical widths are floats (1920/1.3333 = 1439.9999…), so "exact" needs an epsilon anyway; near-touching edges are almost never a deliberate layout choice, while a 5px dead zone is always a cursor trap.
- **D-02:** Adjacency is evaluated on both axes — left/right neighbors and vertically stacked monitors get the same treatment (top/bottom edges).
- **D-03:** Sandwiched monitor (adjacent on two opposite edges — both cannot survive a resize) preserves adjacency to the neighbor sharing the largest boundary; ties prefer left/top. No cascading position shifts to third monitors in v1. The broken side is recorded in the scale audit log (`audit_scale_change`).
- **D-04:** Fail-safe — if the recomputed position would create a new overlap with any other monitor, abort the position change and keep the original position (warn via audit log). A recompute must never produce a worse state than doing nothing.

### Non-adjacent monitors
- **D-05:** If the scaled monitor was not adjacent to anything and its growth would create a new overlap, apply a minimal clamp — shift it just enough along the shared axis to eliminate the overlap.
- **D-06:** Deliberate gaps are preserved in logical pixels as stored — the coordinate is kept exactly; the physical gap may shift with scale. No proportional/physical-space rescaling of offsets.

### Apply strategy
- **D-07:** Single-pass + verify — compute the new position from `clean_scale`'s output (which is provably Hyprland-stable: it only emits scales producing integer logical dimensions) and apply scale + corrected position in one `hyprctl eval`, so the monitor never occupies a broken intermediate position on screen. After applying, re-read `hyprctl monitors -j` once and warn (audit log) if the applied scale diverges from what was computed on — insurance against upstream snapping changes. Do NOT use two-pass apply (scale-then-position) — the intermediate frame can flash an overlap/gap.
- **D-08:** The recomputed position is persisted to `monitors.lua` alongside the scale — the existing awk rewriter must gain the ability to rewrite `position =` in place (same in-place-rewrite-or-append contract as scale). Fixing only the live position leaves a stale coordinate that recreates the bug on every `hyprctl reload`.

### GDK_SCALE policy
- **D-09:** `omarchy_gdk_scale` is updated to `round(max(all monitor scales))` after any scale change — not the scaled monitor's own value. Deterministic, needs no "primary" concept (Hyprland has none), and XWayland apps stay sharpest on the densest display since downscaling beats upscaling. Whether to use `round` (stock semantics) or `ceil` (sharper on sub-1.5-only setups) is left to research — flag explicitly.

### the Agent's Discretion
- Tolerance constant (~5px starting value) may be tuned if research shows Hyprland coordinate rounding needs more headroom.
- Exact audit-log wording and whether divergence warnings also surface a desktop notification.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase artifacts
- `.planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-CONTEXT.md` — locked decisions D-01..D-05: hybrid persistence contract (in-place rewrite vs append), awk rewriter invariants (comment/string blanking, top-level keys, depth-aware value termination), backups, audit log
- `.planning/phases/01-per-monitor-scale-persistence-in-the-scaling-cli/01-VERIFICATION.md` — verified Phase 1 behavior this phase must not regress
- `.planning/phases/02-per-monitor-display-panel/02-CONTEXT.md` — panel calls this CLI with explicit monitor arg; fixes here flow to the panel for free

### Implementation targets
- `bin/omarchy-hyprland-monitor-scaling` — the script under change; `clean_scale` (~line 58), live apply eval (~line 111), `persist_monitor_scale` (~line 124), `omarchy_gdk_scale` rewrite (~line 480), `audit_scale_change`
- `test/shell.d/monitor-scaling-test.sh` — 36-case suite the recompute logic must extend (pure-function tests for position math are expected)
- `config/hypr/monitors.lua` — stock config documenting `GDK_SCALE` semantics and position conventions

### Project rules
- `AGENTS.md` — bash style rules, atomic commits, test conventions
- Upstream issue `#10922` — the scale-dependent-position bug class this phase fixes (reference in commit message)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `clean_scale` — already snaps requests to scales producing integer logical sizes; its output is the authoritative "applied scale" for position math (D-07)
- `persist_monitor_scale` + awk Lua rewriter — in-place field rewriting machinery already handles `scale =`; extending to `position =` follows the same contract
- `audit_scale_change` — existing audit trail; D-03/D-04/D-07 log through it
- `hyprctl monitors -j` — already read once for live geometry; the verify pass re-reads it (D-07)

### Established Patterns
- Position replay: script already reads live `x,y` and replays them in the eval — Phase 3 replaces "replay verbatim" with "recompute then replay"
- All geometry inputs come from `hyprctl monitors -j` (real applied values) — never trust config-file positions for adjacency math
- Monitor names are validated `^[A-Za-z0-9._-]+$` before entering eval strings — keep that boundary

### Integration Points
- `~/.config/hypr/monitors.lua` — both `scale =` and `position =` on the target's `hl.monitor()` rule are now written
- Panel (`shell/plugins/panels/monitor/`) needs no changes — it calls the CLI and inherits the fix
- `GDK_SCALE` write happens in `persist_monitor_scale`'s sed pass — the value changes from target-derived to max-of-monitors-derived

</code_context>

<specifics>
## Specific Ideas

- The user explicitly invoked "world-class UX designer + senior engineer" framing twice during discussion — the locked decisions encode that reasoning: store relationships not derived values; never create a broken state; atomic apply to avoid visible jiggle; adjacency normalized like macOS/GNOME magnetic snapping.
- The concrete reproduction layouts to test: left-of-origin monitor (`-1200x0` @ 1.6 → rescale), right-of-origin monitor, vertical stack, floating monitor with deliberate gap, sandwiched monitor (synthetic 3-monitor fixtures).

</specifics>

<deferred>
## Deferred Ideas

- **Cascading position shifts** — pushing downstream neighbors to preserve *all* adjacencies when a sandwiched monitor resizes. Correct UX (macOS arrangement metaphor) but rewrites untouched monitors' positions; needs a layout graph. Candidate for a future phase or upstream v2.
- **GDK_SCALE round vs ceil** — `ceil` keeps XWayland apps sharp on setups where all scales are < 1.5 (e.g. 1.25 → ceil 2 renders crisp-downscaled vs round 1 blurry-upscaled); departs from upstream's nearest-integer semantics. Research flag, decided at planning time.
- **`auto-*` declarative positions** — Hyprland's `auto-left`/`auto-right`/`auto-up`/`auto-down` express adjacency scale-invariantly but only relative to the whole layout (can't say "left of eDP-1 specifically"); ambiguous for 3+ monitors. Investigate in research; if viable for the common case, it may inform a future config-format improvement — not this phase's mechanism.

</deferred>

---

*Phase: 3-scale-aware-monitor-position-adjustment*
*Context gathered: 2026-09-14*
