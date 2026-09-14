# Phase 3: Scale-aware monitor position adjustment - Pattern Map

**Mapped:** 2026-09-14
**Files analyzed:** 2 modified + 3 read-only contract references
**Analogs found:** 2 / 2 (every modified file has in-repo analogs; the position-recompute awk pass composes existing jq→TSV→awk idioms — no new machinery dialect)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `bin/omarchy-hyprland-monitor-scaling` | utility (CLI command) | file-I/O + request-response (hyprctl IPC, `monitors.lua` rewrite) | itself (awk rewriter, `clean_scale`, `audit_scale_change` kept verbatim) + `bin/omarchy-chromium-copy-url-host` (BASH_SOURCE dispatch guard) + `bin/omarchy-plugin-list` (jq `@tsv` → `awk -F '\t'`) | exact (partial-file analogs) |
| `test/shell.d/monitor-scaling-test.sh` | test | file-I/O (stub `bin/`, fixture `monitors.lua`, eval/log capture) + direct `source` of the script under test | itself + `test/shell.d/windows-vm-compose-test.sh` (sources a `bin/` script, `:23-24`) + `test/shell.d/monitor-clamshell-scale-test.sh` (env-switched stub JSON, `:19-37`) | exact |
| `bin/omarchy-hyprland-monitor-clamshell` | — NOT MODIFIED — second `monitors.lua` parser | file-I/O (sed/regex single-line rule reader) | `monitor_rule_regex`/`configured_monitor_value`/`read_monitor_position` (`:77-89`, `:156-165`) define what position writes must stay parseable as | constraint only |
| `bin/omarchy-monitor-state` | — NOT MODIFIED — caller of the bare-arg contract | request-response (positional stdout) | `:20` calls `omarchy-hyprland-monitor-scaling` with no args | constraint only |
| `config/hypr/monitors.lua` | — NOT MODIFIED — shipped default config | reference for key order and `GDK_SCALE` semantics | `:8, :14, :16-22` document `output, mode, position, scale, transform` order and "nearest integer" GDK wording | constraint only |

## Pattern Assignments

### `bin/omarchy-hyprland-monitor-scaling` (utility, file-I/O + hyprctl IPC)

The file is its own primary analog: `clean_scale`, `audit_scale_change`, the awk Lua rewriter, and the dispatch `case` all stay. Excerpts below mark **KEEP** (unchanged machinery to mirror), **REPLACE** (the code being deleted), **EXTEND** (machinery gaining a sibling feature), and **ANALOG** (patterns imported from other files).

**Metadata header — KEEP verbatim** (`:1-5`). `args` already reads `[up|down|SCALE] [monitor]` from Phase 1; no metadata change → `test/cli` lint stays green untouched:

```bash
# omarchy:summary=Show, set, or adjust Hyprland monitor scaling
# omarchy:args=[up|down|SCALE] [monitor]
# omarchy:examples=omarchy hyprland monitor scaling | omarchy hyprland monitor scaling 1.6 | omarchy hyprland monitor scaling up | omarchy hyprland monitor scaling down | omarchy hyprland monitor scaling 1.6 HDMI-A-1
```

**Monitor fetch — REPLACE the per-field jq fan-out with a single array fetch** (`:78-94`). Current shape fetches once for the target row, then re-parses it 11×. New shape per RESEARCH step 1/Q8: `monitors_json=$(hyprctl monitors -j)` once, then `monitor_info=$(printf '%s\n' "$monitors_json" | jq -e -c --arg monitor "$target_monitor" '...select...')` — the `jq -e` + `|| { echo >&2; exit 1; }` guard chain is KEEP. The full array is needed anyway for neighbor geometry and the GDK max. Grow the field list with `local transform="$(echo "$monitor_info" | jq -r '.transform // 0')"` — the live eval currently drops `transform`/`mirror`/`reserved` (pre-existing bug, RESEARCH Q8: rescaling a portrait monitor un-rotates it live). Keep `monitors -j` (non-`all`) — it already excludes disabled and mirror outputs; `monitors all -j` would add phantom boxes at mirror hosts' positions (contrast `bin/omarchy-monitor-state:6`, `bin/omarchy-hyprland-monitor-clamshell:112` which legitimately need `all`).

