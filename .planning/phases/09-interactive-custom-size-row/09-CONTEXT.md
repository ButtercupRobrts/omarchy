# Phase 9: Interactive `Custom size…` row - Context

**Gathered:** 2026-09-17
**Status:** Ready for planning

<domain>
## Phase Boundary

The mp4 `Select quality` menu gains a fourth row `Custom size…` that opens `omarchy-menu-input`, feeds the typed answer through the same `parse_target_size` → `plan_target` → `transcode_video_target` path Phase 8 shipped for `--target`, re-prompts once on empty/unparseable input, and cancels cleanly on Esc. Zero QML changes, zero `omarchy-menu-select` changes — the sentinel rides through `select_quality`'s return contract.

This phase is the menu surface only — all parsing, planning, encoding, and refusal behavior is Phase 8's shipped contract, reused verbatim.
</domain>

<decisions>
## Implementation Decisions

### Carried forward (locked by ROADMAP + Phase 8 — not re-decided)
- **D-00a:** mp4 menus only — gif never shows the row (palette output ignores `-b:v`); pictures never see the quality menu at all
- **D-00b:** `target:<bytes>` (or equivalent sentinel) prefix through `select_quality`'s return, branched before the tier whitelist — the sentinel label can never reach the tier `case` or ffmpeg; strip-at-first-tab re-validation stays the single chokepoint
- **D-00c:** `omarchy-menu-input "Target size (e.g. 25M)"` is the prompt surface — already shipped; `[[ -s $selection_file ]]` semantics: non-empty → print + exit 0, else exit 1
- **D-00d:** Re-prompt once on empty submit or unparseable input, then cancel cleanly; Esc exits before the start notification like every sibling prompt
- **D-00e:** `omarchy-menu-input` must be stubbed in the harness (`FAKE_INPUT` knob + call-log line) in the same commit — the suite cannot hang on the real binary's `done_file` spin-wait
- **D-00f:** Interactive Custom-size run produces ffmpeg argv byte-identical to the equivalent `--target` invocation — one code path behind both entry points

### Floor refusal UX
- **D-01:** A *parseable but too-small* input (e.g. `10M` below the achievable floor) aborts exactly like the CLI — planner refusal is terminal, the error surfaces with the achievable minimum, the menu ends. The re-prompt budget is for typos, not for retrying past a refusal. Keeps `plan_target` semantics identical across entry points — **Reversibility:** reversible — a later phase could plumb the refusal text back into a re-prompt without breaking the contract

### Re-prompt affordance
- **D-02:** The second prompt carries an error hint (e.g. `Invalid size — e.g. 25M`) rather than re-showing the identical prompt — an identical re-prompt reads as "didn't take" instead of "invalid". Cost is one prompt-string variable — **Reversibility:** trivially reversible

### the agent's Discretion
- Exact sentinel label/subtext text (`Custom size…` + short subtext per the uniform-row-height requirement)
- Re-prompt loop shape (bounded counter vs. boolean flag) — must terminate after exactly one retry
- Where the sentinel branch sits in `select_quality`'s return handling — as long as it's before the tier whitelist and preserves D-00b
- Test row naming/fixtures for the `FAKE_INPUT` stub
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research
- `.planning/research/ARCHITECTURE.md` — sentinel/prefix contract, `omarchy-menu-input` input-mode quirks
- `.planning/research/PITFALLS.md` — pitfalls 8, 11 (input-mode and harness-hang landmines)

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — MENU-02
- `.planning/ROADMAP.md` — Phase 9 goal and 5 success criteria (authoritative)

### Phase 8 shipped contract (the machinery this phase reuses)
- `bin/omarchy-transcode` — `parse_target_size` :308-324, `plan_target` :337-385, `transcode_video_target` :398-466, `select_quality` :247+, refusal ordering + menu-skip gate `:602`, `output_path` token naming
- `.planning/phases/08-non-interactive-target-size-targeting/08-CONTEXT.md` — Phase 8 locked decisions
- `deferred-items.md` (phase 08) — IN-01 (`--target ""` test pin) and IN-03 (`plan_target` `*)` arm) are natural to close here since this phase adds the second caller the helpers were shaped for

### Menu plumbing
- `bin/omarchy-menu-input` — full file (~57 lines); exit 1 on empty selection file, prints + exit 0 on submit
- `bin/omarchy-menu-select` — `--default-index` and post-`--` arg pattern (Phase 4)
- `shell/plugins/menu/Menu.qml` — input mode (already shipped; no changes this phase)
- `docs/menu.md` — `mode: input` schema notes
- `test/shell.d/transcode-quality-test.sh` — stub harness (ffmpeg/magick/file/notification/menu stubs; `run_transcode` + `TMPDIR` export conventions)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `select_quality()` (`bin/omarchy-transcode:247+`) — builds `"\t<tier>\t<subtext>"` rows, calls `omarchy-menu-select … -- --default-index 1`; the sentinel row appends here
- `parse_target_size` / `plan_target` / `transcode_video_target` — the full Phase 8 pipeline, called identically to a `--target` run once the sentinel resolves to bytes
- `omarchy-menu-input` — free-text sibling of `omarchy-menu-select`; prompt is a plain arg, so D-02's error hint is a variable, not new plumbing

### Established Patterns
- Rows are `"\t<label>\t<subtext>"` — leading empty glyph field, tab-separated (PITFALLS/ARCHITECTURE)
- Menu selection return values pass through a strip/validate chokepoint before use — the sentinel prefix rides the same channel
- Refusals die before menus and before the start notification (v1.1 hoisted-validation convention)
- Harness: stub bins on PATH, `run_transcode` wrapper, per-run call logs, `TMPDIR` export

### Integration Points
- `select_quality` row construction — append the sentinel row (mp4 only)
- `main()`/`select_quality` return handling — branch `target:<bytes>` before tier validation; skip-tier path when sentinel selected
- `usage()`/`# omarchy:examples=`/`# omarchy:args=` — unchanged (no new CLI surface; the row is menu-only) — verify during planning
- `test/shell.d/transcode-quality-test.sh` — `omarchy-menu-input` stub + interactive-parity rows (Custom row ≡ `--target` argv), re-prompt-once, Esc-cancel, gif-menu-absent
</code_context>

<specifics>
## Specific Ideas

- Both recommendations accepted as presented (abort-like-CLI for floor refusals, error-hint re-prompt). No overrides.
- Rationale user endorsed implicitly: re-prompt budget is for typos; a refusal is information to absorb, and `plan_target` must stay identical across entry points.
</specifics>

<deferred>
## Deferred Ideas

- **Re-prompt on planner refusal with floor plumbed into the prompt** — explicitly rejected for this phase; revisit only if users find the dead-end jarring
- **Prefilled/remembered last custom size** — `omarchy-menu-input` has no initial-value arg today; would need a payload field (new capability, own phase)
- **Custom size row in gif menu** — gif ignores `-b:v`; deliberately absent per D-00a
</deferred>

---

*Phase: 9-interactive-custom-size-row*
*Context gathered: 2026-09-17*
