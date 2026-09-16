# Phase 4: Menu `defaultIndex` plumbing - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning

<domain>
## Phase Boundary

`omarchy-menu-select` accepts `--default-index N` as a post-`--` menu arg, emits `defaultIndex` in the select-mode JSON payload, and `Menu.qml`'s `openDmenu` initializes `selectedIndex` from it so a caller can pre-highlight a row. Purely additive — when the field is absent, behavior is byte-identical to today. This unblocks Phase 6's "Enter = medium" contract. No transcode changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### Flag surface
- **D-01:** Flag is `--default-index N`, placed after `--` alongside `--width`/`--maxheight` in `omarchy-menu-select`'s menu-args loop (`bin/omarchy-menu-select:32-53`). Never a positional option — tokens before `--` are menu options, and positional defaults would corrupt all 16 callers including stdin-fed ones. — **Reversibility:** costly — the flag name becomes a public CLI contract documented in `docs/menu.md`; renaming later means touching docs and any callers that adopt it.
- **D-02:** The payload gains an optional `defaultIndex` integer field, emitted only when set (same pattern as `width`/`maxHeight` in the perl JSON block, `bin/omarchy-menu-select:76-87`). Absent field = today's behavior exactly.

### Menu.qml behavior
- **D-03:** `openDmenu` (`shell/plugins/menu/Menu.qml:861-881`) initializes `selectedIndex` from the payload field instead of the hardcoded `0` at line 874. Index resolution lives in `MenuModel.js` as a plain function so it's node-testable per repo convention (`Model.js` files end with a guarded `module.exports`).
- **D-04:** Out-of-range/invalid values clamp via the existing `rebuildDmenuDisplay` bounds check (`Menu.qml:596-598`) — no new validation logic needed.
- **D-05:** `defaultIndex` is initial-only: typing in the filter resets the highlight to row 0 per existing `setFilter` behavior. This is correct (the user is actively searching); add a comment so nobody "fixes" it.

### Scope
- **D-06:** Document the flag in `docs/menu.md` — it's a public menu-schema feature other commands may adopt.
- **D-07:** All decisions for this phase were locked by milestone research; the user elected to skip discussion. Planner should follow `.planning/research/ARCHITECTURE.md` line references directly.

### Agent's Discretion
- Naming of internal QML/JS helpers, exact test-file organization within `test/shell.d/` conventions, and commit granularity within the phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research
- `.planning/research/ARCHITECTURE.md` — line-level integration points: `openDmenu` 861–881, `rebuildDmenuDisplay` 553–603, `activateIndex` 759–787; payload patterns; MenuModel.js testability recommendation
- `.planning/research/PITFALLS.md` — pitfall 2 (`defaultIndex` must be a `--` arg; 16 call sites verified)
- `.planning/research/SUMMARY.md` — locked design context

### Repo conventions
- `AGENTS.md` — bash/QML style rules, helper-command policy
- `.planning/codebase/CONVENTIONS.md` — verified conventions: `[[ ]]`/`(( ))`, `set -euo pipefail` weight-matching, Model.js `module.exports` test pattern, command metadata rules (test/cli lints `bin/` metadata)
- `docs/menu.md` — menu schema doc that must gain the flag

### Source files
- `bin/omarchy-menu-select` — the script being extended
- `shell/plugins/menu/Menu.qml` — `openDmenu`/`rebuildDmenuDisplay`/`activateIndex`/`setFilter`
- `shell/plugins/menu/MenuModel.js` — where index resolution should live for testability
- `bin/omarchy-menu-plugin` — precedent for tab-field handling in select returns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bin/omarchy-menu-select`'s post-`--` arg loop and perl JSON payload — `--default-index` slots in beside `--width`/`--maxheight` with identical handling
- `rebuildDmenuDisplay`'s index clamp (`Menu.qml:596-598`) — free out-of-range safety
- `cursorActive` already true in select mode (`Menu.qml:875`) — Enter hits the highlighted row with no extra wiring

### Established Patterns
- Payload fields are optional and additive; absent = default behavior (precedent: `width`, `maxHeight`)
- `Model.js` dual-mode files: ES5-style functions, `module.exports` guarded export, imported by QML and `require`d by node tests
- Tab-field row protocol: `glyph⇥label⇥subtext` — first field is always the icon slot

### Integration Points
- `omarchy-shell shell summon omarchy.menu "$payload"` — unchanged transport; only the payload gains a field
- `test/shell.d/menu-test.sh` `run_node_test` helper + `omarchy-shell` payload-capture stub — existing test pattern to extend
- 16 existing `omarchy-menu-select` call sites — all must remain behavior-identical (no flag passed = no payload field)

</code_context>

<specifics>
## Specific Ideas

- The flag exists to serve Phase 6's quality menu (`-- --default-index 1` pre-highlights `medium`), but must be built generically — any select menu can use it.
- Keep the change additive enough to be an independently revertible commit — it's the milestone's only cross-component contract change.

</specifics>

<deferred>
## Deferred Ideas

- `--print-label`-style helpers and label-based (rather than index-based) default selection — noted in research; not needed by any current caller
- Re-applying the default after the user clears the filter — deliberately rejected in D-05 (initial-only)

</deferred>

---

*Phase: 4-menu-defaultindex-plumbing*
*Context gathered: 2026-09-15*
