# Phase 3 Research: Scale-aware monitor position adjustment

**Researched:** 2026-09-14
**For:** PLAN of phase 3 (SCALE-08..SCALE-10), decisions D-01..D-09 already locked in `03-CONTEXT.md`

---

## Summary

Everything this phase needs is verifiable against Hyprland source and the existing awk machinery. Three upstream facts drive the design:

1. **Hyprland snaps a non-clean requested scale to the *nearest* 1/120-grid scale producing integer logical dims** (`src/helpers/Monitor.cpp`, `CMonitor::applyMonitorRule`) — nearest, not upward. `clean_scale` (`bin/omarchy-hyprland-monitor-scaling:58-68`) emits scales that always pass Hyprland's integer check untouched, so position math can trust `clean_scale`'s output as the applied scale (D-07). The observed live `1.4 → 1.3333334` divergence happened only because a raw `hyprctl eval` bypassed `clean_scale` (which computes 1.5, rounding *up*).
2. **Overlap detection is a pixman integer-region intersection of `logicalBox() = {m_position, m_size}`** where `m_size = round(transformedPixelSize / scale)` — touching edges (zero-area shared boundary) never warn; any ≥1 px positive-area intersection does. Reserved areas do *not* shrink the overlap box (`logicalBoxMinusReserved()` is a separate query).
3. **`auto-left`/`auto-right`/`auto-up`/`auto-down` (and `auto-center-*`) exist and are layout-global**: each resolves against the bounding-box edge of *all* monitors, pinning the free coordinate to 0 — confirmed correct to defer (CONTEXT deferred-ideas is right; details below), though they are scale-invariant and could inform a future config-format improvement.

The implementation is a single-file change to `bin/omarchy-hyprland-monitor-scaling` plus test-suite extension. The awk rewriter's `top_level_key`/`value_start`/`value_end` machinery already generalizes to `position =`; the only real subtlety is **applying two in-place splices back-to-front** (descending offset) because `block_nostr` offsets go stale after the first splice. One *pre-existing* bug surfaced that this phase should absorb: the live eval drops `transform`/`mirror`/reserved fields, so rescaling a portrait monitor silently un-rotates it — and the appended-rule path never writes `transform`.

---

## Findings

### Q1 — Hyprland scale snapping: the exact rule

Source: `src/helpers/Monitor.cpp`, `CMonitor::applyMonitorRule` (the algorithm landed via commits `6b6f339`, `07132741`, `6a88f2e` — originally `/360` grid, now `/120`):

```cpp
Vector2D logicalSize = m_pixelSize / m_scale;          // m_pixelSize = physical mode dims
if (!*PDISABLESCALECHECKS &&
    (logicalSize.x != std::round(logicalSize.x) || logicalSize.y != std::round(logicalSize.y))) {
    // invalid scale, will produce fractional pixels. find the nearest valid.
    float searchScale = std::round(m_scale * 120.0);
    double scaleZero = searchScale / 120.0;
    if ((m_pixelSize / scaleZero) == (m_pixelSize / scaleZero).round())
        m_scale = scaleZero;
    else {
        for (size_t i = 1; i < 90; ++i) {              // search up to ±89/120 ≈ ±0.74
            double scaleUp   = (searchScale + i) / 120.0;   // UP checked first →
            double scaleDown = (searchScale - i) / 120.0;   // ties prefer the larger scale
            if ((m_pixelSize / scaleUp)   == .round()) { m_scale = scaleUp;   break; }
            if ((m_pixelSize / scaleDown) == .round()) { m_scale = scaleDown; break; }
        }
        // not found: explicit scale → error + m_scale = getDefaultScale() + warning
        //            notification; autoScale → m_scale = std::round(scaleZero)
    }
}
```

The rule, in words:

- If `pixelSize / requested` yields integer logical dims on both axes → **scale passes through unchanged** (the `if` body is skipped entirely).
- Otherwise: round requested to the 1/120 grid; if that grid point is clean use it; else scan `i = 1..89` testing `+i` before `−i` each step — **nearest clean scale wins, ties prefer upward**.
- If nothing clean within ±89/120: an *explicit* request falls back to `getDefaultScale()` (auto) with a parse error + `misc:disable_scale_notification` notification; an *auto* request gets `round(scaleZero)`.
- `debug:disable_scale_checks = true` bypasses all of this (fractional logical dims are then possible).

