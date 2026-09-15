# Phase 6: Interactive quality prompt + size estimates - Pattern Map

**Mapped:** 2026-09-15
**Files analyzed:** 2 modified, 6 reference-only (contract sources, not touched)
**Analogs found:** 2 / 2 — both touch points are in-place edits to files whose own idiom is the primary pattern; every sub-pattern also has a named secondary analog below.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `bin/omarchy-transcode` (modified — 5 new helpers + 3-line `main()` block) | utility (leaf `bin/` command) | file-I/O + interactive request-response | itself (edit surface IS the idiom source); `bin/omarchy-capture-screenrecording` for ffprobe, `bin/omarchy-menu-plugin` for tab rows | exact (self) + role-match |
| `test/shell.d/transcode-quality-test.sh` (extended — dual-mode menu stub, ffprobe stub, sized fixture) | test | e2e stub-harness (process boundary via env-named log files) | itself (Phase-5 harness); `test/shell.d/menu-plugin-test.sh` for the answering `FAKE_PICK` stub; `test/shell.d/plymouth-set-test.sh` for `truncate -s` | exact (self) + role-match |
| `test/shell.d/base-test.sh` (reference only — NOT modified) | test | — | — | n/a — `pass`/`fail`/`ROOT` contract already sufficient; research §5 names no base-test.sh changes |
| `bin/omarchy-menu-select` (reference only) | utility | request-response | — | contract source, unchanged since Phase 4 |
| `shell/plugins/menu/Menu.qml` + `MenuModel.js` (reference only) | component | event-driven | — | row-parse/return/clamp contract source; read reference for the tab⇥subtext wire format |
| `bin/omarchy-menu-file` (reference only) | utility | request-response | — | the one existing caller that passes `-- <menu args>` |

## Pattern Assignments

### `bin/omarchy-transcode` (utility, file-I/O + request-response)

**Analog:** the file itself — there is no closer bash-command analog; every new construct mirrors an in-file idiom. Secondary analogs below cover the three constructs the file does not yet contain (ffprobe, tab-field rows, `--` menu args).

#### Edit site 1: helper slot between `copy_to_clipboard` and `main` (`:150-158`)

```bash
150|copy_to_clipboard() {
151|  local output="$1"
152|  local uri
153|
154|  uri="file://$(realpath -- "$output")"
155|  printf '%s\n' "$uri" | wl-copy --type text/uri-list
156|}
157|
158|main() {
```

The gap at `:157` is the conflict-free insertion slot — upstream PR #6698 inserts its helpers between `transcode_video` and `copy_to_clipboard` (RESEARCH §1a), so ALL new helpers (`video_duration`, `video_audio_kbps`, `quality_token`, `quality_kbps`, `estimate_label`, `select_quality`) land here, not adjacent to `transcode_video`.

Conventions to mimic (verified across the file):

- **`printf` stdout-return contract** — functions answer on stdout, callers capture with `$( )`: `printf '%s' "$candidate"` (`:72`), `echo picture` (`:40`). `select_quality` prints the stripped pick; `quality_token`/`quality_kbps`/`estimate_label`/`video_duration` all print, never set globals.
- **Locals on shared lines** — `local input="$1" format="$2" resolution="$3" output="$4"` (`:108`), `local dir base stem name candidate n` (`:54`). Match this; no one-per-line locals.
- **`case` patterns at `case` indent, single-line arms** — the tier-table shape to copy verbatim is `transcode_video`'s quality case (`:122-130`):

```bash
122|  case "$quality" in
123|  high) crf_x264=18; crf_x265=20; gif_fps=15 ;;
124|  medium) crf_x264=23; crf_x265=24; gif_fps=10 ;;
125|  low) crf_x264=28; crf_x265=28; gif_fps=5 ;;
126|  *)
127|    echo "Invalid video quality: $quality (expected high, medium, or low)" >&2
128|    return 1
129|    ;;
130|  esac
```

