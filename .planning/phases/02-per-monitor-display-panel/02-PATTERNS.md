# Phase 2: Per-monitor Display panel - Pattern Map

**Mapped:** 2026-09-14
**Files analyzed:** 5 modified + 4 read-only contract references
**Analogs found:** 5 / 5 (every modified file has in-repo analogs; the only novel machinery — a `scalesWithCurrent` sorted-insert helper — composes existing `Model.js` primitives)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `shell/plugins/panels/monitor/Panel.qml` | QML bar-widget panel | request-response (stateProc poll → property fan-out → view) + action spawns | itself (large parts stay verbatim) + `shell/plugins/bar/Bar.qml` (`slotScreenName` own-screen idiom) + `shell/Ui/KeyboardPanel.qml` (`anchorWindow`/`screen`) + sibling panels (`network`, `power` argv call sites) | exact (partial-file analogs) |
| `shell/plugins/panels/monitor/Model.js` | pure-JS helper module | transform (scale math + displays JSON parse) | itself — all new helpers reuse `normalizeScale`/`cleanScale`/`matchingScaleIndex`/`availableScales` | exact |
| `bin/omarchy-monitor-state` | utility (state producer) | request-response (hyprctl → jq → 8 positional stdout lines) | itself — one-word jq projection extension; `test/shell.d/monitor-state-test.sh` pins the contract | exact |
| `test/shell.d/monitor-test.sh` | test | Node `run_node_test` over `Model.js` | itself + every `run_node_test` file (`app-search-test.sh`) | exact |
| `test/shell.d/monitor-state-test.sh` | test | stubbed-PATH fixture → real script → line-index asserts | itself (must-update assertions for the new `scale` field) | exact |
| `bin/omarchy-hyprland-monitor-scaling` | — NOT MODIFIED — CLI contract consumed by `setScale` | `[up|down|SCALE] [monitor]` positional args | Phase 1 verified contract (`01-VERIFICATION.md`) | constraint only |
| `shell/plugins/bar/Bar.qml` | — NOT MODIFIED — own-screen idiom source | `slotScreenName`/`slotWindow`/`targetWindow`/`injectProps` | constraint + analog | constraint only |
| `shell/Ui/KeyboardPanel.qml` | — NOT MODIFIED — `QsWindow` attached-property usage | `anchorItem.QsWindow.window` → `screen` | constraint + analog | constraint only |
| `shell/plugins/bar/BarModel.js` | — NOT MODIFIED — summon routing | `pickPanelSlot` already lands panels on the focused screen's instance | constraint only | constraint only |

## Pattern Assignments

### `shell/plugins/panels/monitor/Panel.qml` (QML panel)

The file is its own primary analog: state plumbing, cursor model, and section layout stay verbatim. Excerpts below mark **KEEP** (unchanged machinery to mirror), **REPLACE** (the code being deleted), and **ANALOG** (patterns imported from other files).

#### Pattern 1 — Own-screen resolution (the load-bearing pattern for SCALE-05)

**Why `bar` cannot identify the screen:** `Bar.qml` injects the *same* shared root `Item` into every widget instance on every screen (`Bar.qml:1999-2006`):

```qml
function injectProps() {
  var target = activeItem
  if (!target) return
  if ("bar" in target) target.bar = firstParty
    ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
```

Per-screen surfaces come from `Variants { model: Quickshell.screens; delegate: Component { BarPanel { screen: modelData } } }` (`Bar.qml:1196-1206`; `BarPanel` is a `PanelWindow` at `:1234`), and each `BarPanel`'s `ModuleSlot` Loaders create one widget instance inside that screen's window (`Bar.qml:1838-1872`). The only per-screen discriminator is the **window the instance lives in**, reachable via the `QsWindow` attached property.

**ANALOG — the canonical lookup chain** (`Bar.qml:380-382, 388-391, 708-711`):

```qml
function targetWindow(target) {
  return target && target.QsWindow ? target.QsWindow.window : null
}
function slotWindow(slot) {
  if (!slot) return null
  return targetWindow(slot.activeItem) || targetWindow(slot)
}
function slotScreenName(slot) {
  var window = slotWindow(slot)
  return window && window.screen ? String(window.screen.name || "") : ""
}
```

