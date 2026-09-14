# Phase 1: Per-monitor scale persistence in the scaling CLI - Pattern Map

**Mapped:** 2026-09-14
**Files analyzed:** 2 modified + 2 read-only contract references
**Analogs found:** 2 / 2 (all modified files have in-repo analogs; one pattern — the multi-line awk Lua rewriter — has no in-repo precedent and is specified by RESEARCH.md §5)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `bin/omarchy-hyprland-monitor-scaling` | utility (CLI command) | file-I/O + request-response (hyprctl IPC, `monitors.lua` rewrite) | itself (functions kept verbatim) + `bin/omarchy-refresh-config` (backup) + `bin/omarchy-hyprland-monitor-focused-apple` (`[monitor]` arg resolution) | exact (partial-file analogs) |
| `test/shell.d/monitor-scaling-test.sh` | test | file-I/O (stub `bin/`, fixture `monitors.lua`, log capture) | itself + `test/shell.d/monitor-clamshell-scale-test.sh` (fixture-function convention) + `test/shell.d/monitor-output-name-test.sh` (rejection-test shape) | exact |
| `bin/omarchy-monitor-state` | — NOT MODIFIED — caller/contract reference | request-response (positional stdout contract) | `test/shell.d/monitor-state-test.sh` pins the contract | constraint only |
| `bin/omarchy-hyprland-monitor-clamshell` | — NOT MODIFIED — parser-compatibility contract | file-I/O (second `monitors.lua` parser) | itself: `monitor_rule_regex`/`configured_monitor_value` define the write format | constraint only |

## Pattern Assignments

### `bin/omarchy-hyprland-monitor-scaling` (utility, file-I/O + hyprctl IPC)

The file is its own primary analog: large parts stay verbatim. Excerpts below mark **KEEP** (unchanged machinery to mirror), **REPLACE** (the code being deleted), and **ANALOG** (patterns imported from other files).

**Metadata header — KEEP shape, UPDATE args/examples** (`bin/omarchy-hyprland-monitor-scaling:3-5`):

```bash
# omarchy:summary=Show, set, or adjust focused Hyprland monitor scaling
# omarchy:args=[up|down|SCALE]
# omarchy:examples=omarchy hyprland monitor scaling | omarchy hyprland monitor scaling 1.6 | omarchy hyprland monitor scaling up | omarchy hyprland monitor scaling down
```

Update `args` → `[up|down|SCALE] [monitor]` and add a targeted example (e.g. `omarchy hyprland monitor scaling 1.6 HDMI-A-1`). `test/cli:598-611` lints every `bin/omarchy-*` for `summary` presence and rejects empty `args=` and removed fields — see `agents/skills/command-metadata.md`. Also update `usage()` (`:11-13`):

```bash
usage() {
  echo "Usage: omarchy-hyprland-monitor-scaling [up|down|SCALE]"
}
```

**Unsafe-name guard — KEEP and reuse for the new `[monitor]` arg** (`:84-89`). The same regex must vet the user-supplied arg before it is written into Lua/eval strings; `test/shell.d/monitor-output-name-test.sh:107-123` already exercises this path for the focused name:

```bash
  # active_monitor is written into the Lua string eval'd below, so only a plain
  # connector name may pass; a hostile output name could execute otherwise.
  if [[ ! $active_monitor =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Refusing unsafe monitor name" >&2
    exit 1
  fi
```

The identical guard exists in `bin/omarchy-hyprland-monitor-clamshell:14-20` with the same `Refusing unsafe ... name` stderr wording.

**Target-monitor resolution — ANALOG: `bin/omarchy-hyprland-monitor-focused-apple:6-11`** (the `[monitor]`-arg idiom this fork already ships):

```bash
monitor="${1:-}"

hyprctl monitors -j | jq -e --arg monitor "$monitor" '
  .[]
  | select(if $monitor == "" then .focused == true else .name == $monitor end)
  | select(.make == "Apple Computer Inc" and (.model | test("StudioDisplay|ProDisplayXDR|Studio XDR")))
' >/dev/null
```

