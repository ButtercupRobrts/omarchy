# Phase 8: Non-interactive `--target` size targeting - Context

**Gathered:** 2026-09-16
**Status:** Ready for planning

<domain>
## Phase Boundary

`omarchy transcode <video> [mp4] [res] --target <size>` end to end: free-text size parsing into integer bytes → `plan_target` (duration probe → video bitrate with ~2% container reserve minus fixed 192k audio → resolution step-down across the locked 4k/1080p/720p rungs) → two-pass encode → exactly one overshoot retry → actual-size completion notification. Every refusal dies before menus and before the start notification (v1.1 hoisted-validation convention). One atomic commit confined to `bin/omarchy-transcode` plus `test/shell.d/transcode-quality-test.sh`; `transcode_video` and all v1.1 code stay byte-identical (additive-diff constraint while PR #12135 is under upstream review).

The interactive `Custom size…` menu row is **Phase 9** — not this phase. The parser and planner must still be shaped so Phase 9's row hands off cleanly (one shared `parse_target_size`).

</domain>

<decisions>
## Implementation Decisions

### Carried forward (locked by REQUIREMENTS.md / ROADMAP.md / research — not re-decided)
- **D-00a:** Accepted size forms: `25M`, `25m`, `25MB`, `1.5G`, `500K`, bare `25` = MB → integer bytes. Rejected on stderr before any menu/notification: `abc`, `-5M`, `0`, `25.5.2M`, missing value (exit 2 like `--path`'s missing-value arm). MiB convention throughout — same scale `estimate_label`/`output_size_label` already report as "MB"
- **D-00b:** Budget math: `video_kbps = target_bytes × 8 ÷ duration_s ÷ 1000 × ~0.98 reserve − audio_kbps`, in awk (repo float convention; `-v` args only, never string-built). `video_duration` + `video_audio_kbps` reused as-is
- **D-00c:** Audio is fixed `-b:a 192k` — no audio step-down ladder (SIZE-14 + the "align audio floor" commit). When 192k audio alone can't fit, refuse
- **D-00d:** Refusal matrix, all pre-menu/pre-notification: `--target` + positional quality → error naming both; `--target` + gif → refuse (palette encoder ignores `-b:v`, verified byte-identical); `--target` + picture → refuse; `--target` skips `select_quality` entirely (`-z $target` added to the menu gate)
- **D-00e:** Planner runs in `main()` before `output_path` and writes the effective rung back into `resolution` — filename, start toast, and done toast all name the actual resolution for free (Pitfall 7)
- **D-00f:** Pass shapes: pass 1 carries `-pass 1 -an -f null /dev/null`; pass 2 carries `-pass 2 -b:v <derived>k -c:a aac -b:a 192k -movflags +faststart`; `-vf`/`-c:v` identical across passes; no `-crf` anywhere on either line. Codec split stays resolution-keyed (x265 at 4k, x264 below)
- **D-00g:** Passlogs live in `mktemp -d` under `TMPDIR` with trap cleanup + explicit rm after pass 2 — never the output dir (Pitfall 1: stale passlog silently corrupts the next run)
- **D-00h:** Output naming via `output_path`'s existing 4th arg: normalized target token → `stem-<effres>-25M.mp4`; dedupe unchanged
- **D-00i:** `transcode_video_target` is a sibling function; scale/codec case tables are duplicated per the file's documented `quality_token` convention — no edits inside existing function bodies, all new code in one contiguous helper block

### Overshoot retry (SIZE-15 mechanics — decided this discussion)
- **D-01:** Trigger is **any byte-over** — `output_bytes > target_bytes` retries. No tolerance band: the target is usually a hard upload cap (25.01M fails a 25M limit), and the ~2% reserve means typical runs land under anyway — **Reversibility:** reversible — a comparison and a constant-free rule; adding a band later is backward compatible
- **D-02:** Tightened budget is `video_kbps₂ = video_kbps₁ × (target_bytes ÷ actual_bytes)` — scale the one controllable term; resolution and 192k audio stay fixed (re-planning could silently change resolution after filename/toasts committed to it) — **Reversibility:** reversible — local to the retry path
- **D-03:** Retry pass 2 writes a sibling temp file and `mv`s onto `$output` only on encode success. No `-y` (v1.1 D-01 excluded overwrite flags); a failed retry leaves the overshot-but-playable first output for the done notification to report — **Reversibility:** reversible — retry-path internals only

### Floors and refusal
- **D-04:** Floor table locked at **2000/800/400 kbps** minimum video bitrate for 4k/1080p/720p — comparator-grounded (deepshrink, 8mb-compressor band). Below a rung's floor → step down; below 720p's floor → refuse. Tests pin each boundary — **Reversibility:** reversible — three constants in a case table; tuning later is a constants edit
- **D-05:** Refusals below every floor name the **computed achievable minimum at the 720p floor**: `(400k + audio_kbps) × duration × 125` bytes — e.g. "Cannot fit under 10M — smallest achievable is ~18M for this duration". Exact wording is implementer discretion; the computed value is the contract

### Degenerate targets
- **D-06:** `target ≥ source size` → **refuse** (nonzero, naming both sizes). Re-encoding to a bigger file is pure quality loss. The message should point at the tier path for format-conversion intent (drop `--target`, pick a quality) — the case where source fits but the user wanted e.g. mov→mp4 — **Reversibility:** reversible — one comparison + error branch
- **D-07:** Duration is gated positive-numeric before division — no `-nan`/`inf`/zero-duration `-b:v` ever reaches argv (Pitfall 4: capture on its own line, never `local x=$(...)` which masks status). Huge derived bitrates ride — ffmpeg/x264 cap internally and overshoot can't come from that direction

### Notifications and prompts
- **D-08:** Pass-scoped notifications on **one notification ID**: start toast fires once planning succeeds ("pass 1/2"), then `omarchy-notification-send -r <id>` replaces it with "pass 2/2" when pass 2 begins — liveness without toast spam (`-r` exists at `bin/omarchy-notification-send:50,106`) — **Reversibility:** reversible — notification text/sequence only
- **D-09:** Step-down is **disclosed with the target** in the toasts — e.g. `clip.mov to mp4 (720p — stepped down from 4k, target ≤25M)`. Silent step-down is the UX lie Pitfall 7 forbids; effective res alone is insufficient — **Reversibility:** reversible — toast strings only
- **D-10:** Unset resolution under `--target` still **prompts as usual** — the pick is a ceiling the planner may step below. `--target` doesn't change which menus appear (except skipping `select_quality`) — **Reversibility:** reversible — prompt gating only

### The agent's Discretion
- Exact refusal/error wording — must name the computed achievable minimum (D-05) and point at the tier path where relevant (D-06); follow the existing `Invalid …` / stderr style
- Pass-scoped toast wording and where the pass-2 update call sits inside `transcode_video_target`
- Normalized filename token shape beyond "digits+unit, filename-safe" (`8mb` → `-8M`)
- Whether `--target`'s gif refusal also checks immediately after the interactive format menu (before the resolution prompt) in addition to the validation block — the validation-block check at ~:380 is mandatory; earlier is optional polish
- Internal naming/structure of `parse_target_size` / `plan_target` / floor table / `transcode_video_target` within the contiguous helper block

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research (v1.2 — this phase's foundation)
- `.planning/research/ARCHITECTURE.md` — integration map with line numbers, step-down ordering consequence, additive-diff rules, two-pass placement, build order
- `.planning/research/PITFALLS.md` — pitfalls 1 (passlog lifecycle), 2 (pass argv drift), 3 (free-text parse), 4 (duration math), 5 (audio floor), 6 (overshoot), 7 (step-down ordering), 9 (flag matrix), 11 (harness traps), 12 (2× encode reads as hang); the "Looks Done But Isn't" checklist is the test plan's skeleton
- `.planning/research/STACK.md` — verified two-pass ffmpeg mechanics on n9.0.1 (flag shapes, passlogfile suffixes, `-fastfirstpass`, reserve math)
- `.planning/research/FEATURES.md` — comparator model, floor grounding, accuracy expectations, anti-features (`-fs`, retry loops, codec switching — all out)
- `.planning/research/SUMMARY.md` — key findings + open-design-calls (this discussion resolved: floors, retry, degenerate targets, notifications)

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — SIZE-10, SIZE-13, SIZE-14, SIZE-15, SAFE-02 (authoritative); Out-of-Scope table (`-fs`, convergence loops, upscale, codec selection, progress UX, gif `--target`)
- `.planning/ROADMAP.md` — Phase 8 goal and 8 success criteria (authoritative contract — including pass argv shapes, `stem-720p-25M.mp4` naming, refusal matrix, passlog hygiene, pass-aware stub)

### Prior phase context (conventions that carry forward)
- `.planning/milestones/v1.1-phases/05-non-interactive-quality-in-omarchy-transcode/05-CONTEXT.md` — no `-y`/`-n` (D-01), `Invalid …` error idiom, `output_path` 4th-arg suffix + dedupe
- `.planning/milestones/v1.1-phases/06-interactive-quality-prompt-size-estimates/06-CONTEXT.md` — probe honesty conventions, `set -euo pipefail` + `|| true` discipline, awk `-v` math convention

### Implementation targets
- `bin/omarchy-transcode` — full file; helpers `output_path` :49-73, `transcode_video` :107-148, `video_duration` :162-168, `video_audio_kbps` :172-178, `estimate_label` :229-240, `output_size_label` :291-299; `main()` arg loop :305-331, quality gate :348-361, format/resolution validation :379-409, quality-menu gate :411-413, `output_path`/notification/dispatch tail :415-428; metadata `:6-7`, `usage()` :11-32
- `test/shell.d/transcode-quality-test.sh` — stub harness to extend (ffmpeg argv recorder, `FAKE_*` knobs, `run_transcode` env — needs `TMPDIR` export + pass-aware stub + per-pass RC knobs)
- `bin/omarchy-notification-send` — `-r <id>` replace support (:50, :106) for pass-scoped toasts
- `docs/menu.md`, `manual/` — no changes needed this phase (CLI flag + usage/metadata lines only; `test/cli` lints the header)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `video_duration` (:162) + `video_audio_kbps` (:172) — the planner's two probe inputs exist verbatim; audio already returns the conservative 192-or-0
- `output_path`'s 4th arg + `[[ -e || -L ]]` dedupe — normalized target token rides it unchanged; `stem-720p-25M.mp4` falls out for free
- `estimate_label` (:229) — the awk `-v` float-math + regex-gate convention the budget math should mirror; MiB scale already labeled "MB"
- `omarchy-notification-send -r` — pass-2 toast replaces the pass-1 toast on one ID
- `test/shell.d/transcode-quality-test.sh` — ffmpeg argv-recording stub (`%q` lines), `FAKE_DURATION`/`FAKE_AUDIO`/`FAKE_OUT_BYTES`/`FAKE_ENCODE_RC` knobs; two passes just record two lines
- `bin/omarchy-menu-select`/`bin/omarchy-menu-input` `trap … EXIT` tempfile precedent — the pattern `transcode_video_target`'s passdir cleanup copies

### Established Patterns
- `set -euo pipefail`: capture probe output on its own line (`duration=$(video_duration …) || refuse`), never inside `local` (masks nonzero status); `(( expr ))` returns 1 on zero
- All validation lives in `main()` before menus and before the start toast — the refusal matrix slots into the same early blocks (quality gate :348, format validation :380)
- Named-case constant tables (`quality_token`, `quality_kbps`) over `declare -A`; deliberate duplication inside the PR-conflict window is the file's documented convention
- `Invalid …` + `usage`-free stderr errors, exit 1 for semantic conflicts / exit 2 for arg-parse failures (`--path` precedent)
- Encoder flags are inline literals in each encode arm — `transcode_video_target` builds its own lines; the tier arms never see `-b:v`/`-pass`

### Integration Points
- `main()` :302-303 — new `target=""` local; arg loop :305-331 — new `--target` arm mirroring `--path` verbatim (no `--target=` form — `--path` doesn't have one)
- Quality gate :348-361 — mutual-exclusion + picture refusal; format validation :380-386 — gif refusal (format may come from the interactive menu); :411-413 — add `&& -z $target`; pre-`output_path` :414-415 — planner block writing `resolution`; dispatch :417-422 — `transcode_video_target` branch
- New helpers appended in one contiguous block between `output_size_label` (:299) and `main` (:301)
- `# omarchy:args=` :6, `# omarchy:examples=` :7, `usage()` :11-32 — synced in the same commit (`test/cli` pins header shape)
- Callers untouched: Nautilus `transcode.py` (path-only by design), menu/keybind entry points, `omarchy-menu-select`, `Menu.qml`

</code_context>

<specifics>
## Specific Ideas

- User again asked for senior-engineer recommendations with reasoning, no assumptions — all recommendations presented were accepted (same pattern as phases 5–6). One clarification requested: the floor table needed a plain-English explanation (bitrate = data-per-second the size budget affords; floors = "below this it looks like mush" line per resolution) before accepting 2000/800/400.
- Retry-temp-then-mv chosen specifically so a failed retry preserves the overshot-but-playable first output — the done notification can still report it honestly rather than leaving nothing.
- Refusal for `target ≥ source` explicitly carries the "drop `--target` for format conversion" pointer — user surfaced no objection when this nuance was raised.

</specifics>

<deferred>
## Deferred Ideas

- **`Custom size…` interactive row** — Phase 9 by design; the parser/planner contracts here are shaped for that handoff but no menu code ships in this phase
- **Sub-720p rungs (480p/360p)** — SIZE-16; only if dogfooding shows 720p-floor refusals are common
- **Repeated overshoot correction loop** — SIZE-17; one retry is the bound, deeper convergence only if real misses appear
- **Intent presets / `--for discord`** — SIZE-11; thin alias over `--target`, needs a maintainer-owned limits table
- **gif size targeting** — SIZE-12; needs a sample-encode estimator (`-b:v` verified meaningless for palette output)
- **Audio step-down ladder (192→96→64) under tight budgets** — rejected in favor of fixed-192k + honest refusal (SIZE-14); revisit only if refusals prove too common in practice
- **Progress bar / percentage during encode** — out of scope per REQUIREMENTS; the pass-scoped toast is the whole progress story
- **Audio drop/mute flag, `--reduce %`, codec selection under `--target`, upscaling to spend leftover budget** — REQUIREMENTS out-of-scope table

</deferred>

---

*Phase: 8-non-interactive-target-size-targeting*
*Context gathered: 2026-09-16*
