# Phase 5 Patterns: Non-interactive quality in `omarchy-transcode`

**Mapped:** 2026-09-15
**Scope:** For each file this phase touches — role, closest existing analog, verbatim excerpts with line numbers, and the conventions the executor must mimic. All excerpts were read from current source this session; every line reference is verified.

Files covered:

1. `bin/omarchy-transcode` — modified (the implementation target)
2. `test/shell.d/transcode-quality-test.sh` — NEW (stub-bin e2e test)
3. `default/agents/skills/omarchy/capture.md` + `manual/12-screenshots-recording.md` — modified (docs)
4. `bin/omarchy` + `test/cli` + `agents/skills/command-metadata.md` — reference only (metadata contract verification)

---

## 1. `bin/omarchy-transcode` — MODIFIED

**Role:** leaf command in `bin/` — `#!/bin/bash`, `set -euo pipefail`, `# omarchy:*` metadata header, `usage()` heredoc, small pure functions, `main()` arg-parse + dispatch, `main "$@"` as the last line. There is no "analog" to copy — this file *is* the pattern source. The executor edits it; the excerpts below show exactly what each edit site looks like today.

### 1a. Metadata header + `usage()` (`:1-30`)

```bash
  1|#!/bin/bash
  2|
  3|# omarchy:group=transcode
  4|# omarchy:name=
  5|# omarchy:summary=Transcode pictures and videos for sharing
  6|# omarchy:args=[--path path] [input] [format] [resolution]
  7|# omarchy:examples=omarchy transcode|omarchy transcode --path ~/Downloads|omarchy transcode ~/Videos/demo.mov mp4 1080p|omarchy transcode ~/Pictures/background.heic jpg medium
  8|
  9|set -euo pipefail
 10|
 11|usage() {
 12|  cat <<'EOF'
 13|Usage:
 14|  omarchy transcode [--path path] [input] [format] [resolution]
 15|
 16|With no input, pick a picture or video from ~/Pictures and ~/Videos,
 17|or only from --path when provided. Then pick the output format and resolution.
 18|
 19|Options:
 20|  --path path  Limit interactive fuzzy file selection to this path
 21|
 22|Formats:
 23|  Pictures: jpg, png
 24|  Videos: mp4, gif
 25|
 26|Resolutions:
 27|  Pictures: high, medium, low
 28|  Videos: 4k, 1080p, 720p
 29|EOF
 30|}
```

Conventions to mimic:

- **Every arg is bracketed** in `omarchy:args` — `[quality]` must be bracketed too, or `command_requires_args` (§4) flips the command to arg-required and bare `omarchy transcode` stops reaching the interactive picker.
- **`examples` separator is a bare `|` with no spaces** — `:7` shows four examples joined `...1080p|omarchy transcode ~/Pictures/...`. (`agents/skills/command-metadata.md:15` writes "` | `" loosely; the file's own line is authoritative — match it.)
- **`usage()` is a `cat <<'EOF'` heredoc** — single-quoted delimiter, section headers as `Name:` followed by two-space-indented `Type: values` lines. The new `Qualities:` block goes after `Resolutions:` (`:26-28`), same shape. No Qualities row for pictures (QUAL-03).

### 1b. `output_path()` (`:46-57`) — gains a 4th param + dedupe loop

```bash
 46|output_path() {
 47|  local input="$1"
 48|  local format="$2"
 49|  local resolution="$3"
 50|  local dir base stem
 51|
 52|  dir=$(dirname -- "$input")
 53|  base=$(basename -- "$input")
 54|  stem="${base%.*}"
 55|
 56|  printf '%s/%s-%s.%s' "$dir" "$stem" "$resolution" "$format"
 57|}
```

Conventions to mimic:

- Returns the path via **`printf` on stdout** (not a global, not `echo`) — the dedupe loop must keep this contract; callers capture with `output=$(output_path ...)`.
- `dirname --` / `basename --` — the `--` guards `-`-leading filenames; keep it.
- `stem="${base%.*}"` — suffix-strip parameter expansion; `/` can never survive into the name.
- New locals go on the `local dir base stem` line's pattern (`local ... n`), not one-per-line.
- Dedupe idiom: `while [[ -e $candidate || -L $candidate ]]; do ... done` — **the `-L` is load-bearing** (dangling symlink → `-e` false → ffmpeg would write through the link). Counter `(( n += 1 ))`, never `(( n++ ))` — see §5 footgun note.

### 1c. `transcode_video()` (`:91-121`) — case-on-enum → variable mapping, then format dispatch

```bash
 91|transcode_video() {
 92|  local input="$1" format="$2" resolution="$3" output="$4"
 93|  local scale
 94|
 95|  case "$resolution" in
 96|  4k) scale='scale=-2:2160' ;;
 97|  1080p) scale='scale=-2:1080' ;;
 98|  720p) scale='scale=-2:720' ;;
 99|  *)
 100|    echo "Invalid video resolution: $resolution" >&2
 101|    return 1
 102|    ;;
 103|  esac
 104|
 105|  case "$format" in
 106|  mp4)
 107|    if [[ $resolution == "4k" ]]; then
 108|      ffmpeg -i "$input" -vf "$scale" -c:v libx265 -preset slow -crf 24 -c:a aac -b:a 192k -movflags +faststart "$output"
 109|    else
 110|      ffmpeg -i "$input" -vf "$scale" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 192k -movflags +faststart "$output"
 111|    fi
 112|    ;;
 113|  gif)
 114|    ffmpeg -i "$input" -vf "fps=10,$scale:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$output"
 115|    ;;
 116|  *)
 117|    echo "Invalid video format: $format" >&2
 118|    return 1
 119|    ;;
 120|  esac
 121|}
```

This is the pattern the tier table copies **directly**:

- **`case "$var" in` with arms at the same indent as `case`** (no extra indent on patterns — `4k)` sits at column 2, not 4). Single-line arms use `pattern) value ;;` on one line (`:96-98`).
- The new `case "$quality"` block goes **between the resolution case and the format case** — same position and same shape as `:95-103`, mapping to `crf_x264`/`crf_x265`/`gif_fps` locals (declared on the `local scale` line's pattern).
- **`Invalid …` idiom:** `echo "Invalid <noun>: $<var>" >&2` + `return 1` inside a `*)` arm (`:99-102`, `:116-119`; also `:67-69`, `:84-87`, `:39-42`). Quality errors follow this verbatim: `Invalid video quality: $quality`.
- The literals being replaced — `-crf 24` (`:108`), `-crf 23` (`:110`), `fps=10` (`:114`) — are exactly the `medium` tier values (D-00a). Substituting `-crf "$crf_x264"` with `crf_x264=23` keeps medium's generated argv byte-identical.
- The gif filter already interpolates `$scale` inside a double-quoted string (`:114`) — interpolating `"fps=$gif_fps,$scale:flags=lanczos,..."` is in-style.

### 1d. `main()` — arg parser, positional extract, validation site, call sites (`:131-205`)

```bash
131|main() {
132|  local input="" format="" resolution="" search_path=""
133|  local type output positional=()
134|
135|  while (( $# > 0 )); do
136|    case "$1" in
137|    --path)
138|      shift
139|      (( $# > 0 )) || { echo "Missing value for --path" >&2; return 2; }
140|      search_path="$1"
141|      ;;
142|    --help | -h)
143|      usage
144|      return 0
145|      ;;
146|    --)
147|      shift
148|      positional+=("$@")
149|      break
150|      ;;
151|    --*)
152|      echo "Unknown option: $1" >&2
153|      usage >&2
154|      return 2
155|      ;;
156|    *)
157|      positional+=("$1")
158|      ;;
159|    esac
160|    shift
161|  done
162|
163|  input="${positional[0]:-}"
164|  format="${positional[1]:-}"
165|  resolution="${positional[2]:-}"
166|  search_path="${search_path:-$HOME/Pictures:$HOME/Videos}"
167|
168|  if [[ -z $input ]]; then
169|    input=$(omarchy-menu-file "Transcode picture or video" "$search_path" "jpg jpeg png webp gif heic avif mp4 mov m4v mkv webm avi")
170|  fi
171|
172|  [[ -n $input ]] || return 1
173|  [[ -f $input ]] || { echo "File not found: $input" >&2; return 1; }
174|
175|  type=$(media_type "$input")
176|
177|  if [[ -z $format ]]; then
178|    if [[ $type == "picture" ]]; then
179|      format=$(omarchy-menu-select "Select format" jpg png)
180|    else
181|      format=$(omarchy-menu-select "Select format" mp4 gif)
182|    fi
183|  fi
184|
185|  if [[ -z $resolution ]]; then
186|    if [[ $type == "picture" ]]; then
187|      resolution=$(omarchy-menu-select "Select resolution" high medium low)
188|    else
189|      resolution=$(omarchy-menu-select "Select resolution" 4k 1080p 720p)
190|    fi
191|  fi
192|
193|  output=$(output_path "$input" "$format" "$resolution")
194|
195|  if [[ $type == "video" ]]; then
196|    omarchy-notification-send -g  "Transcoding video…" "$(basename -- "$input") to $format ($resolution)"
197|    transcode_video "$input" "$format" "$resolution" "$output"
198|    copy_to_clipboard "$output"
199|    omarchy-notification-send -g  "Transcoded to $resolution $format" "Saved and copied to clipboard."
200|  else
201|    transcode_picture "$input" "$format" "$resolution" "$output"
202|    copy_to_clipboard "$output"
203|    omarchy-notification-send -g  "Transcoded to $resolution $format" "Saved and copied to clipboard."
204|  fi
205|}
206|
207|main "$@"
```

What the executor edits here, and the conventions around each site:

- **`:133`** — `quality` joins the second local line: `local type output quality positional=()`.
- **`:163-165`** — the positional-extract idiom is `"${positional[N]:-}"`. The `:-` is mandatory: under `set -u`, `${positional[3]}` on a short array aborts. New line: `quality="${positional[3]:-}"`.
- **Validation goes between `:175` and `:177`** — after `type` is known (QUAL-03 needs it for the picture rejection), before the "Transcoding…" notification at `:196` (D-01: no orphaned notifications). Use `return 1`, matching `:172-173` — never `exit`; `main "$@"` at `:207` propagates it. Usage/option errors use `return 2` (`:139`, `:154`); bad-value errors use `return 1`.
- **`:193`** — `output=$(output_path "$input" "$format" "$resolution" "$quality")`. Note `output_path` already runs before the notification — dedupe inside it satisfies "resolved BEFORE the notification" with zero reordering.
- **`:197`** — `transcode_video ... "$output" "$quality"` (5th arg appended, after output).
- **`:201`** — `transcode_picture` unchanged; pictures never receive quality.
- **Parser details that already work:** `--` bulk-appends `"$@"` (`:146-149`) so a 4th positional after `--` lands in `positional[3]` for free. `positional[4]`+ stays silently ignored — pre-existing leniency, do not "fix".

### Callers that MUST NOT change (verified)

- `default/nautilus-python/extensions/transcode.py:26` — `shlex.join([binary, paths[0]])`; path-only by design (`:19-34`).
- `default/hypr/bindings/utilities.lua:87` — `o.bind("SUPER + CTRL + PERIOD", "Transcode", "omarchy-transcode")`.
- `default/omarchy/omarchy-menu.jsonc:69` — `"trigger.transcode": {…,"action":"omarchy-transcode"}`.
- `bin/omarchy:89` — `GROUP_DESCRIPTIONS[transcode]="Image and video transcoding"` — still accurate, no edit.

---

## 2. `test/shell.d/transcode-quality-test.sh` — NEW

**Role:** `test/shell.d/*-test.sh` e2e test — auto-discovered by `test/shell` (`:8-14`: glob `*-test.sh`, skip `base-test.sh`), sources `base-test.sh`, builds a stub `bin/` on PATH, runs the real script, greps a call log. Filename is locked (`transcode-quality-test.sh`) to avoid an add/add conflict with upstream PR #6698's `transcode-test.sh`.

**Analogs (in order of closeness):**

| Analog | What to copy |
|---|---|
| `test/shell.d/menu-plugin-test.sh` | Multi-stub dir; stubs that append to an env-named call log; wrapper that injects `HOME`/`PATH`/env per run; `[[ $CALLS == *"..."* ]]` assertions |
| `test/shell.d/menu-select-test.sh` | `mktemp`/`trap` preamble shape; single-stub heredoc; per-invocation `PATH="$STUB_DIR:$PATH"` (not a global export); `pass`/`fail` call shape; `: >"$log"` truncation between cases |
| `test/shell.d/screenrecording-test.sh` | Stub that writes `"$@"` to an env-named file; expected-file built with `printf '%s\n'` then `cmp -s` + `diff -u` in the fail detail — the byte-identical-argv assertion pattern |
| `test/shell.d/monitor-scaling-test.sh` | `run_*()` wrapper with a wall of `VAR="${VAR:-default}"` env prefixes; `grep -Fx`/`grep -F`/`! grep` assertion idioms |
| `test/shell.d/base-test.sh` | `pass`/`fail`/`require_command`/`ROOT` contract |
| `${!#}` last-arg idiom | `windows-vm-compose-test.sh:103,487`, `plymouth-set-test.sh:240,259` — precedent for grabbing the output-path argv element in the ffmpeg/magick stubs |

### 2a. Required preamble (`menu-select-test.sh:1-14` — copy verbatim, rename vars)

```bash
  1|#!/bin/bash
  2|
  3|set -euo pipefail
  4|
  5|source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
  6|
  7|require_command perl
  8|
  9|TMPDIR=$(mktemp -d)
 10|trap 'rm -rf "$TMPDIR"' EXIT
 11|
 12|STUB_DIR="$TMPDIR/stub"
 13|mkdir -p "$STUB_DIR"
 14|payloads="$TMPDIR/payloads"
```

(`require_command perl` is specific to that test; ours needs no such line unless a stub needs an external tool. `screenrecording-test.sh:5` uses the shorter `source "$(dirname "$0")/base-test.sh"` — both forms exist; the `:5` `cd`/`BASH_SOURCE` form is the more common one.)

### 2b. Stub heredoc shapes (from `menu-plugin-test.sh:18-47`)

```bash
 18|cat >"$STUB_DIR/omarchy-plugin-list" <<'STUB'
 19|#!/bin/bash
 20|cat "$FAKE_PLUGINS"
 21|STUB
 22|
 23|for command in omarchy-plugin-enable omarchy-plugin-disable; do
 24|  cat >"$STUB_DIR/$command" <<'STUB'
 25|#!/bin/bash
 26|printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
 27|STUB
 28|done
 29|
 30|# Records the rows it was offered, then answers with the pick under test.
 31|cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
 32|#!/bin/bash
 33|cat >"$FAKE_ROWS"
 34|printf '%s\n' "$FAKE_PICK"
 35|STUB
 36|
 37|cat >"$STUB_DIR/omarchy-notification-send" <<'STUB'
 38|#!/bin/bash
 39|printf 'notification: %s\n' "$*" >>"$FAKE_CALLS"
 40|STUB
 ...
 47|chmod +x "$STUB_DIR"/*
```

And the argv-recording variant from `screenrecording-test.sh:65-75`:

```bash
 65|cat >"$stub_bin/omarchy-capture-screenrecording" <<'SH'
 66|#!/bin/bash
 67|
 68|printf '%s\n' "$@" >"$OMARCHY_TEST_RECORDER_ARGS"
 69|SH
 70|
 71|cat >"$stub_bin/omarchy-notification-send" <<'SH'
 72|#!/bin/bash
 73|
 74|printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFICATION_ARGS"
 75|SH
```

Conventions to mimic:

- **Quoted heredoc delimiter** (`<<'STUB'` or `<<'SH'`) — the stub body must not expand at write time; `$@`/`$*`/`${!#}` inside are the stub's own runtime vars. Stub shebang is `#!/bin/bash` on the line immediately after the delimiter.
- **State crosses process boundaries through files named by env vars** (`$FAKE_CALLS`, `$OMARCHY_TEST_RECORDER_ARGS`) — a stub is a fresh process per call, so it can only append to a file. Ours: `CALLS` env var → `>>"$CALLS"`.
- `chmod +x "$STUB_DIR"/*` once after all stubs are written (`menu-plugin-test.sh:47`).
- For the `ffmpeg`/`magick` stubs, combine the two shapes: record argv with `printf ' %q'` per element (keeps spaced filenames one-logical-line — `screenrecording-test.sh`'s `printf '%s\n' "$@"` writes one arg per line, which the research's per-line argv diffing can't use; `%q`-joined single line is the better fit here), then `touch -- "${!#}"` so dedupe/`realpath` see a real file on rerun. `${!#}` = last positional — precedent at `windows-vm-compose-test.sh:487`: `printf '%s\n' "${!#}" >"$df_log"`.
- **`file` stub is mandatory** (verified: real `file -b --mime-type` on an empty fixture returns `inode/x-empty` → `media_type` fails). Shape it on `screenrecording-test.sh:18-55`'s `case "$1" in` stub: `case` on `"${!#}"` extension → `echo video/mp4` / `image/png`.
- **Menu tripwires:** stub `omarchy-menu-file`/`omarchy-menu-select` to `echo "menu invoked" >>"$CALLS"; exit 1` — proves the 4-positional path never goes interactive.
- `wl-copy` stub: `cat >/dev/null` (consumes the `:128` URI pipe).
- `omarchy-notification-send` stub: `menu-plugin-test.sh:37-40`'s `printf 'notification: %s\n' "$*" >>"$FAKE_CALLS"` verbatim — this is also what powers the ordering assertion (`grep -n` line numbers: `Transcoding` before `ffmpeg`).

### 2c. Run wrapper (`menu-plugin-test.sh:51-66` + `monitor-scaling-test.sh:247-261`)

```bash
 51|pick() {
 52|  local verb="$1" choice="$2"
 53|
 54|  : >"$TMPDIR/calls"
 55|  : >"$TMPDIR/rows"
 56|  HOME="$TMPDIR/home" \
 57|    PATH="$STUB_DIR:$PATH" \
 58|    FAKE_PLUGINS="$TMPDIR/plugins.json" \
 59|    FAKE_CALLS="$TMPDIR/calls" \
 60|    FAKE_ROWS="$TMPDIR/rows" \
 61|    FAKE_PICK="$choice" \
 62|    "$ROOT/bin/omarchy-menu-plugin" "$verb" >/dev/null 2>&1
 63|
 64|  ROWS=$(cat "$TMPDIR/rows")
 65|  CALLS=$(cat "$TMPDIR/calls")
 66|}
```

```bash
247|run_scaling() {
248|  HOME="$home_dir" \
249|    XDG_STATE_HOME="$home_dir/.local/state" \
250|    PATH="$stub_bin:$PATH" \
251|    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
 ...
260|    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
261|}
```

Conventions to mimic:

- **PATH is prepended inside the wrapper, per invocation** — `PATH="$STUB_DIR:$PATH" "$ROOT/bin/<target>" "$@"`. (Contrast `screenrecording-test.sh:79`'s global `export PATH="$stub_bin:..."` — the per-invocation form is what RESEARCH §2 prescribes and keeps stub leakage scoped.)
- Truncate the call log at the top of the wrapper: `: >"$TMPDIR/calls"` (`:54-55`).
- `HOME` points into the tmpdir so `search_path` defaulting (`:166` of the target) and any `~` writes stay sandboxed.
- Capture stdout/stderr to files for the error-path assertions (`menu-select-test.sh:66` redirects `2>"$TMPDIR/stderr"` on the negative case).

### 2d. Assertion idioms

From `menu-select-test.sh:49-53,66-72`:

```bash
 49|[[ $output == "b" ]] || fail "menu select returns the picked row" "$output"
 50|pass "menu select returns the picked row"
 51|grep -Fq '"defaultIndex":1' "$payloads" ||
 52|  fail "menu select emits the default index in the payload" "$(cat "$payloads")"
 ...
 66|if run_select "" Pick a b c -- --default-index 2>"$TMPDIR/stderr"; then
 67|  fail "menu select rejects --default-index without a value"
 68|fi
 69|pass "menu select rejects --default-index without a value"
 70|grep -q 'requires a value' "$TMPDIR/stderr" ||
 71|  fail "menu select says --default-index requires a value" "$(cat "$TMPDIR/stderr")"
```

From `monitor-scaling-test.sh:265-273`:

```bash
265|grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling up reaches 3x"
266|grep -F 'position = "0x0"' "$eval_out" >/dev/null || fail "monitor scaling up keeps the live position"
267|! grep -F 'position = "auto"' "$eval_out" >/dev/null || fail "monitor scaling up never emits auto position"
268|grep -Fx 'hl.monitor({ output = "eDP-1", ... })' "$monitor_lua" >/dev/null ||
269|  fail "monitor scaling up persists 3x on an appended eDP-1 rule"
```

From `screenrecording-test.sh:147-150` (expected-file + `cmp -s` + `diff -u` detail — the shape for the **byte-identical medium argv** assertion):

```bash
147|if ! cmp -s "$OMARCHY_TEST_MENU_ARGS" "$expected_menu_args"; then
148|  fail "screenrecording webcam picker passes each webcam as a menu option" "$(diff -u "$expected_menu_args" "$OMARCHY_TEST_MENU_ARGS")"
149|fi
150|pass "screenrecording webcam picker passes each webcam as a menu option"
```

And the `base-test.sh:13-24` contract being called:

```bash
 13|pass() {
 14|  printf 'ok - %s\n' "$1"
 15|}
 16|
 17|fail() {
 18|  local description="$1"
 19|  local detail="${2:-}"
 20|
 21|  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
 22|  printf 'not ok - %s\n' "$description" >&2
 23|  exit 1
 24|}
```

Rules this imposes:

- `fail` **exits the file** — every assertion must leave the tmpdir state consistent for the *next* assertion (hence `: >"$calls"` per run). Order the matrix so a pass prints immediately after its checks.
- Positive case: `cmd || fail "desc" [detail]; pass "desc"`. Negative case: `if cmd; then fail "desc"; fi; pass "desc"` — never `cmd && fail` (under `set -e` a failing `cmd` in `&&` position is fine, but the `if … then fail` form is the file's established idiom).
- `grep -F` for substring, `grep -Fx` for whole-line (exact argv match), `! grep` for absence (`$CALLS` stays empty on pre-notification rejection).

---

## 3. Docs — MODIFIED

**Role:** prose documentation, two audiences. AGENTS.md doc-layout rules: `manual/` is end-user published docs (no internals, no CRF jargon); `default/agents/skills/omarchy/capture.md` is the shipped agent skill reference.

**Path correction:** RESEARCH §6 writes `agents/skills/capture.md` — the verified path is `default/agents/skills/omarchy/capture.md` (the `agents/skills/` tree at repo root holds only task guides; the `omarchy` skill pack ships under `default/`).

### 3a. `default/agents/skills/omarchy/capture.md:56-60`

```markdown
 56|Shrink large captures before sharing them:
 57|
 58|```bash
 59|omarchy transcode <input> [format] [resolution]   # Re-encode pictures/videos for sharing
 60|```
```

Single signature line in a fenced `bash` block — update to `[format] [resolution] [quality]`. Note this block already mixes `<input>` (angle brackets) with `[format]` (brackets) — keep that style, don't normalize.

### 3b. `manual/12-screenshots-recording.md:68-74`

```markdown
 68|## Transcoding before you share
 69|
 70|A 4K screen recording or a raw HEIC off your phone is often too big to just send. `Super + Ctrl + .` (or _Trigger > Transcode_) fixes that. It offers you a fuzzy file picker over `~/Pictures` and `~/Videos`, then asks for a format and a size.
 71|
 72|Pictures go to jpg or png at high, medium, or low, which cap the width at 3160, 2160, and 1080 pixels. Videos go to mp4 or an animated gif at 4k, 1080p, or 720p. The converted file is written next to the original with the resolution in the name — `demo-1080p.mp4` — and the path is copied to the clipboard as a file URI, so you can paste it directly into an app that takes file drops.
 73|
 74|It works from the terminal too, if you already know what you want: `omarchy transcode ~/Videos/demo.mov mp4 1080p`. There's also `omarchy transcode ascii`, which turns an image into ASCII art — that one's mostly for [branding](41-branding.md).
```

Conventions to mimic:

- **Full lines, no hard wrap** (AGENTS.md style rule) — each paragraph is one long line.
- User voice: names features in plain words (`high, medium, or low`, `demo-1080p.mp4`) — add one sentence on the optional quality word and the `-high`/`-low` filename suffix. No CRF/preset/codec internals.
- `:72` already documents `stem-<resolution>.<format>` naming — the new sentence slots in beside it.
- **`manual/41-branding.md:39-42` is NOT touched** — it documents `omarchy transcode ascii` (the separate `omarchy-transcode-ascii` command), which gains no quality arg.

---

## 4. `bin/omarchy` + metadata contract — REFERENCE ONLY (no edits)

### 4a. `command_requires_args` (`bin/omarchy:361-372`)

```bash
361|command_requires_args() {
362|  local key="$1"
363|  local args="${COMMAND_ARGS[$key]}"
364|  local required="$args"
365|
366|  while [[ $required =~ ^(.*)\[[^][]*\](.*)$ ]]; do
367|    required="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
368|  done
369|
370|  required="${required// /}"
371|  [[ -n $required ]]
372|}
```

The regex at `:366` strips every `[...]` span, `:370` deletes spaces, `:371` requires something left. So `# omarchy:args=[--path path] [input] [format] [resolution] [quality]` strips to empty → command stays **arg-optional** → bare `omarchy transcode` still execs the script into the interactive picker. Verified: adding `[quality]` bracketed is behavior-neutral here. (An *unbracketed* `quality` would leave `quality` in `$required` → arg-required → would break the keybind/menu/Nautilus callers that pass no args.)

### 4b. `# omarchy:*` metadata format (`agents/skills/command-metadata.md:5-18,25-31`)

```markdown
  5|Commands in `bin/` can declare CLI metadata in comments near the top of the
  6|file. `bin/omarchy` scans the first 80 lines, and tests expect command metadata
  7|to remain valid.
 ...
 11|- `# omarchy:group=...` - override the command group inferred from the filename
 12|- `# omarchy:name=...` - override the command name inferred from the filename
 13|- `# omarchy:summary=...` - short help text
 14|- `# omarchy:args=...` - usage arguments
 15|- `# omarchy:examples=...` - examples separated with ` | `
 16|- `# omarchy:alias=...` / `# omarchy:aliases=...` - alternate routes
 17|- `# omarchy:hidden=true` - hide from default command listings
 18|- `# omarchy:requires-sudo=true` - mark commands that require sudo
```

### 4c. The lint that enforces it (`test/cli:598-612`)

```bash
598|while IFS= read -r binary_path; do
599|  header=$(awk '
600|    NR == 1 && /^#!/ { next }
601|    /^[[:space:]]*$/ { if (seen) print; next }
602|    /^[[:space:]]*#/ { seen=1; print; next }
603|    { exit }
604|  ' "$binary_path")
605|
606|  grep -q '^# omarchy:summary=' <<<"$header" || fail "metadata summary is present: $binary_path"
607|  ! grep -q '^# omarchy:binary=' <<<"$header" || fail "metadata does not repeat inferred binary: $binary_path"
608|  ! grep -q '^# omarchy:args=$' <<<"$header" || fail "metadata does not include empty args: $binary_path"
609|  ! grep -Eq '^# omarchy:(legacy|usage|visibility|mutates|interactive)=' <<<"$header" || fail "metadata avoids removed fields: $binary_path"
610|  ! grep -Eq '^# omarchy:requires-sudo=false$' <<<"$header" || fail "metadata omits false booleans: $binary_path"
611|done < <(find "$ROOT/bin" -maxdepth 1 -type f -executable -name 'omarchy-*' | sort)
```

Implications: metadata must stay in the contiguous comment block right after the shebang (the awk at `:599-604` stops at the first non-comment, non-blank line — the `set -euo pipefail` at `:9` terminates the header scan). Adding `[quality]` and one `|`-separated example is lint-neutral: `summary` stays, `args` stays non-empty, no removed keys appear.

---

## 5. Conventions checklist (applies to every edit)

From `AGENTS.md` style rules + the target file's own idiom + `docs/testing.md`:

- `#!/bin/bash` shebang (never `#!/usr/bin/env bash`); `set -euo pipefail` near the top.
- `[[ ]]` for string/file tests, `(( ))` for numeric — `(( $# > 0 ))` at `:135`, `(( n += 1 ))` for the dedupe counter. Never `-lt`/`-gt` inside `[[ ]]`.
- Inside `[[ ]]`: unquoted variables, quoted literals — `[[ $type == "picture" ]]` (`:178`).
- Two-space indent; `case` patterns sit at the same indent as `case` (see `:95-103`).
- `"${positional[3]:-}"` — the `:-` default is required under `set -u` for possibly-unset array elements.
- `return 1` for bad-value errors inside `main()`/functions; `return 2` for usage errors; never `exit` outside the real script tail (`main "$@"` propagates).
- **`set -e` counter footgun:** `(( expr ))` exits status 1 when the expression evaluates to 0. `(( n += 1 ))` starting at `n=2` can never hit it; `(( n++ ))` would be safe here too but `+=` avoids the class entirely (PITFALLS). Same reason `:139` uses `(( $# > 0 )) || { …; return 2; }` — a test in `||` position is exempt.
- **`[[ -e $p || -L $p ]]` in the dedupe loop** — plain `-e` misses dangling symlinks and would let ffmpeg write through to an unrelated target.
- Error wording: `echo "Invalid <noun>: $<var>" >&2` — `Invalid video resolution:`/`Invalid video format:`/`Invalid picture resolution:`/`Invalid picture format:` are the four existing instances; `Invalid video quality:` is the fifth.
- Metadata: `# omarchy:key=value` in the comment block immediately under the shebang; `examples` joined by bare `|`; all args bracketed.
- Tests: `mktemp -d` + `trap 'rm -rf "$TMPDIR"' EXIT`; stubs via `cat >… <<'SH'` + `chmod +x`; PATH prepended inside the run wrapper; `pass`/`fail` TAP lines; `fail` exits the file on first failure.
- Atomic commit: script + test + both doc files land together (AGENTS.md Git rule + RESEARCH §6).
