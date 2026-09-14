---
status: issues-found
depth: standard
date: 2026-09-14
scope: 41b7ea3d..HEAD — bin/omarchy-hyprland-monitor-scaling (+354), test/shell.d/monitor-scaling-test.sh (+337)
---

# Phase 1 Review: Per-monitor scale persistence in the scaling CLI

## Verdict

The rewrite is well-executed: the threat-model controls from the plan all hold (monitor arg only ever a `jq --arg` value, identity passed via `ENVIRON` not `-v`, name guard applied to the resolved name before Lua embedding, fixed write path, backup-before-write, symlink-safe `cat >`/`sed -i --follow-symlinks`), the `desc:` selector logic faithfully mirrors Hyprland's `matchesStaticSelector`, and the appended-line format satisfies the clamshell parser contract. All suites pass: `monitor-scaling-test.sh` (30 cases), `monitor-state-test.sh`, `monitor-output-name-test.sh`, `monitor-clamshell-scale-test.sh`, and `./test/cli`.

Three real edge-case bugs were found by probing the awk rewriter with legal-but-uncommon Lua shapes, all in the same class: `match()` takes the *first* hit anywhere in the block without tracking brace depth or levelled comment/string syntax. None trigger on shipped or typical config shapes; none are Critical.

## Critical

None.

## Warning

### W1 — A `scale` key inside a nested table is rewritten instead of the rule's top-level `scale`
`bin/omarchy-hyprland-monitor-scaling:304` — `match(block_nostr, /[{,;[:space:]]scale[[:space:]]*=[[:space:]]*/)` takes the first `scale` key in the whole block regardless of `{` depth. Verified live:

```
hl.monitor({ output = "eDP-1", extra = { scale = 99, top = 24 }, scale = 1.5 })
  → hl.monitor({ output = "eDP-1", extra = { scale = 2, top = 24 }, scale = 1.5 })
```

The monitor's effective scale stays stale (silent persistence failure — the bug this phase exists to fix) and an unrelated nested field is corrupted. The same first-match weakness applies to `block_output` at `:274`: an `output = "..."` inside a nested table *preceding* the real one is read as the block's selector, so a matching nested `output` could trigger a rewrite of the wrong rule, or a real outer `output` be missed in favor of a nested one. Requires nested tables inside `hl.monitor({...})` — plausible (`reserved_area`-style shapes are in the clamshell fixtures) but uncommon with a `scale`/`output` key inside.

### W2 — Levelled long comments `--[==[` / `--[=[` are not tracked
`bin/omarchy-hyprland-monitor-scaling:238` — the comment opener test is `substr(line, i + 2, 2) == "[["`, so `--[==[` falls into the line-comment branch and blanks only the rest of that line. The remaining lines inside the block comment are scanned as live code. Verified live:

```
--[==[
hl.monitor({ output = "eDP-1", scale = 9 })   →   rewritten to scale = 2
]==]
```

Worse than a mis-edit: the rewrite inside dead comment text counts as `matched` (exit 0), so **no named rule is appended** — the file has no effective rule for the monitor and the next reload reverts the scale. Silent persistence failure on a legal (if rare) Lua comment form. The same gap applies to levelled long strings `[=[` at `:245`.

### W3 — A `scale` value containing a top-level comma produces invalid Lua
`bin/omarchy-hyprland-monitor-scaling:307` — the value terminator `match(substr(block_nostr, vstart), /[,;}])` stops at the first `,` without tracking `(`/`)`/`{`/`}` depth inside the expression. Verified live:

```
hl.monitor({ output = "eDP-1", scale = math.max(1, 1.5) })
  → hl.monitor({ output = "eDP-1", scale = 2, 1.5) })
```

The result is a syntax error — on the next config reload the whole `monitors.lua` fails to load. Rare input (scale is normally a literal/variable), and the timestamped backup covers recovery, but this is the one finding that can render the file unloadable. A cheap fix is to also terminate only on separators at depth 0 relative to the value start.

## Info