**ANALOG — widget-side `QsWindow` use** (`shell/Ui/KeyboardPanel.qml:66, 80`; `shell/plugins/bar/widgets/Tray.qml:119-120`):

```qml
readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
...
screen: anchorWindow ? anchorWindow.screen : null
```

**What to copy:** a `readonly` **bound** property on `root`, chained null-guards, `String(... || "")` coercion, `""` fallback — exactly `slotScreenName`'s shape:

```qml
readonly property var ownWindow: root.QsWindow ? root.QsWindow.window : null
readonly property string ownScreenName: ownWindow && ownWindow.screen ? String(ownWindow.screen.name || "") : ""
```

**Why bound, not computed once:** `Component.onCompleted: refresh()` (`Panel.qml:352`) can fire before the `QsWindow` attached property resolves; a binding re-evaluates on attach. Every consumer must tolerate `ownScreenName === ""` — `screen.name` is the connector name (`eDP-1`, `HDMI-A-1`), the same string `hyprctl monitors` reports (proven by `pickPanelSlot` matching `slotScreenName` against `Hyprland.focusedMonitor.name`, `Bar.qml:716-719, 736-740`; `BarModel.js:166-178`).

**Fallback:** mirror the existing focused-display loop shape but key on `name === ownScreenName`, falling back to the focused display while the name is empty:

```qml
function ownDisplay() {
  var fallback = null
  for (var i = 0; i < displays.length; i++) {
    var display = displays[i]
    if (!display) continue
    if (display.focused) fallback = display
    if (display.name === ownScreenName && ownScreenName !== "") return display
  }
  return fallback
}
```

**REPLACE — every `display.focused` lookup that decides what SCALE acts on** (`Panel.qml:45-52, 268-275, 277-284`):

```qml
readonly property var scaleValues: {
  for (var i = 0; i < displays.length; i++) {
    var display = displays[i]
    if (display && display.focused)
      return Model.availableScales(scalePresets, display.width, display.height)
  }
  return scalePresets
}
```

`activeScaleIndex()` (`:268-275`) and `effectiveScale(scale)` (`:277-284`) carry the identical loop; all three re-point at `ownDisplay()`. `MonitorRow.isFocused` (`:863`) keeps `.focused` semantics — the `· focused` row suffix is compositor truth, not targeting (D-05).

#### Pattern 2 — Process invocation (argv-array, re-spawn guard)

**REPLACE — the only `bash -c` scale call site** (`Panel.qml:307-310`):

```qml
function setScale(scale) {
  actionProc.command = ["bash", "-c", "omarchy-hyprland-monitor-scaling " + scale]
  if (!actionProc.running) actionProc.running = true
}
```

**ANALOG — sibling argv call sites with dynamic args** (all pass values as array elements, never string-interpolated):

- `Panel.qml:247` `["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]`
- `Panel.qml:303` `["hyprctl", "keyword", "monitor", name + (enabled ? ",disable" : ",preferred,auto,auto")]`
- `Panel.qml:336` `["omarchy-display-text-size", String(px)]`
- `network/Panel.qml:699` `["omarchy-network-band", band]`
- `power/Panel.qml:168` `["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]`