**Unsafe-name guard — KEEP verbatim** (`:96-101`); the recomputed position must be computed *after* this gate so no unvalidated name reaches an eval or awk `-v`:

```bash
  if [[ ! $active_monitor =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Refusing unsafe monitor name" >&2
    exit 1
  fi
```

**`clean_scale` — KEEP verbatim** (`:55-68`). Its output is the authoritative applied scale for all position math (D-07): any `k` dividing `gcd(120w,120h)` passes Hyprland's integer-logical check untouched (RESEARCH Q1). The `awk -v` idiom here (`-v scale= -v width= -v height=`) is the convention for *trusted numeric* inputs — mirror it for the recompute's `target`/`new_scale`/`TOL` params (the name charset `^[A-Za-z0-9._-]+$` excludes backslashes, so `-v` is safe; see ENVIRON-vs-`-v` gotcha below).

**NEW — `recompute_monitor_position`** (pure function; the jq→TSV→awk idiom). **ANALOG: `bin/omarchy-plugin-list:35-46`** — the closest existing shape of `jq -r '... | @tsv' | awk -F '\t'`:

```bash
jq -r '
  .[] |
  [ .id, (if .enabled then "enabled" else "disabled" end), ... ] | @tsv
' <<<"$plugins" | awk -F '\t' '
  { printf "%-32s %-9s ...\n", $1, $2, ... }
'
```

(The process-substitution variant `done < <(jq -r '... | @tsv')` exists at `bin/omarchy-reminder:34` — pipe-into-awk is the better fit here.) Copy the pipeline shape verbatim: `printf '%s\n' "$monitors_json" | jq -r '.[] | [.name,.x,.y,.width,.height,.scale,(.transform//0)] | @tsv' | awk -F '\t' -v target=... -v new_scale=... -v tol=5 '...'` implementing the RESEARCH-Q5 algorithm (transform-swap w/h, per-axis adjacency candidates within TOL, largest-shared-edge pick, D-04 overlap fail-safe, D-05 minimal clamp). **Adapt:** the function must `return` statuses and print the three-field contract `"<X>x<Y> <kind> <dropped>"` (kind ∈ `unchanged|adjacency|clamp|abort`; dropped = `-` or comma-joined sacrificed sides) — never `exit` — because the BASH_SOURCE guard makes it callable from a sourced context where `exit` would kill the test file (see gotchas). Live `x,y` are the no-change return value; D-04 abort is signaled via the `kind` field (`abort` + live coords + `-`), not a distinct status — non-zero status is reserved for unusable input.

**Live apply — REPLACE verbatim-position replay with atomic scale+position eval** (`:109-111`, D-07). Current:

```bash
  # Replay the monitor's live position rather than "auto" so a runtime rule
  # cannot clobber a configured layout like -1200x0 until the next reload.
  hyprctl eval "hl.monitor({ output = \"$active_monitor\", mode = \"${width}x${height}@${refresh_rate}\", position = \"${x}x${y}\", scale = $new_scale })" >/dev/null
```

New shape: `"${new_x}x${new_y}"` from `recompute_monitor_position` (falling back to live `x,y` on abort), plus `, transform = $transform` appended when non-zero — absorbing the portrait un-rotation bug (RESEARCH Q8). Keep key order `output, mode, position, scale, transform` — that is the shipped order (`config/hypr/monitors.lua:14`: `position = "auto", scale = 1, transform = 1`) and the order every fixture/appended line uses. Do **not** split into two evals — the intermediate frame can flash a gap/overlap (D-07). Note `>/dev/null` and no status check today; consider capturing stderr for the audit line (RESEARCH Q8), minimum: keep the redirect.

**NEW — verify-read (D-07):** after the eval, re-fetch `hyprctl monitors -j` once and compare the target's applied scale to `new_scale` within `|Δ| < ~0.006` (or `|applied·120 − computed·120| < 0.75` — robust to `%.2f` reporting, RESEARCH Q1). Divergence → audit-log `note=scale-divergence` (and optional `omarchy-notification-send` — never `notify-send`, enforced by `test/shell.d/bin-style-test.sh:12-14`).

