# Architecture Research

**Domain:** Target-size transcode (`--target <size>`, SIZE-10) for `bin/omarchy-transcode` — two-pass encode with derived bitrate, resolution step-down, and a "Custom size…" interactive row
**Researched:** 2026-09-16
**Confidence:** HIGH — every integration point traced in the shipped v1.1 code; input-mode path is existing code, not proposed API; two-pass mechanics verified empirically in `research/STACK.md`
**Companion docs:** `research/STACK.md` (verified ffmpeg/numfmt/menu-input mechanics), `research/FEATURES.md` (comparator model, floor grounding, math)

## Integration Map

### Modified components (all inside `bin/omarchy-transcode`)

| Location (file:line) | Change | Size |
|----------------------|--------|------|
| Metadata header `:6-7` | `# omarchy:args=` gains `[--target size]`; add a `--target` example. `test/cli` validates metadata shape | 2 lines |
| `usage()` `:11-32` | Usage line gains `[--target size]`; Options block gains `--target` | ~3 lines |
| `main()` locals `:302-303` | Add `target=""` (+ `video_kbps`, `audio_out`, or a packed plan var) | 1 line |
| Arg loop `:305-331` | New `--target` arm, verbatim mirror of `--path` `:307-310` (shift, `(( $# > 0 ))` value guard → `return 2`, assign). No `--target=X` form — `--path` doesn't have one | ~5 lines |
| Quality gate `:348-361` | Mutual exclusivity: inside the existing `[[ -n $quality ]]` block, `[[ -n $target ]]` → error, `return 1` (matches the picture-quality rejection's exit code, `:350-351`). Also refuse `--target` + picture here — `$type` is already known | ~6 lines |
| Video format validation `:380-386` | After the `mp4 \| gif` case: `[[ -n $target && $format == gif ]]` → refuse. Must sit here (not earlier) because format may come from the interactive menu at `:367` | ~4 lines |
| Quality-menu condition `:411-413` | `[[ $type == "video" && -z $quality ]]` → add `&& -z $target`: a CLI target skips the tier menu entirely | 1 line |
| Pre-`output_path` `:414-415` | New target-mode block: run planner → overwrite `resolution` with the *effective* rung (see "Step-down naming" below) | ~6 lines |
| Video dispatch `:417-422` | `[[ -n $target ]]` → `transcode_video_target`; else existing `transcode_video` call unchanged | ~4 lines |
| `select_quality` `:247-287` | Append one row after the tier loop (`rows+=($'\t'"Custom size…"$'\t'"<subtext>")`, mp4 only) + one sentinel arm in the return case at `:279-285` that hands off to `omarchy-menu-input` | ~12 lines |

### New components (all new functions — zero edits inside existing function bodies)

| Function | Placement | Job |
|----------|-----------|-----|
| `parse_target_size` | Helper block after `output_size_label` (`:299`), before `main` | `25`/`25M`/`25MB`/`25m`/`1.5G` → bytes. Regex-gate first, normalize (strip optional `B`, uppercase unit, bare number → `M`), then `numfmt --from=iec` or awk. One parser shared by the flag and the menu-input path — non-negotiable, it's the "one validation path" property |
| `plan_target` | Same block | Inputs: input path, target bytes, requested resolution. Probes `video_duration` (`:162`) + `video_audio_kbps` (`:172`), computes `video_kbps = bytes×8÷1000÷dur×(1−0.02) − audio` in awk (same float-math convention as `estimate_label` `:229`), walks the floor table stepping resolution down, prints `resolution video_kbps audio_kbps` on stdout. Refuses (stderr + nonzero) on probe failure or below-every-floor, naming the achievable minimum |
| `resolution_floor_kbps` (or a case inside `plan_target`) | Same block | Per-rung minimum-watchable kbps — grounding in FEATURES.md (~2000/800/400 for 4k/1080p/720p; plan-level pick). Small case table matching file style |
| `transcode_video_target` | Same block | Two-pass sibling of `transcode_video` (`:107-148`): pass 1 `-an -f null /dev/null`, pass 2 with `-b:v "${kbps}k"`, `-passlogfile` inside `mktemp -d`, audio+faststart on pass 2 only. Exact flag shapes in STACK.md §"ffmpeg Two-Pass Mechanics" — verified on n9.0.1 |

### Untouched components — verified no changes needed

| Component | Why |
|-----------|-----|
| `bin/omarchy-menu-select` | Hardcodes `mode:"select"` (`:89`) and that's correct — input prompts route through `omarchy-menu-input`. Do not graft an `--input` flag onto it |
| `bin/omarchy-menu-input` | Already shipped (58 lines): `mode:"input"` payload `:39`, same `selectionFile`/`doneFile` handshake, `--width` support. Call it directly |
| `shell/plugins/menu/Menu.qml` | `payload.mode === "input"` routes to `openDmenu` at `:27`; `:866` sets mode; Enter submits `root.filterText` verbatim (`:765-767`, `:1158-1160`); `rebuildDmenuDisplay` early-returns with zero rows for input mode (`:558-561`); card collapses to header-only (`:114-116`). Zero QML work |
| `transcode_picture` `:75-105` | Pictures never see target mode — refused upstream in `main` |
| `transcode_video` `:107-148` | Unchanged — target mode gets a sibling function, not a parameter (see additive strategy) |
| `output_path` `:49-73` | Unchanged — the 4th arg already does suffix-if-non-medium; the normalized target token rides it |
| `output_size_label` `:291-299` | Unchanged — the done toast's actual-size report becomes the target promise-keeper for free |
| `default/nautilus-python/extensions/transcode.py` | Invokes bare `omarchy-transcode <path>` (`_launch_transcode` `:26-34`); the Custom-size row reaches it through the existing interactive path automatically |
| `default/omarchy/omarchy-menu.jsonc:69`, `utilities.lua:87` | Entry points invoke the bare command; no change |
| `bin/omarchy` router | `omarchy-menu-input` is already registered (group `menu`, `:62`) |

## Data Flow — target value end-to-end

```
CLI: --target 25M ──────────────┐
Interactive: "Custom size…" row ─┤
                                 ▼
              ┌── omarchy-menu-input "Target size (e.g. 25M)"  (interactive arm only)
              │         │ typed text, exit 0; Esc → exit 1 → abort like every prompt
              ▼         ▼
        parse_target_size ── regex gate → normalize → bytes
                                 │   invalid → usage error, exit 1-2, BEFORE any toast
                                 ▼
   main() early validation (order matters):
     type=picture  → refuse (:348 block)
     quality set   → mutual-exclusion error (:348 block)
     format=gif    → refuse (:380 block — after format menu)
                                 ▼
        plan_target input bytes requested_resolution
          ├─ video_duration fails      → refuse (no duration, no math)
          ├─ video_kbps ≥ floor[req]   → keep requested resolution
          ├─ else step down rungs      → 4k→1080p→720p
          ├─ (optional) audio step-down 192→96→64 before refusing
          └─ below floor[720p]         → refuse naming achievable minimum
                                 ▼  prints "720p <vkbps> <akbps>"
   resolution := effective rung   ← overwrites the variable, so EVERYTHING
                                 │   downstream (filename, both toasts)
                                 │   names the actual resolution
                                 ▼
   output_path input mp4 eff_res "25M" → stem-720p-25M.mp4  (dedupe intact)
                                 ▼
   start toast: "clip.mov to mp4 (720p)"   — fires once, after planning,
                                 │           so it already names actual res
                                 ▼
   transcode_video_target: pass1 (-an -f null /dev/null)
                           pass2 (-b:v Nk → real output)
                                 ▼
   copy_to_clipboard → done toast "Transcoded to 720p mp4 … (23 MB)"
                       actual size = promise verification (SIZE-02 reuse)
```

### Step-down vs `output_path` naming — the ordering consequence

Today `output_path` runs at `:415` on the *requested* resolution. Under `--target`, the planner must run **first** and write the effective rung back into `resolution` before `:415`. Then `output_path`, the start toast (`:418`), and the done toast (`:422`) all name the actual resolution with zero new plumbing — "effective-resolution honesty" falls out of variable reuse, which is also what the FEATURES research recommends over the comparators' silent downscale. The normalized target token (`25M`) passes as `output_path`'s 4th arg → `stem-720p-25M.mp4`, self-documenting and collision-distinct from tier names. Keep the token shape `digits+unit` so it's always filename-safe.

### Flag vs positional quality — precedence

**Mutually exclusive, error early.** `--target` picks a bitrate; positional quality picks a CRF — contradictory inputs (FEATURES table-stakes row). Check inside the existing `[[ -n $quality ]]` gate at `:348` so it dies before menus and before the start toast, consistent with the v1.1 hoisted-validation decision (PROJECT.md Key Decisions). Interactive reachability is through the quality menu's Custom row, not through the flag — so no precedence rule beyond "both set → error" is needed.

### Two-pass placement — new function, not a parameter

`transcode_video_target` as a sibling function keeps `transcode_video` byte-identical. The resolution→scale case (`:112-120`) and the resolution-gated codec split (`:134-138`) get duplicated — matching the file's own documented convention (`:180-184`: `quality_token` "deliberately duplicates" the CRF table because "a shared table would refactor that code inside the PR conflict window"). Extracting shared `video_scale`/`video_codec` helpers is the cleaner long-term shape but edits `transcode_video`'s body; defer until the upstream PR settles. Passlogfile cleanup: `mktemp -d` + `trap 'rm -rf "$passdir"' RETURN` (or explicit rm) — `set -e` means a failed pass 1 skips pass 2 naturally, but the temp dir needs the trap or it leaks.

### "Custom size…" row → input prompt — the return contract

`select_quality` builds `\t<label>\t<subtext>` rows (`:273`); the menu returns `label\tsubtext`; `:278` strips at first tab. A 4th row fits the wire format, but the label doubles as the sentinel — match `[[ $selection == "Custom size…" ]]` exactly (the `…` is one U+2026 char; glyph fields never return, so the sentinel must be the label). On match: `omarchy-menu-input "Target size (e.g. 25M)"` → `parse_target_size` → return a prefix-tagged value such as `target:26214400` so `main` can distinguish tier from target at `:412` (`case "$quality" in target:*) …`). The existing re-validation case (`:279-285`) is the interception point — extend it, don't bypass it. Show the row **only when `format == mp4`** — `select_quality` already has `$format`; gif must never offer it.

**Input-mode quirks the caller owns** (all verified in Menu.qml / STACK.md):
- **Empty submit ≠ cancel:** Enter on empty writes `\n` → exit 0 with empty stdout. Treat as invalid (reprompt or error), not Esc. Esc = exit 1 = abort.
- **Esc is two-stage** with text present (`:1137` clears first); right-arrow also submits (`:1158`). Harmless.
- No placeholder field — the prompt text is the placeholder (`:1210` dims `prompt + "…"`); no prefill (`filterText` starts `""`, `:877`); no validation/maxLength — all validation is bash-side.
- Reprompt-once vs error-out on garbage is a plan-level call; FEATURES leans reprompt (user is mid-gesture).

### Notifications during a 2× encode

The pair is unchanged: start toast once at `:418`, done toast at `:422`. ffmpeg blocks in the foreground either way — two passes just double wall time; there is no progress mechanism to extend. Notes: (a) because planning precedes `:418`, the start toast already names the effective resolution — optionally add `≤25M` to its body; (b) `omarchy-notification-send` supports `-r <id>` replace (`:50`,`:106`) if a "pass 2/2" mid-encode update is ever wanted — optional polish, not required; (c) pass-1 failure under `set -e` dies before the done toast, identical to today's single-pass failure (start-toast orphan on failure is existing accepted behavior).

## Build Order

Dependency-directed; each step is a viable atomic commit per the repo convention:

1. **`parse_target_size` + `--target` flag + all early refusals** (mutual exclusion, picture, unparseable size; gif refusal after the format menu). Include usage/metadata lines. Nothing encodes yet — every error path is stub-testable.
2. **`plan_target` + floor table + `transcode_video_target` + main wiring** — planner before `output_path`, resolution overwrite, target-token suffix, video dispatch branch. This completes the non-interactive `--target` path end to end. Steps 1–2 may ship as one commit if the split feels artificial; keep them separate if upstream review prefers small hunks.
3. **"Custom size…" row + `omarchy-menu-input` handoff + `target:` prefix contract** in `select_quality`/`main`. Depends on step 1's parser; independent of step 2's encoder internals.
4. **Tests** (extend `transcode-quality-test.sh` — see below) + `docs/menu.md` touch only if the sentinel/prefix contract is documented there (it isn't today — probably no doc change needed; `omarchy-menu-input` is already documented at `docs/menu.md:156-173`).

Steps 1→2→3 are strictly ordered (3 needs 1's parser; 2 needs 1's flag). Nothing here touches `omarchy-menu-select`, `Menu.qml`, or `MenuModel.js` — there is no menu-infrastructure step this milestone, a deliberate contrast with v1.1's phase 4.

## Test Coverage — extend `transcode-quality-test.sh`, don't build a new harness

- **ffmpeg stub** (`:34-48`): records every invocation's `%q` argv — two-pass just records two lines. Assert the `-pass 1` line carries `-an -f null /dev/null` and the `-pass 2` line carries `-b:v <n>k` + `-c:a aac`. **Gotcha verified live:** the stub's `FAKE_OUT_BYTES` arm does `truncate -s N "${!#}"`; for pass 1 `${!#}` is `/dev/null` and `truncate` fails EINVAL (rc=1, prints to stderr — the stub still exits `FAKE_ENCODE_RC` since it has no `set -e`). Harmless noise, but cleaner to teach the stub to skip file creation when the last positional is `/dev/null`.
- **ffprobe stub** (`:96-114`): `FAKE_DURATION` already drives `video_duration`; `FAKE_AUDIO` drives `video_audio_kbps` — both planner inputs already have knobs. `FAKE_DURATION` unset → probe failure → assert honest refusal.
- **New stub needed:** `omarchy-menu-input` (record argv, print `$FAKE_INPUT`) for the Custom-row path. Also drive the sentinel pick via `FAKE_PICK=$'Custom size…\t<subtext>'`.
- **Case rows to add:** `--target 25M` full run → two ffmpeg lines + `stem-720p-25M.mp4`-style name; step-down asserted via `-vf scale=-2:720` on a tight budget; below-floor → nonzero exit + refusal text naming the achievable minimum + empty `$calls` (no toast); `--target`+gif → refuse; `--target`+picture → refuse; `--target`+positional `low` → conflict error pre-side-effects; garbage `--target xyz` → error; Custom row on gif format → row absent from recorded menu argv; empty input-submit → treated as invalid not cancel.
- **Existing pins that keep v1.1 honest:** the medium-argv literal (`:143-168`), the `out=` names, the no-overwrite-flag grep (`:363`) — all still apply; pass-2 lines contain no `-y`/`-n`.

## Additive-Diff Strategy (v1.1 under upstream review — PR #12135)

The rebase surface is the concern: any line v1.2 edits is a line that can conflict if upstream asks for v1.1 changes. Rules that follow:

1. **All new logic lives in new functions** appended in one contiguous block between `output_size_label` (`:299`) and `main` (`:301`). Never reorder existing functions.
2. **`main()` edits are minimal, colocated hunks:** one `local` line, one new case arm next to `--path`, one mutual-exclusion check inside the existing quality gate, one gif-refusal inside the existing video-validation block, one `-z $target` on the menu condition, one pre-`output_path` planner block, one dispatch branch. Each is adjacent-to, not interleaved-with, v1.1 lines.
3. **Duplicate, don't extract:** `transcode_video_target` duplicates the scale/codec cases rather than refactoring `transcode_video` — the file's own precedent (`quality_token`, `:180-184`) and it keeps the v1.1 function byte-identical.
4. **Reuse the contracts v1.1 shipped:** `output_path`'s 4th arg, `select_quality`'s `\tlabel\tsubtext` wire + strip-revalidate chokepoint, `video_duration`/`video_audio_kbps` probes, the awk float-math convention, the MiB-labeled-`MB` scale. No signature changes to any existing function.
5. **Zero files outside `bin/omarchy-transcode`** need edits for the feature itself (menu-input is shipped; only the test file grows). The whole feature is one script + one test file.
6. **Residual conflict windows** if v1.1 changes under review: the arg loop, the quality gate, `select_quality`'s row list and return case, the `main` tail. These are the same regions v1.1 added — small hunks, rebase-cheap. `transcode_video`, `output_path`, `transcode_picture`, `media_type`, `copy_to_clipboard`, and all four helpers stay untouched.

## Open Design Calls (for the plan, not blocking)

| Call | Options | Lean |
|------|---------|------|
| Audio under tight budgets | Step 192→96→64 inside `plan_target`, or refuse at fixed 192k | Step-ladder per FEATURES (3 constants in a case); without it, legit targets refuse early |
| Garbage at the input prompt | Reprompt once vs error out | Reprompt once |
| Sentinel return shape | `target:<bytes>` prefix vs separate variable | Prefix on `select_quality`'s stdout — one return channel |
| Floor values | ~2000/800/400 kbps for 4k/1080p/720p | Per FEATURES grounding; plan picks, tests pin them |
| Sub-720p rungs | Extend ladder (`scale=-2:480/360`) vs refuse | Refuse — on-brand dignity floor; extend only if dogfooding shows refusals |
| `--target` + unset resolution | Prompt for ceiling as usual vs default to source | Prompt as usual — resolution keeps its "ceiling" meaning, flag doesn't bypass prompts |

## Sources

- `bin/omarchy-transcode` (431 lines, read in full; arg loop `:305-331`, quality gate `:348-361`, validation `:379-409`, menu `:411-413`, dispatch `:417-428`; helpers `output_path` `:49-73`, `video_duration` `:162-168`, `video_audio_kbps` `:172-178`, `select_quality` `:247-287`, `output_size_label` `:291-299`, `transcode_video` `:107-148`)
- `bin/omarchy-menu-select` (120 lines; `--` arg boundary `:32-70`, `mode:"select"` payload `:87-110`, handshake `:81-84`/`:112-119`)
- `bin/omarchy-menu-input` (58 lines; `mode:"input"` `:39`, same handshake)
- `bin/omarchy-menu-file` (48 lines; sibling wrapper pattern — pipes find output into `omarchy-menu-select`)
- `shell/plugins/menu/Menu.qml` (1484 lines, read in full; mode routing `:27`, `openDmenu` `:864-885`, input-mode empty model `:558-561`, submit-is-filterText `:765-767`/`:1158-1160`, `finishRequest` `:118-136`, Esc/cancel `:834-838`/`:1136-1139`, prompt-as-placeholder `:1210`)
- `shell/plugins/menu/MenuModel.js:497-503` (`dmenuDefaultIndex` — v1.1's helper; untouched this milestone)
- `test/shell.d/transcode-quality-test.sh` (stub harness `:17-114`, `run_transcode` `:123-132`, assertion style throughout)
- `test/shell.d/menu-select-test.sh` (payload-capture `omarchy-shell` stub `:19-30` — pattern reusable if menu-side coverage is ever wanted)
- `test/shell.d/base-test.sh` (`pass`/`fail` `:13-21`, `run_node_test` `:79-126`)
- `default/nautilus-python/extensions/transcode.py` (`_launch_transcode` `:19-34`)
- `docs/menu.md:156-173` ("Select and input modes" — the shipped contract)
- `.planning/PROJECT.md` (v1.2 goal `:11-18`, additive-layering constraint `:22`, key decisions `:73-79`)
- `.planning/milestones/v1.1-REQUIREMENTS.md:39` (SIZE-10 deferral note)
- `research/STACK.md`, `research/FEATURES.md` (v1.2 companions — verified ffmpeg mechanics, comparator math, floor grounding)
- `bin/omarchy:62` (menu group registration), `bin/omarchy-notification-send` (`-r`/replace-id `:50`,`:106`)

---
*Architecture research for: omarchy-transcode `--target <size>` two-pass encoding + Custom size menu input (milestone v1.2)*
*Researched: 2026-09-16*
