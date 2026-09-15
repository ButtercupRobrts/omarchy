# Phase 6 Research: Interactive quality prompt + size estimates

**Researched:** 2026-09-15
**Requirements:** QUAL-01, SIZE-01
**Confidence:** HIGH — the full 250-line target file, the shipped `--default-index` plumbing, the tab⇥subtext contract in `Menu.qml`, the Phase-5 test harness, and the repo's two existing `ffprobe` call sites were all read end-to-end this session. One external fact (ffprobe's `--` terminator) could not be executed here and is flagged.
**Scope:** HOW to implement. WHAT is locked in 06-CONTEXT.md (D-00a..i, D-01..D-04) and `.planning/research/` — do not re-litigate subtext formats, fallback wording policy, or row presentation.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

Carried forward (locked by milestone research / prior phases — not re-decided):

- **D-00a:** Prompt order stays file → format → resolution → quality; quality is last because estimates key on format × resolution × tier
- **D-00b:** `medium` is the Enter-default via `omarchy-menu-select "Select quality" … -- --default-index 1` — `--default-index` and `defaultIndex` payload plumbing shipped in Phase 4
- **D-00c:** Row wire format is `"\tlabel\tsubtext"` — leading tab (glyph field) is mandatory; a bare `label\tsubtext` renders the label as the icon (PITFALLS anti-pattern 1). No caller today uses tab fields — this menu is the first
- **D-00d:** Selection return is `label[\tsubtext]` — strip with `${sel%%$'\t'*}` before the `case "$quality"` match (PITFALLS pitfall 1)
- **D-00e:** Bitrate midpoints locked (`.planning/research/STACK.md`): 720p x264 2.5/1.5/0.7 Mbps, 1080p x264 5.5/3.0/1.4 Mbps, 2160p x265 16/9/4.5 Mbps — plus the fixed 192k audio term in every mp4 estimate
- **D-00f:** gif rows get fps subtexts (`15 fps`/`10 fps`/`5 fps`), never size estimates — gif size is content-dominated fiction (20–30× spread)
- **D-00g:** ffprobe runs only inside the `type == video && -z $quality` interactive branch; a 4th positional arg or picture input skips it entirely
- **D-00h:** Estimates display with `~` prefix and 1–2 sig figs (`~110 MB`, never `~113.7 MB`) — fake precision is a researched anti-feature
- **D-00i:** The prompt fires whenever quality is unset on the interactive path, including partial positionals (`omarchy transcode in.mov mp4` still prompts resolution then quality) — consistent with existing unset-positional behavior

Phase-level decisions:

- **D-01:** mp4 subtext is `CRF N · ~N MB` — the ROADMAP success criterion's verbatim format. CRF appears as a calibration anchor; `~` + sig-fig rounding keeps it honest. Subtext is display-only, stripped before matching.
- **D-02:** When a tier's estimate would exceed the source file size (`est_bytes > stat -c %s input`), that row's number is replaced with honest qualitative text — `larger than source` wording (final wording at implementer discretion, ≤~30 chars, no tabs). Per-row: only the exceeding tiers degrade; other rows keep numbers.
- **D-03:** When ffprobe fails or returns non-numeric/`N/A` duration, ALL rows fall back to qualitative subtexts ("Best quality" / "Balanced" / "Smallest file" — exact wording at implementer discretion). Never mix subtext/no-subtext rows (uneven `detailRowHeight`, PITFALLS pitfall 10). All probes guarded `|| true` + `=~ ^[0-9.]+$` so `set -euo pipefail` can't turn a probe hiccup into a silent abort.
- **D-04:** Leading glyph field stays empty — plain text rows consistent with the format and resolution prompts in the same flow.

### The agent's Discretion