**Audit call — EXTEND by appending fields at END of the TSV line** (`:26-53`, call site `:112`). The `printf` field order is load-bearing — `monitor-scaling-test.sh:205` greps the contiguous mid-line substring `requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1` and `:489` greps `monitor=HDMI-A-1`. New `pos=`/`note=` fields go **after** `grandparent=%s`. Extend the signature with optional trailing params (`"${5:-}"` pos, `"${6:-}"` note) and append `\tpos=%s`/`\tnote=%s` clauses conditionally — `audit_scale_change` currently runs **before** `persist_monitor_scale` (`:112` vs `:114`), so the recompute must happen before `:112` or the audit call moves after recompute. Keep `mkdir -p ... || return 0` best-effort semantics (`:36`; no rotation, CONCERNS.md:134-136).

**GDK scale — REPLACE the target-derived value with max-of-monitors** (`:103-106`, D-09/Q6). Current:

```bash
  local new_gdk_scale="$(awk -v scale="$new_scale" 'BEGIN { printf "%d", int(scale + 0.5) }')"
```

New: `int(0.5 + max(new_scale, every other monitor's .scale))` from the same `monitors_json` the recompute consumes — `monitors -j` correctly excludes disabled/mirror outputs from the max. Keep **round** semantics (`int(x+0.5)`, "nearest integer" per `config/hypr/monitors.lua:16-20` and `xwayland.force_zero_scaling = true` at `default/hypr/envs.lua:41-44` — RESEARCH Q6).

**Awk rewriter — EXTEND with `position` key via descending-offset edit list.** Existing machinery (KEEP, mirror for position):

- `top_level_key(name)` (`:299-320`) — depth-1 keys only; prev-char separator + `=` lookahead makes `top_level_key("position")` safe against `my_position`/`positionX`
- `value_start`/`value_end` (`:324-350`) — depth-aware value termination, safe on expressions and blanked strings
- `rewrite_scale` (`:388-410`) — the template for `rewrite_position`, including its trailing-whitespace trim (`:393`)
- `process_block` (`:412-418`) — runs per matching block; position rewrite must run for **every** matching block (name + `desc:` duplicate pairs must not disagree)
- `END` exit contract (`:450`): `exit(matched > 0 ? 0 : 3)` — consumed by the `case $status` at `:454-474`

**CRITICAL REFACTOR — descending-offset edit list** (RESEARCH Q4): `rewrite_scale` splices `block_orig` immediately while `block_nostr`/`block_blank` keep *original* offsets. Adding a second splice behind it is a stale-offset bug whenever `position` precedes `scale` in the block (the common order — e.g. fixture `monitor-scaling-test.sh:177`: `position = "-1200x0", scale = 1.6`). Copy-vs-adapt: convert `rewrite_scale`'s splice into a **span collector** `(kstart, vend, "scale = N")` plus the same for `position`, plus insertion spans; then apply all edits to `block_orig` in **descending offset order**. Insertion points (before the block's final `}`) are always the highest offsets and so go first; two missing keys become one combined insertion reusing the `,`/`;`/`{` separator logic at `:404-408`. Behavior when `position` exists but holds `auto*` or a var ref: skip `auto*` values and only rewrite literals/var-refs when the recomputed value differs from live `x,y` (Q4 decision confirmed — `auto*` positions re-derive every reload so nothing goes stale).

**KEEP — append path already writes position** (`:460-468`). Only the *in-place* path needs new awk; the appended line picks up recomputed `x`/`y` for free through `$8`/`$9`, and gains `transform = N` when non-zero for the portrait fix:

```bash
    printf 'hl.monitor({ output = "%s", mode = "%sx%s@%s", position = "%sx%s", scale = %s })\n' \
      "$active_monitor" "$width" "$height" "$refresh_rate" "$x" "$y" "$new_scale" >>"$monitor_lua"
```

**KEEP — GDK sed pass runs on every persist path** (`:477-482`); only the *value* (`new_gdk_scale`) changes:

```bash
  sed -i --follow-symlinks -E \
    -e "s|^local omarchy_gdk_scale = .*|local omarchy_gdk_scale = ${new_gdk_scale}|" \
    -e 's|^hl\.env\("GDK_SCALE", ".*"\)|hl.env("GDK_SCALE", "'"$new_gdk_scale"'")|' \
    "$monitor_lua"
```

