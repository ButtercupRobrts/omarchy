# Phase 4: Menu `defaultIndex` plumbing — Pattern Mapping

Maps every file this phase touches to the closest existing analog in the codebase, with the concrete excerpts to copy. All line numbers verified against the working tree on 2026-09-15.

## File Inventory

| File | Change | Role / data flow | Closest existing analog |
|---|---|---|---|
| `bin/omarchy-menu-select` | modify | **Producer**: argv → JSON payload → `omarchy-shell shell summon` | itself — `--width`/`--maxheight` arm (lines 34–50) + optional-int perl fields (lines 84–85) |
| `shell/plugins/menu/Menu.qml` | modify | **Consumer/controller**: payload → `dmenu*` properties → `displayModel` | itself — `dmenuWidth`/`dmenuMaxHeight` coercion in `openDmenu` (lines 869–870); `resolveRoute` delegation to `MenuModel` (lines 891–893) |
| `shell/plugins/menu/MenuModel.js` | modify | **Pure logic** (node-testable): payload → clamped index | every existing helper — ES5 `function`+`var` style, guarded `module.exports` (lines 493–524) |
| `docs/menu.md` | modify | **Contract doc** for the payload schema | "Select and input modes" section (lines 156–167) — gains the flag doc |
| `test/shell.d/menu-test.sh` | modify (extend `run_node_test` block) | **Unit + source-contract tests** | existing block: `menu-test.sh:7–641` |
| `test/shell.d/menu-select-test.sh` *(new, name at discretion)* | create | **End-to-end payload test** via stub `omarchy-shell` | `menu-plugin-test.sh:9–66` stub-bin harness; `plugin-enable-test.sh:12–17` arg-recording `omarchy-shell` stub |

---

## 1. `bin/omarchy-menu-select` — add `--default-index N`

**Data flow:** `argv options` → collect until `--` → parse menu args → perl `encode_json` payload → `omarchy-shell shell summon omarchy.menu "$payload"` → block on `doneFile` → `cat selectionFile`.

### 1a. Variable declaration — copy the `menu_*=""` block (lines 25–27)

```bash
options=()
menu_width=""
menu_maxheight=""
```

**Add:** `menu_defaultindex=""` on the next line. Underscore name matches `menu_maxheight`.

### 1b. Post-`--` flag arm — copy the `--width` arm (lines 29–53)

```bash
while (( $# > 0 )); do
  if [[ $1 == "--" ]]; then
    shift
    while (( $# > 0 )); do
      case "$1" in
        --width)
          shift
          if (( $# == 0 )); then
            echo "omarchy-menu-select: --width requires a value" >&2
            exit 1
          fi
          menu_width="$1"
          ;;
        --height|--maxheight)
          arg="$1"
          shift
          if (( $# == 0 )); then
            echo "omarchy-menu-select: $arg requires a value" >&2
            exit 1
          fi
          menu_maxheight="$1"
          ;;
      esac
      shift
    done
    break
  fi

  options+=("$1")
  shift
done
```

**Add** a `--default-index` arm inside the `case`, mirroring `--width` exactly (kebab-case matches `--maxheight`; value-required guard with the same error shape):

```bash
        --default-index)
          shift
          if (( $# == 0 )); then
            echo "omarchy-menu-select: --default-index requires a value" >&2
            exit 1
          fi
          menu_defaultindex="$1"
          ;;
```

Unknown menu args are silently ignored today (no `*)` arm) — keep that; don't add one.

### 1c. Perl payload — copy the optional-int pattern (lines 76–87)

```perl
payload=$(perl -MEncode=decode -MJSON::PP=encode_json,decode_json -e '
  my $payload = {
    mode => "select",
    prompt => decode("UTF-8", $ARGV[0]),
    options => decode_json($ARGV[1]),
    selectionFile => decode("UTF-8", $ARGV[2]),
    doneFile => decode("UTF-8", $ARGV[3])
  };
  $payload->{width} = int($ARGV[4]) if length($ARGV[4] // "");
  $payload->{maxHeight} = int($ARGV[5]) if length($ARGV[5] // "");
  print encode_json($payload)
' "$prompt" "$options_json" "$selection_file" "$done_file" "$menu_width" "$menu_maxheight")
```