Mirror the `select(if $monitor == "" then .focused == true else .name == $monitor end)` selector in `set_scale` and in the `up`/`down` dispatch arms (currently `jq -e -c '.[] | select(.focused == true)'` at `:77`, `:182`, `:187`). `jq -e` returning empty/non-zero for an absent target needs an explicit `echo ... >&2; exit 1` — the script runs without `set -e` (CONCERNS.md:145-150).

**Live apply — REPLACE `position = "auto"` with live x/y replay (D-04)** (`:97`). Current:

```bash
  hyprctl eval "hl.monitor({ output = \"$active_monitor\", mode = \"${width}x${height}@${refresh_rate}\", position = \"auto\", scale = $new_scale })" >/dev/null
```

New shape: extract `.x`/`.y` from `monitor_info` (same jq object already fetched) and emit `position = \"${x}x${y}\"`. Keep key order `output, mode, position, scale` — that is the order clamshell emits (`bin/omarchy-hyprland-monitor-clamshell:173,237`) and the order fixture files and appended lines use everywhere.

**Audit log — KEEP format unchanged** (`:26-53`). `monitor=` field now records the target rather than always the focused monitor; the `printf` field order at `:42-52` must not change:

```bash
  printf 'at=%s\trequested=%s\tcurrent=%s\tnew=%s\tmonitor=%s\tpid=%s\tppid=%s\tparent=%s\tgppid=%s\tgrandparent=%s\n' \
```

Test asserts on it: `monitor-scaling-test.sh:52` greps `requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1`.

**`clean_scale` / `scale_from_current` — KEEP verbatim** (`:55-68`, `:115-172`). Both are pure awk heredoc-free functions invoked via `awk -v`; the preset-stepping logic is unchanged by this phase.

**Persistence branches — REPLACE both** (`:100-112`, the code this phase deletes):

```bash
  # Persist to monitors.lua if the user still has Omarchy's generic catch-all
  # defaults, so the scale survives reboots.
  if [[ -f $monitor_lua ]] && grep -q '^local omarchy_monitor_scale = ' "$monitor_lua"; then
    sed -i -E \
      -e "s|^local omarchy_monitor_scale = .*|local omarchy_monitor_scale = ${new_scale}|" \
      -e "s|^local omarchy_gdk_scale = .*|local omarchy_gdk_scale = ${new_gdk_scale}|" \
      "$monitor_lua"
  elif [[ -f $monitor_lua ]] && grep -Eq '^hl\.monitor\(\{ output = "", mode = "preferred", position = "auto", scale = ("auto"|[0-9.]+) \}\)' "$monitor_lua"; then
    sed -i -E \
      -e "s|^(hl\.monitor\(\{ output = \"\", mode = \"preferred\", position = \"auto\", scale = )([^ ]+)( \}\))|\\1${new_scale}\\3|" \
      -e 's|^hl\.env\("GDK_SCALE", ".*"\)|hl.env("GDK_SCALE", "'"$new_gdk_scale"'")|' \
      "$monitor_lua"
  fi
```

Replacement per D-01/D-02/RESEARCH §5: one awk pass (blank comments → string-aware brace counting → capture `hl.monitor(...)` blocks → rewrite/insert `scale` for matching `output` name or `desc:` prefix → distinct exit codes), then `cat "$tmp" > "$monitor_lua"` on match or append a single-line `hl.monitor({ ... })` on no-match. The two `sed` GDK rewrites above are the only pieces carried forward — they must run on **every** persist path (append included).

**Backup-before-write — ANALOG: `bin/omarchy-refresh-config:22,31-32`** (D-05):

```bash
backup_config_file="$user_config_file.bak.$(date +%s)"
...
if [[ -f $user_config_file ]]; then
  cp -f "$user_config_file" "$backup_config_file"
```

Mirror as `cp -- "$monitor_lua" "$monitor_lua.bak.$(date +%s)"` immediately before the rewrite/append. Note `omarchy-refresh-config:35-39` also *deletes* the backup when content is unchanged and diffs on change — do **not** copy that; D-05 wants the backup to persist.

**Symlink-safe write idiom — ANALOG: `bin/omarchy-font-set:37` / `bin/omarchy-display-text-size:146`**:

```bash
    sed --follow-symlinks -i -E "s/^[[:space:]]*font_family[[:space:]]+.*/font_family $kitty_font_name/" ~/.config/kitty/kitty.conf
```

