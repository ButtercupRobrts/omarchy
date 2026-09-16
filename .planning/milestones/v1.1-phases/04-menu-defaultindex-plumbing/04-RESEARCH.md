# Phase 4: Menu `defaultIndex` plumbing — Research

**Researched:** 2026-09-15
**Confidence:** HIGH — every integration point re-verified against the working tree (line numbers below are current, not from milestone research)
**Scope note:** Decisions D-01..D-07 in `04-CONTEXT.md` are locked; this document covers only what the planner still needs: the verified data flow, the exact caller inventory, the payload transport, and the validation design. `04-PATTERNS.md` already maps each edit site to its copy-from analog with excerpts — read it alongside this file.

---

## 1. What is locked (do not re-litigate)

- `--default-index N` is a **post-`--` menu arg** in `omarchy-menu-select`, beside `--width`/`--maxheight` (D-01). Never positional — every token before `--` becomes a menu row, and stdin-fed callers read options via `mapfile` when argv options are empty (`bin/omarchy-menu-select:61-63`).
- Payload gains optional `defaultIndex` int, emitted **only when the flag was passed** — absent field = byte-identical payload (D-02). The perl block's `int($ARGV[n]) if length($ARGV[n] // "")` pattern is the mechanism.
- Index resolution lives in `MenuModel.js` as a plain, node-testable function (D-03); `openDmenu` initializes `selectedIndex` from it instead of the hardcoded `0` (`Menu.qml:874`).
- No new validation code — `rebuildDmenuDisplay`'s existing clamp (`Menu.qml:596-598`) handles out-of-range (D-04).
- `defaultIndex` is initial-only; `setFilter` resetting `selectedIndex` to 0 on first keystroke stays, plus a "don't fix this" comment (D-05).
- Document the flag in `docs/menu.md` (D-06). One atomic, independently revertible commit is preferred.

## 2. Verified end-to-end data flow (select mode)

```
bin/omarchy-menu-select
  argv: <prompt> [option...] [-- menu args...]
  post-"--" case loop ................. lines 32-53  (add --default-index arm here)
  stdin fallback: mapfile -t options .. lines 61-63  (only when zero argv options)
  perl JSON::PP payload ............... lines 76-87  (add $ARGV[6] → defaultIndex)
  omarchy-shell shell summon omarchy.menu "$payload"  line 89
  poll: while [[ ! -e $done_file ]] ... lines 91-93
  cat $selection_file / exit 1 ........ lines 95-99

bin/omarchy-shell
  3-arg summon gets "{}" appended ..... lines 51-53  (our call has 4 args — unaffected)
  qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@" ... line 59  (argv verbatim, timeout 2s)

shell/shell.qml
  IPC summon(id, payloadJson) ......... lines 1704-1706
  shell.summon() → pendingPayloads queue  lines 1141-1179 (payload stashed at 1172)
  deliverIfLoaded() → loader.item.open(payloadJson)   lines 1242-1257

shell/plugins/menu/Menu.qml
  open(payloadJson): JSON.parse, mode dispatch  lines 21-32
  openDmenu(payload) .......................... lines 861-881
    dmenuWidth = Math.max(1, Number(payload.width || 300))        line 869
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))  line 870
    selectedIndex = 0            ← line 874, THE edit site
    cursorActive = mode !== "input"  ← line 875, already true for select
    rebuildDisplay() → rebuildDmenuDisplay()  ← line 878 → 606-609 → 553-603
  rebuildDmenuDisplay
    option split: icon/label/detail at "\t"     lines 568-571
    filter skip (query non-empty)               lines 572-573
    selectedIndex clamp [0, count-1]            lines 596-598
    Qt.callLater(revealCursor)                  lines 600-602  (scrolls default row into view)
  Enter key → activateIndex(cursorActive ? selectedIndex : 0)   lines 1154-1157
  activateIndex dmenu branch: bounds-guard 766; writes "label[\tdetail]"  lines 766-768
  applyDmenuSelection → finishRequest(selection)  lines 815-820 → 117-135
    resultProc: printf selection > selectionFile; : > doneFile   line 132
    cancel: : > doneFile only → empty selection_file → script exits 1
```

