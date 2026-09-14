# Phase 2 Research: Per-monitor Display panel

**Researched:** 2026-09-14
**For:** PLAN of phase 2 (SCALE-05..SCALE-07), decisions D-01..D-05 already locked in `02-CONTEXT.md`

---

## Summary

The phase goal is achievable almost entirely inside `shell/plugins/panels/monitor/Panel.qml` + `Model.js`, plus one optional jq change in `bin/omarchy-monitor-state`. The key discovery: `Bar.qml`'s root is a **single shared Item** — per-screen identity does NOT come through the injected `bar` property (`Bar.qml:2002` injects the same `root` into every widget instance). The only per-screen discriminator is the window the widget instance lives in, reachable via the `QsWindow` attached property (`root.QsWindow.window.screen.name`) — the exact source `slotScreenName` uses (`Bar.qml:708-711`). Every `display.focused` lookup in the panel (`scaleValues` :45-52, `activeScaleIndex` :268-275, `effectiveScale` :277-284, `MonitorRow.isFocused` :863) becomes a `display.name === ownScreenName` lookup with a focused-display fallback.

Per-display scale plumbing is cheapest via a one-word jq addition in `omarchy-monitor-state:22-23` (`scale` is already a field of `hyprctl monitors -j`), but note the tension: `REQUIREMENTS.md:40` and `STATE.md:72` recorded an init decision preferring the panel read `hyprctl monitors -j` itself — planner should re-confirm which wins (analysis below favors extending the JSON; it does not touch the 8-line positional contract).

The apply path simplifies to direct argv — `["omarchy-hyprland-monitor-scaling", scale, ownScreenName]` — dropping the `bash -c` wrapper entirely, matching sibling Process call sites.

---

## Findings

### Q1 — Own-screen resolution

- `Bar.qml` root is one `Item` shared by all screens (`shell/plugins/bar/Bar.qml:11`). Per-screen surfaces come from `Variants { model: Quickshell.screens; delegate: Component { BarPanel { screen: modelData } } }` (`Bar.qml:1196-1206`; `BarPanel` is a `PanelWindow` at `:1234`).
- Each `BarPanel` contains `ModuleSlot`s whose Loaders create one widget instance per screen (`Bar.qml:1796-1872`). `injectProps` gives every instance `target.bar = root` — the SAME root (`Bar.qml:1999-2006`). **`root.bar` is screen-agnostic; it cannot identify the monitor.**
- The screen discriminator used by the bar itself: `slotScreenName(slot)` → `slotWindow(slot)` → `targetWindow(target)` → `target.QsWindow.window` → `window.screen.name` (`Bar.qml:708-711, 388-391, 380-382`). `QsWindow` is the attached window object on any Item inside a `QsWindow`/`PanelWindow`; widget code uses it directly (`Tray.qml:119-120` `anchorItem.QsWindow.window`; `KeyboardPanel.qml:66` `anchorItem.QsWindow.window` → `screen: anchorWindow ? anchorWindow.screen : null` at `:80`).
- `screen.name` is the connector name (`eDP-1`, `HDMI-A-1`) — the same string `hyprctl monitors` reports; proven because `pickPanelSlot` matches `slotScreenName` against `Hyprland.focusedMonitor.name` (`Bar.qml:716-719, 736-740`).
- **What the monitor panel's root should read:** a bound property like `readonly property string ownScreenName: { var w = root.QsWindow ? root.QsWindow.window : null; return (w && w.screen) ? String(w.screen.name || "") : "" }`. Equivalent safe source: `button.QsWindow.window` or `panel.anchorWindow` (KeyboardPanel exposes `readonly property var anchorWindow` at `Ui/KeyboardPanel.qml:66`, and its own `screen` at `:80` — `panel.screen.name` works once `panel` exists).
- **Zero-size placeholder** (center-anchored widget): the placeholder instance lives in the SAME bar window as the drawn copy (`BarModel.js:136-141`), so its `QsWindow.window.screen` is still correct — targeting is right even if the placeholder's panel were opened. `pickPanelSlot` already prefers drawn slots for routing (`BarModel.js:142-155, 166-178`).
- **Reload:** `Component.onCompleted: refresh()` (`Panel.qml:352`) can fire before `QsWindow` attaches — keep `ownScreenName` a *binding* (re-evaluates on attach) and fall back to the focused display while it is `""`.
- **Unplug:** the Variants delegate destroys the whole `BarPanel` subtree, widget and `KeyboardPanel` included — no stale instance survives (`KeyboardPanel.qml:343-344` also re-evaluates `Quickshell.screens` for its dismissal twins).

