---
phase: 01-per-monitor-scale-persistence-in-the-scaling-cli
plan: 01
subsystem: infra
tags: [hyprland, monitors, scaling, lua, awk, bash, gsd]

requires:
  - phase: none
    provides: first phase of the milestone
provides:
  - omarchy-hyprland-monitor-scaling persists scale on the target monitor's own hl.monitor() rule (in-place rewrite or single-line append)
  - live hyprctl eval replays the monitor's live x/y position instead of position = "auto"
  - optional [monitor] positional arg on the scaling CLI for per-monitor targeting
  - timestamped monitors.lua.bak.<ts> backup and symlink-safe writes on every persist
affects: [02-per-monitor-display-panel]

actuals:
  tokens: 9000
  tasks: 4
  commits: 3

tech-stack:
  added: []
  patterns: [awk block rewriter with comment/string blanking at stable byte offsets, ENVIRON-passed monitor identity, sentinel exit codes driving append-vs-rewrite]

key-files:
  created: []
  modified:
    - bin/omarchy-hyprland-monitor-scaling
    - test/shell.d/monitor-scaling-test.sh

key-decisions:
  - "persist_monitor_scale takes 13 args (the plan's 9 plus description/make/model/serial) so the awk rewriter receives full monitor identity for desc: matching via ENVIRON"
  - "awk exit contract: 0 = rewrote >=1 matching block, 3 = no rule names the output (append path), anything else = warn and no write"
  - "summary metadata updated to drop 'focused' since the command now targets arbitrary monitors"
  - "task 4 produced no separate commit: the plan's 'one atomic commit' unit (bin + tests together) was already satisfied by the task-1 commit; tasks 2-3 were test-only commits"

patterns-established:
  - "Single awk pass over monitors.lua: comments and string contents blanked to spaces at identical byte offsets, hl.monitor() blocks captured by string-aware paren/brace depth, scale key spliced into the original text at blanked-text offsets or inserted before the closing brace"
  - "Monitor identity passed to awk via env/ENVIRON, never -v, so EDID description text with backslashes survives"
  - "All writes go through the file (cat tmp > file, >> append, sed -i --follow-symlinks) so a symlinked monitors.lua stays a symlink"

requirements-completed: [SCALE-01, SCALE-02, SCALE-03, SCALE-04]

coverage:
  - id: D1
    description: "Scale change rewrites the target monitor's own hl.monitor() rule in place (name- or desc:-keyed, single- or multi-line, inserting scale when absent) or appends a single-line name-keyed rule when unlisted; catch-all and omarchy_monitor_scale stay byte-identical"
    requirement: SCALE-01
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh#monitor scaling rewrites the monitor's own hl.monitor rule and 9 shape cases"
        status: pass
    human_judgment: false
  - id: D2
    description: "Live hyprctl eval apply replays live .x/.y position, never position = \"auto\""
    requirement: SCALE-02
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh#position = \"0x0\" assertions and targeted -1200x0 case"
        status: pass
    human_judgment: false
  - id: D3
    description: "Stock configs (omarchy_monitor_scale variable or literal catch-all) still persist via the append path"
    requirement: SCALE-03
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh#appended-rule assertions on stock and literal-catch-all fixtures"
        status: pass
    human_judgment: false
  - id: D4
    description: "Realistic monitors.lua shapes handled: multi-line rules, desc: selectors, missing scale keys, comment-shielded rules, nested-table/semicolon-safe offsets, symlinked configs, timestamped backups"
    requirement: SCALE-04
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh#10 fixture writers and shape cases"
        status: pass
    human_judgment: false
  - id: D5
    description: "Optional [monitor] arg: targeted set/step, unknown/unsafe names and >2 args rejected with no eval and no write; bare call unchanged"
    requirement: SCALE-01
    verification:
      - kind: unit
        ref: "test/shell.d/monitor-scaling-test.sh#targeting and rejection cases; test/shell.d/monitor-state-test.sh"
        status: pass
    human_judgment: false

duration: 23min
completed: 2026-09-14
status: complete
---

