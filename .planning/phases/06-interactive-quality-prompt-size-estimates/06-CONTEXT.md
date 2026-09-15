# Phase 6: Interactive quality prompt + size estimates - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning

<domain>
## Phase Boundary

The interactive video transcode flow gains a "Select quality" menu step after format+resolution. mp4 rows carry `CRF N · ~N MB` estimate subtexts computed from `ffprobe` duration × the locked per-resolution/tier bitrate table + the 192k audio term; gif rows carry `N fps` subtexts. `medium` is pre-highlighted via `--default-index 1` (Phase 4 plumbing). The selection's subtext is stripped before tier matching. Pictures see no new prompt; non-interactive callers (positional quality arg, Nautilus) never run ffprobe. The completion-notification size is Phase 7 — not this phase.

</domain>

<decisions>
## Implementation Decisions

### Carried forward (locked by milestone research / prior phases — not re-decided)
- **D-00a:** Prompt order stays file → format → resolution → quality; quality is last because estimates key on format × resolution × tier
- **D-00b:** `medium` is the Enter-default via `omarchy-menu-select "Select quality" … -- --default-index 1` — `--default-index` and `defaultIndex` payload plumbing shipped in Phase 4
- **D-00c:** Row wire format is `"\tlabel\tsubtext"` — leading tab (glyph field) is mandatory; a bare `label\tsubtext` renders the label as the icon (PITFALLS anti-pattern 1). No caller today uses tab fields — this menu is the first
- **D-00d:** Selection return is `label[\tsubtext]` — strip with `${sel%%$'\t'*}` before the `case "$quality"` match (PITFALLS pitfall 1)
- **D-00e:** Bitrate midpoints locked (`.planning/research/STACK.md`): 720p x264 2.5/1.5/0.7 Mbps, 1080p x264 5.5/3.0/1.4 Mbps, 2160p x265 16/9/4.5 Mbps — plus the fixed 192k audio term in every mp4 estimate
- **D-00f:** gif rows get fps subtexts (`15 fps`/`10 fps`/`5 fps`), never size estimates — gif size is content-dominated fiction (20–30× spread)
- **D-00g:** ffprobe runs only inside the `type == video && -z $quality` interactive branch; a 4th positional arg or picture input skips it entirely
- **D-00h:** Estimates display with `~` prefix and 1–2 sig figs (`~110 MB`, never `~113.7 MB`) — fake precision is a researched anti-feature
- **D-00i:** The prompt fires whenever quality is unset on the interactive path, including partial positionals (`omarchy transcode in.mov mp4` still prompts resolution then quality) — consistent with existing unset-positional behavior

### Subtext wording
- **D-01:** mp4 subtext is `CRF N · ~N MB` — the ROADMAP success criterion's verbatim format. CRF appears as a calibration anchor (users learn CRF 18 ⇒ bigger), while `~` + sig-fig rounding keeps it honest. FEATURES.md's "never surface CRF" targets CRF as an input control, not informational subtext — **Reversibility:** reversible — a subtext string; changing it touches no contract (subtext is display-only, stripped before matching)

### Estimate honesty vs source
- **D-02:** When a tier's estimate would exceed the source file size (`est_bytes > stat -c %s input`), that row's number is replaced with honest qualitative text — `larger than source` wording (final wording at implementer discretion, ≤~30 chars, no tabs). Showing the raw number anyway is the lying case success criterion 2 forbids. Per-row: only the exceeding tiers degrade; other rows keep numbers — **Reversibility:** reversible — local to row construction

### Probe-failure fallback
- **D-03:** When ffprobe fails or returns non-numeric/`N/A` duration, ALL rows fall back to qualitative subtexts ("Best quality" / "Balanced" / "Smallest file" — exact wording at implementer discretion). Never mix subtext/no-subtext rows (uneven `detailRowHeight` looks buggy, PITFALLS pitfall 10). All probes guarded `|| true` + `=~ ^[0-9.]+$` so `set -euo pipefail` can't turn a probe hiccup into a silent abort (pitfall 8) — **Reversibility:** reversible — fallback strings only

### Row presentation
- **D-04:** Leading glyph field stays empty — plain text rows consistent with the format and resolution prompts in the same flow. Icon-ing only the quality step introduces a second visual dialect mid-flow; icons on all prompts is scope creep

