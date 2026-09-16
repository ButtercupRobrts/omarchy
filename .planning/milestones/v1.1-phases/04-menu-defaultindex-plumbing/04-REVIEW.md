---
phase: 04-menu-defaultindex-plumbing
reviewed: 2026-09-15T11:16:04Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - bin/omarchy-menu-select
  - shell/plugins/menu/Menu.qml
  - shell/plugins/menu/MenuModel.js
  - docs/menu.md
  - test/shell.d/menu-test.sh
  - test/shell.d/menu-select-test.sh
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: resolved
---

# Phase 4: Code Review Report

**Reviewed:** 2026-09-15T11:16:04Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found → resolved (WR-01 fixed in `fix(04-01)` follow-up commit; IN-01 covered by the same guard; IN-02 left as-is for readability)

## Summary

Reviewed the `--default-index N` post-`--` flag → `defaultIndex` payload field → `openDmenu` pre-highlighted cursor path across the diff `25c92c76^..HEAD` (implementation commit `46956936`, verified atomic — exactly the six `files_modified` paths). The core contract is implemented correctly: the flag arm mirrors `--width`, the absent-flag payload carries no `defaultIndex` key (verified end-to-end against a stub `omarchy-shell`), `MenuModel.dmenuDefaultIndex` is ES5-clean and correctly floor/NaN/clamp-guarded, and `openDmenu` assigns `selectedIndex` before `rebuildDisplay()` so the existing `rebuildDmenuDisplay` clamp bounds it. Both test files run green (menu-select: 10/10, menu-test: all assertions including the 11 new helper cases and 5 source pins). One robustness warning: flag values that perl `int()` numifies to non-finite (`1e1000`, `inf`, `nan`) emit bare `Inf`/`NaN` tokens — invalid JSON that `JSON.parse` rejects in `Menu.qml`, discarding the payload and hanging the CLI on `doneFile` forever. The same latent defect already exists in `--width`/`--maxheight`; the new arm inherits it.

## Warnings

### WR-01: Non-finite `--default-index` values emit invalid JSON and wedge the CLI on `doneFile` forever

**File:** `bin/omarchy-menu-select:97` (also `shell/plugins/menu/Menu.qml:23,27-31`, `bin/omarchy-menu-select:103-105`)
**Issue:** `$payload->{defaultIndex} = int($ARGV[6])` numifies the caller's string through perl `int()`. Values like `1e1000`, `inf`, `nan`, or `-inf` produce non-finite results, and `JSON::PP::encode_json` emits them as bare `Inf`/`NaN` tokens — which are not valid JSON. Proven against the real script: `omarchy-menu-select Pick a b c -- --default-index 1e1000` emits `{"defaultIndex":Inf,...}`. In the real shell path, `JSON.parse(payloadJson)` throws at `Menu.qml:23`, the catch substitutes `({})`, `payload.mode` is undefined, and `open()` falls through to `openRoute("root")` — the menu opens in menu mode instead of select mode, `mode` is `"menu"`, so `cancel()`/`finishRequest` never runs, `doneFile` is never created, and the `while [[ ! -e $done_file ]]` loop at `bin/omarchy-menu-select:103-105` spins forever even after the user dismisses the menu. This contradicts the phase threat model's claim that a hostile payload "can only move the highlight ... never ... wedge the menu". The identical defect already exists for `--width`/`--maxheight` (`--width 1e1000` emits `"width":Inf`), so this is a replicated pre-existing pattern rather than a new class of bug — but each new arm widens the surface, and a computed index is the most plausible of the three to receive a pathological value.
**Fix:** Validate the value as a plain integer before it reaches perl — either in bash at the case arm:

```bash
        --default-index)
          shift
          if (( $# == 0 )); then
            echo "omarchy-menu-select: --default-index requires a value" >&2
            exit 1
          fi
          if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
            echo "omarchy-menu-select: --default-index requires an integer" >&2
            exit 1
          fi
          menu_defaultindex="$1"
          ;;
```

or gate the emission in perl (`$payload->{defaultIndex} = int($ARGV[6]) if $ARGV[6] =~ /^-?\d+$/;`). The same guard applied to `menu_width`/`menu_maxheight` would close the pre-existing instances too, though that is outside this commit's scope.