**Dispatch guard — ANALOG: `bin/omarchy-chromium-copy-url-host:48-50` / `bin/omarchy-chromium-ytdlp-host:194-196`** — wrap the top-level `if (( $# > 2 ))` + `case` block (`:544-590`) so the file is sourceable:

```bash
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
```

Adapted here as `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then` … `fi` around the existing `if`/`case` (no `main` refactor needed — smaller diff). The inverted precedent exists at `test/shell.d/base-test.sh:3-6` (abort-if-executed). A second, hackier precedent — `test/shell.d/windows-vm-compose-test.sh:23-24` does `set -- help; source "$ROOT/bin/omarchy-windows-vm"` against a script with *no* guard, relying on the `help)` arm being a no-op — confirms sourceability is an accepted repo pattern, but the guard is the clean form.

**Dispatch — KEEP `case` shape** (`:549-590`): `up`/`down` arms (`:560-577`) each fetch `hyprctl monitors -j` a second/third time — RESEARCH Q8 recommends threading the single fetch through, but the `--arg monitor` selector and `scale_from_current` pipe must stay verbatim. The bare `""` arm (`:550-556`, `focused_monitor_scale | normalize_scale`) is a positional contract — `bin/omarchy-monitor-state:20` consumes it; do not touch. Numeric validation `*` arm (`:581-588`) stays.

---

### `test/shell.d/monitor-scaling-test.sh` (test, stub/fixture + new unit layer)

**Analog:** itself (e2e structure kept) + `test/shell.d/windows-vm-compose-test.sh:23-24` (source-the-production-script precedent) + `monitor-clamshell-scale-test.sh:19-37` (env-switched stub JSON).

**Harness — KEEP verbatim** (`:1-16`): `set -euo pipefail`, base-test source, `mktemp -d` + `trap`, `stub_bin`/`eval_out`/`home_dir`/`monitor_lua`/`scale_log` paths.

**NEW — source the script under test for the unit layer.** Precedent (`windows-vm-compose-test.sh:23-24`):

```bash
set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
```

Adapted (with the guard in place, no `set --` shim needed — `$0` vs `${BASH_SOURCE[0]}` differ so dispatch is skipped):

```bash
source "$ROOT/bin/omarchy-hyprland-monitor-scaling"
```

Caveats the implementer must respect: top-level `SCALES=`/`STATE_DIR=`/`SCALE_LOG=` assignments (`bin/...:7-9`) execute at source time against the *test process's* env — keep `recompute_monitor_position` fully param/stdin-driven so the stale `STATE_DIR` binding never matters; and **never call `set_scale`/dispatch arms from the unit layer** — their `exit 1` paths (`:82`, `:100`, `:546`, etc.) would kill the test file outright (`test/shell:27` runs each file via `bash "$test"`).

**Unit-layer assertion shape — adapt the existing expected-failure idiom** (`:506-513`):

```bash
set +e
pos=$(recompute_monitor_position "$monitors_json" "HDMI-A-1" 1.5)
status=$?
set -e
(( status == 0 )) || fail "..."
[[ $pos == "-1280x0 adjacency -" ]] || fail "..." "actual: $pos"
```

Required because `pos=$(failing_func)` under `set -e` aborts the file — wrap exactly as the existing `run_scaling` status-capture blocks do.

**Stub `hyprctl` — KEEP shape, GROW knobs** (`:18-42`). Current:

```bash
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  internal=$(printf '{"name":"eDP-1","focused":true,"scale":%s,...}' ...)
  if [[ ${OMARCHY_TEST_EXTERNAL_MONITOR:-0} == "1" ]]; then
    printf '[%s,%s]' "$internal" '{...HDMI-A-1...-1200...}'
  else
    printf '[%s]' "$internal"
  fi
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"
```

