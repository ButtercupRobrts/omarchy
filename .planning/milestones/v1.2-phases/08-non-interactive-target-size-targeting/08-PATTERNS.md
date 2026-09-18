# Phase 8 Pattern Mapping: Non-interactive `--target` size targeting

**Mapped:** 2026-09-16 against `bin/omarchy-transcode` (431 lines) and `test/shell.d/transcode-quality-test.sh` (663 lines) at HEAD.
**Files touched:** exactly two — `bin/omarchy-transcode` (modified, additive) and `test/shell.d/transcode-quality-test.sh` (modified, extended). No new files.

---

## 1. File inventory — roles and data flow

| File | Role | Data flow | Change class |
|------|------|-----------|--------------|
| `bin/omarchy-transcode` | Target script — the whole feature | raw `--target` text → `parse_target_size` → integer bytes + normalized token → refusal matrix → `plan_target` (2 probes → `eff_res video_kbps`) → `output_path` 4th-arg token → `transcode_video_target` (pass1 → `-r` toast → pass2 → ≤1 retry) → shared clipboard/size/done-toast tail | Modified: one contiguous helper block (`:299→:301`) + six minimal `main()` hunks + metadata/`usage()` lines. All existing function bodies byte-identical (PR #12135 conflict window). |
| `test/shell.d/transcode-quality-test.sh` | Stub harness — proves argv, ordering, refusals | `FAKE_*` env knobs → stub binaries record `%q` argv lines + `out=` lines into `$CALLS` → per-row `grep`/`cmp`/emptiness assertions | Modified: pass-aware `ffmpeg` stub dispatch, `-p` arm on the notification stub, `TMPDIR` export in `run_transcode`, `FAKE_PASS1_RC`/`FAKE_PASS2_RC`/`FAKE_OUT_BYTES2` knobs, ~20 new case rows. All v1.1 pins keep passing unchanged. |

**Read-only references** (patterns copied from, never edited): `bin/omarchy-notification-send` (`-p`/`-r` mechanics), `bin/omarchy-menu-select` / `bin/omarchy-menu-input` (`mktemp` + `trap EXIT`), `bin/omarchy` (`command_requires_args`), `agents/skills/command-metadata.md`, `test/shell.d/base-test.sh` (`pass`/`fail`).

---

## 2. `bin/omarchy-transcode` — site-by-site analogs

### 2a. Metadata header `:6-7` + `usage()` `:11-32`

**Analog:** the existing `args=`/`examples=` lines themselves, plus `agents/skills/command-metadata.md`.

```bash
# bin/omarchy-transcode:6-7 (current)
# omarchy:args=[--path path] [input] [format] [resolution] [quality]
# omarchy:examples=omarchy transcode|omarchy transcode --path ~/Downloads|omarchy transcode ~/Videos/demo.mov mp4 1080p|omarchy transcode ~/Pictures/background.heic jpg medium|omarchy transcode ~/Videos/demo.mov mp4 1080p low
```

```bash
# bin/omarchy-transcode:14, :20 (current)
  omarchy transcode [--path path] [input] [format] [resolution] [quality]
...
  --path path  Limit interactive fuzzy file selection to this path
```

**Pattern to copy:**
- `[--target size]` goes in *bracketed* form in both `args=` and the `Usage:` line — `command_requires_args` (`bin/omarchy:361-372`) strips every `[...]` span and requires a non-empty remainder to force args; all-bracketed keeps bare `omarchy transcode` routed to the interactive picker.
- Examples join on a bare `|` (the skill doc says "` | `" but the existing line uses `|`; match the file). Append `omarchy transcode ~/Videos/demo.mov mp4 1080p --target 25M`.
- Options block gets one line matching `--path`'s two-space-aligned shape: `--target size  Target output size (e.g. 25M, 1.5G); bare number means MB`.
- `test/cli:606-612` pins metadata shape — all three sites in the same commit.

### 2b. Arg loop `--target` arm (`:305-331`)

**Analog — the `--path` arm verbatim (`:307-311`):**

```bash
    --path)
      shift
      (( $# > 0 )) || { echo "Missing value for --path" >&2; return 2; }
      search_path="$1"
      ;;
```

**Pattern to copy:** same `shift`-then-`(( $# > 0 ))` missing-value guard, `Missing value for --target` on stderr, `return 2` (arg-parse exit code). Then `target_bytes=$(parse_target_size "$1") || return 2` and `target_token=$(numfmt --to=iec "$target_bytes")`. **No `--target=` form** — `--path` doesn't have one; unknown `--foo=bar` falls through to the `--*)` arm (`:321-325`) which prints `Unknown option:` + usage + `return 2`. Duplicate `--target` → last wins, same as `--path`.

### 2c. `main()` locals (`:302-303`)

```bash
# current
  local input="" format="" resolution="" search_path=""
  local type output quality size positional=()
```

**Pattern:** add one adjacent `local` line — `local target_bytes="" target_token="" video_kbps="" requested_resolution="" notify_id=""`. `target_bytes` (not the raw string) is the mode signal; raw text is discarded after parse (Pitfall 3 — raw text never reaches argv or a filename).

### 2d. Refusal matrix — three insertion sites

**Analog — the quality gate (`:348-361`):**

```bash
  if [[ -n $quality ]]; then
    if [[ $type == "picture" ]]; then
      echo "Invalid argument: quality applies to videos only" >&2
      return 1
    fi

    case "$quality" in
    high | medium | low) ;;
    *)
      echo "Invalid video quality: $quality (expected high, medium, or low)" >&2
      return 1
      ;;
    esac
  fi
```

**Analog — the video validation block (`:379-393`):**

```bash
  if [[ $type == "video" ]]; then
    case "$format" in
    mp4 | gif) ;;
    *)
      echo "Invalid video format: $format" >&2
      return 1
      ;;
    esac
```

**Pattern to copy:** `Invalid …`/`echo … >&2; return 1` idiom, no `usage` echo on semantic conflicts. Placement:
- `--target` + quality conflict: first check *inside* the existing `[[ -n $quality ]]` gate (`-n $target_bytes` → stderr naming both, `return 1`).
- `--target` + picture: new adjacent block after `:361` — `[[ -n $target_bytes && $type == "picture" ]]`.
- `--target` + gif: inside the video validation block after the `mp4 | gif` case at `:380-386` — **must** sit here, not earlier, because `format` may arrive via the menu at `:363-369`. Exit 1 (semantic), not 2.

### 2e. Quality-menu gate (`:411-413`)

```bash
# current
  if [[ $type == "video" && -z $quality ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
  fi
```

**Pattern:** one added term — `&& -z $target_bytes`. The resolution prompt (`:371-377`) above stays untouched and still fires under `--target` (D-10: the pick is the planner's ceiling).

### 2f. Planner block + `output_path` (`:414-415`)

**Analogs — the capture idiom and `output_path` itself:**

```bash
# :340 — capture on its own line; failure aborts via set -e with stderr already printed
    input=$(omarchy-menu-file "Transcode picture or video" "$search_path" "jpg jpeg png webp gif heic avif mp4 mov m4v mkv webm avi")

# output_path :49-73 — the 4th-arg suffix slot and dedupe loop (byte-identical)
  local quality="${4:-}"
  ...
  name="$stem-$resolution"
  if [[ -n $quality && $quality != "medium" ]]; then
    name="$name-$quality"
  fi
  candidate="$dir/$name.$format"
  n=2
  while [[ -e $candidate || -L $candidate ]]; do
    candidate="$dir/$name-$n.$format"
    (( n += 1 ))
  done
```

**Pattern to copy:**

```bash
  if [[ -n $target_bytes ]]; then
    requested_resolution="$resolution"
    plan=$(plan_target "$input" "$target_bytes" "$requested_resolution")
    read -r resolution video_kbps <<<"$plan"
  fi

  output=$(output_path "$input" "$format" "$resolution" "${target_token:-$quality}")
```

- `plan=$(…)` on its own line — `local plan=$(…)` would mask the nonzero status (Pitfall 4). Under `set -e` a refusal aborts with `plan_target`'s stderr already emitted.
- Writing `resolution` back **before** `:415` is the Pitfall-7 fix: filename, start toast, and done toast all name the effective rung for free.
- `${target_token:-$quality}`: under `--target`, `quality` is always `""` (mutual exclusion), so the token rides the existing non-`medium` suffix branch → `stem-720p-25M.mp4`; dedupe unchanged → `…-25M-2.mp4`. Tier path unaffected because `target_token` is empty there.

### 2g. Dispatch + notification plumbing (`:417-428`)

```bash
# current video tail (:417-422) — last three lines stay shared and byte-identical
    omarchy-notification-send -g  "Transcoding video…" "$(basename -- "$input") to $format ($resolution)"
    transcode_video "$input" "$format" "$resolution" "$output" "$quality"
    copy_to_clipboard "$output"
    size=$(output_size_label "$output" || true)
    omarchy-notification-send -g  "Transcoded to $resolution $format" "Saved and copied to clipboard${size:+ ($size)}."
```

**Analog for `-p`/`-r` — `bin/omarchy-notification-send`:**

```bash
# :43-47 — -p/--print-id is a flag, takes no value
  if [[ $opt == -p || $opt == --print-id ]]; then
    print_id=1
    ...
# :65-71 — -r validates a numeric id into replaces_id
  -r | --replace-id)
    [[ $val =~ ^[0-9]+$ ]] || { echo "Invalid $opt value ..." >&2; exit 1; }
    replaces_id=$val
# :205-208 — -p prints the bare id (strips busctl's "u " prefix)
if ((print_id)); then
  out=$("${notify_cmd[@]}")
  printf '%s\n' "${out##* }"
```

**Pattern:** inner `if [[ -n $target_bytes ]]` branch — `notify_id=$(omarchy-notification-send -p -g <glyph> "Transcoding video…" "$body")` (body carries effective res + step-down disclosure + target, "pass 1/2"), then `transcode_video_target "$input" "$resolution" "$output" "$video_kbps" "$target_bytes" "$notify_id"`; `else` holds today's two lines byte-identical. `copy_to_clipboard`/`output_size_label`/done toast stay shared below the `if`. Inside the new function, the `-r "$notify_id"` replace is wrapped in a real `if` — `[[ $notify_id =~ ^[0-9]+$ ]] && omarchy-notification-send …` as a bare statement aborts under `set -e` when the guard fails (§4 footgun).

### 2h. New helper block — `parse_target_size` (`:299→:301` slot)

**Analogs — the file's gate-then-verify style:**

```bash
# video_duration :162-168 — probe, regex-gate, print-or-fail
video_duration() {
  local duration
  duration=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null || true)
  [[ $duration =~ ^[0-9.]+$ ]] || return 1
  printf '%s' "$duration"
}

# media_type :43-44 — stderr message + return 1 refusal shape
    echo "Unsupported file type: $mime" >&2
    return 1
```

**Pattern:**
1. Regex-gate `^[0-9]+(\.[0-9]+)?([kKmMgG][bB]?)?$` first → `Invalid target size: <input>` on stderr, `return 1` (callers own exit codes — the flag arm propagates `return 2`).
2. Normalize: strip optional trailing `[bB]`, uppercase the unit letter, append `M` when bare.
3. `bytes=$(numfmt --from=iec "$normalized")` as belt over the regex — research-verified accept/reject table (08-RESEARCH §2): `25M`→`26214400`, `1.5G`→`1610612736`, `500K`→`512000`; raw `25m`/`25MB`/bare `25` all misbehave in numfmt, which is exactly what the normalize step fixes.
4. `(( bytes > 0 )) || reject` — kills `0`, `0M`, `0.0K` uniformly.
5. Pure validator: integer bytes on stdout, nothing else. Shared with Phase 9's `Custom size…` row by design.

**`numfmt` note:** zero existing `numfmt` usage in `bin/` — this phase introduces it to the tree. It's a runtime invariant (coreutils, no `omarchy-cmd-present` guard — AGENTS.md). The MiB scale it produces matches what `estimate_label`/`output_size_label` already label "MB". Token side: `numfmt --to=iec "$target_bytes"` — `26214400`→`25M`, `1048576`→`1.0M` (the `.` is filename-safe; pin whichever shape ships).

### 2i. New helper block — `plan_target`

**Analogs — awk `-v` math + named-case constant tables:**

```bash
# estimate_label :229-240 — awk -v args only, never string-built; BEGIN block;
# MiB scale labeled "MB"
  awk -v dur="$1" -v kbps="$2" -v audio="$3" -v src="$4" 'BEGIN {
    bytes = dur * (kbps + audio) * 125
    if (src != "" && bytes > src) { print "larger than source"; exit }
    mb = bytes / 1048576
    ...
    printf "~%.0f MB", r
  }'

# quality_kbps :217-223 — named-case constants, never declare -A
quality_kbps() {
  case "$1" in
  720p)  case "$2" in high) echo 2500  ;; medium) echo 1500 ;; low) echo 700  ;; esac ;;
  1080p) case "$2" in high) echo 5500  ;; medium) echo 3000 ;; low) echo 1400 ;; esac ;;
  4k)    case "$2" in high) echo 16000 ;; medium) echo 9000 ;; low) echo 4500 ;; esac ;;
  esac
}

# select_quality :253-256 — the two-step stat/probe captures the planner reuses
    duration=$(video_duration "$input") || duration=""
    src_bytes=$(stat -c %s "$input" 2>/dev/null || true)
    [[ $src_bytes =~ ^[0-9]+$ ]] || src_bytes=""
    audio_kbps=$(video_audio_kbps "$input")
```

**Pattern (08-RESEARCH §3 verbatim skeleton):** cheap refusals before probes —
1. `src_bytes=$(stat -c %s "$input" 2>/dev/null || true)` → `[[ $src_bytes =~ ^[0-9]+$ ]] && (( target_bytes >= src_bytes ))` → D-06 refusal naming both sizes + tier-path pointer.
2. `duration=$(video_duration "$input") || { echo … >&2; return 1; }` — capture on its own line, never `local`.
3. `audio_kbps=$(video_audio_kbps "$input")` — 192-or-0, conservative.
4. `video_kbps=$(awk -v b=… -v d=… -v a=… 'BEGIN { if (d <= 0) exit 1; printf "%d", b*8/d/1000*0.98 - a }')` — duration gated *inside* awk because `(( ))` can't compare floats (`60.033` is a syntax error there). `%d` may print negative — that's fine, the floor loop converts it to the 720p refusal (the floor refusal *is* the SIZE-14 audio-only refusal; comment says so).
5. Floor loop: `case "$res" in 4k) floor=2000 ;; 1080p) floor=800 ;; 720p) floor=400 ;; esac` inside `while :` — `(( video_kbps >= floor )) && break`, else step `4k→1080p→720p`, else D-05 refusal with `min_label=$(awk -v a -v d 'BEGIN { printf "%.0f MB", (400+a)*d*125/1048576 }')`.
6. `printf '%s %s\n' "$res" "$video_kbps"` — exactly two words on stdout.

### 2j. New helper block — `transcode_video_target`

**Analog — `transcode_video`'s scale/codec tables (`:112-138`), duplicated deliberately:**

```bash
  case "$resolution" in
  4k) scale='scale=-2:2160' ;;
  1080p) scale='scale=-2:1080' ;;
  720p) scale='scale=-2:720' ;;
  *)  echo "Invalid video resolution: $resolution" >&2; return 1 ;;
  esac
  ...
    if [[ $resolution == "4k" ]]; then
      ffmpeg -i "$input" -vf "$scale" -c:v libx265 -preset slow ... "$output"
    else
      ffmpeg -i "$input" -vf "$scale" -c:v libx264 -preset fast ... "$output"
    fi
```

Duplication is the file's own documented convention — `quality_token`'s rationale comment (`:180-184`) states the constants "deliberately duplicate transcode_video's quality case" because "a shared table would refactor that code inside the PR conflict window." New function copies that structure with `-b:v "${video_kbps}k"` in place of `-crf` — **no `-crf` anywhere in the new function** (Pitfall 2: last-option-wins ambiguity).

**Verified pass argv (STACK.md / RESEARCH §4):**
- pass 1: `… -b:v Nk -pass 1 -passlogfile "$passdir/2pass" -an -f null /dev/null`
- pass 2: `… -b:v Nk -pass 2 -passlogfile "$passdir/2pass" -c:a aac -b:a 192k -movflags +faststart "$output"`
- `-vf`/`-c:v`/`-preset`/`-b:v` byte-identical across passes; `-an` only on pass 1; `-movflags +faststart` only on pass 2; no `-fastfirstpass` (libx264 default already true); never `-x265-stats`.

**Analog — `mktemp` + `trap EXIT` (`bin/omarchy-menu-select:81-84`, `bin/omarchy-menu-input:32-35`, `bin/omarchy-plymouth-preview:35-36`):**

```bash
selection_file=$(mktemp)
done_file=$(mktemp)
rm -f "$done_file"
trap 'rm -f "$selection_file" "$done_file"' EXIT
```

```bash
# omarchy-plymouth-preview:35-36 — the mktemp -d / rm -rf shape
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
```

**Pattern:** `passdir=$(mktemp -d)` (honors `TMPDIR` — the harness export makes cleanup observable) + `trap '[[ -n ${passdir:-} && -d $passdir ]] && rm -rf "$passdir"' EXIT`. **EXIT, not RETURN** — under `set -e` a failed pass aborts without firing function-return traps; the guard keeps the persisted trap inert after return (script has no other EXIT trap today). Delete the directory whole (x264 writes `-0.log`+`.mbtree`, x265 `-0.log`+`.cutree` — never enumerate suffixes), explicitly *after* the retry block because the retry reuses the passlog.

**Overshoot retry pattern (RESEARCH §4):** `actual=$(stat -c %s "$output" 2>/dev/null || true)` + `^[0-9]+$` gate (the `output_size_label:293-294` two-step); trigger `(( actual > target_bytes ))` — any byte-over; `retry_kbps=$(awk -v k -v t -v a 'BEGIN { printf "%d", k*t/a }')`; retry encodes to `"$passdir/retry.mp4"` wrapped in `if ffmpeg …; then mv -f -- "$passdir/retry.mp4" "$output"; fi` — a bare `cmd && cmd` statement aborts under `set -e` and would kill the run instead of degrading; no `-y` needed (passdir is unique); failed retry leaves the overshot-but-playable first output for the done toast.

---

## 3. `test/shell.d/transcode-quality-test.sh` — site-by-site analogs

### 3a. Pass-aware `ffmpeg` stub (`:34-48`)

**Analog — the current shared stub body and the ffprobe stub's argv dispatch (`:96-114`):**

```bash
# :34-48 — current: last positional is the output; breaks under two-pass
for command in ffmpeg magick; do
  cat >"$STUB_DIR/$command" <<'SH'
#!/bin/bash
{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
  printf 'out=%q\n' "${!#}"
} >>"$CALLS"
if [[ -n ${FAKE_OUT_BYTES:-} ]]; then
  truncate -s "$FAKE_OUT_BYTES" "${!#}"
fi
exit "${FAKE_ENCODE_RC:-0}"
SH
done
```

```bash
# :99-113 — ffprobe already dispatches on " $* " globs; copy this shape
case " $* " in
*" stream=codec_type "*)
  ...
  ;;
*)
  ...
  ;;
esac
```

**Pattern:** keep the shared `for command in ffmpeg magick` loop; inside the heredoc dispatch `case " $* " in *" -pass 1 "* | *" -pass 2 "* | *)`. Pass 1 records the argv line only and synthesizes passlog artifacts by walking `$@` for the arg after `-passlogfile` (`touch "$val-0.log" "$val-0.log.mbtree"`), then `exit "${FAKE_PASS1_RC:-${FAKE_ENCODE_RC:-0}}"` — never `truncate /dev/null`. Pass 2 records argv + `out=` + truncate with a per-invocation size (`FAKE_OUT_BYTES` first, `FAKE_OUT_BYTES2` on the second pass-2 — counter file next to `$CALLS`, e.g. `$CALLS.pass2n`, since env can't persist across stub invocations), `exit "${FAKE_PASS2_RC:-${FAKE_ENCODE_RC:-0}}"`. The `*)` arm keeps today's behavior for `magick` and hypothetical single-pass calls — moving `out=` inside the non-pass-1 arms keeps every existing `grep -Fx "out=…"` pin single-line.

### 3b. `omarchy-notification-send` stub — `-p` arm (`:55-58`)

```bash
# current
cat >"$STUB_DIR/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$CALLS"
SH
```

**Pattern:** after the `CALLS` line add `case " $* " in *" -p "* | *" --print-id "*) echo 7 ;; esac` — the script's `notify_id=$(…)` capture needs a printed id or the `-r` path never exercises. Recorded lines now carry `-p`/`-r 7` flags; all existing pins grep toast *text* so they hold. **Same commit** — this is Pitfall 11's harness trap.

### 3c. `run_transcode` env (`:123-132`) — `TMPDIR` export

```bash
# current
run_transcode() {
  local status=0

  : >"$calls"
  HOME="$TMPDIR/home" PATH="$STUB_DIR:$PATH" CALLS="$calls" \
    "$ROOT/bin/omarchy-transcode" "$@" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr" || status=$?
  ...
```

**Pattern:** add `TMPDIR="$TMPDIR"` to the env prefix. `mktemp -d` honors `TMPDIR`, so script-side passdirs land inside the sandbox — `find "$TMPDIR" -name '*-0.log*'` becomes the cleanup assertion.

### 3d. Assertion idioms to reuse (all existing, all keep passing)

- **Literal argv diff:** the `expected-medium-argv` printf block (`:143-148`) + `cmp -s` (`:158-168`) — extend to two expected files for the two pass lines.
- **`out=` pin:** `grep -Fx "out=$TMPDIR/in-1080p.mp4" "$calls"` (`:170`) — now `out=$TMPDIR/in-1080p-25M.mp4`.
- **Ordering:** `grep -n … | head -n1 | cut -d: -f1` + `(( notify_line < ffmpeg_line ))` (`:201-207`) — notification precedes encode.
- **Emptiness levels:** `[[ -s $calls ]]` fail (`:220-223`) for parse-level refusals; `grep -q 'notification:' || grep -q '^ffmpeg '` (`:434`, `:557`) for post-menu refusals; `grep -q '^menu-select:'`/`'^ffprobe:'` (`:417`) for the never-prompts/never-probes pins — `--target` runs add the positive twin: exactly 2 `^ffprobe:` lines.
- **Knob invocation:** `FAKE_DURATION=60 FAKE_PICK=$'medium\t…' run_transcode …` (`:380`) — per-row env prefix.
- **No-overwrite scan:** `grep -E '(^|[[:space:]])-[yn]([[:space:]]|$)' "$ffmpeg_calls"` (`:363-366`) — now covers pass lines too (pass 1 ends `/dev/null`, still no `-y`/`-n`).
- **Pass filtering:** `grep '^ffmpeg .* -pass 1 '` / `' -pass 2 '`; cross-pass `-vf`/`-c:v` identity by extraction; `wc -l` on `^ffmpeg` = 3 for the retry row (never 4).
- **`fail`/`pass`:** `base-test.sh:13-24` — `fail "<desc>" "$(cat "$calls")"` always dumps the log as detail.

---

## 4. Cross-cutting rules (bind every site)

- `#!/bin/bash` shebang, `set -euo pipefail` (both files already have it).
- Bash 5 conditionals: `[[ ]]` for string/file tests (no quoting vars, quote literals), `(( ))` for numeric — `(( $# > 0 ))`, `(( n += 1 ))`, `(( actual > target_bytes ))`. Never `-lt` inside `[[ ]]`.
- Two-space indent, no tabs (except the deliberate `$'\t'` row literals in test/menu argv).
- Captures on their own lines — `local x=$(cmd)` masks nonzero status (D-07/Pitfall 4).
- `(( expr ))` returns 1 when the expr is 0 — safe inside `if`/`while` conditions, fatal as a bare statement on a computed value. Same for `[[ cond ]] && cmd` as a statement — use a real `if` (notify guard, retry ffmpeg).
- Floats never enter `(( ))` — gate duration inside awk (`d <= 0 → exit 1`).
- `stat` on maybe-missing files: `|| true` + `=~ ^[0-9]+$` gate (`:254`, `:293-294` — never `stat | numfmt` under pipefail).
- Exit codes: `return 2` for arg-parse failures (`--path` precedent), `return 1` for semantic conflicts; `Invalid …`/`Missing value for …` stderr idiom, no `usage` echo on semantic errors.
- Encoder flags are inline literals per arm; no `-y`/`-n` anywhere (v1.1 D-01; dedupe + unique passdir are the whole collision policy).
- No `omarchy-cmd-present` guards on ffmpeg/ffprobe/numfmt/stat — runtime invariants per AGENTS.md.
- Comment style: a rationale comment above each new helper, matching `quality_token` (`:180-184`), `video_duration` (`:158-161`), `output_size_label` (`:289-290`) — explain the *why* (PR-window duplication, conservative defaults, honesty constraints), not the what.
- Additive-diff: existing function bodies byte-identical; `main()` edits are colocated hunks (locals line, one case arm, checks inside/adjacent to existing gates, one `-z` term, one planner block, one dispatch branch); one atomic commit for both files.

## PATTERN MAPPING COMPLETE
