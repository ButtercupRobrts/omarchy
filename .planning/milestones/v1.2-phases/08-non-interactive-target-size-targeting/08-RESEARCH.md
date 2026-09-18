# Phase 8 Research: Non-interactive `--target` size targeting

**Researched:** 2026-09-16
**Requirements:** SIZE-10, SIZE-13, SIZE-14, SIZE-15, SAFE-02
**Confidence:** HIGH — `bin/omarchy-transcode` (431 lines) and `test/shell.d/transcode-quality-test.sh` (663 lines) read end-to-end at HEAD `4f104d58`; every edit site below is verified against current source. `numfmt` accept/reject behavior re-verified live on this system; two-pass flag shapes already verified on installed ffmpeg n9.0.1 (`research/STACK.md`).
**Scope:** HOW to implement. WHAT is locked in `08-CONTEXT.md` (D-00a..i, D-01..D-10) and `.planning/research/` — do not re-litigate floor values, the retry count, the refusal set, or the additive-diff constraint. Phase 9's `Custom size…` row is out of scope here; this phase only owes it a reusable `parse_target_size`/`plan_target` contract.

---

## 1. Exact edit surface in `bin/omarchy-transcode`

File anatomy (verified): metadata `:3-7`, `usage()` `:11-33`, `media_type` `:35-47`, `output_path` `:49-73`, `transcode_picture` `:75-105`, `transcode_video` `:107-148`, `copy_to_clipboard` `:150-156`, `video_duration` `:162-168`, `video_audio_kbps` `:172-178`, `quality_token` `:185-213`, `quality_kbps` `:217-223`, `estimate_label` `:229-240`, `select_quality` `:247-287`, `output_size_label` `:291-299`, `main()` `:301-429`, `main "$@"` `:431`.

All new code lands in **one contiguous helper block between `output_size_label` (:299) and `main` (:301)** plus minimal colocated `main()` hunks. `transcode_video`, `output_path`, `select_quality`, and every existing helper stay **byte-identical** (additive-diff constraint while PR #12135 is under upstream review — see §6).

### 1a. Metadata header `:6-7` and `usage()` `:11-32`

- `:6` `# omarchy:args=` gains a bracketed `[--target size]` — e.g. `[--path path] [--target size] [input] [format] [resolution] [quality]`. All-bracketed keeps `command_requires_args` (`bin/omarchy:361-371`, strips every `[...]` span then tests for non-empty remainder) treating the command as arg-optional — bare `omarchy transcode` still routes to the interactive picker. Verified: the function exists and behaves this way at `:361`.
- `:7` `# omarchy:examples=` appends `|omarchy transcode ~/Videos/demo.mov mp4 1080p --target 25M` — separator is a bare `|`, no spaces (`agents/skills/command-metadata.md`).
- `usage()` line `:14` gains `[--target size]`; Options block gains one `--target size  Target output size (e.g. 25M, 1.5G); bare number means MB` line. `test/cli` pins the metadata shape (`test/cli:606-612`: summary present, no empty `args=`, no removed fields) — sync all three sites in the same commit.

### 1b. `main()` locals `:302-303`

```bash
local input="" format="" resolution="" search_path=""
local type output quality size positional=()
local target_bytes="" target_token="" video_kbps="" requested_resolution="" notify_id=""
```

`target_bytes` is the mode signal everywhere (`-n $target_bytes`); the raw string is never kept — bytes and the normalized token are the only canonical values (Pitfall 3: raw text must never reach argv or the filename).

### 1c. Arg loop `:305-331` — the `--target` arm

New arm immediately after `--path` (`:307-311`), mirroring it verbatim — no `--target=` form, `--path` doesn't have one:

```bash
--target)
  shift
  (( $# > 0 )) || { echo "Missing value for --target" >&2; return 2; }
  target_bytes=$(parse_target_size "$1") || return 2
  target_token=$(numfmt --to=iec "$target_bytes")
  ;;
```

- Missing value → `return 2` (D-00a, `--path` precedent).
- Unparseable → `parse_target_size` prints `Invalid target size: <input>` to stderr and returns nonzero; the arm propagates `return 2`. Recommended: all flag-parse failures exit 2, all semantic conflicts (quality/picture/gif/floor/source) exit 1 — pin whichever the implementation chooses.
- Parsing inside the loop dies before `media_type`, before any menu, before any notification — and before `File not found`, matching `--path`'s ordering.
- Duplicate `--target` → last wins (same as `--path`); no special handling.

### 1d. Refusal matrix — four sites, in order

All pre-menu-or-earliest-possible and always pre-notification (v1.1 hoisted-validation convention, commit `c1947f8d`):

| Check | Site | Condition | Action |
|-------|------|-----------|--------|
| Missing/unparseable value | arg loop arm (§1c) | — | `return 2` |
| `--target` + positional quality | inside existing `[[ -n $quality ]]` gate `:348-361` | `[[ -n $target_bytes ]]` first check inside the gate | stderr naming both (`--target` and the tier word), `return 1` |
| `--target` + picture | adjacent new block after `:361` (type known at `:346`) | `[[ -n $target_bytes && $type == "picture" ]]` | stderr + `return 1` |
| `--target` + gif | inside the video validation block `:379-393`, after the `mp4 \| gif` case | `[[ -n $target_bytes && $format == "gif" ]]` | stderr + `return 1` |

The gif check **must** sit at `:380+`, not earlier: `format` may come from the interactive menu at `:363-369`. A positional `gif` run dies with an untouched call log; a menu-picked `gif` run dies with only `menu-select:` lines in the log — both before the notification. (D-10 discretion: an optional earlier check right after the format menu is polish; the `:380` check is mandatory.)

### 1e. Quality-menu gate `:411-413`

```bash
if [[ $type == "video" && -z $quality && -z $target_bytes ]]; then
```

One added `&& -z $target_bytes` — a CLI target skips `select_quality` entirely (D-00d). `quality` stays `""`, which is also what makes `output_path`'s suffix slot free for the target token (§1f). The resolution prompt at `:371-377` still fires when unset (D-10: the pick is the planner's ceiling).