Reconciling the observed behavior: for 1920×1080, `gcd(120·1920, 120·1080) = 14400`; request 1.4 → grid k=168, not a divisor; divisors of 14400 adjacent to 168 are 160 and 180 — distance 8 vs 12 → **Hyprland picks 160/120 = 1.3333** (nearest), while `clean_scale` walks `k++` only → 180/120 = **1.5** (up-only). Both are "clean"; they differ in direction. This is exactly why D-07 makes `clean_scale` the authoritative applied scale: **any k that divides `gcd(120w,120h)` produces integer logical dims, so Hyprland's entry check is false and the requested value is kept verbatim** (IEEE-754 caveat: `w/(k/120)` correctly rounds to the exact integer — the true quotient is within ~1e-13 of it — so the `== round()` check passes; confirmed by the live session where `clean_scale`-produced values applied exactly).

`hyprctl monitors -j` reports `m_scale` (the snapped real scale) — the live session saw `1.3333334`; older `HyprCtl.cpp` formatted `%.2f`. Planner: compare verify-read scale with tolerance, not string equality — `|applied − computed| < ~0.006` (or `|applied·120 − computed·120| < 0.75`, robust to 2-decimal reporting) distinguishes "reporting precision" from a real snap to a different grid step (adjacent clean scales are ≥ 1/120 apart, typically much more).