Key invariants the plan can rely on:

- **Ordering inside `openDmenu`:** `dmenuOptions` is assigned (865), then `selectedIndex` (874), then `rebuildDisplay()` (878). Any value assigned at 874 gets clamped by the rebuild at 596-598 — so resolving `defaultIndex` before `rebuildDisplay()` is both necessary and sufficient for safety.
- **Index alignment:** `defaultIndex` is a `dmenuOptions` index; `selectedIndex` is a `displayModel` index. At open `filterText` is `""` so every option is appended in order — 1:1. After a keystroke they diverge, but `setFilter` resets to 0 anyway, so the initial-only semantics stay coherent.
- **Enter path needs zero wiring:** `cursorActive` is already `true` in select mode (875); Enter hits `activateIndex(selectedIndex)` (1157).
- **Input mode ignores the field naturally:** `cursorActive` false, `rebuildDmenuDisplay` early-returns (557-560), Enter returns `filterText`. `omarchy-menu-input` keeps its own arg loop (only `--width`) — no change needed there.
- **`width`/`maxHeight` consumption for contrast:** they're `Style.space()` units — `cardWidth` (111) and `dmenuRowListHeight` (205). `defaultIndex` is a raw index, not a space unit; it is consumed once at open and never referenced again. A `dmenuDefaultIndex` property is optional — assigning `selectedIndex = MenuModel.<helper>(payload, dmenuOptions.length)` directly also satisfies D-03.

## 3. Payload transport — limits and escaping

`$payload` travels as **one quoted argv element** end to end:

`omarchy-menu-select` → `omarchy-shell` argv → `qs ipc call --` argv → IPC method `summon(id, payloadJson)` → `pendingPayloads` string queue → `open(payloadJson)` → `JSON.parse`.

- **No shell re-parsing anywhere.** The JSON is never eval'd or word-split; quoting is preserved through every hop. `Util.shellQuote` is used only for the *selection write-back* paths (`Menu.qml:130-132`), not for the inbound payload.
- **No size constraint of concern.** Ceiling is ARG_MAX (~2 MB); today's largest payloads (keybindings menus, several hundred rows) already pass through fine. `defaultIndex` adds ~17 bytes.
- **No schema validation in the middle.** `omarchy-shell` passes the payload opaquely; `summon` treats it as a string. A new field is invisible to everything except `openDmenu` — this is what makes the change end-to-end additive.
- **Failure surface:** `qs ipc` wrapped in `timeout 2s` (`omarchy-shell:58-59`); a non-running shell fails the summon but `omarchy-menu-select` would still poll `done_file` forever — pre-existing behavior, unchanged by this phase.

## 4. Caller inventory — verified sweep list

Milestone research says "16 callers"; the verified count is **15 direct `omarchy-menu-select` invocation sites in 12 files**, plus a forwarding wrapper and a routed entry path. The sweep should cover this list, not the number 16.

### Direct call sites in `bin/`

| File:line | Options source | Post-`--` args today |
|---|---|---|
| `bin/omarchy-webapp-remove:39` | argv array | `--width 520 --maxheight 520` |
| `bin/omarchy-tui-remove:22` | argv array | `--width 520 --maxheight 520` |
| `bin/omarchy-theme-remove:12` | argv array | `--width 520 --maxheight 520` |
| `bin/omarchy-capture-screenrecording-with-webcam:15` | argv array | `--width 520 --maxheight 520` |
| `bin/omarchy-games-retro-install:17` | argv array | none |
| `bin/omarchy-transcode:179` | argv `jpg png` | none |
| `bin/omarchy-transcode:181` | argv `mp4 gif` | none |
| `bin/omarchy-transcode:187` | argv `high medium low` | none |
| `bin/omarchy-transcode:189` | argv `4k 1080p 720p` | none |
| `bin/omarchy-menu-timezone:9` | **stdin** (`timedatectl` pipe) | `--width 520 --maxheight 520` |
| `bin/omarchy-menu-keybindings:660` | **stdin** (`cut` pipe) | `--width 800 --height 500` |
| `bin/omarchy-menu-tmux-keybindings:137` | **stdin** (`printf` pipe) | `--width 800 --height $menu_height` |
| `bin/omarchy-menu-herdr-keybindings:231` | **stdin** (`printf` pipe) | `--width 800 --height $menu_height` |
| `bin/omarchy-menu-plugin:33` | **stdin** (herestring) | none |
| `bin/omarchy-menu-file:48` | **stdin** (find|sort|cut pipe) + forwarded `"$@"` | `--width 800 --maxheight 500 "$@"` |

