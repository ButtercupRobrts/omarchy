# Phase 5 Research: Non-interactive quality in `omarchy-transcode`

**Researched:** 2026-09-15
**Requirements:** QUAL-02, QUAL-03, SAFE-01
**Confidence:** HIGH — the full 207-line target file, test harness, router, and docs were read end-to-end; every edit site below is verified against current source.
**Scope:** HOW to implement. WHAT is locked in 05-CONTEXT.md (D-00a..d, D-01..D-04) and `.planning/research/` — do not re-litigate tier values, the dedupe policy, or strict validation.

---

## 1. Exact edit surface in `bin/omarchy-transcode`

Current file anatomy (verified): metadata header `:3-7`, `usage()` `:11-30`, `media_type()` `:32-44`, `output_path()` `:46-57`, `transcode_picture()` `:59-89`, `transcode_video()` `:91-121`, `copy_to_clipboard()` `:123-129`, `main()` `:131-205`, `main "$@"` `:207`.

### 1a. `main()` — locals, positional parse, validation block

**Locals (:132-133):** add `quality` to the second local line:

```bash
local input="" format="" resolution="" search_path=""
local type output quality positional=()
```

**Positional parse (:163-165):** add after `resolution=`:

```bash
quality="${positional[3]:-}"
```

`${positional[3]:-}` is required — under `set -u`, `${positional[3]}` on a short array aborts; the `:-` form is exactly what the three existing lines do.

**Validation block — insert between `:175` (`type=$(media_type "$input")`) and `:177` (format prompt):**

Recommended shape — a single `[[ -n $quality ]]`-gated block that keeps the empty string meaning "caller didn't specify" (Phase 6's prompt triggers on `-z $quality`; normalizing to `medium` here would erase that signal and make Phase 6's diff bigger):

```bash
if [[ -n $quality ]]; then
  if [[ $type == "picture" ]]; then
    echo "Invalid argument: quality applies to videos only" >&2   # wording is discretion — keep "Invalid ..." style
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

Why here and not inside `transcode_video()`:

- **QUAL-03 needs `type`.** `transcode_picture()` never receives a quality arg, so the picture rejection can only live in `main()` after `media_type` resolves at `:175`.
- **SAFE-01/D-01's no-orphan rule.** The "Transcoding video…" notification is sent at `:196` *before* `transcode_video` runs. Validation inside `transcode_video`'s `case` would print the error after the start notification — an orphaned "Transcoding…" with no completion, the exact failure shape D-01 exists to prevent. Validating in `main()` makes bad quality a pre-notification failure.
- **Prompt ordering is unaffected.** A 4th positional is only reachable when slots 0–2 are also given (positionals collect in order at `:156-158`), so the format/resolution prompts at `:177-191` are already skipped on every path that can carry a quality value. Inserting validation before `:177` never changes prompt order.

`return 1` (not `exit 1`) — matches the file's idiom (`return 1`/`:139,153,172,173`, `return 2` for usage errors); `main "$@"` at `:207` propagates it as the script's exit status.

### 1b. `transcode_video()` (:91-121) — tier mapping

Signature gains a 5th param. Recommended structure per CONTEXT `code_context` ("`case` → variable mapping before the format dispatch"):

```bash
transcode_video() {
  local input="$1" format="$2" resolution="$3" output="$4"
  local quality="${5:-medium}"          # empty positional = medium, byte-identical by construction
  local scale crf_x264 crf_x265 gif_fps

  case "$resolution" in ... esac        # unchanged :95-103

  case "$quality" in
  high)   crf_x264=18; crf_x265=20; gif_fps=15 ;;
  medium) crf_x264=23; crf_x265=24; gif_fps=10 ;;   # locked values = today's literals
  low)    crf_x264=28; crf_x265=28; gif_fps=5  ;;
  *)
    echo "Invalid video quality: $quality (expected high, medium, or low)" >&2
    return 1
    ;;
  esac

  case "$format" in
  mp4)
    if [[ $resolution == "4k" ]]; then
      ffmpeg -i "$input" -vf "$scale" -c:v libx265 -preset slow -crf "$crf_x265" -c:a aac -b:a 192k -movflags +faststart "$output"
    else
      ffmpeg -i "$input" -vf "$scale" -c:v libx264 -preset fast -crf "$crf_x264" -c:a aac -b:a 192k -movflags +faststart "$output"
    fi
    ;;
  gif)
    ffmpeg -i "$input" -vf "fps=$gif_fps,$scale:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$output"
    ;;
  ...