`quality_token` re-states these nine constants (deliberate duplication — a shared table would refactor Phase-5 code inside the PR #6698 conflict window; add a comment pointing here). `quality_kbps` uses the same nested-case shape keyed on resolution (D-00e table: 720p 2500/1500/700, 1080p 5500/3000/1400, 4k 16000/9000/4500 kbps).

- **Error idiom:** `echo "Invalid <noun>: $<var>" >&2` + `return 1` inside a `*)` arm (`:127-129`, `:117-119`, `:101-103`, `:84-87`, `:43-45`). `return`, never `exit` — `main "$@"` at `:250` propagates.

#### Edit site 2: the prompt block in `main()` (`:220-236`)

The new block copies the format/resolution prompt shape exactly — same guard, same `$( )` capture, same silent-Esc propagation:

```bash
220|  if [[ -z $format ]]; then
221|    if [[ $type == "picture" ]]; then
222|      format=$(omarchy-menu-select "Select format" jpg png)
223|    else
224|      format=$(omarchy-menu-select "Select format" mp4 gif)
225|    fi
226|  fi
227|
228|  if [[ -z $resolution ]]; then
229|    if [[ $type == "picture" ]]; then
230|      resolution=$(omarchy-menu-select "Select resolution" high medium low)
231|    else
232|      resolution=$(omarchy-menu-select "Select resolution" 4k 1080p 720p)
233|    fi
234|  fi
235|
236|  output=$(output_path "$input" "$format" "$resolution" "$quality")
```

New code (inserted between `:234` and `:236`, per RESEARCH §1b):

```bash
  if [[ $type == "video" && -z $quality ]]; then
    quality=$(select_quality "$input" "$format" "$resolution")
  fi
```

- Esc semantics come free: `omarchy-menu-select` exits 1 on empty selection (`bin/omarchy-menu-select:110-113`), the command substitution propagates it, `set -e` aborts — identical to `:222`/`:230`/`:232` today.
- The block sits AFTER the positional validation at `:205-218` already ran — so the stripped pick bypasses main's `case`. RESEARCH §6 recommends a one-line `high|medium|low` re-check inside `select_quality` to keep the no-orphan-notification invariant.

#### Secondary analog A — guarded ffprobe calls (`bin/omarchy-capture-screenrecording:261,267`)

The repo's only two ffprobe call sites — copy the incantation shape verbatim (note: **no `--` terminator**, RESEARCH §3 routes around the unverified flag):

```bash
261|  if ffprobe -v error -select_streams v:0 -read_intervals %+0.2 -show_entries packet=flags -of csv=p=0 "$latest" 2>/dev/null | grep -q D; then
...
267|  if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$latest" 2>/dev/null | grep -q audio; then
```

Conventions: `-v error`, `-show_entries <key>`, `-of csv=p=0` (or `default=noprint_wrappers=1:nokey=1` for duration per STACK.md), `2>/dev/null` inside a guarded `$( … || true)` or `if` condition — never bare under `set -euo pipefail` (PITFALLS pitfall 8). `video_audio_kbps` mirrors `:267` almost verbatim, but tests the substitution's exit status (`if streams=$(ffprobe …)`) to distinguish probe-failure (keep 192) from proven no-audio (drop to 0) — RESEARCH §3.

#### Secondary analog B — tab-field menu rows + return parse (`bin/omarchy-menu-plugin:25-36`)

```bash
 25|# The id rides along as row subtext: it tells same-named plugins apart on
 26|# screen and comes back with the selection as the key to act on.
 27|rows=$(jq -r --arg icon "$PLUGIN_ICON" \
 28|  ". as \$plugins
 29|   | .[] | select($filter)
 30|   | \$icon + \"\\t\" + .name + \"\\t\" + .id" <<<"$plugins")
...
 33|selection=$(omarchy-menu-select "${1^} plugin" <<<"$rows") || exit 0
 34|[[ -n $selection ]] || exit 0
 35|
 36|id=$(cut -f2 <<<"$selection")
```

This is the proven multi-field precedent: `field⇥field⇥field` rows in, `label⇥subtext` back out, caller extracts its key. Two deliberate deviations for Phase 6: (a) field 1 stays EMPTY (`"\thigh\tCRF 18 · ~110 MB"` — D-00c/D-04, plain-text rows like the sibling prompts; a bare `label\tsubtext` would render the label as the icon); (b) rows go as argv (`rows+=(…)` + `"${rows[@]}"`) not stdin, because the `--` menu-args tail needs the option stream on argv — `omarchy-menu-select` accepts both (`:68` argv append, `:72-74` stdin fallback). The strip idiom is `${selection%%$'\t'*}` (first tab) per D-00d — `cut -f2` here is the field-extract precedent, but `%%` is the prescribed one-expansion form.

#### Secondary analog C — `-- <menu args>` forwarding (`bin/omarchy-menu-file:48`)

```bash
48|  omarchy-menu-select "$label" -- --width 800 --maxheight 500 "$@"
```

The only existing caller passing post-`--` menu args. Our call follows identically: `omarchy-menu-select "Select quality" "${rows[@]}" -- --default-index 1` (D-00b; `--default-index` arm at `omarchy-menu-select:54-61`, payload plumbing `:97-100`).

#### Secondary analog D — awk float math (`bin/omarchy-hyprland-monitor-scaling:68-77`)

```bash
 68|clean_scale() {
 69|  awk -v scale="$1" -v width="$2" -v height="$3" '
 70|    function gcd(a, b, t) { while (b) { t = a % b; a = b; b = t } return a }
 71|    BEGIN {
 ...
 76|      printf "%g\n", k / 120
 77|    }'
 78|}
```

The repo's float convention: `awk -v var="$arg"` injection + `BEGIN{}` + `printf` answer. `estimate_label` copies this shape; `-v` values MUST be regex-gated to `[0-9.]+`/`[0-9]+` first — awk `-v` interprets C escapes, so the regex is what makes it safe (RESEARCH Security, V5).

#### Contract sources (reference only — do NOT modify)

`bin/omarchy-menu-select:9-15` — the wire-format doc comment, verbatim:

```bash
  9|# An option may lead with an icon, as "<glyph><TAB><label>", and may trail a
 10|# subtext shown under the label, as "<glyph><TAB><label><TAB><subtext>". The
 11|# menu shows the glyph but never returns it. A plain option returns the label
 12|# alone; an option with a subtext returns "<label><TAB><subtext>", so callers
 13|# with same-named rows get the subtext back as the stable key.
 14|#
 15|# Passing "--default-index N" after "--" pre-highlights row N of the menu.
```

`shell/plugins/menu/Menu.qml` — the parsing/return/highlight side of that contract:

```bash
569|      var parts = String(root.dmenuOptions[i] || "").split("\t")
570|      var icon = parts.length > 1 ? parts.shift() : ""
571|      var label = parts.shift() || ""
572|      var detail = parts.join("\t")
...
771|      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
...
874|    dmenuDefaultIndex = MenuModel.dmenuDefaultIndex(payload, dmenuOptions.length)
878|    selectedIndex = dmenuDefaultIndex
879|    cursorActive = mode !== "input"
```

`shell/plugins/menu/MenuModel.js:497-503` — the out-of-range clamp (`index >= count → count - 1`), so `--default-index 1` on a 3-row menu is always safe.

---

### `test/shell.d/transcode-quality-test.sh` (test, e2e stub-harness) — EXTENDED

**Analog:** itself — the Phase-5 harness is extended in place (filename locked to dodge PR #6698's `transcode-test.sh` add/add). What changes: the `:54-60` menu tripwires split apart (`omarchy-menu-file` stays a tripwire; `omarchy-menu-select` becomes dual-mode), a new `ffprobe` stub, sized fixtures via `truncate -s`, and ~10 new assertion rows per RESEARCH §5d.

#### The existing harness being extended (`:17-77` — all conventions carry over)

```bash
 17|cat >"$STUB_DIR/file" <<'SH'
 18|#!/bin/bash
 19|case "${!#}" in
 20|*.mov | *.mp4 | *.mkv | *.webm) echo video/mp4 ;;
 ...
 30|for command in ffmpeg magick; do
 31|  cat >"$STUB_DIR/$command" <<'SH'
 32|#!/bin/bash
 33|{
 34|  printf '%s' "${0##*/}"
 35|  printf ' %q' "$@"
 36|  printf '\n'
 37|  printf 'out=%q\n' "${!#}"
 38|} >>"$CALLS"
 39|SH
 40|done
 ...
 52|# Tripwires: every row below passes all four positionals, so a menu invocation
 53|# means the run went interactive -- exiting 1 fails the run under set -e.
 54|for command in omarchy-menu-file omarchy-menu-select; do
 55|  cat >"$STUB_DIR/$command" <<'SH'
 56|#!/bin/bash
 57|printf 'menu invoked: %s\n' "${0##*/}" >>"$CALLS"
 58|exit 1
 59|SH
 60|done
 61|
 62|chmod +x "$STUB_DIR"/*
 ...
 68|run_transcode() {
 69|  local status=0
 70|
 71|  : >"$calls"
 72|  HOME="$TMPDIR/home" PATH="$STUB_DIR:$PATH" CALLS="$calls" \
 73|    "$ROOT/bin/omarchy-transcode" "$@" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr" || status=$?
 74|
 75|  grep '^ffmpeg' "$calls" >>"$ffmpeg_calls" 2>/dev/null || true
 76|  return "$status"
 77|}
```

Conventions the extension MUST keep:

- Quoted heredocs (`<<'SH'`), `#!/bin/bash` stub shebang, single `chmod +x "$STUB_DIR"/*`.
- State crosses process boundaries only through env-named files (`$CALLS`).
- `: >"$calls"` is the ONLY per-run reset; fixtures are row-local (`touch`/`ln -s` then `rm -f` immediately after asserting — `:133-138`, `:205-210`).
- `run_transcode` prepends `PATH="$STUB_DIR:$PATH"` per invocation; new env knobs (`FAKE_PICK`, `FAKE_DURATION`, `FAKE_AUDIO`, `FAKE_PROBE_RC`) join that prefix list the same way — per-invocation, so they can't leak between rows.

#### Analog: the answering `FAKE_PICK` stub (`test/shell.d/menu-plugin-test.sh:30-35,51-66`)

```bash
 30|# Records the rows it was offered, then answers with the pick under test.
 31|cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
 32|#!/bin/bash
 33|cat >"$FAKE_ROWS"
 34|printf '%s\n' "$FAKE_PICK"
 35|STUB
```

Phase 6's dual-mode variant (RESEARCH §5a) merges this with the existing tripwire: `${FAKE_PICK+x}` unset ⇒ exit-1 tripwire (every Phase-5 row keeps "menu invoked = failure" semantics); set ⇒ record argv + `printf '%s' "$FAKE_PICK"`. Note `printf '%s'` NOT `%s\n` — the real `omarchy-menu-select` `cat`s the selection file with no trailing newline (`:111`), and `FAKE_PICK` must carry a literal `$'\t'` to prove the strip (`FAKE_PICK=$'medium\tCRF 23 · ~23 MB'`).

#### Analog: arg-dispatched probe stub

New — no existing arg-dispatch stub is this close, but the shape is the `file` stub's `case "${!#}"` extension dispatch (`:19-23`) applied to `case " $* "` content matching (RESEARCH §5b): `*" codec_type "*` ⇒ audio probe (emit `audio` when `FAKE_AUDIO=yes`); otherwise duration probe (emit `$FAKE_DURATION`, honor `FAKE_PROBE_RC`). Both still append `ffprobe: $*` to `$CALLS` — the zero-`ffprobe:`-lines assertions (gif path, non-interactive path) depend on that record line.

#### Analog: sized sparse fixture (`test/shell.d/plymouth-set-test.sh:834-839`)

```bash
834|# Bound the descriptor read as well as the final destination. A sparse file
835|# makes the real 64 MiB + 1 byte boundary deterministic without storing a
836|# large fixture in the repository.
837|setup_run
838|cp -- "$test_tmp/logo.png" "$test_tmp/logo.png.keep"
839|truncate -s "$((64 * 1024 * 1024 + 1))" "$test_tmp/logo.png"
```

The one `truncate -s` precedent in the suite. Load-bearing here: `touch`ed fixtures are 0 bytes ⇒ `stat -c %s` = 0 ⇒ EVERY estimate exceeds the source ⇒ every row degrades to `larger than source` (RESEARCH §5c). Estimate rows need `truncate -s 40M "$TMPDIR/in.mov"` (or a separate sized fixture); the D-02 per-row-degrade pin needs a fixture sized BETWEEN tier estimates.

#### Assertion idioms (already in the file — reuse, don't invent)

- Byte-identity: `cmp -s` + `diff -u` fail detail (`:99-109`) — reuse for the "interactive pick `medium` ⇒ argv byte-identical to positional `medium`" row, against the existing `:84-89` `expected-medium-argv` fixture.
- Recorded-argv grep: `grep '^ffmpeg ' "$calls" | grep -F -- '-crf 28'` (`:117-118`); `grep -Fx "out=…"` for whole-line (`:119`). Remember `%q` escaping on recorded argv — `fps=5\,` (`:199`), and menu rows contain literal `$'\t'`.
- Negative-run shape: `if run_transcode …; then fail …; fi` + stderr grep (`:150-157`, `:248-256`).
- Absence proof: `[[ -s $calls ]]` guard (`:159-162`) — extended to "zero `menu-select:`/`ffprobe:` lines in `$CALLS`" for the non-interactive and picture rows.
- `pass`/`fail` contract from `base-test.sh:13-24` — `fail` exits the file, so assertion order must leave tmpdir consistent for the next row.

---

## Shared Patterns

### Probe guard discipline (applies to every new helper touching ffprobe/stat)

**Source:** `bin/omarchy-capture-screenrecording:261,267` + file-wide `set -euo pipefail` (`:9`)
**Apply to:** `video_duration`, `video_audio_kbps`, `select_quality` (stat call)

```bash
# Every probe: $(… 2>/dev/null || true) then regex validation, or `if` condition.
# =~ ^[0-9.]+$ for duration, =~ ^[0-9]+$ for src_bytes — regex-gating is also
# what makes awk -v injection safe (V5). Never feed probe output to (( )) —
# (( expr )) returns status 1 when the result is 0 (set -e footgun class,
# already documented at transcode-quality-test.sh's (( n += 1 )) precedent).
```

### Tab⇥subtext wire protocol (the one new cross-cutting contract)

**Source:** `bin/omarchy-menu-select:9-15` (doc), `shell/plugins/menu/Menu.qml:569-572` (parse), `:771` (return)
**Apply to:** `select_quality` row construction + strip — and ONLY there (the protocol lives in exactly one place per RESEARCH §1a)

```bash
rows+=($'\t'"$tier"$'\t'"$subtext")        # leading tab = empty glyph field (D-00c/D-04)
printf '%s' "${selection%%$'\t'*}"         # strip at FIRST tab before matching (D-00d)
```

Rules: subtext ≤~30 chars, never a literal tab (it's filter corpus + return key); all rows always carry a subtext in every state (uniform `detailRowHeight`, D-03); numeric and qualitative subtexts MAY mix per-row (D-02 degrade), subtext/no-subtext may not.

### Unquoted-var / quoted-literal `[[ ]]` + two-space indent (AGENTS.md style)

**Source:** `bin/omarchy-transcode` throughout — `[[ $type == "picture" ]]` (`:206`), `[[ $resolution == "4k" ]]` (`:134`), `[[ -n $quality ]]` (`:205`), `[[ -z $format ]]` (`:220`)
**Apply to:** all new code — `[[ $format == "mp4" ]]`, `[[ $src_bytes =~ ^[0-9]+$ ]]`, `(( $# > 0 ))` shapes only; `#!/bin/bash` shebang; `return 1` for bad values.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `bin/omarchy-transcode` — `estimate_label` sig-fig rendering | utility | transform | No existing analog rounds to N significant figures with a `~` prefix; `numfmt --to=iec` was evaluated and rejected (emits compact `108M`/`1.1G`, no sig-fig control, wrong unit shape). Use RESEARCH §1a's awk `BEGIN` body — the awk `-v`/`BEGIN`/`printf` wrapper convention still copies from `omarchy-hyprland-monitor-scaling:68-77`. |
| `test/shell.d/transcode-quality-test.sh` — arg-dispatched `ffprobe` stub | test | stub | No existing stub dispatches on argv *content*; the `file` stub dispatches on argv *shape* (`case "${!#}"`, :19-23) and is the closest in-file precedent. RESEARCH §5b supplies the body. |

## Metadata

**Analog search scope:** `bin/` (all `omarchy-menu-*` callers + ffprobe/awk call sites), `shell/plugins/menu/`, `test/shell.d/`, `agents/skills/command-metadata.md`, prior-phase artifacts `.planning/phases/04-*/` and `05-*/`
**Files scanned:** `bin/omarchy-transcode` (250 lines, full), `bin/omarchy-menu-select` (114, full), `bin/omarchy-menu-plugin` (46, full), `bin/omarchy-menu-file` (:40-48), `bin/omarchy-capture-screenrecording` (:245-284), `bin/omarchy-hyprland-monitor-scaling` (:65-104), `shell/plugins/menu/Menu.qml` (:560-604, :760-789, :860-889), `shell/plugins/menu/MenuModel.js` (:488-507), `test/shell.d/transcode-quality-test.sh` (313, full), `test/shell.d/base-test.sh` (127, full), `test/shell.d/menu-select-test.sh` (121, full), `test/shell.d/menu-plugin-test.sh` (:14-68), `test/shell.d/plymouth-set-test.sh` (:833-844), `agents/skills/command-metadata.md`, `05-PATTERNS.md`, `05-01-PLAN.md` — all analog paths verified git-tracked via `git ls-files`
**Pattern extraction date:** 2026-09-15
