---
status: fixes-applied
iteration: 1
date: 2026-09-14
scope: W1, W2, W3 from 01-REVIEW.md (fix scope: critical_warning)
---

# Phase 1 Review Fix: Per-monitor scale persistence in the scaling CLI

All three Warning findings were fixed in the awk rewriter of `bin/omarchy-hyprland-monitor-scaling`, each committed atomically with its regression fixtures.

## W1 — Nested-table `scale`/`output` keys rewritten as if top-level

- **Finding**: `match()` on `block_nostr` took the first `scale`/`output` key anywhere in the block, so `extra = { scale = 99 }` was rewritten instead of the rule's own `scale`, and a nested `output` could be read as the block selector (`:304`, `:274`).
- **Fix**: new `top_level_key(key)` helper (bin/omarchy-hyprland-monitor-scaling:299) locates the `{` of the `hl.monitor(` table constructor, then scans `block_nostr` tracking `{`/`}`/`(`/`)` depth and accepts a `key =` pair only at depth 1, with the same leading-delimiter and `=`-after-whitespace rules as before. `value_start(pos)` (:324) returns the first value char. `block_output` (:357) and `rewrite_scale` (:388) now go through these helpers instead of bare `match()`.
- **Verification**: `hl.monitor({ output = "eDP-1", extra = { scale = 99, top = 24 }, scale = 1.5 })` → `scale = 2` at top level, nested `scale = 99` untouched. `hl.monitor({ extra = { output = "eDP-1" }, output = "DP-2", scale = 1.5 })` → rule untouched, named eDP-1 rule appended. Both covered by `write_nested_scale_rule_config` / `write_nested_output_rule_config` fixtures in `test/shell.d/monitor-scaling-test.sh`.
- **Commit**: `ecde5f70 fix(monitor-scaling): match only top-level monitor table keys in the Lua rewriter`

## W2 — Levelled long comments `--[==[` / long strings `[=[` untracked

- **Finding**: the comment-opener test required literal `[[` after `--`, so `--[==[` blanked only one line and dead text was scanned as live code — a commented-out rule was rewritten in place and counted as `matched`, suppressing the append (silent persistence failure). Same gap for levelled long strings (`:238`, `:245`).
- **Fix**: `scan_line` (:210) now recognizes `--[=*[` comment openers and `[=*[` string openers via `match(..., /^\[=*\[/)` / `/^=*\[/`, records the level, and closes only on the matching `]=*]` (remembered in `comment_close` / `long_close`, built by the new `eq_str` helper at :198). Blank/keep semantics unchanged: comments blanked in both shadows, long-string contents blanked only in `s_out`, byte offsets preserved.
- **Verification**: `--[==[` fenced fake rule → left byte-identical, named rule appended. `[=[ ... ]=]` string containing a fake rule → line untouched, named rule appended. Live probe of `--[==[ fake ]==] hl.monitor({...})` on one line → dead text ignored, real rule rewritten. Covered by `write_levelled_comment_rule_config` / `write_levelled_string_rule_config` fixtures.
- **Commit**: `a5b87b80 fix(monitor-scaling): track levelled long comments and strings in the Lua blanking pass`

## W3 — `scale` value truncated at a nested comma → invalid Lua

- **Finding**: the value terminator `match(substr(block_nostr, vstart), /[,;}])` stopped at the first `,` regardless of nesting, so `scale = math.max(1, 1.5)` became `scale = 2, 1.5)` — a syntax error that breaks the whole file on reload (`:307`).
- **Fix**: new `value_end(pos)` helper (:336) scans forward from the value start tracking `(`/`)`/`{`/`}`/`[`/`]` depth and terminates only on `,`/`;` at depth 0 or a closer that would unbalance the value start depth. `rewrite_scale` replaces the whole bounded expression, so the splice can never emit a truncated fragment.
- **Verification**: `scale = math.max(1, 1.5)` → `scale = 2` (whole expression replaced, valid Lua). Covered by `write_expression_scale_rule_config` fixture asserting the full line and that no `1.5)` tail survives.
- **Commit**: `57339d8a fix(monitor-scaling): scan scale values depth-aware so nested commas cannot truncate`

## Test results

- `bash test/shell.d/monitor-scaling-test.sh` → 36 ok, 0 failures (5 new cases: levelled comment, levelled string, nested scale, nested output, expression scale)
- `bash test/shell.d/monitor-clamshell-scale-test.sh` → 25 ok, exit 0 (compat)
- `bash test/shell.d/monitor-state-test.sh` → 5 ok; `bash test/shell.d/monitor-output-name-test.sh` → 8 ok
- `./test/cli` → exit 0
- `bash -n bin/omarchy-hyprland-monitor-scaling` → clean

## Remaining risks / notes

- Info findings I1–I12 are unchanged and still open; the rewriter still considers only the first `hl.monitor()` call per line (I1) and `b_out` still lets a `hl.monitor(` inside a long string open a non-matching block (I9) — harmless now that key/value reads are depth- and string-aware.
- `top_level_key` scans from the *first* `{` after `hl.monitor(`; a contrived multi-arg call like `hl.monitor(foo({scale=1}), {...})` would read keys of the inner `foo` table. Not a legal Hyprland shape.
- An already-unbalanced value (e.g. `scale = f(1.5` with no closer) terminates at the first `)`/`}`/`]` at depth 0; output on malformed input stays malformed but never splices a partial expression.
- No apostrophes may appear in comments inside the single-quoted awk program — two slipped in during the fix and were caught by `bash -n`; worth remembering for future edits there.