```

Notes for the planner:

- **Byte-identical medium argv, not byte-identical source.** `-crf "$crf_x264"` with `crf_x264=23` produces the literal argv `-crf 23`; "byte-identical" (D-00b) is a property of the generated command line, which the stub-argv test diffs. Keeping `23`/`24`/`10` as the `medium` case values keeps the numbers textually present for review.
- **Two CRF variables, not one.** The codec is chosen by `resolution` (4k→x265, else x264) *inside* the format arm, after the quality case — so the quality case must map all three knobs at once. Do not key the CRF case on codec.
- **Keep the `*)` arm in `transcode_video`** even though `main()` validates earlier — it matches the file's validate-in-`case` idiom (`:99-102`, `:116-119`), protects anyone who sources the file and calls the function directly (the `monitor-scaling-test.sh` harness does exactly this with its target), and is unreachable-cheap.
- Alternative (rejected): per-tier literal ffmpeg lines (`medium) ffmpeg ... -crf 23 ...`). Preserves literals verbatim but triples the mp4 block to 6 near-identical lines; the variable mapping is a smaller, clearer diff.
- gif interpolation `"fps=$gif_fps,..."` — the filter string already interpolates `$scale` (`:114`), so this is in-style. Medium yields `fps=10` verbatim.

### 1c. `output_path()` (:46-57) — quality suffix + dedupe

Gains a 4th param and the collision loop:

```bash
output_path() {
  local input="$1" format="$2" resolution="$3" quality="${4:-}"
  local dir base stem name candidate n

  dir=$(dirname -- "$input")
  base=$(basename -- "$input")
  stem="${base%.*}"

  name="$stem-$resolution"
  if [[ $quality != "medium" && -n $quality ]]; then
    name="$name-$quality"
  fi

  candidate="$dir/$name.$format"
  n=2
  while [[ -e $candidate || -L $candidate ]]; do
    candidate="$dir/$name-$n.$format"
    (( n += 1 ))
  done

  printf '%s' "$candidate"
}
```

Decisions embedded in this shape:

- **Dedupe counter goes after the full computed name**, per D-01's example `stem-1080p-2.mp4` → low tier dedupes to `stem-1080p-low-2.mp4`, medium to `stem-1080p-2.mp4`. No stem re-parsing.
- **`[[ -e || -L ]]`, not just `-e`:** `-e` is false for a dangling symlink; without `-L` the loop would hand ffmpeg a symlink path that writes through to the target — a silent clobber of an unrelated file. See threat model.
- **`(( n += 1 ))` not `(( n++ ))`:** under `set -e`, `(( expr ))` returns status 1 when the expression evaluates to 0 — `n` starts at 2 so `(( n++ ))` never actually hits 0 here, but `n += 1` is immune to the footgun entirely (PITFALLS documents this trap).
- **Loop cannot run forever in practice:** each iteration probes a fresh name; it exits at the first gap. Residual TOCTOU (a file materializing between the check and ffmpeg's open) degrades to *today's* behavior — ffmpeg prompts/refuses — never worse.
- **Dedupe applies to pictures too.** `output_path` is shared; the `[[ $type == "video" ]]` branch isn't entered until `:195`. This intentionally upgrades the picture path from magick's silent-overwrite to dedupe — the PITFALLS-documented inconsistency (pitfall 4). The planner should call this out as deliberate in the plan and UAT notes; it is the same "deliberate collision policy" SAFE-01 requires, applied uniformly.
- **Timing is free:** `output=$(output_path ...)` at `:193` already runs before the `:195-204` notification block, so putting the loop inside `output_path` satisfies "resolved BEFORE the Transcoding notification" with zero reordering.

### 1d. Call sites in `main()`

- `:193` → `output=$(output_path "$input" "$format" "$resolution" "$quality")`
- `:197` → `transcode_video "$input" "$format" "$resolution" "$output" "$quality"` (quality as 5th arg, after output — appending keeps the existing positional shape)
- `:201` `transcode_picture` — **unchanged signature**; pictures never receive quality (QUAL-03).

### 1e. `usage()` (:11-30) and metadata (:6-7)

- `:6` → `# omarchy:args=[--path path] [input] [format] [resolution] [quality]` — all bracketed, so `command_requires_args` (`bin/omarchy:361-370`, strips every `[...]` span) still treats the command as arg-optional; bare `omarchy transcode` keeps exec'ing into the interactive picker.
- `:7` → append `|omarchy transcode ~/Videos/demo.mov mp4 1080p low` — the `examples` separator is a bare `|` (see `agents/skills/command-metadata.md`), no surrounding spaces, matching the existing line.
- `usage()` line 14 → `[--path path] [input] [format] [resolution] [quality]`; add a block after Resolutions:

```
Qualities:
  Videos: high, medium, low (default: medium)
```

Do not add a Qualities row for pictures — QUAL-03 forbids it.

---

## 2. Test strategy — `test/shell.d/transcode-quality-test.sh`

**Filename locked:** `transcode-quality-test.sh` (CONTEXT D-05/architecture §upstream) — upstream PR #6698 adds `test/shell.d/transcode-test.sh`; a distinct name avoids an add/add conflict entirely. `test/shell` auto-discovers `*-test.sh`.

### Stub binaries (PATH-shadowing, per `menu-plugin-test.sh`/`monitor-scaling-test.sh` precedent)

Required stubs in `$TMPDIR/stub` (or `fake_bin`), `chmod +x`:

| Stub | Why required | Behavior |
|------|--------------|----------|
| `file` | **Mandatory** — real `file -b --mime-type` on an empty fixture returns `inode/x-empty` → `media_type` fails "Unsupported file type" (verified). Determinism too. | `case "${!#}" in *.mov/*.mp4/*.mkv/*.webm) echo video/mp4 ;; *.png/*.heic/*.jpg) echo image/png ;; *) echo application/octet-stream ;; esac` |
| `ffmpeg` | Record argv, never encode | Append one line to `$CALLS`; `touch -- "${!#}"` so a second run can dedupe and `realpath` sees a real file |
| `magick` | Same for pictures | Same recording + `touch` |
| `wl-copy` | `:128` pipes to it; may be absent in test env | `cat >/dev/null` (consumes the URI line) |
| `omarchy-notification-send` | `:196,199,203` call it; real one needs a running desktop | Append `notification: $*` to `$CALLS` |
| `omarchy-menu-file`, `omarchy-menu-select` | Only reached when positionals are missing — tests always pass all 4, so these are **tripwires** | `echo "menu invoked: $0" >>"$CALLS"; exit 1` — proves the non-interactive path stays non-interactive |

`realpath`, `dirname`, `basename`, `touch` — real coreutils, no stubs.

**Recording argv without ambiguity:** join with `%q` so spaced filenames stay one-logical-line and comparisons stay exact:

```bash
cat >"$STUB_DIR/ffmpeg" <<'SH'
#!/bin/bash
{
  printf 'ffmpeg'
  printf ' %q' "$@"
  printf '\n'
  printf 'out=%s\n' "${!#}"
} >>"$CALLS"
touch -- "${!#}"
SH
```

The separate `out=` line gives tests a direct handle on the computed output path (dedupe assertions) without parsing the flag list.

### Run wrapper

```bash
run_transcode() {
  : >"$calls"
  HOME="$TMPDIR/home" PATH="$STUB_DIR:$PATH" CALLS="$calls" \
    "$ROOT/bin/omarchy-transcode" "$@" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr"
}
```

All fixtures are `touch`ed empty files in `$TMPDIR` — safe because `file` is stubbed.

### Assertion matrix (maps to success criteria)