### Indirect callers via `omarchy-menu-file` (free pass-through)

`omarchy-menu-file` appends caller `"$@"` *after* `-- --width 800 --maxheight 500`, i.e. inside menu-select's post-`--` loop — `--default-index` propagates through it with no edit. Its callers: `bin/omarchy-transcode:169` and `bin/omarchy-games-retro-install:22` (both pass no extra args today).

### Routed entry path

`omarchy menu select …` resolves through `bin/omarchy`'s longest-prefix router (`resolve_direct_route`, ~lines 389-406) and `exec`s `bin/omarchy-menu-select` with args verbatim — same binary, no shim. Both entry paths reach the same parser.

### Why none can be affected

- The flag lives behind `--`; a caller that doesn't pass it produces `menu_defaultindex=""` → `length("")` fails → **no `defaultIndex` key in the payload** → `payload.defaultIndex` is `undefined` in QML → the helper must return 0 → behavior byte-identical.
- The stdin fallback (`mapfile`, lines 61-63) is untouched; post-`--` parsing is orthogonal to where options came from.
- Unknown post-`--` args are silently ignored today (no `*)` arm in the case) — keep that; adding `--default-index` doesn't change tolerance for other args.

## 5. Per-file change map (details + excerpts in `04-PATTERNS.md`)

| File | Change |
|---|---|
| `bin/omarchy-menu-select` | `menu_defaultindex=""` var (~line 27); `--default-index` case arm mirroring `--width` (value-required guard, assign `menu_defaultindex="$1"`); perl: `$payload->{defaultIndex} = int($ARGV[6]) if length($ARGV[6] // "");` + append `"$menu_defaultindex"` to argv; mention flag in header comment (9-13) and both usage strings (18, 67). `# omarchy:args=` line 6 unchanged (`test/cli:606-611` lints shape, not content) |
| `shell/plugins/menu/MenuModel.js` | New ES5 helper, e.g. `dmenuDefaultIndex(payload, optionCount)`, defensive-coercion style (`Number(...)`, `Math.floor`, NaN-safe); add to guarded `module.exports` (493-524) |
| `shell/plugins/menu/Menu.qml` | In `openDmenu`: resolve default via `MenuModel.<helper>` and assign `selectedIndex` from it (replaces line 874); optional `property int dmenuDefaultIndex: 0` beside lines 61-62 for shape-consistency; comment near `setFilter`'s `selectedIndex = 0` (722) noting initial-only semantics |
| `docs/menu.md` | "Select and input modes" (156-167): document the `--` menu-args surface incl. `--default-index N` → `defaultIndex` field → pre-highlights row N, initial-only. Note: `width`/`maxHeight` are currently undocumented there too — one covering sentence is enough |
| `test/shell.d/menu-test.sh` | Extend `run_node_test` block: unit cases on the helper + regex-over-source pin on `openDmenu` wiring (idiom at 615-623) |
| `test/shell.d/menu-select-test.sh` (new; name discretionary) | Stub `omarchy-shell` that captures `$4` (the payload), parses `selectionFile`/`doneFile` out of it, writes the pick, touches done — then asserts on the captured JSON |

## 6. Edge-case semantics (decided by existing code, verified)