### 1f. Planner block + `output_path` `:414-415`

Insert immediately before `:415` (after all menus, before naming):

```bash
if [[ -n $target_bytes ]]; then
  requested_resolution="$resolution"
  plan=$(plan_target "$input" "$target_bytes" "$requested_resolution")
  read -r resolution video_kbps <<<"$plan"
fi

output=$(output_path "$input" "$format" "$resolution" "${target_token:-$quality}")
```

- `plan=$(plan_target …)` on its own line: a nonzero return aborts `main` via `set -e` with `plan_target`'s stderr already printed — the refusal propagation path (same shape as `input=$(omarchy-menu-file …)` at `:340`). Never `local plan=$(…)` (masks status — D-07/Pitfall 4).
- `plan_target` prints exactly `eff_res video_kbps` on stdout; all refusals go to stderr.
- Overwriting `resolution` before `:415` is the Pitfall-7 fix: `output_path`, the start toast, and the done toast all name the *effective* rung for free (D-00e).
- `output_path`'s 4th arg becomes `${target_token:-$quality}`: under `--target`, `quality` is always `""` (mutual exclusion), so the token rides the existing non-medium suffix logic → `stem-720p-25M.mp4` (D-00h); the `[[ -e || -L ]]` dedupe is unchanged → collisions produce `stem-720p-25M-2.mp4`. One-line edit; tier path unaffected because `target_token` is empty there.

### 1g. Dispatch `:417-422` — target branch + notification plumbing

Restructure the video branch so lines `:420-422` (`copy_to_clipboard`, `output_size_label`, done toast) stay shared and byte-identical:

```bash
if [[ $type == "video" ]]; then
  if [[ -n $target_bytes ]]; then
    # start toast with -p to capture the daemon id (D-08); body names
    # effective res + step-down disclosure + target (D-09), pass 1/2
    notify_id=$(omarchy-notification-send -p -g <glyph> "Transcoding video…" "$body")
    transcode_video_target "$input" "$resolution" "$output" \
      "$video_kbps" "$target_bytes" "$notify_id"
  else
    omarchy-notification-send -g <glyph> "Transcoding video…" "$(basename -- "$input") to $format ($resolution)"
    transcode_video "$input" "$format" "$resolution" "$output" "$quality"
  fi
  copy_to_clipboard "$output"
  size=$(output_size_label "$output" || true)
  omarchy-notification-send -g <glyph> "Transcoded to $resolution $format" "Saved and copied to clipboard${size:+ ($size)}."
else
  ...
```

- **`-p`/`--print-id` exists and prints the bare id** — `bin/omarchy-notification-send:205-208` (`${out##* }` strips busctl's `u ` prefix). `-r <id>` replaces in place (`:65-71`, `:196-203`). This is the whole pass-scoped-notification mechanism (D-08): start toast carries "pass 1/2"; `transcode_video_target` issues `-r "$notify_id"` with "pass 2/2" when pass 2 begins. Guard the replace call with `[[ $notify_id =~ ^[0-9]+$ ]]` inside an `if` (see §4 footgun list — `[[ … ]] && cmd` as a statement is silently inert when the test fails: a failing non-final `&&` member is errexit-exempt, so the guard *works*, but `if` states the intent plainly and survives a later `&&`-append flipping which failure is fatal).
- The done toast names `$resolution` = effective rung automatically, and `output_size_label` reports the post-retry actual size — SIZE-02 becomes the hit/miss report for free. Disclosure of step-down in the done toast is optional (the start toast carries it; `requested_resolution` remains in scope if the implementer wants symmetry).
- A failed pass 1 under `set -e` dies before the done toast — identical to today's single-pass failure posture; the orphan start toast is existing accepted behavior.

### 1h. New helper block (between `:299` and `:301`)

Three new functions, contiguous, commented in the file's established style (rationale comment above each, like `quality_token`'s `:180-184`):