### Q2 — State plumbing

- `bin/omarchy-monitor-state` emits 8 positional lines (`:1-23`): brightness, internal, external, internal-enabled, mirror, focused-name, focused-scale, displays JSON. Line 7's JSON is built by `jq -c '[.[] | {name, enabled:(.disabled != true), focused:(.focused == true), width, height}]'` at `:22-23`.
- `hyprctl monitors all -j` already carries `.scale` per monitor (the scaling CLI reads it: `bin/omarchy-hyprland-monitor-scaling:16, 85`). **Adding `scale` to the jq projection is a literal one-word change** (`{name, enabled, focused, width, height, scale}`) and is non-breaking: the 8-line positional contract is untouched and `parseDisplays` (`Model.js:94-112`) passes parsed objects through verbatim, so `display.scale` simply appears on each row.
- **Consumers of the script / JSON shape:** only `Panel.qml:388` (`stateProc`) → `updateDisplays(lines[7])` (`:293-297, :402`) → `Model.parseDisplays`. The panel's IPC `state()` re-exposes `displays` (`:211-218`) — additive field is safe. Repo-wide grep for `omarchy-monitor-state`/`updateDisplays`/`parseDisplays` finds no other runtime consumer.
- **Test coupling:** `test/shell.d/monitor-state-test.sh:112-116` asserts the line-7 JSON **byte-for-byte**; fixtures lack `scale`, so expectations must be updated (either fixtures gain `"scale":N` or expected JSON gains `"scale":null`).
- **Tension to resolve:** `REQUIREMENTS.md:40` ("Rewriting `omarchy-monitor-state` positional contract — Panel reads `hyprctl monitors -j` itself") and `STATE.md:72` record an init decision for a separate hyprctl call; `02-CONTEXT.md` leans the other way. Adding a JSON field does not rewrite the *positional* contract (line count/order unchanged), and it keeps one Process/one update path instead of a second poll that races `stateProc`. If the planner prefers zero contract change, the fallback is a second `Process { command: ["hyprctl", "monitors", "all", "-j"] }` merged by `name` — note `monitors` (non-`all`) **drops mirror and disabled outputs**, so `all` is required to keep the DISPLAYS rows consistent (confirmed `test/shell.d/monitor-modeless-test.sh:132`).

### Q3 — Apply path