**Resolution:** fixed in the `fix(04-01)` follow-up commit. Implemented perl-side, but coercing non-finite results to `0` rather than dropping the key — `("$di" =~ /^-?[0-9]+$/) ? $di + 0 : 0` — which preserves the locked "garbage → `defaultIndex:0`" contract (`abc`→0 e2e assertion still holds; a value-gate would have *omitted* the field and contradicted it). Also resolves IN-01: a flag-shaped token like `--width` numifies to 0 exactly as before, and non-finite strings can no longer reach the payload. New regression test `menu select coerces a non-finite default index to 0` runs the real script under `timeout 10` so a recurrence fails fast instead of hanging. The latent `--width`/`--maxheight` instances are pre-existing and out of this commit's scope — filed to `deferred-items.md`.

## Info

### IN-01: `--default-index` unconditionally swallows a flag-shaped value token

**File:** `bin/omarchy-menu-select:54-61`
**Issue:** The arm consumes the next token as its value regardless of shape: `-- --default-index --width 400` sets `menu_defaultindex="--width"` (→ `defaultIndex:0` via `int()`), `--width` is never parsed, and `400` is silently dropped as an unknown arg. The sibling arms behave identically (`--width --default-index` likewise captures the flag as the width), so this is consistent with existing semantics and the plan's "mirror `--width` exactly" instruction — but a numeric-value check (the same fix as WR-01) would turn this silent mis-parse into a clear error.
**Fix:** Covered by the WR-01 fix; a `^-?[0-9]+$` check rejects flag-shaped tokens with a clear message.

### IN-02: `dmenuDefaultIndex` QML property is write-once/read-once plumbing

**File:** `shell/plugins/menu/Menu.qml:63,874,878`
**Issue:** `property int dmenuDefaultIndex` is assigned at :874 and read exactly once at :878, then never touched again — `openExistingMenu` resets `selectedIndex` directly, so the property holds a stale value while the menu is in `menu`/`input` mode (harmless, but dead state). It could be inlined as `selectedIndex = MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)`. Keep-or-inline is a judgment call; the current shape does match the `dmenuWidth`/`dmenuMaxHeight` naming convention.
**Fix:** Optional — inline the helper call into the `selectedIndex` assignment, or leave as-is for readability/debuggability.

## Verified clean (no findings)

- **Back-compat contract:** absent flag → `menu_defaultindex=""` → `length("")` fails → no `defaultIndex` key (bin/omarchy-menu-select:97); grep sweep confirms no shipped caller under `bin/` passes the flag. `encode_json` key order is randomized regardless, so "byte-identical" correctly means key-set-identical — the test asserts absence, not byte equality.
- **Arg parsing:** flag parses only inside the post-`--` loop; stdin-fed options survive (`mapfile` runs after the arg loop, only when argv options are empty); missing value exits 1 with `requires a value` before any summon; no `*)` arm added.
- **Ordering invariant:** `dmenuOptions` (:868) → `dmenuDefaultIndex` (:874) → `selectedIndex` (:878) → `opened = true` (:881) → `rebuildDisplay()` (:882); `rebuildDmenuDisplay` re-clamps (:597-599) and `Qt.callLater(revealCursor)` (:601-603) scrolls the row into view; `cursorActive = mode !== "input"` (:879) means Enter hits `activateIndex(selectedIndex)` (:1161). Display indices align 1:1 with `dmenuOptions` at open since `filterText` is `""`.
- **MenuModel.js:** ES5 throughout (`var`/`function`, no arrows); `dmenuDefaultIndex` handles NaN/null/undefined/`{}`/`[]`/negative/float/`-0`/`Infinity` and `optionCount` of 0/NaN/negative; exported under the existing `typeof module` guard.
- **Test harness:** stub `omarchy-shell` captures `$4` and satisfies the `selectionFile`/`doneFile` handshake synchronously; env-prefix exports reach the stub through the script; `if run_select ... ; then` correctly guards the expected-failure case under `set -e`; file mode 644 is fine (runner invokes `bash "$test"`).
- **Style:** `#!/bin/bash`, `set -euo pipefail`, `[[ ]]`/`(( ))`, unquoted vars in `[[ ]]`, `menu_defaultindex` matches `menu_maxheight` naming, `# omarchy:args=`/`# omarchy:examples=` untouched.
- **Docs:** `docs/menu.md` "Select and input modes" documents the flag, the payload field, initial-only semantics, and absent-field row-0 default accurately.

---

_Reviewed: 2026-09-15T11:16:04Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