New shape — direct argv, monitor arg appended only when known (empty → the CLI's focused-default, `bin/omarchy-hyprland-monitor-scaling:79-83`):

```qml
function setScale(scale) {
  var cmd = ["omarchy-hyprland-monitor-scaling", String(scale)]
  if (root.ownScreenName !== "") cmd.push(root.ownScreenName)
  actionProc.command = cmd
  if (!actionProc.running) actionProc.running = true
}
```

**KEEP — the `if (!actionProc.running)` re-spawn guard** (`:304, :309`; same idiom at `:233` `refresh()`, `:337` `setTextSize`, and `stateProc` `:386`). `actionProc` is *shared* with `toggleDisplay` and its `onRunningChanged: if (!running) root.refresh()` (`:432-436`) re-polls after either action — do not add a second Process or a second refresh path. CONCERNS.md:70-76 flags unguarded Process re-spawns as a repo-wide hazard.

**When `bash -c` *is* used:** only where shell features are needed — pipes/conditionals inside `dnsCommand` (`network/Panel.qml:530, 733`), a multi-statement script (`:825`). `app-search-test.sh:126-129` additionally pins that `bash -c` call sites must not use `"-lc"` (login shells retrigger watchers). None of that applies to a two-arg CLI call — dropping `bash -c` is the convention-correct move.

#### Pattern 3 — Panel state parsing (positional lines → displays JSON)

**KEEP — `stateProc` line-index parsing** (`Panel.qml:386-405`):

```qml
Process {
  id: stateProc
  command: ["omarchy-monitor-state"]
  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: {
      var lines = String(text || "").split("\n")
      ...
      root.focusedMonitor = String(lines[5] || "").trim()
      root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
      root.updateDisplays(String(lines[7] || "[]").trim())
    }
  }
}
```

**KEEP — `updateDisplays`/`parseDisplays` pass-through** (`Panel.qml:293-297`; `Model.js:94-112`):

```qml
function updateDisplays(displaysJson) {
  var parsed = Model.parseDisplays(displaysJson)
  root.displays = parsed.displays
  root.enabledDisplayCount = parsed.enabledDisplayCount
}
```

`parseDisplays` returns parsed objects **verbatim** — a `scale` field added by the jq projection appears as `display.scale` on every row with zero parser changes. The 8-line positional contract is untouched (D-06).

**Contract reference — `bin/omarchy-monitor-state:22-23`** (the one-word change, `scale` added to the projection):

```bash
printf '%s\n' "$monitors_json" | jq -c \
  '[.[] | {name, enabled:(.disabled != true), focused:(.focused == true), width, height, scale}]'
```

`hyprctl monitors all -j` already carries `.scale` per monitor (the scaling CLI reads it, `bin/omarchy-hyprland-monitor-scaling:85`). Keep `monitors all -j` — plain `monitors -j` drops mirror and disabled outputs (`test/shell.d/monitor-modeless-test.sh:132`), which would desync the DISPLAYS rows from the CLI's view in exactly the mirrored case.

#### Pattern 4 — Scale pill row machinery (KEEP, plus one new helper)

**KEEP — the preset/match/effective chain** (`Panel.qml:44-52, 268-284`; `Model.js:7-11, 22-34, 36-53, 55-80`):

- `scalePresets` `["1","1.25","1.6","2","3","4"]` (`:44`)
- `availableScales(scales, w, h)` collapses presets that resolve to the same effective scale (`Model.js:55-80`)
- `matchingScaleIndex(scales, current, w, h)` finds the pill whose `cleanScale` equals `normalizeScale(current)` (`Model.js:36-53`)
- `activeScaleIndex()`/`effectiveScale()` bridge QML→Model (`:268-284`)

**KEEP — `ScalePill` + `Grid` reflow** (`:768-790, 833-856`):

```qml
Grid {
  id: scaleRow
  columns: root.scaleValues.length
  readonly property real cellWidth: root.scaleValues.length > 0
    ? (width - spacing * (columns - 1)) / columns : 0
  Repeater { model: root.scaleValues
    ScalePill { scaleValue: modelData; scaleIndex: index; width: scaleRow.cellWidth } }
}
```

`columns`/`cellWidth` recompute automatically when `scaleValues` grows 6→7 (dynamic pill appears) or shrinks 7→6 (after apply). Keyboard nav needs nothing new: `sectionCount("scale")` reads `scaleValues.length` (`:87`), `moveCursorH` clamps to `length-1` (`:135-141`), `clampCursor` re-clamps on `onScaleValuesChanged` (`:161-184, :373`), `activateCursor` → `setScale(scaleValues[selectedIndex])` (`:149-153`).

**NEW HELPER — `scalesWithCurrent` (D-04 dynamic pill), implemented in `Model.js` so it is Node-testable.** Insert the normalized current scale in numeric order only when `matchingScaleIndex` finds no preset match:

```js
function scalesWithCurrent(scales, currentScale, width, height) {
  if (!Array.isArray(scales)) return []
  if (matchingScaleIndex(scales, currentScale, width, height) >= 0) return scales
  var current = Number(normalizeScale(currentScale))
  if (!isFinite(current)) return scales
  var out = scales.slice()
  var at = out.length
  for (var i = 0; i < out.length; i++) {
    if (Number(out[i]) > current) { at = i; break }
  }
  out.splice(at, 0, normalizeScale(currentScale))
  return out
}
```

Then `scaleValues` wraps `availableScales(...)`: `Model.scalesWithCurrent(Model.availableScales(scalePresets, d.width, d.height), ownScale, d.width, d.height)`. `eDP-1` at 1.5 on 1920×1080 → `[1, 1.25, 1.5, 1.6, 2, 3, 4]` (7 pills); `matchingScaleIndex` then marks the inserted pill `active` with no new state tracking. **Add `scalesWithCurrent` to the `module.exports` block** (`Model.js:114-124`) or the Node test cannot see it.

**NEW PROPERTY — `ownScale`:** `normalizeScale(ownDisplay().scale)` falling back to `monitorScale` while the own display is unknown. Do **not** repurpose `monitorScale` (`:26`, set from `lines[6]` at `:401`) — see anti-patterns.

#### Pattern 5 — Header two-element pattern (SCALE — name · scale)

**ANALOG — every section header is `PanelSectionHeader` left + right-aligned status `Text`:**

```qml
Item {
  width: parent.width
  implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)
  PanelSectionHeader { id: scaleHeader; text: "SCALE"; anchors.left: parent.left; ... }
  Text { id: scaleMonitor; anchors.right: parent.right; anchors.rightMargin: Style.space(6); ... }
}
```

Identical shape at BRIGHTNESS (`:592-617`, right text `Math.round(...) + "%"`) and TEXT SIZE (`:665-692`, right text `... + "px"`).

**REPLACE — `scaleMonitor` text and visibility gate** (`:752-765`). Current:

```qml
Text {
  id: scaleMonitor
  textFormat: Text.PlainText
  text: root.focusedMonitor
  // Only worth naming when more than one display is in play.
  visible: root.focusedMonitor !== "" && root.enabledDisplayCount > 1
  color: Qt.darker(root.bar.foreground, 1.4)
  ...
}
```

Per D-03 the right text becomes the own-monitor name + scale using the **`· ` (middle-dot + space) separator convention** already established by `MonitorRow`'s `name + (focused ? " · focused" : "")` (`:896`):

```qml
text: root.ownScreenName + " · " + root.ownScale + "x"
visible: root.ownScreenName !== ""
```

Dropping the `enabledDisplayCount > 1` gate is what makes the single-monitor form `SCALE — eDP-1 · 1.5x` consistent (D-03, SCALE-07). Keep `textFormat: Text.PlainText` — connector names and scale strings must never be interpreted as markup.

#### Pattern 6 — DISPLAYS row rendering (scale suffix, visibility gating)

**KEEP — section gating** (`:794-802` separator + Column both `visible: root.displays.length > 1`; `visibleSections` pushes `"monitors"` under the same condition `:75-82`). SCALE-07 collapses automatically — leave all three gates alone.

**ADAPT — `MonitorRow` name Text** (`:894-903`). Current:

```qml
Text {
  textFormat: Text.PlainText
  text: monitorRow.display.name + (monitorRow.display.focused ? " · focused" : "")
  ...
  elide: Text.ElideRight
  width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
}
```

Per D-01 append the scale as another `· `-separated suffix; per D-02 the `MouseArea`/`canToggle` toggle (`:864, :917-927`) and the `󰄬` enabled check (`:905-914`) stay untouched. Scale comes from `monitorRow.display.scale` normalized through `root.normalizeScale` — gate the suffix on `display.enabled` (a disabled row's width/height are 0 and its stored scale is stale, RESEARCH Q8). Composition mirrors the existing ternary-chain style:

```qml
text: monitorRow.display.name
      + (monitorRow.display.enabled ? " · " + root.normalizeScale(monitorRow.display.scale) + "x" : "")
      + (monitorRow.display.focused ? " · focused" : "")
```

**KEEP — enabled dimming** (`:864` `canToggle` → `:873` `opacity: canToggle ? 1.0 : 0.45`), the `󰍹` row icon (`:884-892`), `CursorSurface` cursor plumbing (`:866-867`), and `isFocused`/`current` fill (`:863, :868-871`).

#### Keyboard summon routing — no code needed (context pattern)

`BarModel.pickPanelSlot` (`BarModel.js:166-178`) already prefers an open copy, then the focused screen's copy, then the drawn slot over the zero-size placeholder (`:142-155`). A `shell summon omarchy.monitor` lands on the focused screen's bar instance — which under D-05 targets its own screen. Self-consistent; no panel code touches this.

---

### `shell/plugins/panels/monitor/Model.js` (pure helpers)

**KEEP verbatim:** `clampBrightness`, `normalizeScale`, `gcd`, `cleanScale`, `matchingScaleIndex`, `availableScales`, `brightnessName`, `parseDisplays` (`:1-112`). ES5 style (`var`, `function`, no arrow functions) — every function is a top-level `function name(...)`.

**ADD:** `scalesWithCurrent` (shape specified above). Optionally a pure `findDisplayByName(displays, name)` if the planner wants the own-display loop Node-testable too — the QML-side `ownDisplay()` fallback logic can delegate to it.

**KEEP — guarded CommonJS export** (`:114-124`); add new names to the object:

```js
if (typeof module !== "undefined") {
  module.exports = {
    ...
    scalesWithCurrent: scalesWithCurrent
  }
}
```

This is what lets `run_node_test` `requireFromRoot('shell/plugins/panels/monitor/Model.js')` (`monitor-test.sh:8`) exercise helpers headlessly (CONVENTIONS.md:91-94).

---

### `bin/omarchy-monitor-state` (one-word jq extension, per D-06)

**REPLACE — line-7 projection** (`:22-23`): add `scale` to the object list. One word; everything else about the file stays — `monitors all -j` (`:6`), the bare `omarchy-hyprland-monitor-scaling` call feeding line 6 (`:20`), line ordering.

**Constraint:** the script's consumers read **by line index** — `Panel.qml:392-402` and `monitor-state-test.sh:45-57`. Adding a JSON *field* keeps the contract; adding/reordering a *line* breaks it (the test's own warning, `monitor-state-test.sh:32-34`).

---

### `test/shell.d/monitor-test.sh` (Node coverage for new helpers)

**KEEP — harness shape** (`:1-8`):

```bash
#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const monitor = requireFromRoot('shell/plugins/panels/monitor/Model.js')
```

`run_node_test` (`base-test.sh:79-127`) pipes a prelude (`pass`/`fail`/`assert`/`assertEqual`/`assertDeepEqual`/`requireFromRoot`) + the heredoc into `node`; TAP-flavored `ok -`/`not ok -`, first failure exits.

**GROW — assert cases for `scalesWithCurrent`** in the established `assertDeepEqual(actual, expected, 'monitor ...')` style (`:31-55`). Cases worth pinning: identity when current matches a preset; sorted insertion for a non-preset (1.5 between 1.25 and 1.6); identity when `currentScale` is non-finite/empty; insertion respecting mode-filtered `availableScales` output.

---

### `test/shell.d/monitor-state-test.sh` (fixture + expectation update — mandatory, same commit)

**KEEP — stubbed-PATH fixture pattern** (`:5-30`):

```bash
test_bin=$(mktemp -d)
monitors_file=$(mktemp)
cleanup() { rm -rf "$test_bin"; rm -f "$monitors_file"; }
trap cleanup EXIT

cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
[[ $* == "monitors all -j" ]] || exit 1
cat "$FAKE_MONITORS"
EOF
...
chmod +x "$test_bin"/*
```

Runner `monitor_state()` writes the fixture to `$monitors_file`, runs the real script with `PATH="$test_bin:$PATH"` + `FAKE_MONITORS` env, collects lines via `mapfile` (`:36-43`). `assert_line`/`assert_line_count` check by index (`:45-57`).

**REPLACE — fixtures gain `"scale":N`** (`:59-80`: `extended`, `mirrored`, `reverse_mirrored`, `clamshell`). Real `hyprctl` reports `scale` as a float (e.g. `1.500000`) — jq passes it through; pick integer-friendly values (`"scale":1.6` prints `1.6`).

**REPLACE — byte-for-byte line-7 assertions** (`:111-117`). These pin the exact JSON:

```bash
[[ ${state_lines[7]-} == '[{"name":"eDP-1","enabled":true,"focused":false,"width":1920,"height":1080,"scale":1.6},...]' ]] ||
  fail "monitor state lists every display for the panel" "actual: ${state_lines[7]-<missing>}"
```

Update both `extended` and `clamshell` expectations with `"scale":<n>` appended as the last key (jq emits keys in projection order — `name,enabled,focused,width,height,scale`). This is guaranteed breakage, not optional (RESEARCH risk 1).

**OPTIONAL — textual QML assertions** for `ownScreenName` sourcing and argv shape: `app-search-test.sh:82-113` is the idiom — `grep`/regex-extract a function body out of the QML file in the Node test, then `.includes(...)` on the fragment (e.g. pin that `setScale` builds an argv array containing `ownScreenName`, or that `scaleValues` consults `ownDisplay()`). `TESTING.md:90-92` endorses pinning invariants this way when QML can't run headless.

---

## Shared Patterns

### Own-screen identity (`QsWindow` attached property)
**Source:** `shell/plugins/bar/Bar.qml:380-391, 708-711`; `shell/Ui/KeyboardPanel.qml:66, 80`; `Tray.qml:119-120`
**Apply to:** `Panel.qml` — `readonly property string ownScreenName` resolved from `root.QsWindow.window.screen`, `""` fallback, kept a binding so pre-attach evaluation heals itself. **Never** derive screen identity from `root.bar` (shared root, `Bar.qml:1999-2006`) or `Quickshell.screens` index (order isn't connector-stable).

### argv-array Process spawns + re-spawn guard
**Source:** `Panel.qml:247, 303, 309, 336`; `network/Panel.qml:699`; `power/Panel.qml:168`; guard idiom `Panel.qml:233, 304, 309, 337`; CONCERNS.md:70-76
**Apply to:** `setScale` — `["omarchy-hyprland-monitor-scaling", String(scale)]` + conditional `ownScreenName` push; drop `bash -c` (no shell features in play); keep `if (!actionProc.running)` and the shared `actionProc`/`onRunningChanged → refresh()` path (`:432-436`).

### Focused-vs-own property discipline
**Source:** `Panel.qml:23, 26, 210-218, 400-401`
**Apply to:** `Panel.qml` — `focusedMonitor`/`monitorScale` keep **focused-monitor** semantics: they feed brightness `--monitor` (`:247`) and the IPC `state()` payload (`:210-218`), whose handler is registered first-come across per-screen instances (`:220-230`; `manageIpc: false :13`; collision documented at `runtime-smoke-test.sh:549-565`). Add **parallel** `ownScreenName`/`ownDisplay()`/`ownScale` — never redefine the shared names, or `state()` becomes instance-dependent.

### `· ` separator convention
**Source:** `Panel.qml:896` (`name · focused`); CONTEXT specifics (`02-CONTEXT.md:85-86`)
**Apply to:** `scaleMonitor` header text (`name · scale`) and `MonitorRow` scale suffix — same middle-dot + space, same PlainText, same `Qt.darker(root.bar.foreground, 1.4)` caption styling for the header element (`:758`).

### Section header pattern (PanelSectionHeader + right Text)
**Source:** `Panel.qml:592-617` (BRIGHTNESS), `:665-692` (TEXT SIZE), `:737-766` (SCALE)
**Apply to:** the SCALE header edit — keep `scaleHeader` PanelSectionHeader and the wrapping `Item` with `Math.max(...)` implicitHeight; only the right `Text`'s `text`/`visible` change.

### Bash test conventions
**Source:** `test/shell.d/base-test.sh`; TESTING.md; `docs/testing.md:120-137`
**Apply to:** both test files — `#!/bin/bash`, `set -euo pipefail`, source `base-test.sh`, `mktemp` + `trap ... EXIT`, stub executables on `PATH`, `OMARCHY_TEST_*`/fixture env vars, `pass`/`fail` TAP output, "assert the invariant, not the snapshot" — except where the contract itself is positional/byte-exact (line-7 JSON is pinned verbatim by design).

### QML conventions
**Source:** CONVENTIONS.md:75-102; `agents/skills/shell-dev.md`
**Apply to:** all `Panel.qml`/`Model.js` edits — `id: root`, grouped property banners, `Color.*`/`Style.*` tokens, `qs.Ui`/`qs.Commons` imports, targeted edits only (Nerd Font glyphs at `Panel.qml:472` `󰍺`/`󰍹`, `:535`, `:885`, `:907` `󰄬` — shell-dev.md:41-47).

## Anti-patterns to Avoid

| Anti-pattern | Why it bites | Citation |
|---|---|---|
| Unguarded `proc.running = true` / new `Process` per action | Double-spawns race `actionProc`'s shared `onRunningChanged → refresh()`; repo-wide flagged hazard | CONCERNS.md:70-76; `Panel.qml:304-310, 432-436` |
| Repurposing `focusedMonitor`/`monitorScale` to own-screen meaning | `stateIpc()` (`:210-218`) and the brightness `--monitor` arg (`:247`) share those fields; whichever per-screen instance owns the IPC handler answers for all — instance-dependent results | `Panel.qml:220-230`; `runtime-smoke-test.sh:549-565`; RESEARCH risk 4 |
| Wholesale `Panel.qml` rewrite | Raw Nerd Font glyphs (`󰍺 :472`, `󰍹 :535/:885`, `󰄬 :907`) can be stripped by editing tools — targeted edits only | `agents/skills/shell-dev.md:41-47`; CONCERNS.md:54-58 |
| Shipping the jq change without touching `monitor-state-test.sh` | `:112-116` asserts line-7 JSON byte-for-byte — guaranteed failure | RESEARCH risk 1; `monitor-state-test.sh:111-117` |
| `bash -c "... " + name` string interpolation for the monitor arg | Connector names are safe today, but argv-array is the sibling convention and removes quoting entirely; `bash -c` is reserved for pipes/scripts | `Panel.qml:308` (being replaced); `network/Panel.qml:530, 733, 825` (legit bash uses) |
| Reading `hyprctl monitors -j` (non-`all`) in a second Process | Drops mirror + disabled outputs → DISPLAYS rows desync; also races `stateProc`'s single update path | `test/shell.d/monitor-modeless-test.sh:132`; `bin/omarchy-monitor-state:6`; RESEARCH Q2 fallback note |
| Adding `import Quickshell.Hyprland` / `Hyprland.focusedMonitor` to the panel | Panel deliberately doesn't import it — `focusedMonitor` comes from state-script `lines[5]` (`:400`) refreshed on a 5 s timer (`:379-384`); D-05 targets the *hosting* screen, not focus | `Panel.qml:1-7, 379-384, 400`; RESEARCH Q8 |
| Snapshotting `ownScreenName` in `Component.onCompleted` or a plain property | `QsWindow` may not be attached yet — a binding re-evaluates on attach; a snapshot stays `""` | `Panel.qml:352`; RESEARCH Q1 reload note |
| Scale suffix / pill reads on disabled rows | Disabled displays carry `enabled:false`, `width/height:0` — `cleanScale`/`availableScales` already guard zero dims (`Model.js:26-27, 56`), but a stale stored `scale` would print nonsense | `Panel.qml:864, 873`; RESEARCH Q8 |

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scalesWithCurrent` helper in `Model.js` | transform (sorted insert) | pure function | No in-repo precedent for inserting a dynamic value into the preset ladder — but it composes three existing primitives (`matchingScaleIndex`, `normalizeScale`, splice) and plugs into the unchanged `scaleValues`/`ScalePill`/`matchingScaleIndex` machinery, so no new state tracking is needed. |

## Metadata

**Analog search scope:** `shell/plugins/panels/monitor/` (Panel.qml, Model.js, manifest.json), `shell/plugins/bar/` (Bar.qml, BarModel.js, widgets/Tray.qml), `shell/Ui/KeyboardPanel.qml`, `shell/plugins/panels/{network,power}/Panel.qml`, `bin/` (omarchy-monitor-state, omarchy-hyprland-monitor-scaling), `test/shell.d/` (base-test, monitor-test, monitor-state-test, monitor-modeless-test, app-search-test, runtime-smoke-test), `.planning/codebase/{CONVENTIONS,CONCERNS,TESTING}.md`, `agents/skills/shell-dev.md`
**Files scanned:** 20 (all analog paths verified against the tree; line numbers confirmed by direct read)
**Pattern extraction date:** 2026-09-14