- Current: `setScale(scale)` → `actionProc.command = ["bash","-c","omarchy-hyprland-monitor-scaling " + scale]` (`Panel.qml:307-310`).
- Quickshell `Process.command` is an argv list executed directly — no shell. Sibling call sites pass dynamic args as array elements: `["omarchy-brightness-display","--no-osd","--monitor",root.focusedMonitor,percent+"%"]` (`:247`), `["hyprctl","keyword","monitor",name+...]` (`:303`), `["omarchy-display-text-size",String(px)]` (`:336`), `["omarchy-network-band",band]` (network `:699`), `["omarchy-powerprofiles-set",src,profile]` (power `:168`).
- **Recommended:** `actionProc.command = ["omarchy-hyprland-monitor-scaling", String(scale)]` + `root.ownScreenName` appended only when non-empty — safest quoting (none), and degrades to the CLI's focused-default when the screen is transiently unknown. `bash -c` is only needed where shell features are used (pipes, `&&`, globbing) — not here.
- CLI contract (Phase 1, verified): `[up|down|SCALE] [monitor]`; SCALE numeric 1..4 via `^[0-9]+([.][0-9]+)?$` + range check (`:582-583`); target resolved with `jq --arg monitor` over `hyprctl monitors -j`, `select(.name == $monitor)` — empty arg → focused (`:79-83`); unknown name → `"No such monitor"` exit 1; `$# > 2` rejected (`:544-547`). Screen names are connector names satisfying the CLI's own `^[A-Za-z0-9._-]+$` guard (`:98`).
- `actionProc` is shared with `toggleDisplay`; `onRunningChanged: if (!running) root.refresh()` (`:432-436`) already re-polls after apply — a failed target just refreshes with no error surfacing (see edge cases).

### Q4 — Header + dynamic pill

- **Header:** `PanelSectionHeader` `id: scaleHeader` `text: "SCALE"` at `Panel.qml:741-748`. The "name only when 2+ displays" logic is the right-aligned `scaleMonitor` `Text` at `:752-765`: `text: root.focusedMonitor`, `visible: root.focusedMonitor !== "" && root.enabledDisplayCount > 1`. D-03's `SCALE — HDMI-A-1 · 1.6x` maps most naturally onto this existing two-element header pattern (same as brightness's `BRIGHTNESS` + `percent%` at `:596-616` and `TEXT SIZE` + `px` at `:669-691`): keep `scaleHeader` and make the right text `ownScreenName + " · " + ownScale + "x"`, dropping the `enabledDisplayCount > 1` gate.
- **Pills:** `scaleRow` `Grid` `:768-790` — `columns: root.scaleValues.length`, `Repeater { model: root.scaleValues }` of `ScalePill` (`:833-856`): `text: root.effectiveScale(scaleValue) + "x"`, `active: root.activeScaleIndex() === scaleIndex`, `onClicked: root.setScale(scaleValue)`. `cellWidth` (`:774-776`) resizes automatically when the count changes.
- **`matchingScaleIndex` machinery carries the dynamic pill for free:** `activeScaleIndex()` (`:268-275`) matches `cleanScale(candidate, w, h) === normalizeScale(current)` (`Model.js:36-53`) — inserting the normalized current value into `scaleValues` makes that pill `active` with no new state tracking.
- **Insertion point:** implement in `Model.js` as a pure helper (Node-testable), e.g. `scalesWithCurrent(scales, currentScale, width, height)` returning `scales` unchanged when `matchingScaleIndex(...) >= 0`, else `scales` plus `normalizeScale(current)` spliced in numeric order. `scaleValues` (`:45-52`) then wraps `availableScales(...)` with it. Example: `eDP-1` at 1.5 on 1920×1080 → `[1, 1.25, 1.5, 1.6, 2, 3, 4]` (7 pills).
- **Keyboard nav implications:** `sectionCount("scale")` already returns `scaleValues.length` (`:87`); `moveCursorH` clamps to `length-1` (`:135-141`); `clampCursor` (`:161-184`) re-clamps on `onScaleValuesChanged` (`:373`); `activateCursor` calls `setScale(scaleValues[selectedIndex])` (`:149-153`) — activating the current pill re-applies the same value (harmless no-op through the CLI). Grid column count grows/shrinks when the dynamic pill appears/disappears after apply — a 7→6 reflow, acceptable.

### Q5 — Single-monitor behavior