- **I1 — Two `hl.monitor()` calls on one line** (`:351`, `:274`, `:304`): they form a single block and only the first `output`/`scale` is considered. Verified: `hl.monitor({output="eDP-1",scale=1.5}) hl.monitor({output="eDP-1",scale=3})` rewrites only the first; the second (which wins under Hyprland last-match) stays at 3. Contrived shape; silent stale value.
- **I2 — `hl.monitor` nested inside a top-level multi-line table/constructor** is never detected (`:351` requires `depth == 0`) → append fallback. Verified graceful: the appended named rule still wins, but the stale rule remains in the file. Single-line `hl.monitor` inside `if ... then`/`end` *is* handled correctly (verified).
- **I3 — Non-`"`-quoted output selectors** (`output = 'eDP-1'`, `output = [[...]]`, `output = mon`) don't match `block_output`'s `"` regex (`:274`) → append fallback. Verified: outcome still correct since the appended named rule wins; the file just keeps a stale duplicate.
- **I4 — Trailing backslash inside a quoted string at EOL** (`:226-230`): `substr(line, i, 2)` yields 1 char for `b_out` but `"  "` for `s_out`, misaligning offsets by one for the rest of the block. Only reachable with an unterminated string (already-invalid Lua), so impact is bounded.
- **I5 — `cat "$tmp" >"$monitor_lua"` result unchecked** (`:377`): a failed/truncated write still proceeds to the GDK `sed`. Also `mktemp`'s `$tmp` leaks on signal (no trap). Minor.
- **I6 — Backup accumulation** (`:140`): every persist leaves a `monitors.lua.bak.<ts>` forever; nothing prunes, and two runs in the same second share a backup name (second backup then captures post-first-run content). Per D-05 and mirrors `omarchy-refresh-config`, but worth noting as a residual.
- **I7 — `-h|--help` accepts a trailing arg** (`:476`): `scaling -h extra` prints usage and exits 0 since only `$# > 2` is guarded. Trivial.
- **I8 — GDK patterns are column-anchored** (`:398-401`): indented `  local omarchy_gdk_scale = ...` or variant `hl.env(...)` spacing is not updated. Both shipped forms are covered; pre-existing shape assumption.
- **I9 — Block detection uses `b_out`** (`:351`), which keeps string contents: `hl.monitor(` inside a quoted/long string can open a "block" that absorbs following lines until depth resolves. Matching still requires a real `output = "..."` in `block_nostr`, so it can only fire if swallowed lines contain a real `output`+`scale` — contrived, noted for completeness.
- **I10 — Persisted rules pin `mode`/`position` to live values permanently** (`:385-386`): the D-04 "replay live position" trade-off now lives in the file, so a monitor whose file rule said `auto` becomes coordinate-pinned across reboots. Mandated format (clamshell contract); flagged as the known residual from RESEARCH §3.
- **I11 — `local x="$(cmd)"` masks jq exit status** at `:84-94` — safe here because `monitor_info` already passed `jq -e`; split-assignment was correctly used for `monitor_info` itself (`:78-83`). Style nit only.
- **I12 — Test gaps**: no fixtures for missing/unreadable `monitors.lua`, the `hl.env("GDK_SCALE", ...)` form, `;` separators, nested tables, `desc:` matching via `{make} {model} {serial}`, rewrite-all-of-multiple-matches, no-trailing-newline append, or the `--[==[` shape behind W2. Several were verified manually during review (missing→warn+exit 0+no create; unreadable→warn+exit 1+no write; `hl.env`→updated; `;`→` scale = N` inserted after `;`; make/model/serial desc→matched; name+desc rules→both rewritten; no-trailing-newline→newline prepended). Worth codifying the cheap ones, especially a regression test if W1–W3 are fixed.

## What was verified correct

- Injection: `[monitor]` arg flows only through `jq --arg`; the `^[A-Za-z0-9._-]+$` guard (`:98`) vets the *resolved* name, so a hostile headless-output name is refused and a hostile arg fails jq selection first — both covered by tests. Duplicate-name JSON yielding two objects → newline in `active_monitor` → guard rejects (safe failure).
- `desc:` selector: trimmed, comma-stripped, prefix-matched against `description` and reconstructed `{make} {model} {serial}` (`:286-297`) — mirrors Hyprland.
- `output = ""` catch-all can never match (target is non-empty by guard) — D-02 enforced mechanically; variable and literal catch-all forms verified untouched.
- Comment shielding: `--` line comments and `--[[ ]]` multi-line regions blanked at byte-identical offsets; commented rules correctly ignored → append path. Inline `--[[ fake ]] real_rule` on one line handled correctly.
- Insertion respects `,`/`;`/`{` context and lands before the table's closing `}`, not inside trailing comments (verified multi-line + trailing `--` comment case).
- Exit-code contract: 0→`cat >` (symlink-safe, verified link survives), 3→append with trailing-newline guard, other→warn+`return 1`+no write.
- Style: `#!/bin/bash`, no tabs, `[[ ]]`/`(( ))` used per AGENTS.md, all expansions quoted, `local`-then-assign split where exit status matters.
- Plan acceptance greps: no `position = "auto"`, no `omarchy_monitor_scale` writes, args metadata line present once, `monitors.lua.bak.` present, `.x` live-position read present.

## Suggested follow-ups (non-blocking)

1. Track `{`/`}` depth inside `rewrite_scale`'s key match and `block_output`'s `output` match (W1) and inside the value-terminator scan (W3) — a depth counter over `block_nostr` fixes both.
2. Accept `--[=*[` openers / `]=*]` closers and `[=[` long strings (W2).
3. Add fixtures for the verified-but-untested paths listed in I12.