Growth per RESEARCH Q7: (a) `OMARCHY_TEST_MONITORS_JSON` raw pass-through branch ahead of the fixture emission (arbitrary 3-monitor/portrait/gap layouts); (b) `OMARCHY_TEST_MONITORS_JSON_AFTER_EVAL` emitted when set **and** `$OMARCHY_TEST_HYPRCTL_EVAL_OUT` exists — the eval-out file doubles as the stub's post-eval state marker (stubs are fresh processes each call; state must travel through the filesystem; existing tests already `rm -f "$eval_out"` per case, `:481`, `:495`, `:504`); (c) `transform`/`reserved` fields in fixture JSON for portrait cases. Keep the `>` overwrite on eval capture — a single `eval_out` line is itself the D-07 "one atomic eval" assertion (`grep -Fc`/`wc -l` to assert single-line).

**Fixture writers — KEEP convention, add position-bearing shapes** (`:44-180`): one `write_<name>_config()` per `monitors.lua` shape, `<<'LUA'` heredocs, comment naming the property under test. Existing fixtures that already exercise position: `write_other_monitor_config` (`:175-180`, literal `position = "-1200x0"`), `write_scaleless_rule_config` (`:88-93`, `transform = 1`), `write_multiline_rule_config` (`:75-84`). New fixtures needed: named rule with literal position matching the recompute target (`position = "-1200x0"` on `HDMI-A-1`), a rule with `scale` **before** `position` and vice-versa (descending-offset coverage), `position = "auto"` named rule (skip-write case), and an unquoted var-ref position (shape exists in clamshell fixture `monitor-clamshell-scale-test.sh:139-143`: `position = omarchy_monitor_position`).

**Runner — KEEP `run_scaling` env convention** (`:182-194`), thread new `OMARCHY_TEST_*` vars through the same way:

```bash
run_scaling() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    ...
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
}
```