- With `displays.length == 1` today: `visibleSections` yields `[brightness?, "textsize", "scale"]` — no `"monitors"` (`:75-82`); the DISPLAYS `Column` and its separator are `visible: root.displays.length > 1` (`:795-802`); `scaleMonitor` header text hides via `enabledDisplayCount > 1` (`:757`); hero icon picks `󰍹` (`:535`); pills and keyboard nav work unchanged (single monitor is always `focused`).
- **SCALE-07 needs little beyond preserving `displays.length > 1` gating** plus the header-form decision (D-03 leaves it discretionary — showing `SCALE — eDP-1 · 1.5x` on a single monitor is consistent with D-03's rationale and simplest: drop the count gate entirely). One subtlety: `enabledDisplayCount` counts `enabled === true` rows — a disabled second monitor would make `displays.length == 2` but `enabledDisplayCount == 1`; today the header uses `enabledDisplayCount` while the section uses `displays.length`. Reusing `displays.length > 1` vs `enabledDisplayCount > 1` for the header gate is a planner detail.

### Q6 — Testing

- **`test/shell.d/monitor-test.sh`** — Node unit tests of `Model.js` via `run_node_test` + `requireFromRoot` (`base-test.sh:79-127`). Any new Model helpers (own-display lookup, `scalesWithCurrent`) get direct coverage here; existing `availableScales`/`matchingScaleIndex`/`cleanScale` cases at `:15-55` are the pattern.
- **`test/shell.d/monitor-state-test.sh`** — bash suite stubbing `hyprctl`/`omarchy-brightness-display`/`omarchy-hyprland-monitor-scaling` on PATH (`:14-30`), asserts all 8 lines by index (`:45-57`) and exact line-7 JSON (`:112-116`). Must be updated if `scale` is added.
- **Textual QML assertions** are an established pattern (`TESTING.md:90-91`; `app-search-test.sh:82-113` regex-extracts function bodies) — can pin e.g. `ownScreenName` sourcing or argv shape without a compositor.
- **`runtime-smoke-test.sh:543-546`** opens/closes `omarchy.monitor` via IPC under a real (compositor-gated) test shell — catches load-time QML errors; `:549-565` documents the one-IPC-handler-per-screen collision (first registration wins; direct `omarchy.monitor` IPC reaches an arbitrary instance — self-consistent under D-05 since whichever panel you see targets its own screen).
- **`test/acceptance.d/panels-test.sh`** opens the monitor panel in a VM and screenshots (`:66-69`) — runs only in the omarchy-iso VM, not in-session.
- **Headless panel targeting cannot be exercised** — `QsWindow`/screen bindings need a running shell. `visual-verification.md` applies: `omarchy-restart-shell` after QML edits, `omarchy capture screenshot fullscreen save`, `wtype` for keyboard paths. The user's real setup (eDP-1@1.5 non-preset + HDMI-A-1@1.6 at -1200x0) is the verification fixture from `02-CONTEXT.md:85`.
- `test/cli` metadata lint unaffected: `omarchy-monitor-state` keeps `summary`/`group` (no args change); the scaling CLI's `omarchy:args=[up|down|SCALE] [monitor]` was already updated in Phase 1 (`bin/omarchy-hyprland-monitor-scaling:4`).

### Q7 — Plugin vs source

- Confirmed first-party plugin at `shell/plugins/panels/monitor/`: `manifest.json` (`id: omarchy.monitor`, `kinds: ["bar-widget"]`, `entryPoints.barWidget: Panel.qml`, `allowMultiple: false`), `Panel.qml`, `Model.js`. This is source-tree development — no clone needed for the final change (PROJECT.md allows clone iteration for hot-reload).
- `Model.js` is consumed only by this `Panel.qml` — grep for `cleanScale|matchingScaleIndex|normalizeScale|availableScales|parseDisplays|brightnessName|clampBrightness` across `shell/` hits only the monitor panel (audio's `Panel.qml:420` comment references the same *ladder idea*, not the module). No osk or other widget shares it or the state contract.
- `omarchy-monitor-state` likewise serves only this panel plus `monitor-state-test.sh`.
- IPC: each per-screen instance registers `IpcHandler target: "omarchy.monitor"` (`:220-230`, `manageIpc: false :13`) — first registration wins for direct `omarchy-shell omarchy.monitor <fn>` calls; `shell summon omarchy.monitor` instead routes through `findPanelWidget`/`pickPanelSlot` → focused screen's instance (`Bar.qml:726-756`, `BarModel.js:166-178`).

### Q8 — Edge cases

- **Mirrored displays:** `omarchy-monitor-state` uses `monitors all -j`, so mirror rows appear in the DISPLAYS JSON with `enabled`/`scale`. But the scaling CLI selects from `hyprctl monitors -j` (non-`all`), which **drops mirror outputs** (`test/shell.d/monitor-modeless-test.sh:132`) — `omarchy-hyprland-monitor-scaling 1.6 <mirror-name>` exits 1 `"No such monitor"`. If Quickshell still reports the mirrored screen, that bar's pills will fail quietly (Process exits → `refresh()` only, `:435`). Mirroring is an explicit user action (`omarchy-hyprland-monitor-internal-mirror`); planner should decide whether to detect `mirrorOf`/non-selectable targets or accept the silent no-op.
- **Disabled displays:** rows carry `enabled:false`, `width/height:0`; `MonitorRow` already dims and blocks toggle-off of the last display (`:864, :873`); `cleanScale`/`availableScales` guard zero dims (`Model.js:27, 56`). A `scale` suffix on a disabled row would show whatever hyprctl last reported — planner may gate the suffix on `enabled`.
- **Screen unplug while open:** delegate destruction removes the instance and its KeyboardPanel; no code needed. The *other* screens' panels are unaffected.
- **`Hyprland.focusedMonitor` changing while open:** Panel.qml does **not** import `Quickshell.Hyprland` — its `focusedMonitor` is `lines[5]` from the state script (`:400`), refreshed every 5 s while open (`:379-384`). Under own-screen targeting, focus movement only affects which row shows `· focused`; the apply target stays the hosting screen.
- **`focusedMonitor` property's current role:** declared `:23`; feeds (a) brightness `--monitor` arg (`:247`), (b) `stateIpc` field (`:214`), (c) the SCALE header label (`:755`). Keep it for (a)/(b); only (c) switches to own-screen. **Do not repurpose `monitorScale`** (`:26`, set from `lines[6]` at `:401`, exposed via `stateIpc :215`) to own-screen semantics — the IPC `state()` result would become instance-dependent (whichever instance owns the handler answers). Add a separate `ownScale` property instead.
- **Transient empty `ownScreenName`** (pre-attach, or a screen not present in the displays JSON): every lookup needs a focused-display fallback so `scaleValues`/`activeScaleIndex`/`effectiveScale` never return empty mid-bind.

## Risks / Pitfalls

1. **Test breakage is guaranteed, not optional:** `monitor-state-test.sh:112-116` pins line-7 JSON byte-for-byte — plan a fixture + expectation update in the same commit as the jq change.
2. **Mirror targets are unreachable through the Phase-1 CLI** (`monitors -j` drops mirrors) — pills on a mirrored screen's bar silently no-op. Detect-and-hide vs. accept is a planner call.
3. **Dynamic pill index churn:** after applying a preset, the current pill disappears → `scaleValues` shrinks 7→6 → cursor `selectedIndex` re-clamps (`clampCursor` covers this) but a mid-row `selectedIndex` can land on a different preset after refresh. Cosmetic; acceptable.
4. **Don't leak own-screen semantics into shared state:** `monitorScale`/`stateIpc`/`focusedMonitor` have focused-monitor meaning for brightness + IPC — add parallel own-* properties rather than redefining.
5. **Nerd Font glyphs** in Panel.qml (`󰍺` :472/535, `󰍹`, `󰄬` :907) — targeted edits only, no wholesale rewrite (`shell-dev.md:41-47`).
6. **`bash -c` removal is safe** but keep the `if (!actionProc.running)` guard pattern (`:309`) — CONCERNS.md:70-76 flags unguarded Process re-spawns as a repo-wide hazard.
7. **Direct `omarchy.monitor` IPC `open`** reaches the first-registered instance on an arbitrary screen (`runtime-smoke-test.sh:549-565` documents the collision) — self-consistent under D-05, but the *summon* path (`shell summon`) is the one that lands on the focused screen; no code change needed, worth a plan note.
8. **Visual verification is mandatory** (`visual-verification.md`): restart shell, open the panel on each screen, screenshot both headers/pill rows, exercise h/l + Enter with `wtype`.

## Recommended approach

1. **`bin/omarchy-monitor-state:22-23`** — add `scale` to the jq projection (pending planner confirmation of the REQUIREMENTS/STATE tension; recommended — single Process, single update path, positional contract untouched). Update `monitor-state-test.sh` fixtures + expected JSON in the same commit.
2. **`Panel.qml` targeting** — add `readonly property var ownWindow` / `readonly property string ownScreenName` resolved from `root.QsWindow.window.screen` (mirroring `slotScreenName`), plus `function ownDisplay()` returning `displays.find(name === ownScreenName)` with focused-display fallback. Re-point `scaleValues`, `activeScaleIndex`, `effectiveScale` at `ownDisplay()`.
3. **`ownScale`** — `normalizeScale(ownDisplay().scale)` fallback `monitorScale`; keep `monitorScale`/`focusedMonitor` semantics for brightness + `stateIpc`.
4. **`Model.js`** — add `scalesWithCurrent(scales, currentScale, width, height)` (sorted numeric insertion when `matchingScaleIndex` finds no match); wire into `scaleValues`. Node-test in `monitor-test.sh`.
5. **`setScale`** — `actionProc.command = ["omarchy-hyprland-monitor-scaling", String(scale)]` plus `root.ownScreenName` appended when non-empty; drop `bash -c`.
6. **Header (D-03)** — `scaleMonitor` text → `ownScreenName + " · " + ownScale + "x"`, visible whenever `ownScreenName !== ""` (drop `enabledDisplayCount > 1`).
7. **DISPLAYS row (D-01)** — `MonitorRow` name text → `display.name + (display.scale ? " · " + Model.normalizeScale(display.scale) + "x" : "") + (display.focused ? " · focused" : "")` — preserves click-to-toggle (D-02) and the `displays.length > 1` gate (SCALE-07).
8. **Verify** — `bash test/shell.d/monitor-test.sh`, `monitor-state-test.sh`, `monitor-scaling-test.sh`, `./test/cli`; then `omarchy-restart-shell` + screenshots on both monitors (eDP-1@1.5 exercises the dynamic pill; HDMI-A-1@1.6 exercises targeting + position preservation end-to-end).

## Open questions

- **Plumbing confirmation:** extend `omarchy-monitor-state`'s JSON (recommended) vs. a second `hyprctl monitors all -j` Process in the panel — REQUIREMENTS.md:40/STATE.md:72 lean the latter, 02-CONTEXT leans the former.
- **Single-monitor header form:** `SCALE — eDP-1 · 1.5x` (recommended, consistent with D-03) vs. bare `SCALE`.
- **Should brightness `--monitor` also switch to `ownScreenName`?** Today it adjusts the *focused* display's brightness (`:247`); own-screen would be more consistent but is arguably out of scope ("Brightness controls — already functional", PROJECT.md:34).
- **Mirror-name target:** silently fail (CLI exit 1) vs. detect `mirrorOf` and disable pills on that screen's bar.
- **Disabled-display rows:** show the `· Nx` suffix or suppress it when `enabled === false`.
- **Dynamic pill position:** numeric-sorted insertion (recommended) vs. appended at the end.
- **`stateIpc` shape:** add `ownScreen`/`ownScale` fields for completeness, or leave the IPC surface untouched.