- Exact qualitative wording for `larger than source` and the three fallback subtexts — keep ≤~30 chars, no tabs
- Whether to also probe `stream=codec_type` and drop the +192k term on audio-less sources (researcher may fold it into the same ffprobe call or skip it)
- Whether to note upscales (source height < target) in the subtext — research marks it optional-or-defer
- Helper function placement/naming — keep new helpers adjacent to `transcode_video` or below `copy_to_clipboard` to shrink the PR #6698 conflict window; `case`-table style over `declare -A`
- awk vs integer math for the estimate — awk is the repo's float convention
- Test file: `test/shell.d/transcode-quality-test.sh` (avoids add/add collision with PR #6698's `transcode-test.sh`)

### Deferred Ideas (OUT OF SCOPE)

- **Upscale flag in subtext** (source 1080p → 4k) — left as implementer/researcher discretion; a user-facing warning is a possible v1.x refinement
- **Audio-stream-aware estimates** (drop +192k when no audio stream) — researcher may fold into the single probe call or defer
- **Icons on all transcode prompts** — scope creep; if ever wanted, it's a whole-flow visual pass
- **gif size estimates** — v2 (SIZE-12); needs a sample-encode estimator, table is fiction
- **Nautilus batch quality remembering** — post-v1.1; interacts with open upstream PR #6698
- **Completion-notification actual size** — Phase 7, deliberately out of this phase

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| QUAL-01 | The video transcode flow offers a quality step (high/medium/low) after format and resolution; mp4 maps to CRF tiers (x264 18/23/28, x265 20/24/28), gif maps to fps tiers (15/10/5) | §1 (main() block + row construction), §3 (tier→token table doubles as the subtext's CRF anchor); encoder-side tiers already shipped in Phase 5 at `bin/omarchy-transcode:122-130` |
| SIZE-01 | mp4 quality menu rows show a `~N MB` estimate as subtext (ffprobe duration × per-resolution/tier bitrate table + fixed 192k audio); gif rows show fps instead of a size estimate | §2 (probe incantations + guards), §3 (awk arithmetic + sig-fig rendering — the `~N MB` shape is awk's job, NOT `numfmt`), §4 (honesty fallback wiring) |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Quality prompt row construction + estimate math | `bin/omarchy-transcode` (new helpers below `copy_to_clipboard`) | — | All inputs (format, resolution, duration, source size) are known in the script; the menu only renders argv it is handed |
| Pre-highlighted `medium` | `bin/omarchy-menu-select` `--default-index` → `Menu.qml` `openDmenu` | `MenuModel.dmenuDefaultIndex` | Shipped in Phase 4; this phase only passes the flag |
| Subtext strip before tier matching | `bin/omarchy-transcode` `main()` / helper | — | Return contract is `label[\tsubtext]` (Menu.qml:771); stripping is the caller's job per D-00d |
| Nothing else | — | — | No `Menu.qml`, `MenuModel.js`, `omarchy-menu-select`, `transcode.py`, or `omarchy-menu-file` changes in this phase — the whole contract they need already shipped |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ffprobe | ffmpeg 9.0.1 (system, Arch `extra/ffmpeg`) [VERIFIED: `pacman -Q ffmpeg` → `ffmpeg 2:9.0.1-4`] | Duration probe (+ optional audio-stream detection) for the estimate | Already a de-facto runtime invariant; repo precedent at `bin/omarchy-capture-screenrecording:261,267` |
| awk | system (gawk) | Float math for `duration × bitrate` + sig-fig rendering of `~N MB` | bash has no floats; awk is the repo's float convention (`omarchy-hyprland-monitor-scaling`, `omarchy-network-speedtest`) [CITED: .planning/research/STACK.md:18] |
| `stat -c %s` | coreutils | Source byte size for the D-02 "larger than source" comparison | Platform invariant, already `[[ -f ]]`-gated at `bin/omarchy-transcode:201` |
| `omarchy-menu-select --default-index` | shipped Phase 4 | Pre-highlight `medium` | Contract verified at `bin/omarchy-menu-select:54-61,97-100`, `Menu.qml:874-878`, `MenuModel.js:497-503` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `numfmt --to=iec` | coreutils | **Not needed in this phase** — it emits compact iec forms (`108M`, `1.1G` via `--to=iec`; `--suffix=B` adds `B` with no space and no sig-fig control), which cannot produce the locked `~N MB` shape [ASSUMED — could not execute numfmt in this sandbox; behavior is coreutils-documented] | Phase 7's actual-size notification is where numfmt belongs (`stat -c %s | numfmt --to=iec`) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| awk-rendered `~N MB` (MiB scale) | `numfmt --to=iec` on byte count | numfmt picks the unit for you (`M`/`G`) and has no sig-fig rounding — wrong tool for a fixed-`MB` 1–2-sig-fig display |
| Two guarded ffprobe calls (duration + audio presence) | One combined `-show_entries format=duration:stream=codec_type` call | Combined output needs key-parsing (`codec_type=audio` line scan + `duration=` extract); two calls keep each probe trivially guarded and mirror repo precedent verbatim |
| `select_quality` helper containing the menu call + strip | Row building inline in `main()` | A helper keeps main()'s diff to ~3 lines, shrinking the PR #6698 conflict window and keeping the tab protocol in one place |

**Installation:** none — ffmpeg/ffprobe, awk, coreutils are all present (`/usr/bin/ffprobe`, `/usr/bin/ffmpeg`, `/usr/bin/numfmt`, `/usr/bin/awk`, `/usr/bin/perl` verified on disk this session).

## Package Legitimacy Audit

N/A — this phase installs zero external packages. All tooling is already a platform invariant.

---

## 1. Exact edit surface in `bin/omarchy-transcode`

Current file anatomy (verified this session): metadata header `:3-7`, `usage()` `:11-33`, `media_type()` `:35-47`, `output_path()` `:49-73`, `transcode_picture()` `:75-105`, `transcode_video()` `:107-148`, `copy_to_clipboard()` `:150-156`, `main()` `:158-248`, `main "$@"` `:250`.

### 1a. New helpers — placed between `copy_to_clipboard` (ends :156) and `main` (:158)

**Placement rationale (PR #6698):** the open upstream PR inserts `media_type_for_format`/`transcode_file`/`transcode_directory` **between `transcode_video` and `copy_to_clipboard`** [CITED: .planning/research/ARCHITECTURE.md:160]. The gap between `copy_to_clipboard` and `main` is therefore the conflict-free slot — put ALL new helpers there, not "adjacent to transcode_video" (the other discretion option lands exactly in the PR's insertion zone).

Recommended helper set (`case`-table style per discretion, matching the file's idiom):

```bash
# Echoes the display token for a tier: "CRF N" for mp4 (codec keyed on
# resolution, mirroring transcode_video's x264/x265 split), "N fps" for gif.
quality_token() {
  local format="$1" resolution="$2" quality="$3"

  case "$format" in
  mp4)
    if [[ $resolution == "4k" ]]; then
      case "$quality" in
      high) printf 'CRF 20' ;;
      medium) printf 'CRF 24' ;;
      low) printf 'CRF 28' ;;
      esac
    else
      case "$quality" in
      high) printf 'CRF 18' ;;
      medium) printf 'CRF 23' ;;
      low) printf 'CRF 28' ;;
      esac
    fi
    ;;
  gif)
    case "$quality" in
    high) printf '15 fps' ;;
    medium) printf '10 fps' ;;
    low) printf '5 fps' ;;
    esac
    ;;
  esac
  # Unknown format → empty token; callers use the qualitative fallback.
}
```

```bash
# Video bitrate midpoint in kbps for mp4 (D-00e locked table, Mbps→kbps).
quality_kbps() {
  case "$1" in                      # resolution
  720p)  case "$2" in high) echo 2500  ;; medium) echo 1500 ;; low) echo 700  ;; esac ;;
  1080p) case "$2" in high) echo 5500  ;; medium) echo 3000 ;; low) echo 1400 ;; esac ;;
  4k)    case "$2" in high) echo 16000 ;; medium) echo 9000 ;; low) echo 4500 ;; esac ;;
  esac
}
```

```bash
# "~N MB" at 1-2 sig figs, or "larger than source" when the estimate would
# exceed the input's byte size. Empty $4 disables the comparison (stat failed).
estimate_label() {
  awk -v dur="$1" -v kbps="$2" -v audio="$3" -v src="$4" 'BEGIN {
    bytes = dur * (kbps + audio) * 125          # kbps×1000/8 bytes per second
    if (src != "" && bytes > src) { print "larger than source"; exit }
    mb = bytes / 1048576                      # MiB — matches numfmt --to=iec scale Phase 7 reports
    if (mb < 1) { print "~1 MB"; exit }
    d = int(log(mb) / log(10)) - 1            # round to 2 significant figures
    if (d < -1) d = -1
    r = int(mb / (10 ^ d) + 0.5) * (10 ^ d)
    printf "~%d MB", r
  }'
}
```

```bash
# Prints the pick (label only) or nothing; propagates menu-select's exit.
select_quality() {
  local input="$1" format="$2" resolution="$3"
  local duration="" src_bytes="" audio_kbps=192 tier subtext selection
  local rows=()

  if [[ $format == "mp4" ]]; then
    duration=$(video_duration "$input") || duration=""
    src_bytes=$(stat -c %s "$input" 2>/dev/null || true)
    [[ $src_bytes =~ ^[0-9]+$ ]] || src_bytes=""
    audio_kbps=$(video_audio_kbps "$input")
  fi

  for tier in high medium low; do
    if [[ $format == "gif" ]]; then
      subtext=$(quality_token gif "$resolution" "$tier")
    elif [[ -n $duration && -n $(quality_kbps "$resolution" "$tier") ]]; then
      subtext="$(quality_token mp4 "$resolution" "$tier") · $(estimate_label "$duration" "$(quality_kbps "$resolution" "$tier")" "$audio_kbps" "$src_bytes")"
    else
      case "$tier" in                       # D-03 fallback — uniform qualitative subtexts
      high) subtext="Best quality" ;;
      medium) subtext="Balanced" ;;
      low) subtext="Smallest file" ;;
      esac
    fi
    rows+=($'\t'"$tier"$'\t'"$subtext")
  done

  selection=$(omarchy-menu-select "Select quality" "${rows[@]}" -- --default-index 1) || return
  printf '%s' "${selection%%$'\t'*}"
}
```

```bash
video_duration() {
  local duration
  duration=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null || true)
  [[ $duration =~ ^[0-9.]+$ ]] || return 1
  printf '%s' "$duration"
}

# 192 when the input has an audio stream, 0 when it provably has none;
# probe failure keeps 192 (conservative — overestimate, never under).
video_audio_kbps() {
  local streams
  if streams=$(ffprobe -v error -select_streams a -show_entries stream=codec_type \
      -of csv=p=0 "$1" 2>/dev/null); then
    [[ $streams == *audio* ]] || { echo 0; return; }
  fi
  echo 192
}
```

Notes for the planner:

- **`select_quality` owns the strip.** `main()` stays at 3 lines and the tab⇥protocol lives in one place. The strip happens inside the helper (`${selection%%$'\t'*}`) — D-00d is satisfied either way, but centralizing means a future reader can't miss it.
- **Two CRF constants duplicated, deliberately.** `quality_token` re-states the CRF/fps tier values from `transcode_video:122-130` because the subtext must name the *effective* codec's CRF (x265 20/24/28 at 4k, not x264's). A shared table would refactor Phase-5 code inside the PR #6698 conflict window — duplication of nine constants is the smaller, more reviewable surface. Add a comment pointing at `transcode_video`'s case.
- **The strip is `%%$'\t'*` on the FIRST tab.** Return shape verified: `activateIndex` writes `picked.label + "\t" + picked.detail` when detail exists [VERIFIED: shell/plugins/menu/Menu.qml:771 — `root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)`]. `"low\tCRF 28 · ~9 MB"` → `low`. ✓
- **Unknown-format positional** (`omarchy transcode in.mov avi`): `quality_token`/`quality_kbps` fall through to empty → D-03 qualitative fallback rows → encode later fails `Invalid video format` exactly as it does today (pre-existing orphan documented in 05-RESEARCH §3 — do NOT silently fix).
- **gif never probes** (recommended): `select_quality` only calls ffprobe when `format == mp4`. gif subtexts are pure table output — cheaper and strictly within D-00g's "only inside the interactive video branch" bound. If the planner prefers uniform probing, it is also legal; pick one and pin it in the test.

### 1b. `main()` — the whole new block

Insert between the resolution block (ends :234) and `output=$(output_path ...)` (:236):

```bash
  if [[ $type == "video" && -z $quality ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
  fi
```

- **Esc/cancel semantics:** `omarchy-menu-select` exits 1 on an empty selection file [VERIFIED: bin/omarchy-menu-select:110-113 — `if [[ -s $selection_file ]]; then cat … else exit 1`]; the command substitution propagates it, `set -e` aborts silently — identical to today's format/resolution Esc behavior (same shape at `:222` etc.).
- **Fires on partial positionals** per D-00i: `in.mov mp4` prompts resolution then quality; `in.mov mp4 1080p ""` prompts quality (empty = unset, consistent with Phase 5's empty-positional rule).
- **Pictures skip it** via `type == "video"` (QUAL-03 preserved); **non-interactive callers skip it** via `-z $quality` (D-00g) — a 4th positional means the block never runs and ffprobe is never spawned.
- No `local` needed inside the block if `select_quality` owns the locals.

## 2. The estimate arithmetic — why awk renders, not numfmt

- Locked formula: `est_MB = dur_s × (video_kbps + 192) / 8192` [VERIFIED: .planning/research/STACK.md:44 — "est_MB = dur_s × (video_kbps + 192) / 8192 via awk"]. Equivalent byte form used above: `bytes = dur × (kbps + audio_kbps) × 125`, `mb = bytes / 1048576` — same scale (MiB), and it keeps the estimate on the same unit `numfmt --to=iec` will report the actual size in Phase 7.
- **1–2 sig figs** (D-00h): `d = int(log(mb)/log(10)) - 1; r = int(mb/(10^d) + 0.5) * (10^d)` → 23.4 → `~23 MB`, 113.7 → `~110 MB`, 1187 → `~1200 MB`, 0.5 → floored `~1 MB`. Never a decimal point.
- **D-02 comparison in the same awk call:** `src` is the raw `stat -c %s` byte count; `bytes > src` → `larger than source` instead of the number. Subtext then reads `CRF 18 · larger than source` (26 chars — within the ≤~30 budget, and only *the number* is replaced per D-02, so the CRF anchor stays).
- **`stat` failure → `src=""` → comparison disabled** → numeric estimate shows anyway (degrading to qualitative on a stat hiccup would punish a path that was already `[[ -f ]]`-verified).
- **Zero/absurd duration:** `duration=0` yields `mb=0` → floored to `~1 MB`. Harmless; optionally tighten the duration regex guard to also reject `0*` — planner's call, not required.

## 3. Probes under `set -euo pipefail` (pitfall 8, phase-scoped)

| Probe | Incantation | Guard |
|-------|-------------|-------|
| Duration | `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input"` | `$(… 2>/dev/null || true)` then `=~ ^[0-9.]+$`, else `duration=""` → D-03 fallback rows |
| Audio presence | `ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$input"` | `if streams=$(… 2>/dev/null); then [[ $streams == *audio* ]] || kbps=0` — probe *failure* keeps 192 |
| Source size | `stat -c %s "$input"` | `|| true` + `=~ ^[0-9]+$`, else `src_bytes=""` → comparison disabled |

**Recommendation on the audio probe (discretion): DO IT.** `video_audio_kbps` mirrors `omarchy-capture-screenrecording:267` almost verbatim — `ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$latest" 2>/dev/null | grep -q audio` [VERIFIED: bin/omarchy-capture-screenrecording:267]. The 192k term is ~25% of a 720p/low estimate (PITFALLS pitfall 5); silent gpu-screen-recorder outputs are a real input class in Omarchy. Cost: ~10 lines, ~ms. The failure-mode detail that matters: **distinguish probe-failure from no-audio** by testing the substitution's exit status (`if streams=$(ffprobe …)`), not just grepping — a failed probe must keep 192 (conservative over-estimate), only a successful probe reporting no `audio` line drops it.

**On `--` in the ffprobe incantation:** STACK.md's incantation ends `-- "$input"`, but the repo's own two call sites omit `--` (`ffprobe … "$latest"`). ffprobe `--` terminator support exists in ffmpeg ≥5.0 [ASSUMED — execution blocked in this sandbox; Arch ships 9.0.1 so it would work, but the repo precedent doesn't bother]. **Recommend omitting `--`** to match `omarchy-capture-screenrecording` — inputs from `omarchy-menu-file` are absolute paths (never `-`-leading), and dropping it removes the only unverified piece of the incantation. If kept, one smoke command at implementation time settles it.

## 4. Row construction, menu call, strip — the exact sequence

Verified contracts:

- **Row parsing** [VERIFIED: shell/plugins/menu/Menu.qml:569-572 — `var parts = String(root.dmenuOptions[i] || "").split("\t"); var icon = parts.length > 1 ? parts.shift() : ""; var label = parts.shift() || ""; var detail = parts.join("\t")`]: a `\t`-containing option's FIRST field is the icon — so rows must be `"\thigh\tCRF 18 · ~110 MB"` (empty glyph field, D-00c/D-04). Bare `"high\t…"` renders `high` as the icon.
- **Return** [VERIFIED: Menu.qml:771, quoted above]: `label\tsubtext` → strip at first tab.
- **Pre-highlight** [VERIFIED: Menu.qml:874,878 — `dmenuDefaultIndex = MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)` then `selectedIndex = dmenuDefaultIndex`; MenuModel.js:497-503 clamps `index >= count` to `count - 1`]: `-- --default-index 1` puts the cursor on `medium` (row order high/medium/low); Enter activates it via `cursorActive` (already true in select mode, :879).
- **Subtext is also filter corpus + return key** (Menu.qml:573-574, 771): ≤~30 chars, never a literal tab. All proposed subtexts fit: `CRF 18 · ~110 MB` (16), `CRF 20 · ~2400 MB` (17), `CRF 18 · larger than source` (26), `15 fps` (6), `Best quality`/`Balanced`/`Smallest file` (≤14).
- **Uniform heights:** every row always carries a subtext — numeric, `larger than source`, fps, or qualitative fallback — so `detailRowHeight` is uniform in every state (D-03's no-mixed-rows rule holds even in the per-row-degraded D-02 case, since degraded rows still have subtext).

## 5. Test strategy — extend `test/shell.d/transcode-quality-test.sh`

**Extend, don't fork** (discretion locked the filename). The existing file already has the `file`/`ffmpeg`/`magick`/`wl-copy`/`omarchy-notification-send` stubs, `%q` argv recording, and the `run_transcode` wrapper [VERIFIED: test/shell.d/transcode-quality-test.sh:17-77]. Two stub changes unlock the interactive coverage:

### 5a. Dual-mode `omarchy-menu-select` stub (replaces the exit-1 tripwire at :54-60)

```bash
cat >"$STUB_DIR/omarchy-menu-select" <<'SH'
#!/bin/bash
printf 'menu-select: %s\n' "$*" >>"$CALLS"
if [[ -z ${FAKE_PICK+x} ]]; then
  exit 1                                   # tripwire: non-interactive rows never set it
fi
[[ -n $FAKE_PICK ]] || exit 1              # empty pick = Esc, same as the real script
printf '%s' "$FAKE_PICK"
SH
```

`${FAKE_PICK+x}` distinguishes *unset* (tripwire — every Phase-5 row keeps its "menu invoked = failure" semantics via the recorded `menu-select:` line and the exit-1) from *set* (Phase-6 interactive rows). `FAKE_PICK` is passed per-invocation as an env prefix so it can't leak between rows.

### 5b. `ffprobe` stub — arg-dispatched, env-driven

```bash
cat >"$STUB_DIR/ffprobe" <<'SH'
#!/bin/bash
printf 'ffprobe: %s\n' "$*" >>"$CALLS"
case " $* " in
*" codec_type "*) [[ ${FAKE_AUDIO:-yes} == "yes" ]] && echo audio ;;
*) [[ -n ${FAKE_DURATION+x} ]] && { printf '%s\n' "$FAKE_DURATION"; exit "${FAKE_PROBE_RC:-0}"; } ;;
esac
SH
```

`codec_type` in argv ⇒ the audio probe (emit `audio` or nothing); otherwise the duration probe (emit `$FAKE_DURATION`, or honor `FAKE_PROBE_RC=1` for the hard-failure row).

### 5c. Fixture detail that will bite: `stat` on the input

`touch`-created fixtures are 0 bytes → **every** estimate exceeds the source → every row degrades to `larger than source`. Interactive estimate rows need a sized fixture: `truncate -s 40M "$TMPDIR/in.mov"` (sparse, instant, `stat` reports the size) — or keep a separate sized fixture for estimate rows.

### 5d. Assertion matrix (maps to the six ROADMAP criteria)

| # | Invocation | Assert | Criterion |
|---|-----------|--------|-----------|
| Quality prompt fires | `in.mov mp4 1080p` + `FAKE_PICK=$'medium\tCRF 23 · ~23 MB'` + `FAKE_DURATION=60` | `menu-select:` argv contains `--default-index 1`, `Select quality`, and all three `\t`-joined rows (`CRF 18`/`CRF 23`/`CRF 28` with `~N MB`); ffmpeg argv = the literal medium line | 1, 3 |
| Strip before match (pitfall 1) | `FAKE_PICK=$'low\tCRF 28 · ~9 MB'` | ffmpeg argv has `-crf 28`; `out=…in-1080p-low.mp4` — proves the subtext never reached `case` | 4 |
| Sig-fig rendering | `FAKE_DURATION=157` at 1080p | recorded row contains `~110 MB`-scale value (157×5692/8192≈109→`~110 MB`); assert no `.` inside the MB token | 2, D-00h |
| Larger-than-source | tiny `truncate -s 1024` input + `FAKE_DURATION=60` | `larger than source` on the exceeding rows; mixed with numeric rows where applicable (size the fixture between tier estimates for the per-row pin, D-02) | 2 |
| `N/A` duration | `FAKE_DURATION=N/A` | all three rows qualitative (`Best quality`/`Balanced`/`Smallest file`), no `~` anywhere; menu still invoked; pick still transcodes | 2, D-03 |
| Probe hard-fail | `FAKE_PROBE_RC=1` | same all-qualitative fallback; run still reaches ffmpeg | 2, D-03 |
| gif subtexts | `in.mov gif 720p` + `FAKE_PICK=$'low\t5 fps'` | rows carry `15 fps`/`10 fps`/`5 fps`; **zero `ffprobe:` lines** in `$CALLS` (pins gif-skips-probe); ffmpeg argv `fps=5` | 1, D-00f |
| Non-interactive never probes | `in.mov mp4 1080p medium` (4 positionals) | zero `menu-select:` and zero `ffprobe:` lines; medium argv identical | 6, D-00g |
| Pictures never prompt | `img.png jpg medium` | zero `menu-select:`/`ffprobe:` lines; magick `-resize 2160x\>` | 5 |
| Partial positionals | `in.mov mp4` needs a two-pick stub — either queue picks via a call-counter file or leave to UAT; single-prompt rows cover the contract | — | D-00i |
| Enter-default equivalence | `FAKE_PICK=$'medium\t…'` vs positional `medium` | recorded ffmpeg argv byte-identical (`cmp` against `$TMPDIR/expected-medium-argv`, reusing the :84-89 fixture) | 3 |

The payload-level `defaultIndex:1` contract is already proven by `menu-select-test.sh` (Phase 4) — the transcode test only needs the argv-level `--default-index 1` pin since `omarchy-menu-select` is stubbed.

## 6. Interaction details / edges

- **Filter interaction:** typing in the quality menu resets the highlight to row 0 — shipped and documented Phase-4 behavior (`setFilter`, MenuModel.js:493-496 comment). Not a Phase-6 concern.
- **Mixed numeric/qualitative rows are legal** in the D-02 per-row degrade — heights stay uniform because subtext is always present. The forbidden mix is subtext/no-subtext, never numeric/qualitative.
- **`omarchy-menu-file` unchanged:** the file pick at `:197` takes no extra args; its own `"$@"` forwarding (`bin/omarchy-menu-file:48`) is untouched.
- **Nautilus `transcode.py`:** invokes `omarchy-transcode <path>` per file inside the floating terminal (`transcode.py:19-34`) — each video file will now run the full 4-prompt chain including quality. Locked behavior (per-file prompts accepted; batch-remembering deferred, PITFALLS pitfall 9). No change.
- **Post-pick re-validation:** the stripped pick lands in `quality` *after* main()'s `:205-218` validation block already ran — a malformed label would only be caught by `transcode_video`'s own `*)` arm (`:126-129`), post-notification. Our rows are fixed literals so this can't fire in practice; if the planner wants belt-and-suspenders, re-run the `high|medium|low` case on the stripped value inside `select_quality` (one-line `case`, fails before any notification). Recommended — it's cheap and keeps the no-orphan-notification invariant.
- **`usage()` honesty (optional one-word touch):** `:16-17` says "Then pick the output format and resolution." — videos now pick quality too. A ` and quality` append is discretionary; `manual/12-screenshots-recording.md:70`'s "asks for a format and a size" sentence is Phase-7-docs-sweep territory per ROADMAP. `# omarchy:args=` already reads `[quality]` — unchanged.
- **16 existing `omarchy-menu-select` callers:** untouched by definition — this phase adds a call site, changes no shared code (grep count this session: 13 files in `bin/` reference it, consistent with the Phase-4-verified "all callers unchanged" contract).

## Common Pitfalls (phase-scoped, all pre-mapped)

1. **Subtext in the return value breaks `case`** — strip `${sel%%$'\t'*}` (inside `select_quality`). Warning sign: `Invalid video quality` or silent exit after menu close. [PITFALLS pitfall 1]
2. **Bare `label\tsubtext` rows render the label as icon** — leading `\t` mandatory. [PITFALLS anti-pattern 1]
3. **`set -e` turns a probe hiccup into a silent abort** — every probe `|| true` + regex; `(( expr ))` status-1-on-zero footgun avoided by never using `(( ))` on probe output. [PITFALLS pitfall 8]
4. **Mixed subtext/no-subtext rows look buggy** — all three rows always carry a subtext, in every state. [PITFALLS pitfall 10]
5. **`~113.7 MB` fake precision** — sig-fig rounding in awk, `~` prefix, `larger than source` when est > source. [PITFALLS pitfall 3]
6. **ffprobe `--` terminator** — STACK.md's incantation uses it; repo precedent omits it. Omit it. [§3]
7. **Stub fidelity:** 0-byte fixtures make every row `larger than source` — size the fixture; and remember `%q` escaping when grepping recorded argv (`fps=15\,`, tabs as `$'\t'`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Float estimate math | bash arithmetic, `bc` | awk | bash has no floats; `bc` isn't a guaranteed invariant [PITFALLS pitfall 8] |
| `~N MB` rendering | `numfmt --to=iec` post-processing | the awk `printf` inside `estimate_label` | numfmt emits iec compact forms, can't sig-fig-round to a fixed `MB` unit |
| Pre-highlight plumbing | a 4th tab-field or marker in the row | `-- --default-index 1` (shipped) | Markers leak into the return value [PITFALLS anti-pattern 3] |
| Menu return parsing | `cut`, `sed`, awk on the pick | `${sel%%$'\t'*}` | One expansion, established idiom |
| Audio detection | decode probes, `mediainfo` | `ffprobe -select_streams a … csv=p=0` | Repo precedent, ~ms, no decode |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | ffprobe accepts `--` as an option terminator on Arch's ffmpeg 9.x (could not execute ffprobe in this sandbox) | §3 | If wrong, the probe always fails → all rows degrade to qualitative fallback (silent, cosmetic). Recommendation already avoids it: omit `--` per repo precedent |
| A2 | `numfmt --to=iec` emits compact `108M`/`1.1G` forms (documented coreutils behavior; not executed here) | Standard Stack | None — the phase doesn't use numfmt; the claim only justifies awk rendering |
| A3 | `stat -c %s` GNU flag is a coreutils invariant on Arch (used across the repo indirectly; not grepped in `bin/`) | §3 | Low — stat exists at `/usr/bin` and the input is already `[[ -f ]]`-verified |

## Open Questions

1. **None blocking.** All discretion items carry recommendations: audio probe = yes (§3), upscale flag = defer (below), helpers below `copy_to_clipboard` (§1a), extend `transcode-quality-test.sh` (§5), awk math (§2).
2. **Upscale flag — recommended DEFER.** Rationale: (a) flagging needs a third probe (`stream=height`) plus resolution-comparison logic — more `set -e` guard surface for a "possible v1.x refinement" the CONTEXT already files under Deferred Ideas; (b) the estimate already shows the big number honestly (PITFALLS' stated minimum); (c) `CRF 20 · ~2400 MB · upscale` strains the ~30-char budget at exactly the resolutions where the warning matters. If the planner wants it anyway, the clean seam is one more guarded probe inside `select_quality` appending ` · upscale` when `height < target` — ~10 lines.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ffprobe | duration + audio probes | ✓ `/usr/bin/ffprobe` | ffmpeg 9.0.1 | D-03 qualitative fallback if the probe fails at runtime |
| ffmpeg | unchanged encode path | ✓ `/usr/bin/ffmpeg` | 9.0.1 | — |
| awk | estimate math | ✓ `/usr/bin/awk` | system | — |
| stat (`-c %s`) | D-02 source-size compare | ✓ coreutils | — | `src=""` disables comparison |
| omarchy-menu-select `--default-index` | medium pre-highlight | ✓ shipped Phase 4 | repo | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every probe has a designed degradation path, which is the feature.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash harness — `test/shell.d/*-test.sh` + `base-test.sh` `pass`/`fail`; PATH-shadowing stub binaries |
| Config file | none — `test/shell` auto-discovers `*-test.sh` (`test/shell:8-15`) |
| Quick run command | `bash test/shell.d/transcode-quality-test.sh` |
| Full suite command | `./test/shell` and `./test/cli` (or `./test/all`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| QUAL-01 | Quality step after format+resolution; mp4 CRF-tier rows, gif fps-tier rows; `medium` pre-highlighted; pick reaches correct ffmpeg argv | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` — §5d rows 1–2, gif row, Enter-default row | ✅ (extend) |
| SIZE-01 | `~N MB` mp4 subtexts at 1–2 sig figs; `larger than source` degrade; `N/A`/probe-fail all-qualitative fallback; gif fps subtexts; ffprobe only on the interactive path | e2e (stub) | `bash test/shell.d/transcode-quality-test.sh` — §5d rows 3–8 | ✅ (extend) |
| QUAL-01 (partial) | Subtext elision / `detailRowHeight` rendering / cursor on `medium` in the running menu | manual-only | — see below | — |

### Sampling Rate

- **Per task commit:** `bash test/shell.d/transcode-quality-test.sh` and `bash -n bin/omarchy-transcode`
- **Per wave merge:** `./test/shell` and `./test/cli`
- **Phase gate:** Full suite green before `/gsd-verify-work` (excluding the 7 documented pre-existing environmental failures — STATE.md: they reproduce at base commit `41b7ea3d`; don't chase them)

### Wave 0 Gaps

- [ ] None — `test/shell.d/transcode-quality-test.sh` exists and this phase extends it in place; no new framework, fixtures, or files required. (The stub upgrades in §5a/§5b land with the first task, not as a Wave-0 prerequisite.)

### Manual-Only Verifications

| Behavior | Req | Why manual |
|----------|-----|-----------|
| Quality menu opens with cursor on `medium`, subtexts un-elided at ~300px card width, uniform `detailRowHeight` | QUAL-01/SIZE-01 | Rendering/elision is a running-UI property per `agents/skills/visual-verification.md`; stubs prove argv, not pixels. Note from STATE.md: the dev shell loads the packaged `/usr/share/omarchy` tree — live verification may need an installed run or UAT, as Phase 2 recorded |
| Estimate-vs-actual calibration on 2–3 real clips (dogfood) | SIZE-01 | Real encodes only; the ±2× CRF variance is expected — the check is that estimates land inside it, not that they're exact |
| Nautilus multi-select now prompts quality per video file | QUAL-01 | Real Nautilus session; locked behavior, verify it's understood not broken |

## Security Domain

### Applicable ASVS Categories

Local bash CLI; no auth/session/crypto surface. Only input-validation-adjacent categories apply:

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V5 Input Validation | yes | ffprobe output is attacker-controlled data → `=~ ^[0-9.]+$` / `=~ ^[0-9]+$` before it reaches awk/`(( ))`; never `eval`. awk `-v` assignment interprets C escapes — regex-gating the value to digits+dots is what makes `-v dur="$duration"` safe |
| V2/V3/V4/V6 | no | no authn/session/access-control/crypto surface |

### Known Threat Patterns for this change

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Crafted video file → hostile ffprobe output into arithmetic | Tampering | Treat probe output as data: regex-validate before awk; `N/A`/junk → fallback subtexts, never abort |
| Menu return → `quality` → filename/argv | Tampering | The pick is always one of the three literal labels we built; recommend re-running the `high|medium|low` case on the stripped value inside `select_quality` so a foreign label fails before the notification (§6) |
| Tab-bearing filename → option field splitting | Tampering | Not reachable — options are fixed literal strings; filenames never enter menu options (file pick returns a path, not an option row) [PITFALLS security table] |

## Sources

### Primary (HIGH confidence — read this session)

- `bin/omarchy-transcode` (250 lines, full read — all line refs verified against post-Phase-5 state)
- `bin/omarchy-menu-select` (114 lines — tab contract `:9-13`, `--default-index` arm `:54-61`, payload `:97-100`, cancel exit `:110-113`)
- `shell/plugins/menu/Menu.qml` — `rebuildDmenuDisplay` row parse `:564-599`, `activateIndex` return `:762-772`, `openDmenu`/`dmenuDefaultIndex` `:864-885`; `MenuModel.js:493-503` (`dmenuDefaultIndex` clamp + initial-only comment)
- `bin/omarchy-capture-screenrecording:261,267` — repo's two existing guarded ffprobe call sites
- `test/shell.d/transcode-quality-test.sh` (313 lines — Phase-5 stub harness to extend), `menu-select-test.sh` (omarchy-shell handshake stub), `base-test.sh`, `test/shell` runner
- `docs/menu.md:156-173` (`defaultIndex` already documented), `manual/12-screenshots-recording.md:70-74`, `default/agents/skills/omarchy/capture.md:59`
- `default/nautilus-python/extensions/transcode.py:19-34`, `default/omarchy/omarchy-menu.jsonc:69`, `default/hypr/bindings/utilities.lua:87`
- `.planning/research/{STACK,ARCHITECTURE,FEATURES,PITFALLS,SUMMARY}.md`, `06-CONTEXT.md`, `06-DISCUSSION-LOG.md`, `05-{CONTEXT,RESEARCH,01-SUMMARY,VALIDATION,SECURITY}.md`, `04-CONTEXT.md`, `04-01-SUMMARY.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `STATE.md`, `.planning/config.json`
- Environment: `pacman -Q ffmpeg` → `2:9.0.1-4`; `/usr/bin/{ffprobe,ffmpeg,numfmt,awk,perl}` present

### Secondary / not executed

- ffprobe `--` terminator support (ffmpeg ≥5.0) — unverified here; recommendation routes around it (omit `--`, match repo precedent)
- `numfmt --to=iec` output shape — coreutils-documented, not executed; only used to justify awk rendering

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; all binaries verified on disk; repo precedent for every probe
- Architecture: HIGH — every contract (row format, return shape, defaultIndex path, strip idiom) verified in source this session
- Pitfalls: HIGH — all six phase-relevant pitfalls pre-mapped to code locations and test rows
- Estimate table values: locked by D-00e/STACK.md (MEDIUM inherent accuracy — CRF ±2× variance is by design, mitigated by `~`/sig-figs/`larger than source`/Phase-7 actual)

**Research date:** 2026-09-15
**Valid until:** 2026-10-15 (stable — all contracts are in-repo and shipped)

---
*Research for: 06-interactive-quality-prompt-size-estimates*