1. `parse_target_size` — §2. Shared by the flag arm now and Phase 9's menu-input handoff later (the "one parser" contract).
2. `plan_target` — §3. Prints `eff_res video_kbps`; embeds the floor table as a `case` (matching `quality_kbps`'s style — named-case constants, never `declare -A`).
3. `transcode_video_target` — §4. Sibling of `transcode_video`; deliberately duplicates the scale and codec/preset case tables per the file's documented `quality_token` convention (D-00i — extraction would edit `transcode_video`'s body inside the PR conflict window).

---

## 2. `parse_target_size` — verified mechanics

**Contract:** raw text in → integer bytes on stdout, or stderr message + nonzero. Pure validator; callers own exit codes and (Phase 9) re-prompt policy.

**Empirical `numfmt --from=iec` table (re-verified on this system):**

| Input | Result |
|-------|--------|
| `25M` | `26214400` (MiB — the scale `estimate_label`/`output_size_label` already label "MB") |
| `1.5G` | `1610612736` |
| `500K` / `500k` | `512000` |
| `25m` | **rejected** — `invalid suffix in input: 'm'` (lowercase `m` fails but lowercase `k` works; normalize case, never rely on numfmt's asymmetry) |
| `25MB` | **rejected** — `invalid suffix: 'B'` (strip the optional `B`) |
| bare `25` | `25` *bytes* — must append `M` before calling |

**Recipe:**

1. Regex-gate: `^[0-9]+(\.[0-9]+)?([kKmMgG][bB]?)?$` — accepts `25`, `25.5`, `25M`, `25m`, `25MB`, `1.5G`, `500K`; rejects `abc`, `-5M`, `25.5.2M`, ` 25M ` (no whitespace trimming — strict vocabulary matches the file's convention), `25b` (the `B` requires a K/M/G letter). 
2. Normalize: strip optional trailing `[bB]`, uppercase the unit letter, append `M` when no unit.
3. `bytes=$(numfmt --from=iec "$normalized")` — any residual failure → reject (belt over the regex).
4. `(( bytes > 0 )) || reject` — kills `0`, `0M`, `0.0K` uniformly (D-00a lists `0` as rejected; a positive-gate catches every spelling).

**Token for filename/toast:** `numfmt --to=iec "$target_bytes"` — verified: `26214400`→`25M`, `1610612736`→`1.5G`, `512000`→`500K`, `1048576`→`1.0M`. The round-trip canonicalizes `25m`/`25MB`/bare `25` to one token; the `.` in `1.0M`/`1.5G` is filename-safe. Raw user text never reaches `output_path` (Pitfall 3 / security table).

---

## 3. `plan_target` — budget math, floors, ordering

**Signature:** `plan_target <input> <target_bytes> <requested_resolution>` → stdout `eff_res video_kbps`, or stderr refusal + nonzero.

**Internal order** (Pitfalls perf trap — cheap refusals before probes):

```bash
plan_target() {
  local input="$1" target_bytes="$2" res="$3"
  local src_bytes duration audio_kbps video_kbps floor min_label

  # D-06: target >= source → refuse naming both sizes + tier-path pointer
  src_bytes=$(stat -c %s "$input" 2>/dev/null || true)
  if [[ $src_bytes =~ ^[0-9]+$ ]] && (( target_bytes >= src_bytes )); then
    echo "...source is already smaller than the target..." >&2   # point at dropping --target for conversion intent
    return 1
  fi

  # D-07/Pitfall 4: capture on its own line, never in local; no fallback exists
  duration=$(video_duration "$input") ||
    { echo "...cannot determine duration..." >&2; return 1; }
  audio_kbps=$(video_audio_kbps "$input")     # 192-or-0, conservative on failure

  # D-00b: awk -v math, estimate_label convention. Duration gated INSIDE awk —
  # bash (( )) cannot compare floats ("60.033" is a syntax error there).
  video_kbps=$(awk -v b="$target_bytes" -v d="$duration" -v a="$audio_kbps" 'BEGIN {
    if (d <= 0) exit 1
    printf "%d", b * 8 / d / 1000 * 0.98 - a   # %d truncates toward zero
  }') || { echo "...cannot determine duration..." >&2; return 1; }

  # D-04 floor table + step-down (named-case constants, quality_kbps style)
  while :; do
    case "$res" in
    4k) floor=2000 ;; 1080p) floor=800 ;; 720p) floor=400 ;;
    esac
    (( video_kbps >= floor )) && break
    case "$res" in
    4k) res=1080p ;; 1080p) res=720p ;;
    *)  # D-05: below the 720p floor → refuse naming the achievable minimum
      min_label=$(awk -v a="$audio_kbps" -v d="$duration" \
        'BEGIN { printf "%.0f MB", (400 + a) * d * 125 / 1048576 }')
      echo "Cannot fit under ... smallest achievable is ~${min_label} ..." >&2
      return 1
      ;;
    esac
  done

  printf '%s %s\n' "$res" "$video_kbps"
}
```

Notes for the planner:

- **Formula** (D-00b): `video_kbps = target_bytes × 8 ÷ 1000 ÷ duration × 0.98 − audio_kbps`. The 0.98 is the ~2% container/faststart reserve. `awk -v` args only — never string-built math (repo convention).
- **`video_kbps` may go negative** (target < audio alone): `%d` prints e.g. `-54`; the floor loop steps it to the 720p refusal — negative/zero `-b:v` never reaches argv (SC-4). No separate audio-only check needed; the floor refusal *is* the SIZE-14 refusal. Keep a comment saying so.
- **Huge bitrates ride** (D-07): a huge target/short clip derives Mbps-scale `-b:v`; x264/x265 cap internally and overshoot can't come from that direction. No ceiling constant.
- **Floor table locked: 2000/800/400** for 4k/1080p/720p (D-04). Below a rung's floor → step down; below 720p → refuse. No 480p/360p rungs (SIZE-16 deferred; the resolution vocabulary `{4k,1080p,720p}` is load-bearing in `output_path`, `usage()`, and every case arm).
- **Achievable minimum** (D-05): `(400 + audio_kbps) × duration × 125` bytes — kbps×125 = bytes/s. Format with the same `%.0f MB` MiB convention as `output_size_label` (e.g. "smallest achievable is ~4 MB"); exact wording is implementer discretion, the computed value is the contract.
- **Probes only run under `--target`**: the four-positional tier run must keep its never-probes pin (`transcode-quality-test.sh:417`). `plan_target` issues exactly 2 ffprobe calls (duration + audio-presence) — the stub's `stream=codec_type` dispatch already separates them.

**Worked numbers for the test fixture (`FAKE_DURATION=60`, audio=192k, source=120 MiB):**

| Target | bytes | usable kbps (×0.98) | video_kbps | Plan result |
|--------|-------|--------------------:|-----------:|-------------|
| `25M` | 26,214,400 | 3,425.3 | **3,233** | stays at requested rung (≥2000 → even 4k holds) |
| `10M` | 10,485,760 | 1,370.1 | **1,178** | 4k → 1080p (1178 ≥ 800) |
| `5M` | 5,242,880 | 685.1 | **493** | 4k/1080p → 720p (493 ≥ 400) |
| `4M` | 4,194,304 | 548.1 | **356** | refuse — below 720p floor; min = (592×125×60) = 4,440,000 B ≈ **4 MB** |
| `1M` | 1,048,576 | 137.0 | **−55** | refuse — audio alone eats the budget; same floor-refusal path |
| `200M` | 209,715,200 | — | — | refuse — target ≥ 125,829,120 B source (D-06) |

`FAKE_AUDIO=no` variant: audio term drops → `5M`@60s yields 685k → still 720p, but at a higher bitrate — an optional pin that the probed audio term actually moves the math.

---

## 4. `transcode_video_target` — two-pass argv, passlog lifecycle, retry

**Signature (suggested):** `transcode_video_target <input> <resolution> <output> <video_kbps> <target_bytes> [notify_id]`. Format is always mp4 (gif refused upstream); threading it anyway is discretion.

**Verified argv shapes** (n9.0.1, STACK.md; codec split resolution-keyed exactly like `transcode_video:134-138` — x265 `-preset slow` at 4k, x264 `-preset fast` below):

```bash
# shared terms: -i "$input" -vf "$scale" -c:v "$codec" -preset "$preset" -b:v "${video_kbps}k"
# pass 1 — stats only:
ffmpeg -i "$input" -vf "$scale" -c:v "$codec" -preset "$preset" \
  -b:v "${video_kbps}k" -pass 1 -passlogfile "$passdir/2pass" -an -f null /dev/null
# pass 2 — real encode; audio + faststart live here only:
ffmpeg -i "$input" -vf "$scale" -c:v "$codec" -preset "$preset" \
  -b:v "${video_kbps}k" -pass 2 -passlogfile "$passdir/2pass" \
  -c:a aac -b:a 192k -movflags +faststart "$output"
```

- `-vf`/`-c:v`/`-preset`/`-b:v` identical across passes (Pitfall 2); **no `-crf` anywhere** in this function — it belongs to the tier arms only (last-option-wins ambiguity).
- No per-pass preset divergence: libx264 `-fastfirstpass=true` is already the default (verified via `ffmpeg -h encoder=libx264`); libx265 honors `-pass`/`-passlogfile` uniformly — never `-x265-stats`.
- `-movflags +faststart` on pass 2 only (dead weight on the null muxer); `-an` on pass 1 only.

**Passlog lifecycle (Pitfall 1 — FATAL if wrong):**

```bash
passdir=$(mktemp -d)
trap '[[ -n ${passdir:-} && -d $passdir ]] && rm -rf "$passdir"' EXIT
```

- `mktemp -d` per run under `TMPDIR` → unique prefix makes stale-passlog reuse impossible by construction; never point `-passlogfile` at the output dir or `"$output"`.
- Artifacts on n9.0.1: `<prefix>-0.log` + `.mbtree` (x264) / `.cutree` (x265) — delete the directory whole, never enumerate suffixes.
- The trap must be **EXIT**, not RETURN: under `set -e` a failed pass aborts the script without running function-return traps; the EXIT trap still sees the function's locals during unwind. The `[[ -n ${passdir:-} && -d $passdir ]]` guard keeps the persisted trap inert after the function returns (the script has no other EXIT trap — verified, no `trap` anywhere today).
- Explicit `rm -rf "$passdir"` **after the retry block** (not right after pass 2 — the retry needs the passlog), plus clearing `passdir=""` or relying on the guard.

**Overshoot retry (SIZE-15, D-01..D-03):**

```bash
actual=$(stat -c %s "$output" 2>/dev/null || true)
if [[ $actual =~ ^[0-9]+$ ]] && (( actual > target_bytes )); then
  retry_kbps=$(awk -v k="$video_kbps" -v t="$target_bytes" -v a="$actual" \
    'BEGIN { printf "%d", k * t / a }')
  if [[ $retry_kbps =~ ^[0-9]+$ ]] && (( retry_kbps > 0 )); then
    if ffmpeg -i "$input" -vf "$scale" -c:v "$codec" -preset "$preset" \
         -b:v "${retry_kbps}k" -pass 2 -passlogfile "$passdir/2pass" \
         -c:a aac -b:a 192k -movflags +faststart "$passdir/retry.mp4"; then
      mv -f -- "$passdir/retry.mp4" "$output"
    fi
  fi
fi
```

- **Trigger is any byte-over** (D-01): `actual > target_bytes`, no tolerance band.
- **Tightened budget** (D-02): `video_kbps₂ = video_kbps₁ × target_bytes ÷ actual_bytes` — scale the one controllable term; resolution and 192k audio stay fixed (re-planning could silently move resolution after filename/toasts committed).
- **Retry is pass-2-only**, reusing the existing passlog — that's why cleanup waits. It writes into `$passdir` (unique → no pre-existing-file prompt → no `-y` needed anywhere; partials auto-clean via the trap) and `mv`s onto `$output` only on success (D-03). A failed retry is swallowed deliberately — the overshot-but-playable first output remains for the done notification to report honestly. Wrap the retry ffmpeg in `if …; then mv; fi`: the swallow is deliberate, so make it explicit — a bare `ffmpeg && mv` would also survive the ffmpeg failure (non-final `&&` members are errexit-exempt), but it reads as if failure should stop the run and leaves `mv`'s own failure folded into the same ambiguous chain.
- **Exactly one retry** — no loop (SIZE-17 deferred). If still over, the done toast reports actual either way.
- Worked example: first output 27,000,000 B vs target 26,214,400 → `retry_kbps = 3233 × 26214400/27000000 = 3138`.

**`set -e` footgun checklist for the new code:**

- `cmd1 && cmd2` as a *statement*: a failing **non-final** member is errexit-exempt (the list is silently inert — exactly why `(( video_kbps >= floor )) && break` is safe), but a failing **final** member aborts the run. Prefer `if` wherever a guard controls an optional action (the `notify_id` regex guard, the retry `mv`) so intent is explicit and a later `&&`-append can't flip which failure is fatal.
- `(( expr ))` returns 1 when the expression evaluates to 0 → never use `(( video_kbps > 0 ))` on a computed value without structure around it; `(( a > b ))` inside `if`/loop conditions is safe.
- Duration is a float — `(( duration > 0 ))` is a *syntax error* on `60.033`; gate inside awk (`d <= 0 → exit 1`).
- `local x=$(cmd)` masks `cmd`'s status — all captures on their own lines.
- `stat` on a missing file → `|| true` + regex gate, exactly like `output_size_label:293-294`.

---

## 5. Consolidated ordering — one `main()` pass under `--target`

```
--target 25M            → parse to bytes in the arg loop (exit 2 on failure)
input/format/res/qual   → positionals + interactive gaps filled (res prompt still fires — D-10)
media_type              → :346
quality gate :348       → --target+quality conflict, then --target+picture
format validation :380  → --target+gif (covers menu-picked gif)
quality menu :411       → skipped (-z $target_bytes)
planner :414            → target≥source refuse → probe duration → audio → math → floors → eff res
output_path :415        → stem-<effres>-<token>.mp4 (+dedupe)
dispatch :417           → start toast (-p id, pass 1/2, disclosure) → transcode_video_target
                          → pass1 → -r toast (pass 2/2) → pass2 → overshoot? one retry
copy/size/done :420-422 → shared, byte-identical; names effective res + actual size
```

Everything a refusal can hit sits left of the notification boundary; every probe sits right of the format/type checks.

---

## 6. Additive-diff constraints (recap — full rules in ARCHITECTURE.md §Additive-Diff)

1. New logic lives in new functions in one contiguous block `:299→:301`. Never reorder existing functions.
2. `main()` edits are minimal colocated hunks: one locals line, one case arm, checks inside/adjacent-to existing gates, one `-z $target_bytes` on the menu condition, one planner block, one dispatch branch. Adjacent-to, not interleaved-with, v1.1 lines.
3. Duplicate the scale/codec case tables in `transcode_video_target`; do not extract shared helpers — `transcode_video` stays byte-identical (the file's own `quality_token` precedent, `:180-184`).
4. No signature changes to existing functions; reuse `output_path`'s 4th arg, `video_duration`/`video_audio_kbps`, the awk `-v` convention, the MiB-labeled-"MB" scale.
5. One commit, two files: `bin/omarchy-transcode` + `test/shell.d/transcode-quality-test.sh`. No `docs/menu.md`/`manual/` changes (`omarchy-menu-input` already documented; this phase adds no menu surface).
6. Residual conflict windows if v1.1 changes under review: the arg loop, quality gate, validation blocks, dispatch tail — small hunks, rebase-cheap.

**Anti-scope reminders:** no `-fs` (truncates mid-stream), no convergence loop beyond the single retry, no `-maxrate/-bufsize`, no `--target=` form, no audio step-down ladder (fixed 192k + refusal — SIZE-14), no sub-720p rungs, no upscale-to-spend-budget, no gif `--target`, no progress bar, no `omarchy-cmd-present` guards on ffmpeg/numfmt (runtime invariants).

---

## 7. Test harness changes — `test/shell.d/transcode-quality-test.sh`

Extend the existing stub harness; do not build a new one. All changes ship in the same commit as the feature (Pitfall 11 — the harness traps are part of the feature commit, not a follow-up).

### 7a. Pass-aware `ffmpeg` stub (`:34-48`)

Today's stub writes `out=${!#}` and `truncate -s $FAKE_OUT_BYTES "${!#}"` — both break under two-pass (pass 1's last positional is `/dev/null` → `truncate` EINVAL noise + a junk `out=/dev/null` line). Restructure the shared `ffmpeg`/`magick` body to dispatch on argv:

```bash
case " $* " in
*" -pass 1 "*)
  # record line only; synthesize passlog artifacts from the -passlogfile arg
  # so cleanup assertions have real files to count; never truncate /dev/null
  exit "${FAKE_PASS1_RC:-${FAKE_ENCODE_RC:-0}}"
  ;;
*" -pass 2 "*)
  # record line + out= line; per-invocation size queue (see below)
  exit "${FAKE_PASS2_RC_current}"   # queue-consumed
  ;;
*)
  # magick + hypothetical single-pass: existing out=/truncate/FAKE_ENCODE_RC path
  ;;
esac
```

- Passlog synthesis: walk `$@` for the arg after `-passlogfile`, `touch "$val-0.log" "$val-0.log.mbtree"` — gives the `find "$TMPDIR" -name '*-0.log*'` cleanup assertion real artifacts.
- `out=` moves inside the non-pass-1 arms → every existing `grep -Fx "out=…"` pin stays single-line and the pass-2-only `out=` is what dedupe assertions want.
- **Per-invocation queues:** the retry test needs pass-2 #1 to overshoot and pass-2 #2 to land under. `FAKE_OUT_BYTES` stays the first real output; add `FAKE_OUT_BYTES2` (and optionally `FAKE_PASS2_RC` as a `"0 1"` list). Implement with a counter file next to `$CALLS` (e.g. `$CALLS.pass2n`) since env changes can't persist across stub invocations.
- Per-pass RC: `FAKE_PASS1_RC` / `FAKE_PASS2_RC` fall back to `FAKE_ENCODE_RC` — expresses "pass 1 ok, pass 2 dies," the exact cleanup-on-abort scenario (Pitfall 11.3).

### 7b. `omarchy-notification-send` stub (`:55-58`) — `-p` arm

The script captures `notify_id=$(omarchy-notification-send -p …)`; the stub must print an id or the `-r` replace never happens. Add: `case " $* " in *" -p "* | *" --print-id "*) echo 7 ;; esac` after the `CALLS` line. Recorded `notification: $*` lines now include `-p`/`-r 7` flags — assertions should grep toast *text*, which all existing pins already do.

### 7c. `run_transcode` env (`:123-132`) — export `TMPDIR`

`TMPDIR="$TMPDIR"` joins the `HOME=… PATH=… CALLS=…` prefix. `mktemp -d` honors `TMPDIR`, so script-side passdirs land inside the sandbox — passlog cleanup becomes observable and test artifacts stay out of real `/tmp`.

### 7d. Assertion-pattern updates

- Two `^ffmpeg ` lines per run: filter pass-specific pins with `grep '^ffmpeg .* -pass 1 '` / `' -pass 2 '`. Literal full-argv pins extend naturally to two expected files (the `expected-medium-argv` heredoc style at `:143-148`).
- `-vf`/`-c:v` cross-pass identity: extract and compare between the two lines.
- Refusal assertions: parse-level refusals (`abc`, missing value, quality conflict, picture) → `[[ ! -s $calls ]]`; post-probe refusals (below-floor, probe failure) → `calls` may contain `ffprobe:` lines but **zero** `menu-select:`/`notification:`/`ffmpeg` lines; menu-sourced gif refusal → only a `menu-select:` line, nothing after. Pin each level precisely — "before menus and before the start notification" means different emptiness at different stages.
- The existing no-overwrite-flag grep (`:363`, scans `$ffmpeg_calls`) now covers pass lines too — pass 1 ends `/dev/null`, still no `-y`/`-n`.
- The four-positional never-probes pin (`:417`) must keep passing — tier runs never call `plan_target`. Add the positive twin: a `--target` run records exactly 2 `^ffprobe:` lines (duration + audio-presence).

### 7e. New case rows (map to §8)

| Row | Invocation + knobs | Assert |
|-----|--------------------|--------|
| Happy path | `in.mov mp4 1080p --target 25M`, `FAKE_DURATION=60` | 2 ffmpeg lines; pass1 `-pass 1 -an -f null /dev/null`, no `-crf`/`-movflags`/`-c:a`; pass2 `-pass 2 -b:v 3233k -c:a aac -b:a 192k -movflags +faststart`; `out=…/in-1080p-25M.mp4` |
| Parse accepts | `25m`, `25MB`, `1.5G`, `500K`, `25` | each runs; filename tokens `-25M`/`-25M`/`-1.5G`/`-500K`/`-25M` |
| Parse rejects | `abc`, `-5M`, `0`, `25.5.2M` | nonzero + stderr naming input + empty `$calls` |
| Missing value | `… --target` (last arg) | exit 2 |
| Step-down | `--target 10M` at 4k req, `FAKE_DURATION=60` | `out=…/in-1080p-10M.mp4`, `scale=-2:1080`, toast names 1080p + step disclosure |
| Step-down 2 | `--target 5M` at 4k req | `scale=-2:720`, `in-720p-5M.mp4` |
| Below floor | `--target 4M` / `2M`, `FAKE_DURATION=60` | nonzero; stderr names achievable minimum (~4 MB); no notification/ffmpeg lines |
| Audio-only | `--target 1M`, `FAKE_DURATION=60` | refuse same path; no negative `-b:v` anywhere |
| ≥ source | `--target 200M` (120 MiB fixture) | nonzero naming both sizes; stderr points at tier path |
| Probe failure | `FAKE_DURATION` unset / `N/A` / `0` | nonzero pre-notification; `ffprobe:` line present, no fallback |
| Quality conflict | `in.mov mp4 1080p low --target 25M` | nonzero naming both; empty calls |
| gif refusal | positional `gif --target 25M` **and** menu-picked `FAKE_PICK=gif` | nonzero; pre-notification both ways |
| picture refusal | `img.png jpg medium --target 25M` | nonzero; empty calls |
| Menu skip | `in.mov mp4 1080p --target 25M` | no `Select quality` in calls |
| Ceiling prompt | `in.mov mp4 --target 5M`, `FAKE_PICK=4k` | resolution menu fires; planner steps the pick to 720p (D-10) |
| Overshoot retry | `FAKE_OUT_BYTES=27000000 FAKE_OUT_BYTES2=25000000` | exactly 3 ffmpeg lines; pass-2 #2 carries `-b:v 3138k`; no `-y`; done toast `(24 MB)` |
| Failed retry | pass-2 RCs `0 1`, sizes `27000000 …` | exit 0; first output remains; done toast reports the overshot size |
| Passlog hygiene | `FAKE_PASS2_RC=1` and `FAKE_PASS1_RC=1` runs | nonzero; `find "$TMPDIR" -name '*-0.log*'` empty; pass-1 failure → exactly 1 ffmpeg line, no done toast |
| `-r` toast | happy path | a `notification:` line carrying `-r 7` and `pass 2/2` |
| Dedupe | touch `in-1080p-25M.mp4` first | `out=…/in-1080p-25M-2.mp4` |
| usage | `--help` | `--target` documented |

---

## Validation Architecture

Nyquist gate — every Phase-8 success criterion maps to stub-harness assertions; the whole phase is automatable. Commands: `bash test/shell.d/transcode-quality-test.sh` (focused), `./test/cli` (metadata lint), `bash -n bin/omarchy-transcode` (syntax), `./test/shell` (full suite — **7 pre-existing environmental failures** per STATE.md: bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths; do not chase them).

| # | Success criterion | Automated proof |
|---|-------------------|------------------|
| 1 | Two-pass argv shapes + `in-1080p-25M.mp4` naming | §7e "Happy path" row: exactly 2 `^ffmpeg` lines; pass-1 line `grep -F` for `-pass 1`, `-an`, `-f null /dev/null`, `-b:v 3233k`, `scale=-2:1080`, `libx264 -preset fast`; `! grep -F -- '-crf'` and `-movflags` absent on pass 1; pass-2 line carries `-pass 2 -b:v 3233k -c:a aac -b:a 192k -movflags +faststart`; `-vf`/`-c:v` extracted-identical across lines; `grep -Fx "out=$TMPDIR/in-1080p-25M.mp4"`. Also literal-argv diff against two expected files for the strongest pin. |
| 2 | Parser accept/reject matrix, stderr-before-menu | §7e "Parse accepts/rejects" + "Missing value": five accept rows produce runs with the canonical filename token; four reject rows + missing value exit nonzero (`2` for missing) with the rejected input on stderr and `[[ ! -s $calls ]]` — provably before any menu/notification. |
| 3 | Step-down honesty | "Step-down" rows: `4k --target 10M` → `out=in-1080p-10M.mp4` + `scale=-2:1080` + start-toast text carries `1080p` and the step disclosure; `4k --target 5M` → `in-720p-5M.mp4` + `scale=-2:720`. Ordering pin: `notification:` line number precedes `ffmpeg` lines (existing pattern `:201-207`). |
| 4 | Floor/audio/probe refusals; no bad `-b:v` | "Below floor", "Audio-only", "Probe failure" rows: nonzero exit; stderr matches the achievable-minimum pattern (`grep -F 'MB'` + refusal phrasing); `$calls` has no `notification:`/`ffmpeg` lines. Negative pin: no recorded ffmpeg line ever matches `-b:v -\|-b:v 0k\|-nan` — structurally guaranteed because refusals precede dispatch. |
| 5 | Refusal matrix pre-notification | "Quality conflict" (names both, exit 1), "gif refusal" (positional + menu-picked variants), "picture refusal", "Menu skip" (no `Select quality` line), "Ceiling prompt" (resolution menu still fires). Each asserts the correct level of call-log emptiness per §7d. |
| 6 | Exactly one overshoot retry, honest report | "Overshoot retry": `wc -l` on `^ffmpeg` = 3 (never 4 — no silent loop); pass-2 #2's `-b:v` is the tightened literal `3138k` and smaller than #1's; no `-y` on any line; `out=` for #2 is inside the passdir then `mv`'d — final `in-1080p-25M.mp4` exists with 25,000,000 B → done toast `(24 MB)`. "Failed retry": exit 0, first output survives, toast reports its actual (overshot) size. |
| 7 | Passlog hygiene | "Passlog hygiene" rows: after a normal run and after `FAKE_PASS2_RC=1`/`FAKE_PASS1_RC=1` failures, `find "$TMPDIR" -name '*-0.log*'` is empty; pass-1 line's `-passlogfile` arg begins with `$TMPDIR` (proves tmpdir placement + `TMPDIR` export); pass-1 failure → exactly 1 ffmpeg line, no done notification. |
| 8 | Harness pass-aware + v1.1 pins hold | The whole suite going green IS the proof: `cmp` of medium argv vs `expected-medium-argv` (`:158-168`), dedupe rows, menu-row pins, never-probes pin, no-overwrite-flag grep — all unmodified and passing. Plus new positive pin: `--target` runs record exactly 2 `ffprobe:` lines. |

**Requirement traceability:** SIZE-10 ← SC 1+2; SIZE-13 ← SC 3+4; SIZE-14 ← SC 4 (audio-only row); SIZE-15 ← SC 6; SAFE-02 ← SC 2+5.

**Per-task validation:**

| Likely task | Automated check | Manual check |
|-------------|-----------------|--------------|
| 08-01 (single atomic commit: flag + parser + matrix + planner + encoder + retry + harness) | `bash -n bin/omarchy-transcode`; `bash test/shell.d/transcode-quality-test.sh` green; `./test/cli` exit 0; `git diff` review confirms `transcode_video`/`output_path`/`select_quality` byte-identical | Optional dogfood: `omarchy transcode <real-clip> mp4 1080p --target 10M` on a real file → lands under target, playable, both toasts name the effective res. Rationale: stubs prove argv, not encoder acceptance — one real run covers it. Non-blocking. |

**Known limitations to carry into the plan:**

- The notification stub must gain the `-p` arm in the *same* commit or `notify_id` is empty and the `-r` path never exercises (order the stub edit first in the file diff for reviewability).
- `numfmt --to=iec` emits `1.0M` for exact MiB — a `.` in the filename token; accepted (filename-safe, canonical). If the implementer prefers `1M`, normalize the raw string instead — pin whichever ships.
- Retry output lives in the passdir → `mv` may cross filesystems (TMPDIR could be tmpfs, output on disk). `mv` handles cross-fs transparently; the cost is one copy on the rare retry path. The alternative (a sibling temp name in the output dir) needs collision handling the passdir gets for free.
- `--target` after `--` lands in `positional[3]` and is rejected as an invalid quality — safe but the error text names quality, not `--target`. Acceptable edge; note in the plan, don't special-case.
- `omarchy transcode --target 25M` with no input is legal by design (flag anywhere) — the file picker fires, then the matrix applies. Worth one sentence in the plan so it isn't "fixed."

---

*Phase 8 research — consolidates `.planning/research/{ARCHITECTURE,PITFALLS,STACK,FEATURES}.md` + `08-CONTEXT.md` against `bin/omarchy-transcode` and `test/shell.d/transcode-quality-test.sh` at HEAD `4f104d58`.*