### The agent's Discretion
- Exact qualitative wording for `larger than source` and the three fallback subtexts — keep ≤~30 chars, no tabs
- Whether to also probe `stream=codec_type` and drop the +192k term on audio-less sources (pitfall 5's cheap improvement — researcher may fold it into the same ffprobe call or skip it)
- Whether to note upscales (source height < target) in the subtext — research marks it optional-or-defer; the estimate already reflects the big number
- Helper function placement/naming — keep new helpers adjacent to `transcode_video` or below `copy_to_clipboard` to shrink the PR #6698 conflict window; `case`-table style over `declare -A`
- awk vs integer math for the estimate — awk is the repo's float convention
- Test file: `test/shell.d/transcode-quality-test.sh` (avoids add/add collision with PR #6698's `transcode-test.sh`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research
- `.planning/research/ARCHITECTURE.md` — tab contract (empty-glyph rows, return stripping), estimate data flow, function-placement guidance vs upstream PR #6698
- `.planning/research/FEATURES.md` — estimate placement on the final step, honest-approximation rationale
- `.planning/research/PITFALLS.md` — pitfalls 1 (subtext in return value), 3 (fake precision / clamp-against-source), 5 (audio floor, upscale), 8 (probe under `set -e`), 10 (subtext width/heights/protocol)
- `.planning/research/STACK.md` — locked bitrate midpoint table, ffprobe incantation + `N/A` guard, gif omit-estimates rationale, `numfmt`/awk choices

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — QUAL-01, SIZE-01
- `.planning/ROADMAP.md` — Phase 6 goal and 6 success criteria (authoritative; subtext format `CRF 18 · ~110 MB` is the written contract)

### Implementation targets
- `bin/omarchy-transcode` — full file; prompt chain :220-234, quality positional validation :205-218, `output_path` dedupe+suffix :49-73, `transcode_video` tier case :122-130
- `bin/omarchy-menu-select` — `--default-index` flag (shipped Phase 4); header doc comment defines the glyph⇥label⇥subtext contract
- `shell/plugins/menu/Menu.qml` — `openDmenu` defaultIndex handling, `activateIndex` return shape, `rebuildDmenuDisplay` clamp
- `docs/menu.md` — documents `defaultIndex` for future menu authors
- `agents/skills/visual-verification.md` — subtext elision and detailRowHeight need running-UI verification, not just tests

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `omarchy-menu-select --default-index` (shipped Phase 4) — `-- --default-index 1` pre-highlights `medium`; out-of-range clamps via existing `rebuildDmenuDisplay` bounds check
- `${var%%$'\t'*}` strip idiom + `omarchy-menu-plugin`'s `icon⇥name⇥id` multi-field precedent — the tab protocol is already proven
- `output_path()` already takes `quality` for suffix + dedupe (Phase 5) — interactive picks flow through unchanged
- `numfmt`/`stat`/`ffprobe`/`awk` are platform invariants — no new deps, no presence guards
- `test/shell.d/` stub harness: stub `ffprobe` (fixed duration), `omarchy-menu-select` (record argv, answer `$FAKE_PICK`), `omarchy-shell` (capture payload — assert `defaultIndex: 1` lands)

### Established Patterns
- `set -euo pipefail` makes every probe a fatal branch — `|| true` + regex validation on all ffprobe output; remember `(( expr ))` returns status 1 when the result is 0
- Rows are all-subtext or no-subtext — `detailRowHeight` makes mixed rows look buggy (uniform heights required in both normal and fallback states)
- Subtext is display + filter corpus + return key: ≤~30 chars, never contains a tab
- New quality code keys on `type == video && -z $quality` — the same guard shape as the existing format/resolution prompt blocks

### Integration Points
- `main()` after the resolution block (~:234) — new video-only quality prompt block builds `"\tlabel\tsubtext"` rows → `omarchy-menu-select "Select quality" … -- --default-index 1` → strip → existing `case "$quality"` validation at :211-217
- `omarchy-menu-file`'s `"$@"` forwarding propagates menu args through wrappers for free (no wrapper changes needed)
- Callers that must stay untouched: Nautilus `transcode.py` (path-only by design), all 16 other `omarchy-menu-select` callers

</code_context>

<specifics>
## Specific Ideas

- User asked for senior-engineer recommendations with explanations and no assumptions — all four recommendations were presented with reasoning and accepted as given (same pattern as Phase 5's discussion).
- "Larger than source" was chosen over keeping the number precisely because the estimate is least trustworthy exactly where it would mislead (efficient sources re-encode *up* at CRF 18).

</specifics>

<deferred>
## Deferred Ideas

- **Upscale flag in subtext** (source 1080p → 4k) — left as implementer/researcher discretion; a user-facing warning is a possible v1.x refinement
- **Audio-stream-aware estimates** (drop +192k when no audio stream) — researcher may fold into the single probe call or defer
- **Icons on all transcode prompts** — scope creep; if ever wanted, it's a whole-flow visual pass
- **gif size estimates** — v2 (SIZE-12); needs a sample-encode estimator, table is fiction
- **Nautilus batch quality remembering** — post-v1.1; interacts with open upstream PR #6698
- **Completion-notification actual size** — Phase 7, deliberately out of this phase

</deferred>

---

*Phase: 6-interactive-quality-prompt-size-estimates*
*Context gathered: 2026-09-15*
