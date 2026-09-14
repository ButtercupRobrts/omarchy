# Phase 1 Research: Per-monitor scale persistence in the scaling CLI

**Researched:** 2026-09-14
**For:** PLAN of phase 1 (SCALE-01..SCALE-04), decisions D-01..D-05 already locked in `01-CONTEXT.md`

---

## Findings

### 1. The bug mechanism, precisely (why the panel "silently reverts")

`set_scale()` applies the new scale live via `hyprctl eval` (`bin/omarchy-hyprland-monitor-scaling:97`), which works momentarily even when a named rule exists. Then the `sed -i` persistence write to `monitors.lua` trips Hyprland's **config auto-reload**, which clears runtime rules and re-applies the file's stale rule — undoing the eval before it is visible (upstream issue #9950, PR #8300 body, measured on Hyprland 0.56.2). Separately, `omarchy-hyprland-monitor-watch` runs `omarchy-hyprland-monitor-clamshell` on every monitor event and (while docked) every ~2 s; clamshell re-reads `monitors.lua` as ground truth and re-applies its scale/position (`bin/omarchy-hyprland-monitor-clamshell:176-199`), so a stale file scale is actively reverted, not just lost at reboot (PR #8982 body; `bin/omarchy-hyprland-monitor-watch:16-25, 63-68`).

### 2. Hyprland monitor-rule semantics — verified in source

Read `src/config/shared/monitor/MonitorRuleManager.cpp` (hyprwm/Hyprland @ a2636192) and `src/helpers/Monitor.cpp`:

- **`add(CMonitorRule)`** does `erase_if(m_rules, e.m_name == x.m_name); push_back(x)` — rules are keyed by the **raw `output` string**. A runtime `hl.monitor({ output = "eDP-1" ... })` erases a file rule with the identical name string, but **not** a `desc:`-keyed rule that resolves to the same monitor (different `m_name`; both coexist, later one wins).
- **`get(PHLMONITOR)`** iterates `m_rules` in **reverse** — the *last* matching named rule wins. If nothing matches, a second loop returns the first rule with `m_name.empty()` — i.e. `output = ""` is a true fallback, applied only when no named rule matched. **Consequence: a named `hl.monitor` line beats the catch-all regardless of where it sits in the file, and an appended named line always wins over an earlier same-name entry.** This is the formal basis for D-01's append path and D-02's "never touch the catch-all."
- **`matchesStaticSelector`** (Monitor.cpp, latest behavior per commit 2e2e2e2 "bring back old description behavior"): `output` equal to connector name, **or** `desc:<text>` where the monitor's `szDescription` **or** `szShortDescription` (trimmed `"{make} {model} {serial}"`, commas stripped from both) **starts with** the selector text. The selector is trimmed before comparing (PR #8300's awk mirrors this; its tests cover `"desc:  BOE NE180WUM  "`). For matching we need `.description`, `.make`, `.model`, `.serial` from `hyprctl monitors -j`.
- **Unspecified rule fields reset to defaults** — `CMonitorRule` defaults are `m_scale = -1` (auto), `m_offset = {-INT32_MAX,-INT32_MAX}` (auto), empty resolution (preferred) (`MonitorRule.hpp`). An eval'd `hl.monitor()` therefore **fully replaces** the same-named rule; there is no field inheritance. PR #7495's claim that "omitted fields inherit the monitor's existing declaration" is inaccurate — omitting `position` yields `auto`, which merely happens to preserve an already-placed monitor's current coordinates.
- **`hyprctl keyword monitor` does not exist under Lua config** — it fails with `keyword can't work with non-legacy parsers. Use eval.` (hyprmon PR #83; omarchy issue #6968). `hyprctl eval "hl.monitor(...)"` is the only runtime path. Runtime rules are temporary: a config reload clears them and re-applies file rules.
- **Runtime `desc:` rules never apply to connected outputs** (hyprwm/Hyprland issue #15961): `hl.monitor({ output = "desc:..." })` via eval is accepted but ignored for already-connected monitors. We always eval by **connector name**, so this doesn't bite — but it's why the live apply must not translate to desc:.
- **Scale validity**: the wiki states a valid scale "must divide your resolution cleanly (without decimals)". `clean_scale()` (`bin/omarchy-hyprland-monitor-scaling:58-68`) computes `g = gcd(w*120, h*120)` and snaps the request up to the nearest divisor of `g` in 1/120 units — correct: any divisor of `gcd(w,h)`-scaled-by-120 divides both dimensions evenly. Unchanged this phase.
- `position` accepts negative values (`-1200x0`), `auto`, `auto-right/left/up/down`, `auto-center-*`. `hyprctl monitors -j` reports live `x`, `y` (PR #7840's repro uses `jq '.x, .y'`).

### 3. The `position = "auto"` debate (D-04's locked answer has a known trade-off)

- **PR #7840** (closed) implements exactly D-04: read live `x`/`y`, pass `position = "XxY"` — verified to fix monitor-swap on scale change.
- **PR #7495** (open) instead omits `position` entirely, arguing explicit coordinates *pin* an auto-arranged monitor so it no longer reflows when a neighbor's logical size changes. True but bounded: the pin lives in the runtime rule only until the next reload, which restores the file rule. D-04 is locked to live x/y replay — planner should note the residual: a monitor whose *file* rule says `auto` will sit at pinned coords for the rest of the session.
- **Issue #10922** documents Hyprland-side quirks on any rule re-application (auto-positioned neighbors reflowing, stray vertical offsets not fixed by `reload`). Our file write triggers a full reload — some reflow of *other* auto-positioned monitors is inherent Hyprland behavior, out of our control.

### 4. `monitors.lua` real-world shapes (fixtures to support)

Shipped default (`config/hypr/monitors.lua`): `local omarchy_monitor_scale = "auto"` + `hl.monitor({ output = "", ..., scale = omarchy_monitor_scale })` + `local omarchy_gdk_scale` + `hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))`; commented examples invite per-monitor lines. Observed/needed shapes:

- Single-line named rule, literal scale or `scale = omarchy_monitor_scale` (PR #11414's test fixture; issue #9950).
- Multi-line `hl.monitor({\n  output = "eDP-1",\n  ...\n})` — what **nwg-displays** writes (PR #8300/#8808 fixtures).
- `desc:` selectors — the standard advice for connector renumbering across hotplug (PR #8300 tests, #8808; issue #9950 thread).
- Rule with **no** `scale` field (`transform`-only rules) — scale must be *inserted* before the closing `}`.
- `;` separators (legal Lua), nested tables (`reserved_area = { top = 24 }`), trailing `-- comments`, `--[[ ]]` block comments (possibly multi-line) containing fake rules, keys spaced as `output  =  "eDP-1"`, quoted scale `"auto"`, variable-referenced scale/position — all have fixtures in `test/shell.d/monitor-clamshell-scale-test.sh` and PR #8300's test additions.
- Braces/parens **inside quoted values** — a `desc:` selector cut mid-parenthesis (`"desc:LG Electronics (LG HDR"`) breaks naive `{`/`}` depth counting; #8300 counts braces on a copy with string contents blanked (`outside_strings`). **Must-have**, not optional.
- Symlinked `monitors.lua` (dotfiles repos) — `sed -i` and `mv tmp file` both silently detach the link (issue #7625; PR #8300 uses `cat tmp > file` + `sed -i --follow-symlinks`; repo convention already uses `sed --follow-symlinks -i` in `bin/omarchy-display-text-size:146`, `bin/omarchy-font-set:37`).

### 5. Parsing strategy: awk, not sed — the machinery is already proven

sed cannot span multi-line entries. The clamshell parser's limits (`monitor_rule_regex`, `bin/omarchy-hyprland-monitor-clamshell:77-89`) — single-line only, name-keyed only — define the **output contract for appended lines**: always emit single-line `hl.monitor({ output = "NAME", mode = "WxH@R", position = "XxY", scale = S })` (CONTEXT code_context line 76 mandates this). For the *read/rewrite* side, upstream PRs supply a proven design:

- **PR #8300** (open, the most complete): a single awk pass that (a) blanks comments to spaces preserving byte offsets, tracking multi-line `--[[ ]]` state; (b) counts `{`/`}`/`(`/`)` depth on a copy with quoted strings emptied; (c) captures each `hl.monitor(...)` block (multi-line aware); (d) extracts `output = "..."` and matches name or `desc:` prefix against the monitor's description passed via `ENVIRON` (not `-v`, which would eat backslashes in EDID text); (e) rewrites the `scale` field at the same offsets in the original text, or inserts `, scale = N` / ` scale = N` before the block's last `}` honoring `,` vs `;` separator style; (f) distinct exit codes for "rewrote", "no rule names this output", "unreadable"; (g) `cat` over the target instead of `mv`.
- **PR #8808** (open, complementary): adds multi-line folding, `regex_escape`, and `internal_rule_key` (prefer exact connector match, else first `desc:`-prefixed rule) to the *clamshell* parser. Not merged; our writes must stay compatible with the parser as it exists today (single-line name-keyed appends satisfy both versions).
- **PR #11414** (open, competing): `index($0, "output = \"name\"")` + `sub(/scale = [^, }]+/)` — misses multi-line, desc:, spaced keys, commented-out rules, missing-scale insertion, append fallback, backup, symlink. Copilot review flagged unresolved matching/parsing/GDK gaps. Do not copy.
- **PR #8145**: earlier take with the same append-fallback idea but `mv`-based write (detaches symlinks), only two `output=` spacings, no desc:, non-string-aware brace counting.
- **PR #8982**: same named-rule persistence idea buried in a 190-file stale branch; its diagnostic value is the watcher-revert mechanism (finding 1 above).
- **Issue #9950 reporter comments**: a full alternative design (identity-keyed state file `~/.local/state/omarchy/hypr-monitor-scales` + Lua `SyncMonitorScales()` in monitors.lua). Rejected implicitly by D-01 (we persist in-file), but its discovered bugs inform us: (a) Lua module state persists across `hyprctl reload` — irrelevant to our bash approach; (b) `auto-right` resolution raced modeset on reload, swapping monitor sides — residual risk for any reload, mitigated because appended lines carry explicit live positions; (c) `quickshell`'s PATH puts `/usr/share/omarchy/bin` before `/usr/local/bin` — only relevant to local wrapper testing, not to us.

### 6. What D-02 means for the default config (important — changes existing test expectations)

Under D-01+D-02 the two existing persistence branches (`bin/omarchy-hyprland-monitor-scaling:102-112`) are **deleted entirely**. On a stock config, the targeted monitor has no named rule → we **append** one; `local omarchy_monitor_scale` is left untouched. SCALE-03 ("no regression for default configs") is satisfied because the appended named line beats the catch-all by rule semantics (finding 2) and persists. **Consequence: `test/shell.d/monitor-scaling-test.sh` assertions like `grep -Fx 'local omarchy_monitor_scale = 3'` (lines 51, 58, 70, 79, 85, 101, 129) are now assertions of the bug and must be rewritten** to assert the appended line and the *unchanged* variable. GDK locals (`omarchy_gdk_scale`, literal `hl.env("GDK_SCALE", "N")`) keep being updated to nearest-integer on every persist path, per CONTEXT discretion — but see risk R4.

### 7. CLI surface and callers

- Callers today: `default/hypr/bindings/tiling.lua:97-98` (`up`/`down`, focused), `shell/plugins/panels/monitor/Panel.qml:308` (`bash -c "omarchy-hyprland-monitor-scaling " + scale` — Phase 2 appends the screen name here), `bin/omarchy-monitor-state:20` (no-arg read of focused scale — unchanged).
- `up`/`down` currently select `.focused` twice (`:182-189`); with D-03 both branches need target-by-name. Reusable jq pattern exists in `bin/omarchy-hyprland-monitor-focused-apple`: `select(if $monitor == "" then .focused == true else .name == $monitor end)`.
- The `[monitor]` arg must pass the existing name regex `^[A-Za-z0-9._-]+$` (`:86`) before being written into Lua/eval strings; desc:-style args with spaces will fail it — acceptable (panel passes connector names).
- `jq -e` on the selector returns non-zero/empty for an unknown or disabled monitor — needs an explicit error exit (script has no `set -e`; per CONCERNS don't rely on abort-on-error).
- Header metadata: update `# omarchy:args=[up|down|SCALE]` → `[up|down|SCALE] [monitor]`, `usage()`, and add a targeted example (`test/cli` lints metadata).
- Audit log format unchanged; `monitor=` now records the target rather than always-focused.

---

## Recommended implementation shape

One-file change to `bin/omarchy-hyprland-monitor-scaling`, plus test extension.

1. **Target resolution**: `target_monitor="${2:-}"` (or restructure dispatch to take `$2`); resolve `monitor_info` via the `--arg monitor` jq pattern above; `jq -e` failure → `echo ... >&2; exit 1`. Validate target name against `^[A-Za-z0-9._-]+$` (reuse the existing guard comment — it applies to the file write too).
2. **Live apply** (D-04): extract `x`, `y` from `monitor_info`; `hyprctl eval "hl.monitor({ output = \"$name\", mode = \"${w}x${h}@${rr}\", position = \"${x}x${y}\", scale = $new_scale })"`. Keep mode/scale order; always connector name (never desc:).
3. **Backup** (D-05): when `monitors.lua` exists and a write will occur, `cp -- "$monitor_lua" "$monitor_lua.bak.$(date +%s)"` — mirrors `omarchy-refresh-config:22,31-32` (plain `cp` resolves the symlink and backs up content; fine).
4. **Persistence** (D-01/D-02): a single awk program over `monitors.lua`, #8300-shaped:
   - `blank(line)`: comments → spaces at same offsets; `in_block` state for multi-line `--[[ ]]`.
   - `outside_strings(blank)`: quoted contents → spaces, for brace counting only.
   - Block capture: at depth 0, bare line matching `hl\.monitor[[:space:]]*\(` starts accumulation until depth returns to 0; non-block lines print verbatim.
   - `names_monitor(block)`: extract `output[[:space:]]*=[[:space:]]*"..."`; match `== name`, or `desc:` + trimmed selector is a prefix of `description` or reconstructed `"{make} {model} {serial}"`. **`output = ""` never matches** (target name is non-empty) — this is what enforces D-02 mechanically.
   - Rewrite: find `scale` as a key preceded by a table separator (`[{,;[:space:]]scale[[:space:]]*=`) on the blanked block, splice `scale = N` into the original at the same offsets; if absent, insert before the block's final `}` — ` scale = N` if the last non-space char is `,`/`;`, else `, scale = N`.
   - Rewrite **all** matching blocks (Hyprland's last-wins makes the later one effective; rewriting all keeps stale copies from resurfacing if a later rule is deleted — #8300 does the same).
   - Exit: `0` = rewrote ≥1 → `cat "$tmp" > "$monitor_lua"` (symlink-safe); sentinel (e.g. `3`) = no rule matched → append single-line `hl.monitor({ output = "$name", mode = "${w}x${h}@${rr}", position = "${x}x${y}", scale = $new_scale })`; `1` = read failure → warn, no write.
   - Pass `description`/`make`/`model`/`serial` through `ENVIRON`, not `-v` (backslash-escape hazard in EDID text).
5. **GDK**: keep both existing update forms (`local omarchy_gdk_scale = N`; literal `hl.env("GDK_SCALE", "N")`), run on every persist path, using `sed -i --follow-symlinks` or fold into the same awk pass. `tostring(omarchy_gdk_scale)` form needs no match — the local covers it.
6. **Missing `monitors.lua`**: recommend keep current behavior — live apply, skip persistence silently (or warn to stderr; planner's call). Do not create the file: its absence can be deliberate (e.g. user manages monitors elsewhere).
7. **Dispatch**: `up|down|SCALE [monitor]`; bare call still prints focused scale; reject >2 args or a second arg on the bare-read form via `usage`.
8. **Keep unchanged**: `clean_scale`, `scale_from_current`, `audit_scale_change` format, `SCALES` presets, the 1..4 numeric validation, no `set -euo pipefail` (consistent with the script's existing guard-based style).

---

## Edge cases table

| Case | Expected behavior | Why / source |
|------|-------------------|--------------|
| Named single-line rule exists | In-place `scale` rewrite; catch-all/variable untouched | D-01; #11414 test shape |
| Named rule, multi-line | Rewrite `scale` line inside block, preserve formatting | D-01/SCALE-04; nwg-displays shape (#8300) |
| Named rule, `scale` absent | Insert `, scale = N` (or ` scale = N` after trailing `,`/`;`) before closing `}` | D-01; #8300 tests |
| Rule keyed `desc:` matching target | Rewrite that rule in place, keep `desc:` selector (hotplug-resilient) | SCALE-04; selector = prefix of `description` or `{make} {model} {serial}` |
| `desc:` selector with interior spaces (`"desc:  Foo  "`) | Trim selector before prefix-compare | Hyprland trims; #8300 test |
| `desc:` value containing `(`/`)`/`{`/`}` | Doesn't break block boundary — count braces on string-blanked copy | #8300 `outside_strings` + test |
| Rule inside `--[[ ]]` or after `--` | Not matched; falls through to append | #8300 tests; comment-blanking required |
| Trailing `-- comment` inside/after block | Insertion lands in the table, not in the comment | #8300 tests |
| `;` separators | Insertion respects `;` style | Lua-legal; #8300 test |
| `scale = omarchy_monitor_scale` in target's rule | Rewritten to literal — targeting pins it | D-01; deliberate |
| `scale = "auto"` or expression `3 / 2` in target's rule | Rewritten to literal | Same — the field is replaced, not evaluated |
| Stock config (variable or literal catch-all), target unlisted | **Append** named line; variable and catch-all untouched | D-01+D-02; SCALE-03 |
| Another monitor's rule reads `omarchy_monitor_scale`, target unlisted | Append only — never write the variable | D-02; #8300's status-4 case |
| Multiple rules match target (name + desc:) | Rewrite all matching | Last wins in Hyprland; consistency |
| `monitors.lua` missing | Live apply still works; no file created (recommend warn) | Planner decision; current behavior = silent skip |
| `monitors.lua` unreadable | Error, no partial write | #8300 distinguishes from "no match" |
| `monitors.lua` is a symlink | Write through it (`cat >` / `--follow-symlinks`); still a symlink after | #7625; #8300 test |
| Target `[monitor]` not in `hyprctl monitors -j` (disabled/absent/typo) | Error exit, no eval, no write | jq `-e` + explicit guard |
| Unsafe monitor arg (`eDP-1"...`) | Rejected by `^[A-Za-z0-9._-]+$` before Lua embedding | Existing guard `:86`; `monitor-output-name-test.sh` pattern |
| Scale outside 1..4 / non-numeric | usage error (existing) | `:194-201` unchanged |
| GDK_SCALE when scale fractional | Nearest integer, as today | CONTEXT discretion; `#8300` multi-display caveat = R4 |
| Mirrored monitors | `mirror` rules named by their own output; mirror target uses host name — out of scope, note only | Wiki mirror section |

---

## Test plan sketch

Extend `test/shell.d/monitor-scaling-test.sh` per `base-test.sh` conventions (stub `bin/hyprctl`, fake `$HOME`, `trap` cleanup). The stub must grow: `x`, `y`, `description`, `make`, `model`, `serial` fields; optional second monitor + per-monitor `focused`; keep `OMARCHY_TEST_HYPRCTL_EVAL_OUT` capture.

**Must-update existing assertions** (all currently assert the deleted variable-rewrite path): lines 51, 58, 70, 79, 85, 101-102, 129-130 — re-point to appended-line assertions + `local omarchy_monitor_scale` *unchanged*.

**New cases (mapped to decisions/requirements):**

1. Stock variable config → appended `hl.monitor({ output = "eDP-1", mode = "...", position = "0x0", scale = N })`; variable + `omarchy_gdk_scale` behavior (variable stays, GDK local updates). *(D-01/D-02, SCALE-03)*
2. Stock literal catch-all → same append path. *(SCALE-03)*
3. Named rule w/ literal scale → in-place rewrite; other monitor's line + catch-all untouched. *(SCALE-01)*
4. Multi-line rule → scale rewritten on its own line. *(SCALE-04)*
5. Scale-less named rule → scale inserted. *(SCALE-04)*
6. `desc:`-keyed rule → rewritten in place; stub `description`. *(SCALE-04)*
7. Commented-out and `--[[ ]]`-enclosed rules → not matched; append happens instead. *(SCALE-04)*
8. `position` preservation: eval log contains `position = "<liveX>x<liveY>"`, never `"auto"`. *(D-04, SCALE-02)*
9. `[monitor]` arg: two-monitor stub, `scaling 1.6 HDMI-A-1` evals/appends for HDMI-A-1 while eDP-1 focused. *(D-03)*
10. `up`/`down` with `[monitor]` steps from *that* monitor's scale/geometry. *(D-03)*
11. `.bak.<timestamp>` created before rewrite/append. *(D-05)*
12. Missing `monitors.lua` → eval still runs, no file created (or warning asserted). *(edge)*
13. Unknown monitor arg → non-zero exit, no eval/write; unsafe name → rejected. *(edge/security)*
14. Symlinked `monitors.lua` → still a symlink, content updated. *(edge, #8300 pattern)*
15. `;` separators, spaced keys, braces-in-desc: — port #8300's load-bearing fixtures. *(SCALE-04)*
16. Run `monitor-clamshell-scale-test.sh` + `monitor-output-name-test.sh` after the change — the appended lines must remain readable by clamshell's parser (regression gate).

---

## Risks

- **R1 — Parser complexity in bash.** The rewrite needs comment-blanking + string-aware depth tracking + offset-preserving splice — ~100+ lines of awk (#8300's is ~150). Simpler folds (rewrite-then-unfold) destroy formatting; naive sed/index matching is exactly what #11414 got flagged for. Budget accordingly; port #8300's structure rather than inventing a third dialect — CONCERNS already flags the two-parsers drift problem.
- **R2 — Position pinning trade-off (D-04, accepted).** Replaying live x/y converts a `position = "auto"` monitor into pinned coords for the session (until reload). #7495 argues for omitting `position` instead; the locked decision stands, but document the behavioral note in the commit.
- **R3 — Reload side effects on other monitors.** Writing `monitors.lua` triggers a full config reload; auto-positioned *neighbors* can reflow (Hyprland quirk, issue #10922; #9950's reporter saw `auto-right` races). Appended explicit positions protect the target; neighbors remain Hyprland's problem.
- **R4 — GDK_SCALE multi-display critique.** #8300 argues rewriting one integer `GDK_SCALE` from display A's scale rescales XWayland windows on untouched display B (issue #7021) and gates on `enabled == 1`. CONTEXT discretion says keep current nearest-integer update — flag to planner whether to adopt the guard (cheap: `hyprctl monitors all -j` count) or defer to v2.
- **R5 — Test churn is load-bearing.** Roughly a third of the existing suite asserts the deleted persistence path; each must be re-pointed, not deleted, or coverage silently drops (CONTEXT requires the stock catch-all path stay covered).
- **R6 — `--` inside quoted strings.** Neither #8300's `blank()` nor clamshell's `monitor_rules` tracks quote state when stripping `--`, so `output = "desc:A--B"` would be misread. Shared known limitation; acceptable.
- **R7 — Lua string/expr scale values.** A target rule with `scale = "auto"` or `scale = f(x)` gets a literal splice — syntactically safe, semantically pins the monitor (intended), but the expression is discarded on write. Note in plan.
- **R8 — `omarchy-hyprland-monitor-clamshell` divergence stays.** Our appended lines are parser-compatible, but clamshell still can't read multi-line/desc: rules (upstream #8808 unmerged) — a user whose internal rule is desc:-keyed gets correct persistence from us but stale reads from clamshell. Out of Phase-1 scope; note for Phase 2/follow-up.