# Phase 1, Plan 01: Per-monitor scale persistence in the scaling CLI Summary

**`omarchy-hyprland-monitor-scaling` now persists scale on the target monitor's own `hl.monitor()` rule — via an offset-preserving awk rewriter or a single-line name-keyed append — replays live position in the eval apply, and accepts an optional `[monitor]` target.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-09-14T09:47:07Z
- **Completed:** 2026-09-14T10:10:20Z
- **Tasks:** 4
- **Files modified:** 2

## Accomplishments

- Deleted both sed persistence branches (`omarchy_monitor_scale` variable rewrite and the `output = ""` catch-all rewrite); a targeted monitor's scale now persists on its own `hl.monitor()` rule or on an appended single-line name-keyed rule that beats the catch-all under Hyprland's last-matching-rule semantics.
- New `persist_monitor_scale` runs one awk pass that blanks `--`/`--[[ ]]` comments and quoted-string contents to spaces at identical byte offsets, captures multi-line `hl.monitor({...})` blocks by brace/paren depth, matches `output` by connector name or trimmed `desc:` prefix against `.description` or reconstructed `{make} {model} {serial}`, splices `scale = N` into the original text or inserts it before the closing brace, and answers 0/3 via exit code.
- Live apply now emits `position = "${x}x${y}"` read from `hyprctl monitors -j` — `position = "auto"` is gone entirely; appended rules carry live mode/position.
- Optional `[monitor]` positional arg (D-03): `up`/`down`/explicit scale all accept it; `jq -e` selector failures and `>2` args exit non-zero before any eval or write; the bare call still prints the focused scale.
- Timestamped `monitors.lua.bak.<ts>` backup precedes every write; all writes go through the file so a symlinked config stays a symlink; `local omarchy_gdk_scale` and literal `hl.env("GDK_SCALE", "N")` update to the nearest integer on every persist path.
- Command metadata updated (`args`, a targeted example, `usage()`, and the summary now drops "focused").

## Task Commits

Each task was committed atomically:

1. **Task 01-01-01 (tracer): per-monitor persistence core + re-pointed assertions** - `eb68cc30` (fix)
2. **Task 01-01-02: persistence-shape coverage** - `5a4f071b` (test)
3. **Task 01-01-03: [monitor] arg coverage** - `54fec018` (test)
4. **Task 01-01-04: regression sweep** - no commit; the plan's "one atomic commit covering bin + test" unit was already satisfied by the task-1 commit (script and its tests landed together, keeping the suite green), and tasks 2–3 were test-only additions. The sweep changed no files.

## Files Created/Modified

- `bin/omarchy-hyprland-monitor-scaling` — `[monitor]` arg, `persist_monitor_scale` awk rewriter, backup + symlink-safe writes, live x/y eval, deleted sed branches, updated metadata/usage.
- `test/shell.d/monitor-scaling-test.sh` — grown `hyprctl` stub (x/y/description/make/model/serial, `OMARCHY_TEST_EXTERNAL_MONITOR` second monitor), 10 fixture writers, 30 passing cases.

## Decisions Made