For the awk-pass rewrite there is no `sed -i`; use `cat "$tmp" > "$monitor_lua"` (writes through the link) rather than the `mv "$tmp" target` idiom at `bin/omarchy-agent-usage-update:49-51`, which detaches symlinks (upstream #7625).

**Dispatch — KEEP `case` shape, extend arms** (`:174-203`). `up`/`down` currently resolve `.focused` twice per arm; both need the `--arg monitor` selector so stepping reads *that* monitor's scale/geometry. Numeric validation at `:194-201` stays:

```bash
*)
  if [[ $1 =~ ^[0-9]+([.][0-9]+)?$ ]] &&
    awk -v scale="$1" 'BEGIN { exit !(scale >= 1 && scale <= 4) }'; then
    set_scale "$1" "$1"
  else
    usage >&2
    exit 1
  fi
  ;;
```

Reject `>2` args and a second arg on the bare-read form through `usage`. The bare `""` arm (`:175-177`, `focused_monitor_scale | normalize_scale`) is a positional contract — `bin/omarchy-monitor-state:20` calls it with no args and `test/shell.d/monitor-state-test.sh` reads it by line index.

---

### `test/shell.d/monitor-scaling-test.sh` (test, file-I/O stub/fixture)

**Analog:** itself (structure kept) + `test/shell.d/monitor-clamshell-scale-test.sh` for multi-fixture conventions.

**File header / harness — KEEP verbatim** (`:1-16`):

```bash
#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
```

`base-test.sh` supplies `pass`/`fail`/`require_command` and exports `ROOT` (`base-test.sh:8-30`); `fail` prints `not ok -` to stderr and exits the file. `docs/testing.md:120-137` documents "stub the world, run the real code" and "fake `$HOME`, real `$OMARCHY_PATH`".

**Stub `hyprctl` — KEEP pattern, GROW fields** (`:18-30`). Current stub emits a single monitor with `name/focused/scale/width/height/refreshRate`; per RESEARCH §6/test-plan it must grow `x`, `y`, `description`, `make`, `model`, `serial`, an optional second monitor, and per-monitor `focused`:

```bash
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf '[{"name":"eDP-1","focused":true,"scale":%s,"width":%s,"height":%s,"refreshRate":120.0}]' \
    "${OMARCHY_TEST_MONITOR_SCALE:-2}" "${OMARCHY_TEST_MONITOR_WIDTH:-2880}" "${OMARCHY_TEST_MONITOR_HEIGHT:-1800}"
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"
```

`monitor-clamshell-scale-test.sh:19-37` is the richer stub shape to copy for env-switched JSON variants (`OMARCHY_TEST_INTERNAL_DISABLED` pattern); `monitor-output-name-test.sh:33-36` shows the `case "$1" in` dispatch alternative.

**Fixture writers — ANALOG: `monitor-clamshell-scale-test.sh:66-210`**, the canonical convention: one `write_<name>_config()` function per `monitors.lua` shape, heredoc `<<'LUA'` bodies, short comment above each naming the property under test:

```bash
# A specific-output rule that references the omarchy_monitor_scale variable
# (the default template's pattern) instead of a literal value. The variable
# must be resolved, not captured as the literal string "omarchy_monitor_scale".
write_internal_monitor_var_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 1.5
local omarchy_monitor_scale = 1.5
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}
```

Existing fixture shapes to reuse verbatim as new scaling fixtures: scale-less rule (`:147-152`), commented-out rule (`:179-184`), trailing `-- comment` on a rule (`:186-190`), nested table + `;` separators (`:194-209`), block comment mid-rule (`:200-204`), var-referenced scale (`:95-102`), expression scale (`:155-160, 172-176`).

**Runner — KEEP `run_scaling` env convention** (`:39-46`); add new `OMARCHY_TEST_*` vars the same way:

```bash
run_scaling() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
}
```

**Assertion style — KEEP** (`:49-53`): `grep -F`/`grep -Fx` against `$eval_out` and `$monitor_lua`, `|| fail "..."`, one `pass "..."` per case:

```bash
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling up
grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling up reaches 3x"
grep -Fx 'local omarchy_monitor_scale = 3' "$monitor_lua" >/dev/null || fail "monitor scaling up persists 3x"
grep -F $'requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1' "$scale_log" >/dev/null || fail "monitor scaling up writes audit log"
pass "monitor scaling up reaches 3x"
```

**Must-update assertions (now asserting the deleted bug path):** lines 51, 58, 64, 70-71, 79-80, 85-86, 101-102, 129-130 — every `grep -Fx 'local omarchy_monitor_scale = N'` becomes an appended-line assertion plus a *non*-rewrite check on the variable (`grep -Fx 'local omarchy_monitor_scale = "auto"'` on a stock fixture, or absence of the appended value). Negative-grep idiom for "untouched" assertions: `monitor-clamshell-scale-test.sh:235` `! grep -F ... || fail`.

**Expected-failure test shape — ANALOG: `monitor-output-name-test.sh:62-69`** for unknown/unsafe `[monitor]` args (script under test has no `set -e`, so wrap in `set +e`/`set -e` and assert status + no-write):

```bash
set +e
LAPTOP_NAME='eDP-1", disabled = false })os.execute("calc")--' \
  run_monitor omarchy-hyprland-monitor-internal off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "internal off rejects a monitor name with Lua metacharacters"
[[ ! -e $disable_flag ]] || fail "an unsafe monitor name is not written as Lua"
pass "internal off refuses an unsafe monitor name"
```

**Loop-over-fixtures idiom — ANALOG: `monitor-clamshell-scale-test.sh:405-413`** for running one assertion set across several shape fixtures:

```bash
for config in nested_table semicolon block_comment; do
  "write_${config}_config"
  ...
  pass "clamshell recovery reads a ${config//_/ } rule"
done
```

---

### `bin/omarchy-monitor-state` — NOT MODIFIED (contract constraint)

Listed in CONTEXT as a canonical reference; RESEARCH §7 confirms it is unchanged (`:20` calls `omarchy-hyprland-monitor-scaling` with no args, `2>/dev/null || echo`). Constraint on this phase: the bare-invocation stdout of `omarchy-hyprland-monitor-scaling` must remain a single scale value on line 1 — `monitor-state-test.sh:52-57` pins an 8-line contract and `:32-34` warns a dying helper shifts every field. No edits; do not let the new `[monitor]` arg change the no-arg output shape.

### `bin/omarchy-hyprland-monitor-clamshell` — NOT MODIFIED (write-format contract)

Second parser of `monitors.lua`; the appended lines this phase writes must be readable by it. Its matching machinery (`:77-89`):

```bash
monitor_rule_regex() {
  printf '^[[:space:]]*hl\\.monitor\\(\\{.*output[[:space:]]*=[[:space:]]*"%s"' "$1"
}
...
  value=$(monitor_rules | sed -nE '/'"$(monitor_rule_regex "$output")"'/s/.*[{,;[:space:]]'"$key"'[[:space:]]*=[[:space:]]*("[^"]*"|[^,;}[:space:]]+)[[:space:]]*([,;}].*)?$/\1/p' | head -1)
```

Contract derived from it: appended lines must be **single-line**, start `hl.monitor({`, carry `output = "NAME"` with a literal connector name (never `desc:` — runtime eval ignores `desc:` for connected outputs anyway, RESEARCH finding 2), and `scale = <number>` as a `,`-separated key. It cannot read multi-line or `desc:`-keyed rules — those are in-place-rewrite-only shapes this phase must never *emit*. Regression gate: re-run `monitor-clamshell-scale-test.sh` after the change.

## Shared Patterns

### Command metadata header (`# omarchy:*`)
**Source:** `agents/skills/command-metadata.md`; lint at `test/cli:598-611`; example at `bin/omarchy-hyprland-monitor-scaling:3-5`
**Apply to:** `bin/omarchy-hyprland-monitor-scaling`
Keys allowed: `group`, `name`, `summary`, `args`, `examples` (` | `-separated), `alias`/`aliases`, `hidden=true`, `requires-sudo=true`. `summary` mandatory, no empty `args=`, no removed fields (`legacy|usage|visibility|mutates|interactive`), no `requires-sudo=false`.

### Monitor-name safety regex
**Source:** `bin/omarchy-hyprland-monitor-scaling:84-89`, `bin/omarchy-hyprland-monitor-clamshell:14-20`; tests in `test/shell.d/monitor-output-name-test.sh`
**Apply to:** `bin/omarchy-hyprland-monitor-scaling` — vet the new `[monitor]` arg with `^[A-Za-z0-9._-]+$` before embedding in Lua; stderr message `Refusing unsafe ... name`, `exit 1`. Note this rejects `desc:`-style args (spaces) — acceptable per RESEARCH §7.

### User-config write safety
**Source:** `bin/omarchy-refresh-config:22,31-32` (backup), `bin/omarchy-font-set:37` + `bin/omarchy-display-text-size:146` (`sed --follow-symlinks -i`), `bin/omarchy-agent-usage-update:49-51` (tmp+mv — do NOT use, detaches symlinks)
**Apply to:** `bin/omarchy-hyprland-monitor-scaling` — `cp -- "$monitor_lua" "$monitor_lua.bak.$(date +%s)"` before write; awk output lands via `cat "$tmp" > "$monitor_lua"`, not `mv`.

### Bash style (AGENTS.md / CONVENTIONS.md)
**Apply to:** all touched bash
`#!/bin/bash` shebang; two-space indent; `[[ ]]` for string/file tests, `(( ))` for numerics; unquoted vars inside `[[ ]]`, quoted literals (`[[ $1 == "-q" ]]`); `local` for function vars; lowercase snake_case functions; errors to stderr. The scaling script intentionally has **no** `set -euo pipefail` — keep explicit guards (CONCERNS.md:145-150). Test files do use `set -euo pipefail` (`monitor-scaling-test.sh:3`).

### Test harness conventions
**Source:** `test/shell.d/base-test.sh`, `docs/testing.md:120-137`
**Apply to:** `test/shell.d/monitor-scaling-test.sh`
Stub executables in `mktemp -d`/bin prepended to `PATH`; fake `HOME` + `XDG_STATE_HOME`; `trap 'rm -rf ...' EXIT`; `OMARCHY_TEST_*` env vars parameterize stubs; assert via `grep -F`/`grep -Fx` + `|| fail`; one `pass` per named case; "assert the invariant, not the snapshot". Run focused: `bash test/shell.d/monitor-scaling-test.sh` or `./test/shell` for the whole suite (docs/testing.md).

### hyprctl stub JSON contract
**Source:** `test/shell.d/monitor-scaling-test.sh:18-30`, `monitor-state-test.sh:14-18`
**Apply to:** the growing stub — fields consumed by the script after this phase: `name`, `focused`, `scale`, `width`, `height`, `refreshRate`, `x`, `y`, `description`, `make`, `model`, `serial`. `eval` writes its Lua arg to `$OMARCHY_TEST_HYPRCTL_EVAL_OUT` for grep assertions.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| awk Lua-block rewriter inside `bin/omarchy-hyprland-monitor-scaling` | utility (parser/rewriter) | transform (multi-line aware rewrite) | No in-repo precedent: clamshell's parser is single-line sed/regex only (`monitor_rule_regex`, `bin/omarchy-hyprland-monitor-clamshell:77-89`) and RESEARCH §5 rules sed incapable of multi-line entries. Planner should implement the upstream PR #8300 shape specified in RESEARCH §5 (comment-blanking, string-aware brace depth, offset-preserving splice, ENVIRON-passed monitor metadata, sentinel exit codes) — do not invent a third parsing dialect (R1). |

## Metadata

**Analog search scope:** `bin/` (monitor-*, refresh-config, font-set, display-text-size, agent-usage-update, dev-link), `test/shell.d/` (base-test, monitor-*, bin-style), `test/cli`, `config/hypr/monitors.lua`, `shell/plugins/panels/monitor/Panel.qml`, `default/hypr/bindings/tiling.lua`, `agents/skills/command-metadata.md`, `docs/testing.md`, `.planning/codebase/{CONVENTIONS,CONCERNS}.md`
**Files scanned:** 17 (all analog paths verified git-tracked via `git ls-files`)
**Pattern extraction date:** 2026-09-14