**Answers to sub-questions:** clean_scale output always passes through unchanged — yes (subject to `disable_scale_checks` being off; D-07's verify-read is the insurance). For non-integer-producing requests, Hyprland adjusts the *scale* to a nearby clean value (not the logical size); the logical size is *also* rounded for layout (`m_size = (xfmd / m_scale).round()`).

### Q2 — `auto-*` positions: semantics and the deferral verdict

Confirmed present and parsed identically in the Lua API — `hl.monitor({ position = "auto-left" })` reaches the same `CMonitorRule`/`parsePosition` path as hyprlang (`eAutoDirs` in `MonitorRule.hpp`).

Semantics from `CCompositor::arrangeMonitors()` (PRs #5670, #10527):

```cpp
// bounding box of ALL monitors is computed first:
//   maxXOffsetRight = max(m.x + m.size.x);  maxXOffsetLeft = min(m.x)
//   maxYOffsetUp    = min(m.y);             maxYOffsetDown = max(m.y + m.size.y)
case DIR_AUTO_LEFT:  newPosition.x = maxXOffsetLeft  - m->m_size.x; break; // y stays 0
case DIR_AUTO_RIGHT: newPosition.x = maxXOffsetRight;               break; // y = 0
case DIR_AUTO_UP:    newPosition.y = maxYOffsetUp    - m->m_size.y; break;
case DIR_AUTO_DOWN:  newPosition.y = maxYOffsetDown;                break;
// auto-center-*: same edge, centered on the bbox's perpendicular span
```

So `auto-left` = "left of the *leftmost edge of the entire layout*, at y=0" — not "left of a specific monitor". Consequences:

- **Cannot express per-monitor adjacency** ("left of eDP-1 at the same top offset") — the deferred-ideas note in `03-CONTEXT.md` is correct. With 3+ monitors it stacks every `auto-left` output on the same global edge at y=0.
- **No vertical alignment control** — the free axis is pinned to 0 (or bbox-centered for `auto-center-*`).
- `arrangeMonitors()` runs after *every* rule apply — auto-positioned neighbors reflow whenever any monitor changes; this is the upstream #10922/#8992 class of behavior and is why our appended/persisted rules must carry explicit coordinates.
- **Verdict for the record:** not viable as this phase's mechanism — it can't preserve *which* adjacency to keep. However, `auto-*` *is* scale-invariant by construction (re-derived every apply), which is relevant to the persistence question in Q4: a file rule whose `position` is `auto*` needs no coordinate rewrite. A future config-format phase could even *emit* `auto-left` for the canonical "external left of laptop, tops at 0" layout.

### Q3 — What Hyprland counts as an overlap

`CCompositor::checkMonitorOverlaps()` (runs inside `scheduleMonitorStateRecheck()` after every rule apply/reload):

```cpp
CRegion monitorRegion;
for (const auto& m : m_monitors) {
    if (!monitorRegion.copy().intersect(m->logicalBox()).empty()) {
        // ERR log + "Monitor {} overlaps with other monitor(s) in the layout" notification
        break;
    }
    monitorRegion.add(m->logicalBox());
}
```

- `logicalBox()` = `CBox{ m_position, m_size }` where `m_size = (transformedPixelSize / scale).round()` — i.e., **integer logical dims**; `m_position` is integer in practice (rule offsets parse as ints; auto positions come from int arithmetic). Reported JSON `x`,`y` are `(int)m_position` casts.
- `CRegion` is pixman `region32` — integer-pixel intersection. **A shared edge is zero-area → not an overlap → no warning.** Any positive integer-pixel-area overlap warns. Sub-pixel residual differences (e.g. 1439.9999) vanish under int conversion — meaning a sub-1px "overlap" won't warn, and our ~5 px tolerance easily covers float noise; the real hazard remains *gaps* (cursor traps), which Hyprland never warns about at all.
- **Reserved areas do not affect the overlap box**: `logicalBox()` excludes `m_reservedArea` adjustment entirely (post-#12383 reserved handling lives in `logicalBoxMinusReserved()`). The JSON `reserved` field `[left, top, right, bottom]` can be **ignored for adjacency math** — it does not move monitor boxes. Nothing in the repo uses `addreserved`.
- Practical consequence for D-01's tolerance: because `m_size` is integer-rounded, a monitor at "scale 1.6 → 1.5" produces exact integer edges; if our recompute emits exact integers, touching means *exactly* touching — no epsilon needed on the output side. The ~5 px input-side tolerance absorbs: float noise in reported scales, 2-decimal scale reporting (1.33 vs 1.3333 distorts a 1920 px logical width by ~3.6 px — most of the budget, worth noting when tuning TOL), and hand-tuned near-touching configs.

### Q4 — Position persistence: extending the awk rewriter

The smallest correct extension reuses the machinery verbatim. Confirmed first: **the append path already writes position** — `bin/omarchy-hyprland-monitor-scaling:466-467` emits `position = "${x}x${y}"` in the appended single-line rule; only the *in-place* path needs new code, and the call site must pass the *recomputed* x,y (currently live x,y passed at `:114-115`; the `x`/`y` params are used nowhere else inside `persist_monitor_scale` — only at `:466`).

Inside the awk program (`:155-452`):

```awk
# new env: OMARCHY_NEW_POSITION="XxY"  (e.g. "-1280x0"), set only when changed
function rewrite_position(   kstart, vstart, vend) {
    kstart = top_level_key("position")          # :299-320 — depth-1 keys only, separator-checked
    if (!kstart) { /* insert before final } — same shape as rewrite_scale's insertion path (:398-409) */ }
    vstart = value_start(kstart)                # :324-330
    vend   = value_end(vstart)                  # :336-350 — depth-aware; safe on expressions/strings
    while (vend > vstart && substr(block_nostr, vend, 1) ~ /[[:space:]]/) vend--
    block_orig = substr(block_orig, 1, kstart - 1) \
        "position = \"" new_position "\"" substr(block_orig, vend + 1)
}
```

**Critical ordering bug to avoid:** `rewrite_scale` (`:388-410`) splices `block_orig` immediately, while `block_nostr`/`block_blank` keep *original* offsets. If `position` precedes `scale` in the block (the common order), rewriting scale first shifts position's span → stale-offset splice into the wrong byte. Correct pattern: collect **all** edits (scale rewrite-or-insert, position rewrite-or-insert) as `(offset, end, replacement)` spans computed against the untouched `block_nostr`, then apply them in **descending offset order**. Insertion points (missing key → before the block's last `}`) are always the highest offsets and so go first; two missing keys become one combined insertion honoring the existing `,`/`;`/`{` separator logic (`:398-409`).

Other notes:

- `top_level_key("position")` is safe against `my_position`/`positionX` — prev-char must be a separator (`[{,;[:space:]]`, `:312`) and the char after optional whitespace must be `=` (`:313-316`).
- Quoted values are blanked inside `block_nostr` (`position = "auto"` appears as `position = "    "`), so `value_end` can't be fooled by commas inside strings.
- **Decision point for the planner — what to do when the existing `position` is `auto*`:** `auto*` positions re-derive on every reload and are inherently adjacency-safe (Q2); rewriting `"auto"` → `"-1280x0"` trades the user's auto intent for a literal pin that matches what the live eval already did. Recommended: rewrite `position` only when the recomputed position differs from live x,y (shell-side flag), and inside `rewrite_position` skip values starting `"auto` — nothing stale exists to fix there, and the file stays self-consistent. If a block lacks `position` entirely (defaults to auto) the same logic argues for *not* inserting unless the planner prefers file-mirrors-live strictness. D-08's contract ("rewrite position in place like scale") covers the literal-coordinate case either way; the literal-coordinate case is the only one that can go stale.
- Position rewrite must run for **every** matching block (`process_block`, `:412-418`), same as scale — a name+desc: duplicate pair must not disagree.

### Q5 — Adjacency / recompute algorithm (concrete proposal)

Inputs: full `hyprctl monitors -j` array (non-`all` — already excludes disabled *and* mirror outputs, so adjacency is only ever computed between real placed boxes), target name, `new_scale` (clean_scale output), `TOL ≈ 5`. Implementation idiom consistent with the script: `jq -r '.[] | [.name,.x,.y,.width,.height,.scale,(.transform//0)] | @tsv'` → one awk program.

```
For each monitor m:  pw = (m.transform % 2 == 1) ? m.height : m.width     # odd transforms swap
                     ph = (m.transform % 2 == 1) ? m.width  : m.height
                     lw = round-if-within-0.5(pw / m.scale); lh = same    # kill float noise
                     box(m) = { l=m.x, t=m.y, r=m.x+lw, b=m.y+lh }
Target new dims:     nlw = round(pw_t / new_scale)   # exact integer — clean_scale guarantee
                     nlh = round(ph_t / new_scale)

X candidates (for each other m):
    shared_y = min(t.b, m.b) - max(t.t, m.t)
    skip if shared_y <= 0                                # corner-graze is not adjacency
    if |t.r - m.l| <= TOL → cand{ axis:x, side:left-of,  x' = m.l - nlw, shared=shared_y }
    if |t.l - m.r| <= TOL → cand{ axis:x, side:right-of, x' = m.r,       shared=shared_y }
Y candidates (symmetric):
    shared_x = min(t.r, m.r) - max(t.l, m.l);  skip if <= 0
    if |t.b - m.t| <= TOL → cand{ axis:y, side:above, y' = m.t - nlh, shared=shared_x }
    if |t.t - m.b| <= TOL → cand{ axis:y, side:below, y' = m.b,       shared=shared_x }

Per axis, pick the candidate with the largest `shared` (largest shared edge — D-03).
    Tie → prefer the candidate that keeps the target's own top-left edge fixed
    (x: side right-of → x' = m.r keeps left edge; y: side below → y' = m.b keeps top edge).
    This is the natural reading of D-03's "ties prefer left/top" AND is the minimal-move
    choice — flag the reading to the planner, since "prefer left/top" could alternatively
    mean "prefer the neighbor located left/above" (which pins the opposite edge).

New box = (x', y', nlw, nlh) using chosen per-axis moves; unpicked axes keep live coords.
Fail-safe (D-04): if new box has positive-area intersection (>0 on both axes, int math)
    with ANY other monitor → discard position change, keep live x,y, audit-log warn.
No candidates on an axis (D-05): if box at live position now overlaps m → minimal clamp:
    x-separations: x' = m.l - nlw  or  x' = m.r   (whichever |Δx| is smaller)
    y-separations: y' = m.t - nlh  or  y' = m.b
    pick the single smallest |Δ| that resolves all overlaps; apply; re-run D-04 check;
    if still overlapping → abort position change + warn.
No candidates + no new overlap → keep live x,y verbatim (D-06: gaps preserved).
```

Handles the canonical cases: Samsung-left (`t.r ≈ eDP.l = 0`, scale 1.6→1.5 → `x' = 0−1280 = −1280`); right-of-laptop target keeps `x' = m.r` (left edge pinned, growth extends right); vertical stacks symmetric; shrink is symmetric (gap→touching pull-in). Portrait targets and portrait *neighbors* both handled by the transform swap (and note Q8: today the eval would un-rotate a portrait target entirely — fix that first).

### Q6 — GDK_SCALE: round vs ceil — **recommend round (keep upstream semantics)**

CONTEXT/D-09's framing assumed compositor stretching ("round→1 makes XWayland apps blurry-upscaled"). Check the repo: **`xwayland.force_zero_scaling = true`** (`default/hypr/envs.lua:41-44`) — Hyprland reports XWayland outputs at scale 1 / physical pixels and does **not** stretch XWayland surfaces. Under force-zero-scaling, `GDK_SCALE` is the app's *own* physical-pixel render factor:

- No blurriness either way — buffers map 1:1 to physical px; the choice is purely **size fidelity**: on a monitor at scale `s`, a `GDK_SCALE = g` app appears `g/s` the size of its native-Wayland peers.
- All-1.25 setup: round→1 = apps at 0.8× (small but crisp); ceil→2 = 1.6× (large but crisp). `round` is nearest-to-intended size; `ceil` systematically oversizes on every sub-1.5 setup — a *regression* in fidelity, not a sharpness win.
- `round(max)` (D-09) additionally keeps the global correct on mixed setups: 1.25+1.6 → max 1.6 → 2, vs today where scaling the 1.25 display would write 1 and shrink apps everywhere.
- Stock comment already says "nearest integer" (`config/hypr/monitors.lua:16-20`); the sed pass (`bin/omarchy-hyprland-monitor-scaling:479-482`) only needs the *value* changed from `int(new_scale+0.5)` (`:106`) to `int(max(all live scales ∪ new_scale)+0.5)` — max over the other monitors' reported scales and the target's new scale, computed from the same full monitors JSON the recompute already needs. `hyprctl monitors -j` (non-`all`) correctly excludes disabled/mirror outputs from the max.

### Q7 — Test strategy

Current suite (`test/shell.d/monitor-scaling-test.sh`) is **end-to-end only**: a stub `hyprctl` on `PATH` (`:18-42`) emits a fixed 1-or-2-monitor JSON (env-switched via `OMARCHY_TEST_*`) and logs eval args to `$OMARCHY_TEST_HYPRCTL_EVAL_OUT`; `run_scaling` (`:182-194`) runs the real script under a fake `$HOME`; assertions grep the eval capture + `monitors.lua` + audit log. Fixture-writer convention `write_<name>_config()` per `monitors.lua` shape (`:44-180`).

Two-layer recommendation:

1. **Pure-function layer for the geometry truth-table.** Make the script sourceable by guarding the dispatch `case` (`:544-590`) with `if [[ ${BASH_SOURCE[0]} == "$0" ]]` — a ~2-line refactor, zero behavior change when executed, no precedent conflicts. Then the test does `source "$ROOT/bin/omarchy-hyprland-monitor-scaling"` and calls a `recompute_monitor_position <monitors-json|@tsv> <target> <new-scale>` function directly, asserting `"XxY"` output + exit status (add a distinct status/stderr for abort). ~15 geometry cases run in microseconds without stub plumbing.
   *Fallback if the planner rejects sourcing:* end-to-end only — grow the stub with `OMARCHY_TEST_MONITORS_JSON` (raw pass-through) and assert `eval_out` per case. Slower and conflates recompute with persistence assertions, but needs no script refactor.
2. **End-to-end layer for integration.** Stub growth: `OMARCHY_TEST_MONITORS_JSON` for arbitrary layouts (3-monitor sandwich, portrait `transform`, gaps); `transform`/`reserved` fields; a `OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL` knob so the stub returns different JSON after the first `eval` — exercises D-07's verify-read audit warning.

**Existing assertions that WILL change** (update in the same commit):
- `monitor-scaling-test.sh:482-485` — `OMARCHY_TEST_EXTERNAL_MONITOR=1 run_scaling 2.5 HDMI-A-1` currently asserts `position = "-1200x0"` in eval and in the appended rule. Fixture has HDMI `-1200x0@1.6` (1920 wide → right edge 0) adjacent to eDP-1 at `0x0` — under Phase 3 the recompute yields `-768x0` (1920/2.5). Same for `up HDMI-A-1` (`:496-500`): 1.6→2 → `-960x0`.
- Single-monitor assertions (`position = "0x0"`) are unaffected — no neighbors, no recompute.
- GDK assertions on single-monitor fixtures unaffected (max == target scale).

### Q8 — Other failure modes found reading the script (in-scope-adjacent)

- **`transform` is silently reset by the live eval.** `hl.monitor({output, mode, position, scale})` (`:111`) omits `transform`/`mirror`/`sdr*`/`bitdepth`/reserved — rescaling a portrait monitor **un-rotates it live**, and the appended rule (`:466`) never writes `transform`, so reload un-rotates an unlisted portrait monitor. Also breaks Q5's geometry (logical w/h swap). Fix: read `.transform` in `set_scale` (`:84-95`), emit `transform = N` in the eval + appended rule when non-zero. In scope-adjacent and needed for correct portrait adjacency.
- **`hyprctl eval` output/errors are discarded** (`:111`, `>/dev/null`, no status check). A failed eval still proceeds to persist → file/live divergence. D-07's verify-read is the real safety; consider also capturing stderr for the audit log.
- **Triple `hyprctl monitors -j` fetch:** `up`/`down` arms fetch (`:561-576`), then `set_scale` fetches again (`:79`). Geometry/scale can drift between reads. Recommend `set_scale` fetch the full array once (`monitors_json=$(hyprctl monitors -j)` at `:79`) and derive `monitor_info` from it — the full array is needed anyway for neighbors + GDK max.
- **`persist_monitor_scale` takes 13 positional params** (`:125-127`) — don't add two more; pass recomputed x,y through the existing `x`/`y` slots (used only at `:466`).
- **Audit-log extension is safe only if appended at end:** tests grep `requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1` mid-line (`monitor-scaling-test.sh:205`); new fields (`pos=`, `note=adjacency|clamp|abort|scale-divergence`) must go after `grandparent=` (`:42-52`).
- **Reported scale precision:** older HyprCtl emits `"scale": %.2f` — treat all reported scales as ±0.005; round logical dims to nearest int when within ~0.5 before edge math (bakes noise out), and use tolerance in the D-07 verify (Q1).
- **`monitors -j` (non-`all`) is the right input** — it already excludes disabled and mirror outputs; do *not* switch to `all` for adjacency (would add phantom boxes at mirror hosts' positions).
- **`jq -e` guard chain is fine** — unknown/disabled/unsafe names exit before any eval or write (`:79-101`), covered by tests `:502-526`.
- **Pre-existing overlap can still fire Hyprland's notification** on every reload our file write triggers (`checkMonitorOverlaps` checks *all* monitors) — we can't fix third-party overlap; just don't create new ones (D-04).

---

## Recommended approach

One-file change to `bin/omarchy-hyprland-monitor-scaling` + test extension, in this order:

1. **Single fetch:** `monitors_json=$(hyprctl monitors -j)` once in `set_scale`; derive `monitor_info` from it. Read `transform` too.
2. **`recompute_monitor_position`** — pure function (jq → TSV → awk) implementing the Q5 algorithm; returns `X Y` (live coords if unchanged; sentinel for abort). Gate dispatch behind `[[ ${BASH_SOURCE[0]} == "$0" ]]` so tests can `source` and unit-test it.
3. **Atomic eval (D-07):** emit `hl.monitor({ output, mode, position = "<new>", scale = <clean>, [transform] })` once — replacing live-x/y replay at `:111`.
4. **Verify-read:** re-fetch `monitors -j`, compare applied scale to `new_scale` within `|Δ| < ~0.006` (or the `·120`-grid variant); audit-log on divergence.
5. **`persist_monitor_scale`:** pass recomputed x,y (existing slots), `OMARCHY_NEW_POSITION` env + changed-flag into awk; apply scale+position edits via a descending-offset edit list; rewrite `position` only when changed and non-`auto*` (planner decision — see Q4).
6. **GDK:** `new_gdk_scale = int(0.5 + max(new_scale, other monitors' scales))` — keep `round`, per Q6.
7. **Audit:** append `pos=`/`note=` fields at end of the TSV line.
8. **Tests:** extend `monitor-scaling-test.sh` per Q7 — update `:482-500` expectations, add stub JSON knob + post-eval knob, add unit layer for the geometry truth-table.

## Open questions / risks

1. **Reported-scale precision** — is `.scale` full-float or `%.2f` on the installed Hyprland? Affects TOL headroom (a 1.33-reported scale distorts a 1920-wide logical edge ~3.6 px). Check `hyprctl monitors -j | jq '.[].scale'` live; if 2-decimal, consider TOL ≈ 6–8 px or derive edges by rounding `w/scale` to int.
2. **`position = "auto*"` rewrite policy** (Q4 decision point) — recommended: skip auto* values, rewrite literals only when changed.
3. **D-03 tie-break reading** — "prefer left/top": recommended reading keeps the target's top-left edge pinned (minimal move). Confirm in plan.
4. **`transform`/reserved/mirror replay in the eval** — recommended in scope (transform is required for correct portrait math); sdr/bitdepth/vrr/`cm` fields remain unreplayed (rare; note as residual).
5. **`disable_scale_checks` / Hyprland upgrades** — covered by D-07 verify-read; no further action.
6. **Reserved areas** — confirmed irrelevant to the overlap box (`logicalBox` vs `logicalBoxMinusReserved`); ignore `reserved` in edge math.
7. **Pre-existing third-monitor overlaps elsewhere in the layout** will still fire Hyprland's notification on the reload our write triggers — not ours to fix; audit-warn only on *our* recompute aborting.

## Validation Architecture

Requirement → test mapping (all in `test/shell.d/monitor-scaling-test.sh` unless noted; pure-function cases assume the `BASH_SOURCE` guard + direct `recompute_monitor_position` call, returning `XxY` or an abort status):

### SCALE-08 — adjacency preserved, no new overlaps/gaps

| Test name (sketch) | Fixture shape | Expected |
|---|---|---|
| `recompute keeps left-adjacent on grow` | JSON: eDP `0x0` 2880×1800@2; HDMI `-1200x0` 1920×1080@1.6; scale 1.5 | `-1280x0` |
| `recompute keeps left-adjacent on shrink` | same; scale 2 | `-960x0` |
| `recompute pins left edge for right-of neighbor` | target at `1440x0`, neighbor `[0,1440]`; grow | x unchanged, extends right |
| `recompute keeps above/below adjacency` | vertical stack fixtures (both directions) | y' = `m.t−nlh` / `m.b` |
| `recompute normalizes ≤5px gap and ≤5px overlap` | edges off by ±1..5 px | touching after rescale |
| `recompute preserves >5px gap exactly` | gap 50 px | position unchanged (D-06) |
| `recompute handles float-noise adjacency` | reported scale `1.3333334` (lw 1439.9999) | counts as adjacent |
| `recompute sandwich keeps largest shared edge` | 3 monitors, target adjacent to two opposite-edge neighbors, unequal overlaps | anchors to larger; audit `note=` |
| `recompute sandwich tie pins top-left` | equal shared edges | x' keeps left edge |
| `recompute aborts on new third-monitor overlap` | recompute would hit a third box | original x,y + audit warn (D-04) |
| `recompute clamps non-adjacent growth` | floating target grows into neighbor | `x' = m.l − nlw` (minimal shift, D-05) |
| `recompute handles transform=1 target and neighbor` | portrait fixtures | w/h swapped correctly |
| `e2e: eval carries scale+recomputed position in one call` | stub 2-monitor JSON; run CLI | single `eval_out` line has both (D-07) |
| `e2e: verify-read warns on scale divergence` | `OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL` returns different scale | audit-log divergence note |
| `e2e: existing targeted test` | current `OMARCHY_TEST_EXTERNAL_MONITOR` fixture | `-768x0` for `2.5`, `-960x0` for `up` (update `:482-500`) |

### SCALE-09 — recomputed position persists in-place

| Test name | Fixture shape | Expected |
|---|---|---|
| `persists recomputed position on named literal rule` | `hl.monitor({ output = "HDMI-A-1", ..., position = "-1200x0", scale = 1.6 })` + recompute | in-place `position = "-1280x0"` + `scale = 1.5`, byte-identical elsewhere |
| `persists position inside a multi-line rule` | `write_multiline_rule_config` shape w/ literal position | position line rewritten, other lines untouched |
| `position rewrite order-safe` | rule with `scale` *before* `position` and vice-versa | both rewritten correctly (descending-offset edits) |
| `skips position write on auto* values` | named rule `position = "auto"` + changed position | `auto` preserved (if planner accepts Q4 recommendation) |
| `unchanged position not churned` | recompute == live | `position` line byte-identical |
| `append path uses recomputed position` | catch-all-only config | appended single-line rule has `-1280x0` |

### SCALE-10 — GDK_SCALE = round(max(scales))

| Test name | Fixture shape | Expected |
|---|---|---|
| `gdk scale tracks max of monitors` | stub JSON: target→1.25, other@1.6 | `local omarchy_gdk_scale = 2` (not 1) |
| `gdk scale unaffected on single monitor` | existing fixtures | current assertions hold |
| `gdk scale rounds max` | max 1.25 → `= 1`; max 1.6 → `= 2` | both `local` and literal `hl.env` forms |

Cross-cutting: re-run `monitor-clamshell-scale-test.sh` (appended-line contract unchanged — still single-line, name-keyed, explicit `position`), `test/cli` metadata lint (no CLI surface change unless a debug arg is added), and `monitor-state-test.sh` (bare invocation contract untouched).