| # | Invocation | Assert |
|---|-----------|--------|
| Byte-identical medium | `in.mov mp4 1080p medium` **and** `in.mov mp4 1080p` | Recorded argv lines identical to each other, and equal to a literal expected line built the same way: `ffmpeg -i $in -vf scale=-2:1080 -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 192k -movflags +faststart $out`; `out=…/in-1080p.mp4`. **Strongest form:** `diff` the recorded argv line against a heredoc/`printf %q`-built expected line — that is the literal byte-identical check |
| high/low tiers | `in.mov mp4 1080p high` / `low` | `-crf 18` / `-crf 28`; `out=…/in-1080p-high.mp4` / `-low.mp4` |
| x265 tiers | `in.mov mp4 4k low` (+ `high`) | `libx265 -preset slow`, `-crf 28` / `20`; 4k medium → `-crf 24` pins the second locked value |
| gif tiers | `in.mov gif 720p low` / `high` | filter contains `fps=5` / `fps=15`; medium gif → `fps=10` |
| QUAL-03 picture reject | `img.png jpg medium high` | exit ≠ 0; stderr matches `Invalid`; `$CALLS` empty (no ffmpeg, no magick, **no notification** — proves pre-notification rejection); magick never touched |
| Picture untouched | `img.png jpg low` | magick called with `-resize 1080x\>`, output `img-low.jpg` — pins the slot-3 vocabulary (low = resolution) is unchanged |
| Invalid quality | `in.mov mp4 1080p bogus` | exit ≠ 0, stderr `Invalid video quality: bogus`, no ffmpeg/notification calls |
| Whitespace/empty | `… 1080p ""` → medium-equivalent argv + unsuffixed name; `… 1080p " ultra "` → invalid error | pins empty=omitted, whitespace≠valid |
| SAFE-01 dedupe | `touch in-1080p.mp4` then `in.mov mp4 1080p` | `out=…/in-1080p-2.mp4`; pre-create `-2` as well → `-3` |
| Dedupe + suffix | `touch in-1080p-low.mp4` then `in.mov mp4 1080p low` | `out=…/in-1080p-low-2.mp4` |
| Dedupe + pictures | `touch img-medium.jpg` then `img.png jpg medium` | `out=…/img-medium-2.jpg` (pins the uniform policy) |
| Notification ordering | any video run | `grep -n` line numbers in `$CALLS`: `Transcoding` notification precedes `ffmpeg` line; ffmpeg sees the *deduped* name |
| `--` passthrough | `-- in.mov mp4 1080p low` | same as bare — covers `--` handling |
| Quoting | input `my clip.mov` | `%q` log shows one intact argv element for input and `my\ clip-1080p.mp4`-style output |
| Help | `--help` | usage text contains `[quality]` and `high, medium, low` |

Medium-byte-identity is best asserted two ways: (a) the `medium` and omitted runs produce identical recorded lines; (b) the recorded line diffs clean against the known-literal expected line. (a) alone can't catch a shared regression; (b) alone can't catch the two paths diverging.

---

## 3. Interaction details

- **`--path` interplay:** none. `--path` is consumed in the `while` loop (`:137-141`) wherever it appears before `--`; positionals collect independently. `--path` + full positionals works (search_path just goes unused since `:168` is skipped).
- **`--` passthrough:** the `--` arm (`:146-149`) shifts and bulk-appends `"$@"` to `positional` — a 4th positional after `--` lands in `positional[3]` automatically; also the way to pass `-`-leading filenames. No code change; covered by one test row.
- **`set -euo pipefail`:**
  - `output=$(output_path …)` — a `return 1` inside would abort the script via `set -e`; fine (stderr already printed).
  - `(( n += 1 ))` — safe; `(( n++ ))` would also be safe here (n≥2) but `+=` avoids the status-1-on-zero footgun class entirely.
  - The dedupe `while [[ … ]]` loop is immune — `[[ ]]` failing just exits the loop.
  - No new probes/subshells are introduced — Phase 5 adds zero `set -e` hazard beyond the counter.
