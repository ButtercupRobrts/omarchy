# Testing

How Omarchy's test suites are organized and run. Source of truth:
`docs/testing.md`, plus `agents/skills/acceptance-tests.md` and
`agents/skills/visual-verification.md`.

## Entry points

- `./test/all` — aggregate runner; runs `test/cli` and `test/shell`, keeps
  going when one fails, reports failed suites and exits non-zero
  (`test/all`). Deliberately excludes the graphical acceptance suite.
- `./test/cli` — one 714-line script, one suite (`test/cli`). Covers the
  `bin/omarchy` router: help/group rendering, route resolution, aliases,
  hidden commands, and that trailing `--help` never executes the target. Also
  owns the metadata lint over every `bin/omarchy-*` executable
  (`test/cli:606-612`) and the theme pipeline (`omarchy-theme-set-templates`,
  `omarchy-theme-color`, `omarchy-theme-osc`, theme sync commands) run against
  stub binaries and a fake `$HOME` (`docs/testing.md:15-23`).
- `./test/shell` — runs every `test/shell.d/*-test.sh` except `base-test.sh`.
  130+ files, one area each: a shell plugin, a `bin/` command, a config
  invariant, or a still-live migration. Continues past a failing file and
  summarizes at the end — a file exits at its first failed assertion, so
  aborting the run would hide the rest (`docs/testing.md:62-66`).

## Running tests

```bash
./test/all                              # everything except acceptance
./test/cli                              # router + metadata + theme suite
./test/shell                            # all test/shell.d/*-test.sh
bash test/shell.d/<area>-test.sh        # one focused shell test
```

New shell tests: drop `<area>-test.sh` into `test/shell.d/` and `./test/shell`
picks it up automatically. Shared fixtures live in `test/shell.d/fixtures/`.

## The base-test.sh contract

Every shell test begins identically (`docs/testing.md:37-45`):

```bash
#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
```

`test/shell.d/base-test.sh` refuses direct execution, discovers the repo root
and exports it as `ROOT` — tests reference `$ROOT/bin/...` and never depend
on the caller's cwd or an installed Omarchy. Assertions are TAP-flavored
(`base-test.sh:13-30`): `pass "desc"` prints `ok - desc`; `fail "desc"
[detail]` prints detail + `not ok - desc` to stderr and exits the file —
first failure ends it; `require_command <cmd>` fails when a tool is absent.

`test/cli` defines its own `pass`/`fail`/`assert_output_contains` and a
`make_tmpdir`/`trap cleanup EXIT` pattern (`test/cli:11-46`).

## Compositor gating

`require_compositor "desc"` (`base-test.sh:64-77`) keeps the suite green on
headless machines: `compositor_reachable` checks `WAYLAND_DISPLAY`, that the
socket actually exists under `$XDG_RUNTIME_DIR`, then asks Hyprland via
`hyprctl -j monitors` (retried 3x, only when `HYPRLAND_INSTANCE_SIGNATURE` is
set). No compositor → prints `ok - no Wayland compositor; skipping ...` and
exits 0 (a skip is a pass). With a compositor it sets `ulimit -c 0` so a
Quickshell `qFatal()` exit doesn't leave a core dump
(`docs/testing.md:68-90`). Gate only the runtime half; keep static analysis
ungated.

## Unit-testing shell JS from bash

Plugin logic lives in plain `.js` modules (`shell/plugins/menu/MenuModel.js`,
`shell/services/AppSearch.js`, `shell/plugins/bar/BarModel.js`) ending in a
guarded `if (typeof module !== "undefined") module.exports = {...}` — QML
imports them, Node loads them as CommonJS (`docs/testing.md:92-99`).

`run_node_test` (`base-test.sh:79-127`) pipes a prelude + heredoc into
`node`. The prelude mirrors the bash protocol (`pass`, `fail`, `assert`,
`assertEqual`, `assertDeepEqual`, same exit-on-first-failure) and provides
`root`, `path`, `requireFromRoot(rel)`:

```bash
run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
assertEqual(menu.parseMenuJsonc('{ "items": {} }').length, 0, 'parses JSONC')
JS
```

Tests also read QML source and assert on it textually — regex-extracting
function bodies to pin routing invariants (`app-search-test.sh:82-113`).
Roughly a quarter of shell test files use `run_node_test`.

## Test conventions worth copying (`docs/testing.md:120-137`)

- **Stub the world, run the real code**: build a scratch `bin/` of stub
  executables (`sudo`, `brightnessctl`, helper commands) that append args to
  a call log, prepend to `PATH`, run the real script, grep the log
  (`test/shell.d/brightness-display-test.sh:12-52`).
- **Fake `$HOME`, real `$OMARCHY_PATH`**: `HOME=$(mktemp -d)` with
  `trap ... EXIT` cleanup and `OMARCHY_PATH="$ROOT"`.
- **Migrations run directly**: `bash -euo pipefail "$ROOT/migrations/<ts>.sh"`
  against fabricated legacy state; run twice for idempotence and once on
  non-legacy state. Keep the test only while the migration is live; drop it
  once shipped and frozen (`docs/testing.md:130-134`,
  `agents/skills/migrations.md:151-166`).
- **Assert invariants, not snapshots**: pin the named property, not whole
  structures.

## Acceptance suite (VM, not in-session)

`test/acceptance` + `test/acceptance.d/*-test.sh` exercise a real installed
desktop: session health, shell surfaces, panels, keyboard nav, apps. It is
**excluded from `./test/all`** and runs in a disposable VM via the sibling
`omarchy-iso` repo (`agents/skills/acceptance-tests.md:12-33`):

```bash
cd ../omarchy-iso
./bin/omarchy-iso-test release/<iso>.iso --reuse-base --sync-omarchy ../omarchy --no-preview
```

Use `--sync-all ../omarchy` when the run must exercise local `bin/`,
`config/`, or `shell/`; package/install/default changes need a fresh ISO via
`omarchy-iso-make` and a run without `--reuse-base`.

`test/acceptance.d/base-test.sh` exports `ROOT`, artifacts under
`$OMARCHY_ACCEPTANCE_DIR` (default `/tmp/omarchy-acceptance`), defaults
`OMARCHY_PATH=/usr/share/omarchy` (the installed tree, not the checkout).
Helpers: `screenshot` (grim), `screen_contains` (grim at 2x + tesseract OCR),
`wait_until` (poll, screenshot on timeout). `fail` captures
`failure-<step>.png` automatically; tests save `success-<step>.png` for each
visually distinct state and restore user state with traps
(`agents/skills/acceptance-tests.md:35-46`). Global Hyprland keybindings need
QMP virtual keyboard input from the ISO harness; in-guest `wtype` only proves
focused-control typing.

## Visual verification (required for UI changes)

Any change with a visual effect must also be verified in the running UI, not
just via automated tests (`agents/skills/visual-verification.md`):

```bash
omarchy capture screenshot fullscreen save   # prints saved path
omarchy screenrecord --fullscreen            # then: omarchy screenrecord --stop-recording
wtype -k Right -k Return                     # simulate keys into focused UI
```

Inspect artifacts for clipping, overlap, spacing, stale state, focus issues;
capture reference vs. candidate images when changing layer-shell surfaces.
After editing QML, run `omarchy-restart-shell` (`agents/skills/shell-dev.md:10`).
