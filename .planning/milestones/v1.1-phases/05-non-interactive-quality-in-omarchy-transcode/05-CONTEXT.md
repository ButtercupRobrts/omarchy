# Phase 5: Non-interactive quality in `omarchy-transcode` - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Add an optional 4th positional arg to `omarchy transcode`: `omarchy transcode INPUT FORMAT RESOLUTION [QUALITY]` where QUALITY ∈ `high|medium|low`. The arg selects locked per-codec tier tables (x264 CRF 18/23/28, x265 CRF 20/24/28, gif fps 15/10/5). `medium` — and an omitted arg — reproduce today's encoder flags byte-for-byte. Non-default tiers append `-high`/`-low` to the output filename. Pictures reject the 4th positional. Output collisions resolve via dedupe, decided before the "Transcoding…" notification.

This phase is the non-interactive contract only — no menus, no estimates, no notification changes (Phases 6 and 7 build on it).

</domain>

<decisions>
## Implementation Decisions

### Carried forward (locked by milestone research / ROADMAP — not re-decided)
- **D-00a:** Tier tables are fixed: x264 `-crf` 18/23/28, x265 `-crf` 20/24/28 (4K only), gif `fps=` 15/10/5 — `.planning/research/STACK.md`
- **D-00b:** `medium` and an omitted 4th arg produce today's exact command lines — byte-identical by construction (same preset, same audio, same filters; only CRF/fps varies per tier)
- **D-00c:** A 4th positional on a picture input exits non-zero with a clear error — picture flow otherwise untouched
- **D-00d:** Output naming: `stem-<resolution>.<format>` for medium/omitted; `stem-<resolution>-<quality>.<format>` for high/low

### Collision policy
- **D-01:** When the computed output path exists, dedupe: `stem-1080p-2.mp4`, `-3`, … — resolve the final path in `output_path()` (or a wrapper) *before* the "Transcoding…" notification, so failure states are never orphaned and detached/keybind launches never hit ffmpeg's stdin overwrite prompt. Do NOT pass `-y` or `-n`; dedupe makes both unnecessary — **Reversibility:** reversible — local to the path-computation function; reverting restores the pre-phase behavior (silent ffmpeg refusal / tty prompt)

### Validation
- **D-02:** Strict: only `high|medium|low` accepted. Anything else → `exit 1` with `Invalid video quality: <value>` naming the valid set (mirroring the existing `Invalid video resolution:` / `Invalid picture format:` error style at `bin/omarchy-transcode:99-119`). No aliases (`h/m/l`), no raw CRF passthrough — named tiers are the only vocabulary — **Reversibility:** reversible — loosening later (adding aliases) is backward compatible

### Tier scope
- **D-03:** Tiers vary CRF (mp4) and fps (gif) only. Presets stay as today (`-preset fast` for x264, `-preset slow` for x265@4K), audio stays `-c:a aac -b:a 192k`, gif palette pipeline unchanged. The 4K+slow encode-time problem is pre-existing and out of scope — not silently addressed by reshaping tiers

### GIF tier mechanics
- **D-04:** gif `low` is fps=5 only — no palette-size or dither changes. Banding artifacts would read as broken rather than small; palette knobs deferred to a possible v2 pass

### the agent's Discretion
- Exact dedupe loop shape (`-2`/`-3` counter placement) and error-message wording — follow the script's existing `Invalid …` style
- Test file structure/naming — must not collide with open upstream PR #6698's `transcode-test.sh`; use `transcode-quality-test.sh` or similar per PITFALLS

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research
- `.planning/research/STACK.md` — locked tier tables (x264 18/23/28, x265 20/24/28, gif 15/10/5)
- `.planning/research/PITFALLS.md` — pitfall 4 (collision/overwrite per launch path — the reason dedupe is locked), pitfalls 5–7 (audio floor, upscale, misc), tradeoffs table (`-y` = "never without a deliberate decision"), pre-flight checklist rows (collision path, medium byte-compat, docs/metadata sync)
- `.planning/research/ARCHITECTURE.md` — integration points; note Nautilus `transcode.py` invokes with path only — do not add args there
- `.planning/research/FEATURES.md` — named-tiers rationale (raw CRF never exposed)

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — QUAL-02, QUAL-03, SAFE-01
- `.planning/ROADMAP.md` — Phase 5 goal and 5 success criteria (authoritative)

### Implementation target
- `bin/omarchy-transcode` — full file (207 lines); `output_path()` :46-57, `transcode_video()` :91-121, positional parsing :163-165, notification/encode block :195-204, `usage()` :11-30, `# omarchy:args=` :6

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `output_path()` (`bin/omarchy-transcode:46-57`): natural home for the quality suffix + dedupe loop — gains a `quality` param
- Existing `Invalid …` error idiom (:67-69, :84-87, :99-102, :116-119): pattern for quality validation and the picture-rejection error
- `test/shell.d/` harness + `base-test.sh` assertions; stub-`ffmpeg`/`stub-magick` precedent described in PITFALLS (PR #6698's approach) for asserting generated command lines without encoding

### Established Patterns
- `set -euo pipefail` + functions that `return 1` on bad input — quality validation belongs in the `case` arms, consistent with resolution/format validation
- `[[ ]]` string tests, `(( ))` numeric tests, two-space indent, `#!/bin/bash` (AGENTS.md)
- Encoder flags are inline literals in `transcode_video()` — tier tables should be a `case "$quality"` → variable mapping *before* the format dispatch, keeping medium's literals textually identical

### Integration Points
- `main()` :163-165 — add `quality="${positional[3]:-}"`, default `medium` for video, reject-for-picture after `type` is known (:175)
- `transcode_video()` :91-121 — gains `quality` param; x264/x265 CRF and gif fps switch on tier
- `output_path()` :46-57 — gains `quality` param for suffix; dedupe loop added here (or in a small wrapper) so every caller gets collision safety
- Callers that must stay untouched: Nautilus `default/nautilus-python/extensions/transcode.py` (path-only by design), menu trigger + keybind (interactive flow — Phase 6 owns the quality prompt)
- `# omarchy:args=` :6, `usage()` :11-30, `# omarchy:examples=` :7 — updated in the same commit; `test/cli` lints metadata shape

</code_context>

<specifics>
## Specific Ideas

- User explicitly requested pros/cons + reasoned recommendations rather than a quick pick — all four recommendations were accepted as presented (dedupe, strict validation, CRF/fps-only tiers, fps-only gif). No overrides.
- Dedupe rationale the user endorsed: the quality-compare workflow already produces distinct filenames via tier suffixes, so dedupe only fires on an exact re-run — `-2` is the least surprising outcome.

</specifics>

<deferred>
## Deferred Ideas

- **4K+`-preset slow` encode time** — real UX issue (multi-minute silent encode); fix belongs to a notification/elapsed-time improvement, not tier-table changes
- **gif palette/dither knobs for `low`** — possible v2 tier refinement if 5fps still produces too-large gifs
- **Raw CRF passthrough / aliases (`h`, `21`)** — rejected; would need codec-conditional semantics. Revisit only if power users ask
- **Nautilus batch quality** — `transcode.py` stays path-only; batch UX is a separate phase
- **`--target SIZE` 2-pass mode, intent presets ("fits Discord"), sample encodes** — milestone-level deferrals (REQUIREMENTS.md v2 list)

</deferred>

---

*Phase: 5-non-interactive-quality-in-omarchy-transcode*
*Context gathered: 2026-09-15*