- `persist_monitor_scale` takes 13 positional args (plan's 9 + description/make/model/serial) — the monitor identity must reach awk for `desc:` matching; env-passing from `set_scale` into `persist_monitor_scale` internals was less explicit.
- `local status=0` + `|| status=$?` captures the awk exit code — a bare `local status; status=$?` would read `local`'s own exit, not awk's (same `local`-swallows-`$?` hazard the plan flagged for `local x=$(cmd)`).
- `# omarchy:summary=` reworded to drop "focused" — the command now targets arbitrary monitors (deviation, noted).
- awk program contains no literal `'` (uses `sprintf("%c", 39)` for single-quote tracking; apostrophes removed from awk-side comments) since the program lives in a single-quoted shell string.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Apostrophes in awk comments terminated the single-quoted program**
- **Found during:** Task 01-01-01
- **Issue:** `bash -n` failed; comments like "the block's output" inside the awk program ended the shell single-quote early.
- **Fix:** Reworded awk-side comments to avoid apostrophes.
- **Files modified:** `bin/omarchy-hyprland-monitor-scaling`
- **Verification:** `bash -n` exits 0.
- **Committed in:** `eb68cc30`

**2. [Rule 1 - Bug] `local status; status=$?` still read `local`'s exit code**
- **Found during:** Task 01-01-01
- **Issue:** `local` resets `$?` to 0, so the awk exit code was lost and the append path never ran.
- **Fix:** `local status=0` declared before the `env ... awk` call, captured via `|| status=$?`.
- **Files modified:** `bin/omarchy-hyprland-monitor-scaling`
- **Verification:** append path exercised by the stock-config cases.
- **Committed in:** `eb68cc30`

**3. [Rule 3 - Blocking] jq 1.8 preserves `120.0` in `refreshRate`**
- **Found during:** Task 01-01-01
- **Issue:** Test expectations written as `2880x1800@120`; the installed jq renders `120.0`, so the eval/append mode string is `2880x1800@120.0` (same behavior the old eval already had).
- **Fix:** Test expectations carry `@120.0`/`@144.0`.
- **Files modified:** `test/shell.d/monitor-scaling-test.sh`
- **Verification:** full suite green.
- **Committed in:** `eb68cc30`

**4. [Rule 2 - Robustness] Missing trailing newline before append**
- **Found during:** Task 01-01-01
- **Issue:** `>>` append would merge the new rule into the last line of a file lacking a trailing newline.
- **Fix:** Emit `\n` first when the file is non-empty and its last byte is not a newline.
- **Files modified:** `bin/omarchy-hyprland-monitor-scaling`
- **Verification:** append path green in suite.
- **Committed in:** `eb68cc30`

---

**Total deviations:** 4 auto-fixed (2 bugs, 1 blocking, 1 robustness)
**Impact on plan:** All fixes necessary for correctness of the specified design; no scope creep.

## Issues Encountered

- `./test/shell` reports 7 failing files in this environment — all proven pre-existing by re-running them on a detached worktree at the base commit `41b7ea3d`: `config`, `locate`, `screenshot-sanity`, `unowned-system-paths` need a sibling `omarchy-pkgs` checkout; `runtime-smoke` and `bar-icon-geometry` depend on the live compositor/shell; `snapper` needs snapper tooling. None reference the scaling script. All monitor-related suites (`monitor-scaling`, `monitor-state`, `monitor-clamshell-scale`, `monitor-output-name`) pass, and `./test/cli` exits 0.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 2 can call `omarchy-hyprland-monitor-scaling <scale|up|down> <screen-name>` from `shell/plugins/panels/monitor/Panel.qml`; the bare-call contract for `omarchy-monitor-state` is unchanged.
- Residual per RESEARCH §3: a monitor whose file rule says `position = "auto"` stays pinned at live coordinates for the session after a scale change (D-04 trade-off); cleared on reload.
- A `monitors.lua` that is absent is skipped with a stderr warning (never created); an unreadable one warns and returns 1 after the live apply.

## Self-Check: PASSED

- `bash test/shell.d/monitor-scaling-test.sh` — 30 `ok -` lines, exit 0
- `bash test/shell.d/monitor-state-test.sh`, `monitor-clamshell-scale-test.sh`, `monitor-output-name-test.sh` — all `ok -`, exit 0
- `bash -n bin/omarchy-hyprland-monitor-scaling` — exit 0
- `grep -n 'position = "auto"' bin/omarchy-hyprland-monitor-scaling` — no output
- `grep -n 'omarchy_monitor_scale' bin/omarchy-hyprland-monitor-scaling` — no output
- `./test/cli` — exit 0 (metadata lint green)
- `./test/shell` — exits 1 on 7 pre-existing environment failures unrelated to this change (see Issues Encountered); every monitor-related file passes
- `git status --porcelain` — only pre-existing `M bin/omarchy-capture-text` (untouched) and untracked `.planning/state.json` remain; all phase work committed

---
*Phase: 01-per-monitor-scale-persistence-in-the-scaling-cli*
*Completed: 2026-09-14*