- **Validation order vs `media_type`/format:** `media_type` still runs unconditionally at `:175` before anything else (a non-media file fails first — same as today). Format/resolution validation stays inside the `transcode_*` case arms at encode time — meaning `omarchy transcode in.mov avi 1080p low` still sends the start notification then fails "Invalid video format" (pre-existing orphan, unchanged by this phase — flag in plan; do NOT silently "fix" it, that's a separate behavior change).
- **Stem ending in `-1080p`:** input `demo-1080p.mov` → today produces `demo-1080p-1080p.mp4`; unchanged. Dedupe never parses the stem — counter appends to the *whole* computed name, so `demo-1080p-1080p-2.mp4`. The only new ambiguity shape is suffix-vs-counter (`-low` vs `-2`), which can't collide because the counter position is distinct.
- **Empty/whitespace quality:** `""` → `-z` → treated as omitted (medium) for video; silently accepted for pictures too (consistent — "not specified" isn't "specified wrongly"). `" "`/any other non-empty non-tier → `Invalid video quality`. Recommend pinning both in tests.
- **5th+ positionals:** `positional[4]` is silently ignored today and stays ignored — pre-existing leniency, out of scope; note it so the planner doesn't accidentally "fix" it.
- **Nautilus path:** `default/nautilus-python/extensions/transcode.py:19-34` invokes bare `omarchy-transcode <path>` inside `omarchy-launch-floating-terminal-with-presentation` — untouched; its interactive flow gains the quality prompt only in Phase 6.
- **PR #6698 conflict surface (from ARCHITECTURE):** `main()` tail `:193-204`, `output_path` signature, and the function-neighborhood around `:122` all conflict textually when the PR lands. Keep new code minimal in `main()`'s tail and put the quality `case` inside `transcode_video` (which the PR doesn't restructure) to shrink the window.
- **`realpath` behavior (verified):** GNU realpath exits 0 when only the final component is missing — `uri=` at `:127` won't die on a missing output — but stubs should still `touch` the output so dedupe-on-second-run behaves like the real encode.

---

## 4. Validation Architecture

Nyquist gate — per requirement and per likely task. The whole phase is automatable via the stub harness; the only manual items are a real-encode smoke check and the keybind/detached-launch sanity check.

### QUAL-02 — optional 4th positional; medium/omitted byte-identical

- **Automated (stub e2e):** `run_transcode in.mov mp4 1080p medium` and `run_transcode in.mov mp4 1080p` → recorded ffmpeg argv lines identical to each other AND `diff`-equal to the literal expected argv (`-preset fast -crf 23 -c:a aac -b:a 192k -movflags +faststart`, output `in-1080p.mp4`). Tier mapping rows: `high`→`-crf 18`/`in-1080p-high.mp4`, `low`→`-crf 28`/`in-1080p-low.mp4`, `4k`→x265 `-preset slow` CRF 20/24/28, `gif`→`fps=15/10/5`. `--`-passthrough and spaced-filename rows cover the parser edges.
- **Manual:** optional real-encode smoke (`omarchy transcode <clip> mp4 720p high` produces a playable file) — rationale: stubbing proves argv, not encoder acceptance; one dogfood run covers it. Not blocking.

### QUAL-03 — pictures reject the 4th positional

- **Automated:** `run_transcode img.png jpg medium high` → non-zero exit, `Invalid`-style stderr, empty `$CALLS` (no magick, no ffmpeg, **no notification** — proves rejection precedes the notification boundary). Positive control: `img.png jpg low` still invokes magick with `1080x>` resize and unsuffixed-name output.
- **Manual:** none — fully covered by exit code + call-log assertions.

### SAFE-01 — suffix only for non-default; non-interactive-safe collisions

- **Automated:** pre-create `in-1080p.mp4` → run → `out=in-1080p-2.mp4` recorded; pre-create through `-2` → `-3`; same with `-low` suffix → `in-1080p-low-2.mp4`; picture dedupe row pins uniform policy. Ordering: `Transcoding` notification line precedes the ffmpeg line in `$CALLS`, and ffmpeg's output arg is the deduped name (dedupe provably resolved before notification). Symlink row: `ln -s /nonexistent in-1080p.mp4` → still dedupes to `-2` (pins the `-L` check).
- **Manual:** launch a second identical transcode via the actual keybind/menu trigger once during UAT — rationale: the stub proves the path is collision-free before ffmpeg runs, but "no tty, no hang" is a property of the real launch environment (`Util.execDetached`); one manual re-run confirms no overwrite prompt appears. Low cost, high signal.

### Per-task validation

| Likely task | Automated check | Manual check |
|---|---|---|
| Edit `bin/omarchy-transcode` (parse/validate/tiers/suffix/dedupe) | `bash test/shell.d/transcode-quality-test.sh` green (full matrix above); `bash -n bin/omarchy-transcode` | real-encode smoke (optional) |
| Add `test/shell.d/transcode-quality-test.sh` | `./test/shell` green — the new file runs under the auto-discovered suite; no regressions in the 7 known-environmental-failure baseline (STATE.md: they reproduce at base commit — don't chase them) | — |
| Docs/metadata (`usage()`, `# omarchy:args=/examples=`, `capture.md`, `manual/12`) | `./test/cli` green (metadata lint ~`:606-612`: summary present, args non-empty, no removed fields); `omarchy transcode --help` shows `[quality]` | — |
| Collision safety on real launch path | (dedupe unit rows above) | keybind re-run UAT — only item that needs a live session |

---

## 5. <threat_model>

**Trust surface:** caller-controlled argv → `ffmpeg`/`magick` command lines → filesystem writes next to the input file. Inputs are (a) positional args, (b) the input filename itself, (c) the `file` MIME verdict on the input.

- **Quality arg → filename:** the whitelist (`high|medium|low`) is enforced in `main()` *before* `output_path` sees the value — only two literal strings (`high`, `low`) can ever reach the filename; `medium`/empty are excluded by the suffix rule. No path traversal, no flag injection (`-`-leading quality can't survive the `case`; and `--`-leading argv never reaches positionals unless after `--`, where it still can't match the whitelist).
- **Dedupe loop safety:** unbounded counter is fine — each iteration tests a distinct name and terminates at the first gap; no symlink-following hazard *if* `[[ -e || -L ]]` is used (plain `-e` misses dangling symlinks → ffmpeg would write through the link to an arbitrary target — the one real data-loss edge in this design). TOCTOU residual: a file appearing between check and write degrades to today's prompt/refuse behavior, never to silent clobber.
- **Injection surface:** all expansions are already quoted (`"$input"`, `"$output"`, `"$scale"`); `stem` comes from `basename --`/`%.*` so `/` cannot survive into the name; spaces/metachars in filenames are safe argv-wise (test pins this via `%q` recording). Newline-in-filename breaks nothing in the script but makes the one-line-per-call test log ambiguous — use `%q` there. Filenames beginning with `-` are guarded by `basename --`/`dirname --` and by ffmpeg's `-i` consuming the next token as a value.
- **stdin/interactivity:** dedupe removes the only interactive surface (ffmpeg's "Overwrite? [y/N]" stdin read) — after this phase ffmpeg never sees a prompt on any launch path, so detached/keybind launches cannot hang or silently die at the overwrite check. (ffmpeg still reads stdin for `q`-style commands mid-encode — pre-existing, harmless on EOF; no `-nostdin` needed.)
- **`file` output:** attacker-craftable MIME strings only flow into glob matching (`image/*`) and an error echo — no eval, no arithmetic. Safe.
- **`format` value → filename extension:** a `--`-passthrough like `a/b` becomes `stem-1080p.a/b` — `-e` test is false, ffmpeg fails on open. Pre-existing, quoted, no worse today; noted for completeness.

---

## 6. Docs, metadata, conventions inventory

**Files that must change in the same commit (atomic-change convention):**

- `bin/omarchy-transcode:6-7` — `# omarchy:args=` gains `[quality]`; `# omarchy:examples=` gains a `|…mp4 1080p low` example (bare `|` separator)
- `bin/omarchy-transcode:11-30` — `usage()` usage line + `Qualities:` block
- `default/agents/skills/omarchy/capture.md:59` — signature line `omarchy transcode <input> [format] [resolution]` → add `[quality]`
- `manual/12-screenshots-recording.md:72-74` — the paragraph documents `demo-1080p.mp4` naming; add one sentence on the quality arg and `-high`/`-low` suffix (keep it user-voiced, no CRF jargon)

**Not touched:** `manual/41-branding.md` (transcode-ascii only), `bin/omarchy` `GROUP_DESCRIPTIONS[transcode]` (unchanged), `transcode.py`, `omarchy-menu.jsonc:69`, `utilities.lua:87` (all invoke bare/no-arg — untouched by design), `docs/menu.md` (Phase 4 already covered `defaultIndex`).

**test/cli constraints (verified `:606-612`):** header must keep `# omarchy:summary=`; `# omarchy:args=` must not be *empty* (ours isn't); no `legacy/usage/visibility/mutates/interactive/requires-sudo=false` keys. Adding `[quality]` is lint-neutral. `command_requires_args` (`bin/omarchy:361-370`) strips all `[...]` spans → still arg-optional → bare `omarchy transcode` still execs the script.

**AGENTS.md style pins:** `[[ ]]`/`(( ))` (never `-lt` in `[[ ]]`), unquoted vars inside `[[ ]]`, quoted `"$var"` elsewhere, two-space indent, `#!/bin/bash`, `return 1`/`return 2` idiom, atomic commit (script + test + docs together is one coherent change), full lines in markdown (no hard wrap).

**Known-baseline caveat for the runner:** `./test/shell` has 7 pre-existing environmental failures (STATE.md: bar-icon-geometry, config, locate, runtime-smoke, screenshot-sanity, snapper, unowned-system-paths — all reproduce at base commit). The new test is pure-stub — no compositor, no `require_compositor` — and must not be charged against that baseline.

---

## 7. Suggested task decomposition

1. **Script change** — `bin/omarchy-transcode`: locals+positional, validation block after `:175`, `output_path` suffix+dedupe, `transcode_video` quality case + signature, call sites, `usage()` + metadata. (One diff, one commit-unit with 2–3.)
2. **Test** — `test/shell.d/transcode-quality-test.sh` per §2.
3. **Docs** — `capture.md`, `manual/12`, verify `./test/cli`.

## 8. Open micro-decisions for the planner (inside discretion bounds)

- **Picture-rejection wording** — suggest `Invalid argument: quality applies to videos only` or `Quality does not apply to pictures`; CONTEXT leaves wording to discretion, `Invalid …` style required.
- **Empty-string quality** — recommended: treat `""` as omitted (medium), not an error. Pin in test either way.
- **`*)` arm in `transcode_video`'s quality case** — recommended keep (file idiom + sourced-function safety), though `main()` already validates.
- **Dedupe counter start** — `-2` locked by D-01 example; `-e || -L` recommended over plain `-e`.

## Sources

- `bin/omarchy-transcode` (207 lines, read in full — all line refs verified)
- `bin/omarchy` (`command_requires_args` :361-370, dispatch :949-1050), `bin/omarchy-menu-file` (`"$@"` forwarding :48)
- `test/shell.d/base-test.sh`, `menu-plugin-test.sh`, `plugin-enable-test.sh`, `menu-select-test.sh`, `monitor-scaling-test.sh` (stub/state-through-filesystem conventions)
- `test/cli` metadata lint `:598-612`; `test/shell` runner (auto-discovers `*-test.sh`, continues past failures)
- `agents/skills/command-metadata.md`; `AGENTS.md` style rules
- `manual/12-screenshots-recording.md:72-74`, `default/agents/skills/omarchy/capture.md:59`, `default/nautilus-python/extensions/transcode.py:19-34`
- `.planning/research/{STACK,PITFALLS,ARCHITECTURE,FEATURES,SUMMARY}.md`, `05-CONTEXT.md`, `05-DISCUSSION-LOG.md`, `ROADMAP.md` Phase 5 success criteria
- Verified empirically this session: `file -b --mime-type` on empty file → `inode/x-empty`; `realpath` exit 0 on missing final component

---
*Research for: 05-non-interactive-quality-in-omarchy-transcode*