**Add** `$payload->{defaultIndex} = int($ARGV[6]) if length($ARGV[6] // "");` and append `"$menu_defaultindex"` as the last argv. This is the entire back-compat mechanism: flag absent → empty string → `length("")` false → field omitted → byte-identical payload for all 16 existing call sites (PITFALLS pitfall 2; verified 15 invocation sites in `bin/` plus `omarchy-menu-file`'s `"$@"` pass-through).

### 1d. Usage strings + header comment

- Lines 18 and 66 both print `Usage: omarchy-menu-select <prompt> [option...] [-- menu args...]` — mention the new flag (or leave the generic `[-- menu args...]` and document in the header comment + `docs/menu.md`; ARCHITECTURE.md line 74 says to mention it).
- Header comment lines 9–13 documents the row protocol — a good place to note `--default-index` pre-highlights row N.
- `# omarchy:args=` (line 6) stays unchanged — flags already live behind `[-- menu args...]`, and `test/cli` validates this metadata.

### 1e. Propagation for free

`bin/omarchy-menu-file:48` already forwards caller `"$@"` after `--`:

```bash
  omarchy-menu-select "$label" -- --width 800 --maxheight 500 "$@"
```

No change needed there — `--default-index` flows through wrappers automatically.

---

## 2. `shell/plugins/menu/Menu.qml` — consume `payload.defaultIndex`

**Data flow:** `openDmenu(payload)` → `dmenu*` properties → `rebuildDisplay()` → `rebuildDmenuDisplay()` → `displayModel` + `selectedIndex` clamp → Enter at `selectedIndex` via `activateIndex`.

### 2a. Property — copy lines 61–62

```qml
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
```

**Add:** `property int dmenuDefaultIndex: 0` beside them.

### 2b. `openDmenu` (lines 861–881) — the exact edit site

```qml
  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
```

Two changes:
1. After line 870: resolve the default through a new `MenuModel` helper (see §3) rather than inline `Math.max(0, Number(payload.defaultIndex || 0))` — D-03 wants the resolution node-testable. The delegation precedent is `resolveRoute` (lines 891–893):

```qml
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }
```

2. Line 874 `selectedIndex = 0` → `selectedIndex = dmenuDefaultIndex` (or assign directly from the helper call — either satisfies D-03; keeping a `dmenuDefaultIndex` property matches the `dmenuWidth`/`dmenuMaxHeight` shape).

### 2c. Free bounds-safety — `rebuildDmenuDisplay` clamp (lines 596–598)

```qml
    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
```

This runs inside `rebuildDisplay()` at line 878, after `selectedIndex` is set — D-04: out-of-range payload values clamp for free. At open `filterText` is `""`, so `displayModel` indices align 1:1 with `dmenuOptions` (the `continue` filter at lines 572–573 only fires under a query). `Qt.callLater(function() { ... root.revealCursor() })` at lines 600–602 scrolls the default row into view.

### 2d. Enter already hits the highlighted row — no wiring needed

`cursorActive = mode !== "input"` (line 875) plus the key handler (lines 1154–1158):

```qml
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
```

`activateIndex` (lines 759–787) dmenu branch returns `picked.label + "\t" + picked.detail` (line 768) — the subtext-return contract callers must strip (PITFALLS pitfall 1; `bin/omarchy-menu-plugin:36` `cut -f2` precedent).

### 2e. `setFilter` resets the cursor — add the "don't fix this" comment (D-05)

```qml
  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0          // ← resets on first keystroke; correct —
    root.cursorActive = root.mode !== "input"   //   defaultIndex is initial-only
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }
```

Add a comment on/near line 722 noting `defaultIndex` is an initial position, not a persistent anchor (typing means the user is searching).

---

## 3. `shell/plugins/menu/MenuModel.js` — add the index-resolution helper

**Data flow:** `(payload, optionCount)` → clamped non-negative integer → consumed by `Menu.qml` `openDmenu` and by node tests.

### Style rules visible in the file

- ES5 only: `function` declarations, `var`, no arrow functions, no `let`/`const`, no template literals — QML's JS engine and node both load it.
- Defensive coercions everywhere: `String(raw || "")`, `Array.isArray(itemOrder) ? itemOrder : []`, `items || ({})`.
- Doc comments explain *why*, not what (see the `mergeAppRows` orphan comment, lines 98–104).

### Suggested helper (name at agent's discretion per CONTEXT "Agent's Discretion")

```javascript
// defaultIndex positions the cursor on open; it is not a persistent anchor —
// setFilter resets selectedIndex to 0 on the first keystroke, which is right:
// typing means the user is searching, not confirming the caller's default.
function dmenuDefaultIndex(payload, optionCount) {
  var count = Number(optionCount) || 0
  var index = Math.floor(Number(payload && payload.defaultIndex))
  if (!(index > 0)) return 0          // catches NaN, negatives, 0
  if (index >= count) return count > 0 ? count - 1 : 0
  return index
}
```

(QML's `rebuildDmenuDisplay` clamp makes the upper bound redundant-but-harmless; keeping it in the helper makes the node test assert the whole contract in one place.)

### Export guard — copy lines 493–524

```javascript
if (typeof module !== "undefined") {
  module.exports = {
    guardReaders: GUARD_READERS,
    ...
    displayRow: displayRow
  }
}
```

**Add** `dmenuDefaultIndex: dmenuDefaultIndex,` to the exports object. The `typeof module !== "undefined"` guard is what lets QML `import` the file while node `require`s it — keep the guard shape exactly.

---

## 4. `docs/menu.md` — document the flag

**Site:** "Select and input modes" section, lines 156–167. Current text (lines 158–167):

```markdown
The same plugin doubles as the system's dmenu. `omarchy-menu-select` and
`omarchy-menu-input` summon it with a `mode: select` or `mode: input`
payload, then block on a tempfile handshake: the shell writes the selection
to `selectionFile` and touches `doneFile`, and cancellation (empty
selection) exits 1. A select option is `label`, `glyph\tlabel`, or
`glyph\tlabel\tsubtext` — the glyph shows but never returns, the subtext
renders under the label, filters with it, and comes back as
`label\tsubtext` so callers with same-named rows get a stable key. This is
how the pickers behind menu actions (`omarchy-menu-plugin`,
`omarchy-menu-timezone`, ...) present lists without owning any UI.
```

Note: the doc currently never mentions `width`/`maxHeight` either — so there is no payload-field list to append to. Add a sentence covering the `--`-args surface (`--width`, `--maxheight`, `--default-index N` → `defaultIndex` payload field, pre-highlights row N, initial-only). Style per AGENTS.md: full lines, no hard wrapping.

---

## 5. Tests — two layers, both from existing patterns

### 5a. Extend `test/shell.d/menu-test.sh`'s `run_node_test` block

Harness (lines 5–10):

```bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
```

(`run_node_test` itself is `base-test.sh:79–127`: pipes a JS prelude — `assert`/`assertEqual`/`assertDeepEqual`/`requireFromRoot`/`root`/`path` — plus the heredoc into `node`.)

Cover the new `MenuModel` helper: absent field → 0; `defaultIndex: 1` → 1; out-of-range → `count-1`; negative/`NaN`/non-numeric → 0; `optionCount` 0 → 0.

Also add a **file-read assertion** pinning the QML wiring — the established pattern is regex-over-source, e.g. lines 405–408:

```javascript
assert(
  /var icon = parts\.length > 1 \? parts\.shift\(\) : ""\s*\n\s*var label = parts\.shift\(\) \|\| ""\s*\n\s*var detail = parts\.join\("\\t"\)/.test(menuQml),
  'menu select mode reads a leading icon and a trailing subtext off an option'
)
```

Analogous assertion to add: `openDmenu` routes the payload field into `selectedIndex` (e.g. match `selectedIndex = ` inside the `openDmenu` body — see the `function ${functionName}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}` extraction idiom at lines 615–623).

### 5b. New stub-bin test for `omarchy-menu-select` payload emission

No `menu-select-test.sh` exists today; create one (name at discretion — `menu-select-test.sh` is the natural fit, and CONTEXT allows a new file under `test/shell.d/` conventions; `./test/shell` auto-discovers `*-test.sh`).

**Stub-bin skeleton** — from `menu-plugin-test.sh:9–47`:

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$FAKE_ROWS"
printf '%s\n' "$FAKE_PICK"
STUB
chmod +x "$STUB_DIR"/*
```

**`omarchy-shell` stub that records argv** — from `plugin-enable-test.sh:12–17`:

```bash
cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
printf 'ok\n'
SH
chmod +x "$TMPDIR/bin/omarchy-shell"
```

For `omarchy-menu-select` the stub must go one step further — it must **satisfy the tempfile handshake** or the script blocks forever on `doneFile` (`omarchy-menu-select:91–93`). The payload arrives as the stub's last arg (`"$4"` of `shell summon omarchy.menu <json>`); parse `selectionFile`/`doneFile` out of it (perl `decode_json` or python3 — JSON::PP is already a script dep), write the pick to `selectionFile`, touch `doneFile`, and record the raw payload for assertions. Then:

- Run `omarchy-menu-select Pick a b c -- --default-index 1` → captured payload contains `"defaultIndex":1`.
- Run without the flag → captured payload has no `defaultIndex` key (the back-compat assertion — the whole point of the phase).
- Optional: `--default-index` with no value → exits 1 with the `requires a value` message.

---

## Constraints carried into implementation (from PITFALLS/CONTEXT)

- **Never positional:** any flag-shaped token before `--` becomes a menu row; a positional default-index would corrupt all 16 call sites including the 5 stdin-fed ones (`omarchy-menu-timezone`, `omarchy-menu-keybindings`, `omarchy-menu-plugin`, both keybinding-list menus). Post-`--` only. (Pitfall 2, D-01)
- **Additive only:** field emitted iff flag passed; absent = byte-identical behavior. (D-02)
- **No new clamp logic:** `rebuildDmenuDisplay:596–598` already bounds `selectedIndex`. (D-04)
- **Initial-only:** `setFilter` resets to 0 on typing — keep, and comment it. (D-05)
- **Bash style:** `[[ ]]`/`(( ))`, unquoted vars in `[[ ]]`, `#!/bin/bash` shebang, `set -euo pipefail`. (AGENTS.md)
- **JS style:** ES5 `function`/`var` in `MenuModel.js`; QML delegates to `MenuModel.*` and stays thin.
- **Docs:** `docs/menu.md` is codebase reference (the right tree for the payload schema); `manual/` is end-user only.
- **Commit shape:** one atomic commit for the whole flag→payload→cursor path (CONTEXT specifics: "independently revertible").