**Must-update assertions — `:482-500` (same commit).** The `OMARCHY_TEST_EXTERNAL_MONITOR` fixture (HDMI `-1200x0` 1920×1080@1.6, right edge = eDP's left edge `0`) becomes adjacent-aware: `run_scaling 2.5 HDMI-A-1` now yields `position = "-768x0"` (1920/2.5) in eval_out (`:484`) and in the appended rule (`:485`); `run_scaling up HDMI-A-1` (1.6→2) yields `-960x0`. Single-monitor `position = "0x0"` assertions (`:199`, `:211`, `:304`, …) are unaffected — no neighbors, no recompute. GDK assertions on single-monitor fixtures hold (max == target scale); add a divergence case (target→1.25 while other monitor @1.6 → `local omarchy_gdk_scale = 2`, not 1) per RESEARCH SCALE-10.

**Assertion idiom — KEEP** (`grep -F`/`grep -Fx` vs `$eval_out`/`$monitor_lua`/`$scale_log`, `|| fail`, one `pass` per case; negative checks as `! grep -F ... || fail`). Audit-log greps stay valid only if new fields append at line end (see gotchas).

---

### `bin/omarchy-hyprland-monitor-clamshell` — NOT MODIFIED (read-format contract)

Its sed/regex parser defines what persisted `position` must look like. `configured_monitor_value` (`:84-89`) extracts `key` values matching `"[^"]*"|[^,;}[:space:]]+` on single-line rules that also match `monitor_rule_regex` (`:77-79`); `read_monitor_position` (`:156-165`) then validates `^[-[:alnum:]_.+]+$` (a quoted `"-1280x0"` parses; the regex class already admits `-`). Constraints on this phase: appended rules stay **single-line, name-keyed, `,`-separated**; in-place `position = "XxY"` rewrites must keep the value a quoted literal or bare word; clamshell's `monitor_rules` (`:71-75`) only strips `--[[...]]` (not leveled `]==]`) and `--.*$` — do not emit shapes it must read but can't. Regression gate: re-run `monitor-clamshell-scale-test.sh`.

### `bin/omarchy-monitor-state` — NOT MODIFIED (bare-invocation contract)

`:20` runs `omarchy-hyprland-monitor-scaling` bare and `test/shell.d/monitor-state-test.sh` pins the 8-line positional output (`:32-34` warning: a dying helper shifts every field). The BASH_SOURCE guard must not change executed behavior; the `""` arm stays first-class.

### `config/hypr/monitors.lua` — NOT MODIFIED (semantics reference)

`:8` ships the `output, mode, position, scale` key order (with `transform` last at `:14`); `:16-20` documents GDK "nearest integer" — the round-vs-ceil decision (RESEARCH Q6: **round**) must keep this wording true.

## Shared Patterns

### Bash style (AGENTS.md / CONVENTIONS.md)
**Apply to:** all touched bash
`#!/bin/bash` shebang; two-space indent; `[[ ]]` for string/file tests, `(( ))` for numerics (`(( count < 50 ))`, never `-lt`); unquoted vars inside `[[ ]]`, quoted literals (`[[ $1 == "up" ]]`); `local` for function vars; lowercase snake_case functions; errors to stderr; quote strings/paths with spaces rather than `\ `-escaping. The scaling script intentionally has **no** `set -euo pipefail` — keep explicit `|| { ...; exit 1; }` guards (CONCERNS.md:145-150). Test files do use `set -euo pipefail`. No `notify-send` — `omarchy-notification-send` only (`bin-style-test.sh:12-14`).

### awk data-in conventions
**Source:** `bin/omarchy-hyprland-monitor-scaling:148-166` (env for untrusted text) vs `:59`, `:490`, `:583` (`-v` for trusted numerics); ENVIRON precedent also at `bin/omarchy-upgrade-to-quattro:1836`, `bin/omarchy-network-band:99`
**Apply to:** the recompute awk and the rewriter extension — `OMARCHY_NEW_POSITION` goes through `env`/`ENVIRON`; `target`/`new_scale`/`tol` go through `-v` (the name regex already excludes backslashes).

### jq → TSV → awk pipeline
**Source:** `bin/omarchy-plugin-list:35-46` (`jq -r '... | @tsv' | awk -F '\t'`), `bin/omarchy-reminder:34` (process-substitution variant), `bin/omarchy-weather-icon:14`
**Apply to:** `recompute_monitor_position` — project the monitors array to `[name,x,y,width,height,scale,transform//0] | @tsv`, consume with `awk -F '\t'`.

### Test harness conventions
**Source:** `test/shell.d/base-test.sh`, `docs/testing.md:120-137`
Stub the world, run the real code; fake `$HOME`/`XDG_STATE_HOME` + stub `bin/` on `PATH`; `trap ... EXIT` cleanup; `OMARCHY_TEST_*` env parameterizes stubs; `grep -F`/`|| fail` assertions; "assert the invariant, not the snapshot." New for this phase: `source "$ROOT/bin/<script>"` unit layer, precedent `windows-vm-compose-test.sh:23-24`.

## Gotchas

1. **Descending-offset splices are mandatory.** `block_nostr`/`block_blank` offsets refer to the *unmodified* block; the first `substr`-splice into `block_orig` invalidates every later offset. Collect `(offset, end, replacement)` spans for scale + position (rewrites and insertions), then apply highest-offset-first. Insertion points (before the closing `}`) are always highest → naturally first; combine two missing keys into one insertion reusing the `,`/`;`/`{` separator logic (`:398-409`).
2. **`block_nostr` has string interiors blanked — read `auto*` detection from `block_blank`.** `position = "auto"` shows up as `position = "    "` in `block_nostr`; `block_output` (`:356-365`) is the working example of locate-in-`nostr`/read-in-`blank`.
3. **Audit fields append at line END only.** `monitor-scaling-test.sh:205` greps a contiguous mid-line substring (`requested=...\tcurrent=...\tnew=...\tmonitor=...`); anything inserted before `grandparent=` breaks it. New `pos=`/`note=` go last.
4. **Sourced functions must `return`, never `exit`.** `set_scale` (`:82`, `:100`) and dispatch exits would terminate the sourcing test file (run via `bash "$test"`, `test/shell:27`); `recompute_monitor_position` needs status codes — non-zero is reserved for unusable input; D-04 abort is signaled in-band via the `kind` field (`abort`), not a distinct status or stderr marker.
5. **Top-level assignments run at source time.** `STATE_DIR`/`SCALE_LOG` (`:8-9`) bind to the sourcing shell's env — keep the pure function fully parameter-driven; the unit layer must not depend on them.
6. **`x`/`y` slots are free real estate.** Inside `persist_monitor_scale`, `$8`/`$9` are used only at `:466` — pass recomputed coords through them; do not grow the 13-param signature (RESEARCH Q8).
7. **`monitors -j` (non-`all`) is deliberate.** It already excludes disabled *and* mirror outputs — adjacency math and the GDK max both want exactly that set; `all` adds phantom mirror-host boxes.
8. **`local` resets `$?`** — declare `local status=0` *before* `env ... awk ... || status=$?` (`:142-146`); mirror this if a second capture is added.
9. **eval capture is `>` not `>>`** — overwrite keeps "exactly one atomic eval" assertable via line count; the same file doubles as the stub's post-eval marker for the `AFTER_EVAL` knob (fresh stub process per call → filesystem is the only state channel; `rm -f "$eval_out"` per case is already the convention).
10. **Position precedes scale in shipped fixtures** (`monitor-scaling-test.sh:177`, `:161`) — no existing fixture covers the reverse (scale-before-position) order, so the plan's new `write_named_scale_first_rule_config` is the only coverage proving the edit list is safe both ways. Position values may also be unquoted var refs (`position = omarchy_monitor_position`, clamshell fixture `:142`) — `value_end` handles them; rewrite var-refs to literals when changed; skip only `auto*`.
11. **`transform` is currently dropped twice** — the eval (`:111`) omits it (live un-rotates portrait monitors) and the append path (`:466`) never writes it. Both must emit `transform = N` when non-zero, appended *after* `scale` to match `config/hypr/monitors.lua:14` ordering.
12. **`process_block` runs per matching block** (`:412-418`) — a `name`-keyed + `desc:`-keyed duplicate pair must both get the position rewrite; the `matched` count and `exit 3` no-match contract (`:450`, `:460-468`) stay unchanged.
13. **`rewrite_scale`'s trailing-whitespace trim is load-bearing** (`:393`) — copy it into `rewrite_position` so the splice doesn't strand or duplicate whitespace.
14. **The eval's `>/dev/null` discards failure** (`:111`) — D-07's verify-read is the safety net; if stderr is captured for the audit line, keep the stdout redirect.
15. **Reported scales carry float noise** (`1.3333334`, possibly `%.2f` `1.33`) — round logical dims to int when within ~0.5 before edge math, and verify-read compares within `|Δ| < ~0.006` (or the `·120`-grid `< 0.75` variant), never string equality (RESEARCH Q1/Q8). **Resolved live:** installed Hyprland reports full-float scales (`1.3333334`), so TOL≈5 has adequate headroom.
16. **Key-order check `prev ~ /[{,;[:space:]]/` + `=` lookahead** (`:311-316`) is what makes `top_level_key("position")` safe against `my_position`/`positionX` — don't loosen it.
17. **Sourcing runs `SCALES=(...)` etc. under the test's `set -u`** — all current top-level expansions are `${var:-default}`-safe; keep it that way (no bare `${VAR}` additions at top level).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `recompute_monitor_position` geometry pass | pure function (adjacency detection + fail-safe) | transform (JSON → boxes → `XxY`) | No in-repo precedent for monitor-box adjacency math — the algorithm itself is specified by RESEARCH Q5 (D-01..D-06). Only the *pipeline shape* (jq `@tsv` → `awk -F '\t'`) has analogs (`omarchy-plugin-list:35-46`). Implement the spec; do not invent a second coordinate dialect — integer logical px, `round(pw/scale)` dims, TOL≈5. |

## Metadata

**Analog search scope:** `bin/` (omarchy-hyprland-monitor-scaling, omarchy-hyprland-monitor-clamshell, omarchy-monitor-state, omarchy-chromium-copy-url-host, omarchy-chromium-ytdlp-host, omarchy-windows-vm, omarchy-plugin-list, omarchy-reminder, omarchy-refresh-config), `test/shell.d/` (monitor-scaling-test, monitor-clamshell-scale-test, monitor-state-test, windows-vm-compose-test, base-test, bin-style-test), `test/shell`, `config/hypr/monitors.lua`, `default/hypr/envs.lua`, `AGENTS.md`, `docs/testing.md`, `.planning/codebase/{CONVENTIONS,CONCERNS}.md`, `.planning/phases/01-*`, `02-*` artifacts
**Files scanned:** 22
**Pattern extraction date:** 2026-09-14