| Input | Result | Where decided |
|---|---|---|
| Flag absent | `defaultIndex` key not in payload → 0 | perl `length()` guard (menu-select:84-85 pattern) |
| `--default-index 0` | `"defaultIndex":0` emitted → row 0 | explicit zero is harmless; equivalent to absent |
| `--default-index` with no value | exit 1, `requires a value` | new case-arm guard (mirror lines 36-39) |
| Non-numeric (`abc`) | perl `int("abc")` → `0` silently → row 0 | perl coercion; no `use warnings` in the one-liner |
| Float (`1.9`) | `int()` → `1` | perl truncation |
| Negative (`-3`) | `defaultIndex:-3` → clamped to 0 | `rebuildDmenuDisplay` line 598 / helper |
| Out-of-range (`99` of 3 rows) | clamped to `count-1` | `rebuildDmenuDisplay` line 597 / helper |
| Empty options list | `selectedIndex = 0` either way | line 596 (`count === 0`) |
| Typing after open | highlight resets to row 0 | `setFilter` line 722 — keep + comment (D-05) |
| `mode: "input"` payload with the field | ignored | `cursorActive` false; Enter returns filterText |

## 7. Validation Architecture

How each success criterion gets proven, and by which layer. Two test layers exist today and both extend cleanly; a third (running UI) is mandatory per `agents/skills/visual-verification.md` because this change has a visual effect (pre-highlighted row).

### Layer A — node unit tests (`run_node_test` in `test/shell.d/menu-test.sh`)

Against the new `MenuModel.js` helper — covers the resolution contract in one place:

- absent field → `0` (back-compat: the "payload field simply absent" criterion)
- `defaultIndex: 0` → `0`
- `defaultIndex: 1` with 3 options → `1`
- out-of-range (`99`, 3 options) → `2` (clamped to `count-1`)
- negative (`-3`) → `0`
- non-integer (`1.9`) → floored; non-numeric (`"abc"`, `NaN`, `null`, `undefined`) → `0`
- `optionCount` of `0` → `0` (no crash on empty menu)

Plus **source-level pins** on `Menu.qml` (existing regex-over-source idiom, e.g. `menu-test.sh:615-623`):

- `openDmenu` body assigns `selectedIndex` from the resolved default, not a hardcoded `0`
- the assignment appears before `rebuildDisplay()` inside `openDmenu` (so the free clamp applies)
- `setFilter` still resets `selectedIndex = 0` (initial-only semantics preserved — pins D-05)

### Layer B — end-to-end payload test (new `test/shell.d/menu-select-test.sh`)

Runs the real `bin/omarchy-menu-select` against a stub `omarchy-shell` that satisfies the tempfile handshake. Stub sketch (combines `plugin-enable-test.sh:12-17` arg-recording with the handshake the script blocks on):

```bash
cat >"$STUB_DIR/omarchy-shell" <<'SH'
#!/bin/bash
# $4 is the JSON payload of `shell summon omarchy.menu <json>`
printf '%s\n' "$4" >>"$CAPTURED_PAYLOADS"
perl -MJSON::PP=decode_json -e '
  my $p = decode_json($ARGV[0]);
  open my $s, ">", $p->{selectionFile} or exit 1;
  print $s $ENV{FAKE_PICK} // "";
  close $s;
  open my $d, ">", $p->{doneFile} or exit 1;
  close $d;
' "$4"
SH
```

(`perl`/`JSON::PP` is already a hard dependency of the script under test — no new test dep. `jq` is also fine per `menu-plugin-test.sh:7` `require_command jq`.)

Assertions:

- `omarchy-menu-select Pick a b c -- --default-index 1` → captured payload contains `"defaultIndex":1`; script prints the stubbed pick (handshake intact)
- Same call **without** the flag → captured payload has **no** `defaultIndex` key at all — the byte-identical back-compat assertion, provable by `jq 'has("defaultIndex")'` or a `grep -v`-style key check on the raw JSON
- `-- --default-index` with no value → exit 1 + `requires a value` on stderr (mirrors `--width` guard)
- stdin-fed invocation (`printf 'a\nb\n' | omarchy-menu-select Pick -- --default-index 1`) → options array intact + field present (proves the flag can't corrupt the stdin option path — pitfall 2's regression)
- Flag combined with `--width 400 --maxheight 500` → all three payload fields coexist (proves the case-arm doesn't swallow siblings)
- Sweep assertion: `grep -rn 'omarchy-menu-select' bin/ | grep 'default-index'` finds only the new transcode caller once Phase 6 lands — for this phase, asserts **no** existing caller passes the flag

### Layer C — running-UI verification (required, `agents/skills/visual-verification.md`)

After `omarchy-restart-shell` (required for QML changes per `agents/skills/shell-dev.md:10`):

- `omarchy-menu-select "Pick" a b c -- --default-index 1` in a terminal → row `b` visibly highlighted; `wtype -k Return` → terminal prints `b`
- `-- --default-index 99` → last row highlighted (clamp), menu not wedged
- Open with `--default-index 1`, type a filter char → highlight moves to row 0 (initial-only)
- Spot-check one stdin-fed menu (`omarchy-menu-timezone`) renders and selects normally

### Gate mapping

| Success criterion | Proven by |
|---|---|
| 1. `--default-index 1` pre-highlights row `b`; Enter selects it | Layer C (visual + wtype) + Layer A pins (wiring) |
| 2. All existing callers byte-identical; field absent | Layer B (absent-key assertion) + caller sweep |
| 3. Out-of-range clamps safely | Layer A (helper clamp cases) + Layer C (`99`) |
| 4. Typing resets highlight to row 0 | Layer A pin on `setFilter` + Layer C |

No compositor is needed for A/B — both run headless under `./test/shell`. Do not gate them behind `require_compositor`.

## 8. Risks and planner notes

- **Caller-count discrepancy:** research/CONTEXT say 16; verified = 15 direct sites + the `omarchy-menu-file` pass-through + the routed `omarchy menu select` path. Cosmetic — the sweep list above is authoritative.
- **Edit-site drift:** all Menu.qml line numbers verified today (openDmenu 861-881, clamp 596-598, setFilter reset 722, Enter handler 1154-1157). If the file changed since, re-verify before writing the plan's line-pinned tasks.
- **`test/cli` metadata:** `# omarchy:args=` already advertises `[-- menu args...]` — no metadata change needed. Optionally add a `--default-index` example to `omarchy:examples=` (line 7, `|`-separated); not required.
- **Pre-existing suite noise:** STATE.md lists 7 environmental `test/shell` failures reproducing at base — don't attribute them to this phase.
- **Don't over-build:** label-based defaults, `--print-label`, filter-clear re-apply are explicitly deferred (CONTEXT `<deferred>`). One atomic commit; Phase 6 is the first real consumer.

## 9. Sources

- `bin/omarchy-menu-select` (full read; post-`--` loop 29-59, stdin fallback 61-63, perl payload 76-87, handshake 89-99)
- `bin/omarchy-shell` (full read; 3-arg `{}` default 51-53, `qs ipc` transport 58-59)
- `bin/omarchy` (router prefix resolution 389-406, exec 993/1047)
- `shell/shell.qml` (`summon` 1141-1179, `pendingPayloads` 1168-1174, `deliverIfLoaded` 1242-1257, IPC `summon` 1704-1706)
- `shell/plugins/menu/Menu.qml` (`open` 21-32, properties 54-76, `finishRequest` 117-135, `rebuildDmenuDisplay` 553-603, `revealCursor` 687-704, `setFilter` 719-727, `activateIndex` 759-787, `applyDmenuSelection` 815-820, `openDmenu` 861-881, keys 1123-1164)
- `shell/plugins/menu/MenuModel.js` (full read; ES5 style, guarded exports 493-524)
- `bin/omarchy-menu-file`, `bin/omarchy-menu-input`, `bin/omarchy-menu` (wrapper/peer patterns)
- `test/shell.d/base-test.sh` (`run_node_test` 79-127), `menu-test.sh` (full read), `menu-plugin-test.sh`, `plugin-enable-test.sh`, `update-status-test.sh`, `screenrecording-test.sh` (stub patterns)
- `test/cli:598-612` (metadata lint)
- `docs/menu.md`, `docs/testing.md`, `agents/skills/shell-dev.md`, `agents/skills/visual-verification.md`
- `.planning/research/ARCHITECTURE.md`, `PITFALLS.md` (locked decisions)
- `04-CONTEXT.md` (D-01..D-07), `04-PATTERNS.md` (per-site excerpts)
- Caller sweep: `grep -rn 'omarchy-menu-select' bin/` — 15 sites, 12 files, enumerated in §4
