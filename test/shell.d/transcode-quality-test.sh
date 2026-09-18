#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"
calls="$TMPDIR/calls"
ffmpeg_calls="$TMPDIR/ffmpeg-calls"

# `file` is stubbed because a real MIME probe on an empty fixture reports
# inode/x-empty and media_type would reject it; the extension decides here.
cat >"$STUB_DIR/file" <<'SH'
#!/bin/bash
case "${!#}" in
*.mov | *.mp4 | *.mkv | *.webm) echo video/mp4 ;;
*.png | *.heic | *.jpg) echo image/png ;;
*) echo application/octet-stream ;;
esac
SH

# The encoders record their argv -- %q-joined so spaced filenames stay one
# logical line -- plus the output path on its own out= line. They create the
# output file only under FAKE_OUT_BYTES (truncate -s the last positional, the
# output path for both encoder argv shapes): realpath tolerates a missing
# final component, and an unconditional touch would leak files into $TMPDIR
# and make dedupe rows self-collide -- rows that set the knob own the file
# and rm -f it after asserting. FAKE_ENCODE_RC exits the stub non-zero to
# prove the done notification never fires on encode failure.
for command in ffmpeg magick; do
  cat >"$STUB_DIR/$command" <<'SH'
#!/bin/bash
{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
} >>"$CALLS"
case " $* " in
*" -pass 1 "*)
  # Two-pass stats pass: the last positional is /dev/null on the null muxer,
  # never an output -- record argv only. Synthesize the passlog artifacts
  # (-0.log/.mbtree) from the -passlogfile arg so the script's passdir
  # cleanup assertions have real files to count.
  prev=""
  for arg in "$@"; do
    if [[ $prev == "-passlogfile" ]]; then
      touch "$arg-0.log" "$arg-0.log.mbtree"
      break
    fi
    prev="$arg"
  done
  exit "${FAKE_PASS1_RC:-${FAKE_ENCODE_RC:-0}}"
  ;;
*" -pass 2 "*)
  # A real encode pass: records out= and sizes the output. When a run makes
  # more than one pass-2 call (the overshoot retry), the first consumes
  # FAKE_OUT_BYTES and later ones FAKE_OUT_BYTES2; FAKE_PASS2_RC is a
  # space-separated per-invocation RC list ("0 1" = first ok, retry dies)
  # falling back to its last word, then FAKE_ENCODE_RC. The invocation
  # number is the count of pass-2 lines in this run's CALLS, which resets
  # per run with the log itself. A pass-2 call also requires the pass-1
  # artifacts at its own -passlogfile -- a missing flag or a wrong dir exits
  # 90, so argv can never claim a two-pass encode the logs do not back.
  printf 'out=%q\n' "${!#}" >>"$CALLS"
  prev=""
  passlog=""
  for arg in "$@"; do
    if [[ $prev == "-passlogfile" ]]; then
      passlog="$arg"
      break
    fi
    prev="$arg"
  done
  [[ -n $passlog && -f ${passlog}-0.log ]] || exit 90
  n=$(grep -c ' -pass 2 ' "$CALLS")
  size="${FAKE_OUT_BYTES:-}"
  if (( n > 1 )) && [[ -n ${FAKE_OUT_BYTES2:-} ]]; then
    size="$FAKE_OUT_BYTES2"
  fi
  if [[ -n $size ]]; then
    truncate -s "$size" "${!#}"
  fi
  if [[ -n ${FAKE_PASS2_RC:-} ]]; then
    read -ra rcs <<<"$FAKE_PASS2_RC"
    exit "${rcs[$(( n - 1 ))]:-${rcs[-1]}}"
  fi
  exit "${FAKE_ENCODE_RC:-0}"
  ;;
*)
  printf 'out=%q\n' "${!#}" >>"$CALLS"
  if [[ -n ${FAKE_OUT_BYTES:-} ]]; then
    truncate -s "$FAKE_OUT_BYTES" "${!#}"
  fi
  exit "${FAKE_ENCODE_RC:-0}"
  ;;
esac
SH
done

cat >"$STUB_DIR/wl-copy" <<'SH'
#!/bin/bash
cat >/dev/null
SH

cat >"$STUB_DIR/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$CALLS"
case " $* " in
*" -p "* | *" --print-id "*) echo 7 ;;
esac
SH

# omarchy-menu-file stays a pure tripwire: no row below goes through the file
# pick, so an invocation means the run went interactive where it must not --
# exiting 1 fails the run under set -e.
for command in omarchy-menu-file; do
  cat >"$STUB_DIR/$command" <<'SH'
#!/bin/bash
printf 'menu invoked: %s\n' "${0##*/}" >>"$CALLS"
exit 1
SH
done

# omarchy-menu-select is dual-mode. With FAKE_PICK unset it keeps the tripwire
# semantics for the rows that must never go interactive (all-four-positional
# video runs, picture rows, qualities rejected pre-prompt). With FAKE_PICK set
# it records the argv it was offered and answers with that pick -- rows that
# omit the quality positional legitimately fire the quality menu and must set
# it. An empty FAKE_PICK is Esc, matching the real script's exit-1 on an empty
# selection; printf '%s' not '%s\n' because the real script cats the selection
# file with no trailing newline.
cat >"$STUB_DIR/omarchy-menu-select" <<'SH'
#!/bin/bash
printf 'menu-select: %s\n' "$*" >>"$CALLS"
if [[ -z ${FAKE_PICK+x} ]]; then
  exit 1
fi
[[ -n $FAKE_PICK ]] || exit 1
printf '%s' "$FAKE_PICK"
SH

# omarchy-menu-input mirrors the real binary's three states: a set FAKE_INPUT
# prints it and exits 0 (submit); a set-but-empty FAKE_INPUT exits 0 with
# empty stdout (empty submit -- NOT a cancel, the real binary writes "\n" so
# -s is true); unset exits 1 (Esc, and the tripwire for runs that must never
# reach the input prompt). Per-invocation knobs (FAKE_INPUT, FAKE_INPUT2, …)
# feed the re-prompt loop -- same convention as FAKE_OUT_BYTES/FAKE_OUT_BYTES2,
# with the invocation number counted off the just-logged menu-input: line
# exactly like the pass-2 counter above. The log line is written before the
# decision, so an unexpected call still leaves evidence; %s not %q so literal
# tabs in argv stay greppable.
cat >"$STUB_DIR/omarchy-menu-input" <<'SH'
#!/bin/bash
printf 'menu-input: %s\n' "$*" >>"$CALLS"
n=$(grep -c '^menu-input:' "$CALLS")
var=FAKE_INPUT
(( n > 1 )) && var="FAKE_INPUT$n"
[[ -z ${!var+x} ]] && exit 1
printf '%s' "${!var}"
SH

# ffprobe dispatches on argv: the audio-presence probe carries
# `stream=codec_type` glued to `-show_entries`, so ` stream=codec_type ` in
# " $* " selects that arm -- a bare ` codec_type ` glob never matches the real
# argv. That arm exits 0 with empty output on a successful no-stream probe,
# which must stay distinguishable from probe failure or the conservative-192
# rule cannot be exercised. Any other call is the duration probe: FAKE_DURATION
# unset fails hard with no output; FAKE_PROBE_RC overrides the exit status.
cat >"$STUB_DIR/ffprobe" <<'SH'
#!/bin/bash
printf 'ffprobe: %s\n' "$*" >>"$CALLS"
case " $* " in
*" stream=codec_type "*)
  if [[ ${FAKE_AUDIO:-yes} == "yes" ]]; then
    echo audio
  fi
  exit 0
  ;;
*)
  if [[ -n ${FAKE_DURATION+x} ]]; then
    printf '%s\n' "$FAKE_DURATION"
    exit "${FAKE_PROBE_RC:-0}"
  fi
  exit 1
  ;;
esac
SH

chmod +x "$STUB_DIR"/*

# Runs the real script against the stubs. Truncating $calls is the only
# per-run reset -- stubs write outputs only under FAKE_OUT_BYTES, so any row
# that pre-creates a collision fixture (or sets the knob) owns those files and
# must rm -f them right after asserting. ffmpeg argv lines also accumulate in
# $ffmpeg_calls for the no-overwrite-flag pin.
run_transcode() {
  local status=0

  : >"$calls"
  HOME="$TMPDIR/home" PATH="$STUB_DIR:$PATH" CALLS="$calls" TMPDIR="$TMPDIR" \
    "$ROOT/bin/omarchy-transcode" "$@" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr" || status=$?

  grep '^ffmpeg' "$calls" >>"$ffmpeg_calls" 2>/dev/null || true
  return "$status"
}

# A sized fixture: stat reports 120 MiB, above the largest pinned estimate
# (~110 MB at dur=157/1080p/high), so estimate rows render numbers instead of
# degrading to larger-than-source. Sparse, so it costs no real blocks.
truncate -s 120M "$TMPDIR/in.mov"
touch "$TMPDIR/img.png"

# The explicit `medium` and the omitted quality must generate byte-identical
# ffmpeg argv -- and that line must equal the literal known-good invocation,
# so neither direction can hide a shared regression.
{
  printf 'ffmpeg'
  printf ' %q' -i "$TMPDIR/in.mov" -vf scale=-2:1080 -c:v libx264 -preset fast \
    -crf 23 -c:a aac -b:a 192k -movflags +faststart "$TMPDIR/in-1080p.mp4"
  printf '\n'
} >"$TMPDIR/expected-medium-argv"

run_transcode "$TMPDIR/in.mov" mp4 1080p medium
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-explicit-medium" ||
  fail "explicit medium records an ffmpeg line" "$(cat "$calls")"

FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/in.mov" mp4 1080p
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-omitted-medium" ||
  fail "omitted quality records an ffmpeg line" "$(cat "$calls")"

if ! cmp -s "$TMPDIR/argv-explicit-medium" "$TMPDIR/argv-omitted-medium"; then
  fail "explicit medium and omitted quality produce identical ffmpeg argv" \
    "$(diff -u "$TMPDIR/argv-explicit-medium" "$TMPDIR/argv-omitted-medium")"
fi
pass "explicit medium and omitted quality produce identical ffmpeg argv"

if ! cmp -s "$TMPDIR/argv-omitted-medium" "$TMPDIR/expected-medium-argv"; then
  fail "medium quality produces the literal default ffmpeg argv" \
    "$(diff -u "$TMPDIR/expected-medium-argv" "$TMPDIR/argv-omitted-medium")"
fi
pass "medium quality produces the literal default ffmpeg argv"

grep -Fx "out=$TMPDIR/in-1080p.mp4" "$calls" >/dev/null ||
  fail "omitted quality writes the unsuffixed output name" "$(cat "$calls")"
pass "omitted quality writes the unsuffixed output name"

# Non-default tiers select the locked CRF values and take the quality suffix.
run_transcode "$TMPDIR/in.mov" mp4 1080p low
grep '^ffmpeg ' "$calls" | grep -F -- '-crf 28' >/dev/null ||
  fail "low quality selects x264 crf 28" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-1080p-low.mp4" "$calls" >/dev/null ||
  fail "low quality appends -low to the output name" "$(cat "$calls")"
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-low"
pass "low quality selects x264 crf 28 and writes in-1080p-low.mp4"

run_transcode "$TMPDIR/in.mov" mp4 1080p high
grep '^ffmpeg ' "$calls" | grep -F -- '-crf 18' >/dev/null ||
  fail "high quality selects x264 crf 18" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-1080p-high.mp4" "$calls" >/dev/null ||
  fail "high quality appends -high to the output name" "$(cat "$calls")"
pass "high quality selects x264 crf 18 and writes in-1080p-high.mp4"

# An existing output dedupes to -2 instead of tripping ffmpeg's overwrite
# prompt -- the stubs never create it, so the fixture is the only file.
touch "$TMPDIR/in-1080p.mp4"
FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/in.mov" mp4 1080p
grep -Fx "out=$TMPDIR/in-1080p-2.mp4" "$calls" >/dev/null ||
  fail "an existing output dedupes to -2" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4"
pass "an existing output dedupes to -2"

# The deduped path must be resolved -- and the encode started -- only after
# the "Transcoding" notification, so failure states are never orphaned.
notify_line=$(grep -n 'Transcoding' "$calls" | head -n1 | cut -d: -f1 || true)
ffmpeg_line=$(grep -n '^ffmpeg ' "$calls" | head -n1 | cut -d: -f1 || true)
[[ -n $notify_line && -n $ffmpeg_line ]] ||
  fail "the Transcoding notification and ffmpeg call both recorded" "$(cat "$calls")"
(( notify_line < ffmpeg_line )) ||
  fail "the Transcoding notification precedes the ffmpeg call" "$(cat "$calls")"
pass "the Transcoding notification precedes the ffmpeg call"

# A 4th positional on a picture fails before any notification, encoder, or
# menu -- the call log stays empty.
if run_transcode "$TMPDIR/img.png" jpg medium high; then
  fail "a picture transcode rejects a 4th positional"
fi
pass "a picture transcode rejects a 4th positional"

grep -q 'Invalid' "$TMPDIR/stderr" ||
  fail "picture quality rejection reports Invalid" "$(cat "$TMPDIR/stderr")"
pass "picture quality rejection reports Invalid"

if [[ -s $calls ]]; then
  fail "picture quality rejection precedes every side effect" "$(cat "$calls")"
fi
pass "picture quality rejection precedes every side effect"

# `medium` is rejected on pictures too -- the gate is [[ -n $quality ]], not
# a non-default check, so the locked vocabulary never leaks into slot 3.
if run_transcode "$TMPDIR/img.png" jpg medium medium; then
  fail "a picture transcode rejects quality=medium"
fi
pass "a picture transcode rejects quality=medium"

# 4k picks libx265 -preset slow; each tier pins its locked CRF (D-00a).
run_transcode "$TMPDIR/in.mov" mp4 4k high
grep '^ffmpeg ' "$calls" | grep -F -- '-c:v libx265 -preset slow -crf 20' >/dev/null ||
  fail "4k high selects x265 crf 20" "$(cat "$calls")"
pass "4k high selects x265 crf 20"

run_transcode "$TMPDIR/in.mov" mp4 4k medium
grep '^ffmpeg ' "$calls" | grep -F -- '-c:v libx265 -preset slow -crf 24' >/dev/null ||
  fail "4k medium selects x265 crf 24" "$(cat "$calls")"
pass "4k medium selects x265 crf 24"

run_transcode "$TMPDIR/in.mov" mp4 4k low
grep '^ffmpeg ' "$calls" | grep -F -- '-c:v libx265 -preset slow -crf 28' >/dev/null ||
  fail "4k low selects x265 crf 28" "$(cat "$calls")"
pass "4k low selects x265 crf 28"

# gif tiers vary fps only (D-00a, D-04) -- the palette pipeline stays put.
run_transcode "$TMPDIR/in.mov" gif 720p high
grep '^ffmpeg ' "$calls" | grep -F 'fps=15\,' >/dev/null ||
  fail "gif high selects fps=15" "$(cat "$calls")"
pass "gif high selects fps=15"

run_transcode "$TMPDIR/in.mov" gif 720p medium
grep '^ffmpeg ' "$calls" | grep -F 'fps=10\,' >/dev/null ||
  fail "gif medium selects fps=10" "$(cat "$calls")"
pass "gif medium selects fps=10"

run_transcode "$TMPDIR/in.mov" gif 720p low
grep '^ffmpeg ' "$calls" | grep -F 'fps=5\,' >/dev/null ||
  fail "gif low selects fps=5" "$(cat "$calls")"
pass "gif low selects fps=5"

# The dedupe counter climbs past every existing name and appends to the whole
# computed name, quality suffix included.
touch "$TMPDIR/in-1080p.mp4" "$TMPDIR/in-1080p-2.mp4"
FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/in.mov" mp4 1080p
grep -Fx "out=$TMPDIR/in-1080p-3.mp4" "$calls" >/dev/null ||
  fail "two existing outputs dedupe to -3" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4" "$TMPDIR/in-1080p-2.mp4"
pass "two existing outputs dedupe to -3"

touch "$TMPDIR/in-1080p-low.mp4"
run_transcode "$TMPDIR/in.mov" mp4 1080p low
grep -Fx "out=$TMPDIR/in-1080p-low-2.mp4" "$calls" >/dev/null ||
  fail "an existing -low output dedupes to -low-2" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p-low.mp4"
pass "an existing -low output dedupes to -low-2"

# output_path is shared, so pictures dedupe under the same policy instead of
# magick's silent overwrite.
touch "$TMPDIR/img-medium.jpg"
run_transcode "$TMPDIR/img.png" jpg medium
grep -Fx "out=$TMPDIR/img-medium-2.jpg" "$calls" >/dev/null ||
  fail "an existing picture output dedupes to -2" "$(cat "$calls")"
rm -f "$TMPDIR/img-medium.jpg"
pass "an existing picture output dedupes to -2"

# A dangling symlink fails -e but must still dedupe -- without -L ffmpeg would
# write through the link to an unrelated target (T-05-01).
ln -s /nonexistent "$TMPDIR/in-1080p.mp4"
FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/in.mov" mp4 1080p
grep -Fx "out=$TMPDIR/in-1080p-2.mp4" "$calls" >/dev/null ||
  fail "a dangling symlink still dedupes via -L" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4"
pass "a dangling symlink still dedupes via -L"

# Positive control: slot 3 on a picture is still the resolution vocabulary, so
# `img.png jpg low` resizes to 1080x> and writes img-low.jpg -- untouched.
run_transcode "$TMPDIR/img.png" jpg low
grep '^magick ' "$calls" | grep -F -- '-resize 1080x\>' >/dev/null ||
  fail "picture low still selects the 1080x resize" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/img-low.jpg" "$calls" >/dev/null ||
  fail "picture low still writes img-low.jpg" "$(cat "$calls")"
pass "picture low still selects the 1080x resize and writes img-low.jpg"

# A non-tier 4th positional fails pre-notification: non-zero, Invalid naming
# the value, and nothing recorded -- no notification, no encoder.
if run_transcode "$TMPDIR/in.mov" mp4 1080p bogus; then
  fail "a non-tier quality is rejected"
fi
grep -F 'Invalid video quality: bogus' "$TMPDIR/stderr" >/dev/null ||
  fail "a non-tier quality names the rejected value" "$(cat "$TMPDIR/stderr")"
if [[ -s $calls ]]; then
  fail "a non-tier quality fails before every side effect" "$(cat "$calls")"
fi
pass "a non-tier quality is rejected pre-notification"

# An empty 4th positional is "not specified": byte-identical medium argv and
# the unsuffixed name.
FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/in.mov" mp4 1080p ""
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-empty" ||
  fail "an empty quality records an ffmpeg line" "$(cat "$calls")"
if ! cmp -s "$TMPDIR/argv-empty" "$TMPDIR/expected-medium-argv"; then
  fail "an empty quality behaves as omitted" \
    "$(diff -u "$TMPDIR/expected-medium-argv" "$TMPDIR/argv-empty")"
fi
grep -Fx "out=$TMPDIR/in-1080p.mp4" "$calls" >/dev/null ||
  fail "an empty quality writes the unsuffixed output name" "$(cat "$calls")"
pass "an empty quality behaves as omitted"

# Whitespace is not a tier and is never silently trimmed into one.
if run_transcode "$TMPDIR/in.mov" mp4 1080p " ultra "; then
  fail "a whitespace-padded quality is rejected"
fi
grep -F 'Invalid video quality' "$TMPDIR/stderr" >/dev/null ||
  fail "a whitespace-padded quality reports Invalid video quality" "$(cat "$TMPDIR/stderr")"
pass "a whitespace-padded quality is rejected"

# A 4th positional after -- lands in positional[3] identically to the bare
# form.
run_transcode -- "$TMPDIR/in.mov" mp4 1080p low
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-dashdash" ||
  fail "a -- passthrough records an ffmpeg line" "$(cat "$calls")"
if ! cmp -s "$TMPDIR/argv-dashdash" "$TMPDIR/argv-low"; then
  fail "a -- passthrough produces the bare low argv" \
    "$(diff -u "$TMPDIR/argv-low" "$TMPDIR/argv-dashdash")"
fi
pass "a -- passthrough produces the bare low argv"

# Spaced filenames survive as single argv elements end to end; %q records the
# escaped form.
touch "$TMPDIR/my clip.mov"
FAKE_PICK=$'medium\tBalanced' run_transcode "$TMPDIR/my clip.mov" mp4 1080p
grep -F -- "-i $(printf '%q' "$TMPDIR/my clip.mov")" "$calls" >/dev/null ||
  fail "a spaced input stays one argv element" "$(cat "$calls")"
grep -Fx "out=$(printf '%q' "$TMPDIR/my clip-1080p.mp4")" "$calls" >/dev/null ||
  fail "a spaced input produces the escaped output name" "$(cat "$calls")"
pass "a spaced input stays one argv element end to end"

# Dedupe is the whole collision policy: no recorded ffmpeg argv ever carries
# an overwrite-control flag.
if grep -E '(^|[[:space:]])-[yn]([[:space:]]|$)' "$ffmpeg_calls"; then
  fail "no ffmpeg invocation carries an overwrite flag" "$(cat "$ffmpeg_calls")"
fi
pass "no ffmpeg invocation carries an overwrite flag"

# --help advertises the new arg and the video-only quality vocabulary.
run_transcode --help
grep -F '[quality]' "$TMPDIR/stdout" >/dev/null ||
  fail "usage shows [quality]" "$(cat "$TMPDIR/stdout")"
grep -F 'Videos: high, medium, low' "$TMPDIR/stdout" >/dev/null ||
  fail "usage lists the video quality tiers" "$(cat "$TMPDIR/stdout")"
pass "usage documents [quality] and the video tiers"

# An unset video quality fires the Select quality menu end to end: tab-joined
# rows (leading tab = empty glyph field) carrying CRF N · ~N MB subtexts at the
# locked 1080p midpoints plus the 192k audio term, and --default-index 1
# pre-highlighting medium.
FAKE_DURATION=60 FAKE_PICK=$'medium\tCRF 23 · ~24 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
grep -F 'Select quality' "$calls" >/dev/null ||
  fail "an unset video quality fires the Select quality menu" "$(cat "$calls")"
grep -F -- '--default-index 1' "$calls" >/dev/null ||
  fail "the quality menu pre-highlights medium" "$(cat "$calls")"
for row in $'\thigh\tCRF 18 · ~43 MB' $'\tmedium\tCRF 23 · ~24 MB' $'\tlow\tCRF 28 · ~12 MB'; do
  grep -F "$row" "$calls" >/dev/null ||
    fail "the quality menu offers a $row row" "$(cat "$calls")"
done
pass "the quality menu fires with CRF N · ~N MB rows and medium pre-highlighted"

# The Enter-default pick is the medium row: the recorded ffmpeg argv is
# byte-identical to positional medium and lands on the unsuffixed name.
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-menu-medium" ||
  fail "a medium menu pick records an ffmpeg line" "$(cat "$calls")"
if ! cmp -s "$TMPDIR/argv-menu-medium" "$TMPDIR/expected-medium-argv"; then
  fail "a medium menu pick produces the literal medium ffmpeg argv" \
    "$(diff -u "$TMPDIR/expected-medium-argv" "$TMPDIR/argv-menu-medium")"
fi
grep -Fx "out=$TMPDIR/in-1080p.mp4" "$calls" >/dev/null ||
  fail "a medium menu pick writes the unsuffixed output name" "$(cat "$calls")"
pass "a medium menu pick equals positional medium byte-for-byte"

# The label<TAB>subtext return is stripped at the first tab before the tier
# case -- a `low\t...` pick selects crf 28 and the -low suffix.
FAKE_DURATION=60 FAKE_PICK=$'low\tCRF 28 · ~11 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
grep '^ffmpeg ' "$calls" | grep -F -- '-crf 28' >/dev/null ||
  fail "a low menu pick selects x264 crf 28" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-1080p-low.mp4" "$calls" >/dev/null ||
  fail "a low menu pick appends -low to the output name" "$(cat "$calls")"
pass "a menu pick strips the subtext before tier matching"

# The four-positional path never goes interactive: no menu, no probe -- and
# the same medium argv as always.
run_transcode "$TMPDIR/in.mov" mp4 1080p medium
if grep -q '^menu-select:' "$calls" || grep -q '^ffprobe:' "$calls"; then
  fail "a four-positional run never prompts or probes" "$(cat "$calls")"
fi
grep '^ffmpeg ' "$calls" >"$TMPDIR/argv-noninteractive" ||
  fail "a four-positional run records an ffmpeg line" "$(cat "$calls")"
if ! cmp -s "$TMPDIR/argv-noninteractive" "$TMPDIR/expected-medium-argv"; then
  fail "a four-positional medium produces the literal medium argv" \
    "$(diff -u "$TMPDIR/expected-medium-argv" "$TMPDIR/argv-noninteractive")"
fi
pass "a four-positional run never prompts or probes"

# Esc semantics: an empty pick exits the menu stub with 1, which propagates
# through the command substitution and aborts the run silently -- before the
# Transcoding notification, same as the sibling prompts.
if FAKE_PICK="" FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p; then
  fail "an empty menu pick aborts the run"
fi
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "an empty menu pick aborts before the notification" "$(cat "$calls")"
fi
pass "an empty menu pick aborts before the notification"

# Sig-fig rendering: a 157 s clip at 1080p rounds each estimate to 1-2
# significant figures (~110 / ~63 / ~31 MB) -- never a decimal point.
FAKE_DURATION=157 FAKE_PICK=$'medium\tCRF 23 · ~63 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
for row in 'CRF 18 · ~110 MB' 'CRF 23 · ~63 MB' 'CRF 28 · ~31 MB'; do
  grep -F "$row" "$calls" >/dev/null ||
    fail "a 157 s clip offers a $row row" "$(cat "$calls")"
done
if grep '^menu-select: ' "$calls" | grep -E '~[0-9]*\.[0-9]' >/dev/null; then
  fail "estimates never render a decimal point" "$(cat "$calls")"
fi
pass "estimates render at 1-2 significant figures with no decimals"

# A 15 MiB source sits between the low (~12 MB) and medium (~24 MB) estimates
# at 60 s/1080p, so only the exceeding tiers degrade -- per-row, never the
# whole menu.
truncate -s 15M "$TMPDIR/small.mov"
FAKE_DURATION=60 FAKE_PICK=$'low\tCRF 28 · ~12 MB' \
  run_transcode "$TMPDIR/small.mov" mp4 1080p
grep -F $'\thigh\tCRF 18 · larger than source' "$calls" >/dev/null ||
  fail "the high row degrades when its estimate exceeds the source" "$(cat "$calls")"
grep -F $'\tmedium\tCRF 23 · larger than source' "$calls" >/dev/null ||
  fail "the medium row degrades when its estimate exceeds the source" "$(cat "$calls")"
grep -F $'\tlow\tCRF 28 · ~12 MB' "$calls" >/dev/null ||
  fail "the low row keeps its estimate under the source size" "$(cat "$calls")"
rm -f "$TMPDIR/small.mov"
pass "larger than source degrades per row, not per menu"

# Below every tier estimate, all three rows degrade together.
truncate -s 1024 "$TMPDIR/tiny.mov"
FAKE_DURATION=60 FAKE_PICK=$'medium\tCRF 23 · larger than source' \
  run_transcode "$TMPDIR/tiny.mov" mp4 1080p
for row in $'\thigh\tCRF 18 · larger than source' $'\tmedium\tCRF 23 · larger than source' $'\tlow\tCRF 28 · larger than source'; do
  grep -F "$row" "$calls" >/dev/null ||
    fail "a tiny source degrades the $row row" "$(cat "$calls")"
done
rm -f "$TMPDIR/tiny.mov"
pass "a tiny source degrades all three rows to larger than source"

# An N/A duration fails the numeric gate, so all three rows fall back to the
# qualitative vocabulary -- never a subtext/no-subtext mix, never an abort.
FAKE_DURATION=N/A FAKE_PICK=$'medium\tBalanced' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
for subtext in 'Best quality' 'Balanced' 'Smallest file'; do
  grep -F "$subtext" "$calls" >/dev/null ||
    fail "an N/A duration offers the $subtext fallback" "$(cat "$calls")"
done
if grep '^menu-select: ' "$calls" | grep -F '~' >/dev/null; then
  fail "an N/A duration renders no estimates" "$(cat "$calls")"
fi
grep '^ffmpeg ' "$calls" >/dev/null ||
  fail "an N/A duration still transcodes the pick" "$(cat "$calls")"
pass "an N/A duration falls back to qualitative rows and still transcodes"

# A probe that dies outright degrades identically -- cosmetic fallback, and
# the run still reaches ffmpeg.
FAKE_PROBE_RC=1 FAKE_PICK=$'medium\tBalanced' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
for subtext in 'Best quality' 'Balanced' 'Smallest file'; do
  grep -F "$subtext" "$calls" >/dev/null ||
    fail "a failed probe offers the $subtext fallback" "$(cat "$calls")"
done
if grep '^menu-select: ' "$calls" | grep -F '~' >/dev/null; then
  fail "a failed probe renders no estimates" "$(cat "$calls")"
fi
grep '^ffmpeg ' "$calls" >/dev/null ||
  fail "a failed probe still transcodes the pick" "$(cat "$calls")"
pass "a failed probe degrades to qualitative rows without aborting"

# A proven-audio-less source drops the 192k term: 60 s at 1080p renders
# ~41/~23/~11 MB instead of ~43/~24/~12.
FAKE_AUDIO=no FAKE_DURATION=60 FAKE_PICK=$'medium\tCRF 23 · ~23 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
for row in $'\thigh\tCRF 18 · ~41 MB' $'\tmedium\tCRF 23 · ~23 MB' $'\tlow\tCRF 28 · ~11 MB'; do
  grep -F "$row" "$calls" >/dev/null ||
    fail "a source with no audio stream offers a $row row" "$(cat "$calls")"
done
pass "a source with no audio stream drops the 192k estimate term"

# gif rows carry fps subtexts, never size estimates, and the gif path never
# spawns ffprobe.
FAKE_PICK=$'low\t5 fps' run_transcode "$TMPDIR/in.mov" gif 720p
for subtext in '15 fps' '10 fps' '5 fps'; do
  grep -F "$subtext" "$calls" >/dev/null ||
    fail "the gif menu offers a $subtext row" "$(cat "$calls")"
done
if grep -F 'Custom' "$calls" >/dev/null; then
  fail "the gif menu never offers a Custom size row" "$(cat "$calls")"
fi
if grep '^menu-select: ' "$calls" | grep -F '~' >/dev/null; then
  fail "gif rows never carry size estimates" "$(cat "$calls")"
fi
if grep -q '^ffprobe:' "$calls"; then
  fail "the gif path never probes the input" "$(cat "$calls")"
fi
grep '^ffmpeg ' "$calls" | grep -F 'fps=5\,' >/dev/null ||
  fail "a low gif pick selects fps=5" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-720p-low.gif" "$calls" >/dev/null ||
  fail "a low gif pick writes in-720p-low.gif" "$(cat "$calls")"
pass "gif rows carry fps subtexts and never probe the input"

# A forged Custom size… pick on a gif run must die at the whitelist like any
# other foreign label — never minting target: or firing the input prompt.
status=0
FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" gif 720p || status=$?
[[ $status -ne 0 ]] || fail "a forged Custom pick on gif is refused" "exit=$status"
grep -F 'Invalid video quality' "$TMPDIR/stderr" >/dev/null ||
  fail "a forged gif sentinel dies at the whitelist" "$(cat "$TMPDIR/stderr")"
if grep -q '^menu-input:' "$calls"; then
  fail "a forged gif sentinel never fires the input prompt" "$(cat "$calls")"
fi
pass "a forged Custom pick on gif dies at the whitelist"

# Pictures stop after the resolution prompt: no quality menu, no probe.
run_transcode "$TMPDIR/img.png" jpg medium
if grep -q '^menu-select:' "$calls" || grep -q '^ffprobe:' "$calls"; then
  fail "a picture run never prompts for quality or probes" "$(cat "$calls")"
fi
grep '^magick ' "$calls" | grep -F -- '-resize 2160x\>' >/dev/null ||
  fail "a picture run still resizes" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/img-medium.jpg" "$calls" >/dev/null ||
  fail "a picture run writes img-medium.jpg" "$(cat "$calls")"
pass "a picture run never prompts for quality or probes"

# A pick outside the tier vocabulary is re-validated inside select_quality and
# dies there -- the menu and probes ran, but nothing reached the notification.
if FAKE_DURATION=60 FAKE_PICK=$'bogus\tjunk' run_transcode "$TMPDIR/in.mov" mp4 1080p; then
  fail "a foreign-label menu pick is rejected"
fi
grep -F 'Invalid video quality' "$TMPDIR/stderr" >/dev/null ||
  fail "a foreign-label pick reports Invalid video quality" "$(cat "$TMPDIR/stderr")"
grep -q '^menu-select:' "$calls" ||
  fail "a foreign-label pick still records the menu call" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a foreign-label pick dies before the notification" "$(cat "$calls")"
fi
pass "a foreign-label menu pick is rejected before the notification"

# An unknown format fails validation in main() before any menu or
# notification -- format/resolution validate ahead of the quality prompt and
# the start notification, so no orphan "Transcoding" toast can appear.
if FAKE_PICK=$'low\tSmallest file' run_transcode "$TMPDIR/in.mov" avi 1080p; then
  fail "an unknown video format is rejected"
fi
grep -F 'Invalid video format' "$TMPDIR/stderr" >/dev/null ||
  fail "an unknown video format reports Invalid video format" "$(cat "$TMPDIR/stderr")"
if grep -q '^menu-select:' "$calls" || grep -q 'notification:' "$calls" ||
  grep -q '^ffmpeg ' "$calls"; then
  fail "an unknown format dies before any menu, notification, or encode" "$(cat "$calls")"
fi
pass "an unknown format fails before any menu or notification"

# The done notification reports the output's real size: FAKE_OUT_BYTES makes
# the stub write a 39,845,888-byte file, the script's own stat+awk chain
# measures it, and the body lands as "(40 MB)" -- the same decimal-MB scale
# the ~N MB menu estimates and file managers use. Assertions filter on
# 'Transcoded to' because the start
# notification body carries its own parenthetical. The knob-created output
# is this row's fixture -- rm -f it after asserting.
FAKE_OUT_BYTES=39845888 run_transcode "$TMPDIR/in.mov" mp4 1080p medium
grep 'notification:' "$calls" | grep -F 'Transcoded to 1080p mp4' |
  grep -F 'Saved and copied to clipboard (40 MB).' >/dev/null ||
  fail "the video done notification reports the output size" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4"
pass "the video done notification reports the output size"

FAKE_OUT_BYTES=39845888 run_transcode "$TMPDIR/img.png" jpg medium
grep 'notification:' "$calls" | grep -F 'Transcoded to medium jpg' |
  grep -F 'Saved and copied to clipboard (40 MB).' >/dev/null ||
  fail "the picture done notification reports the output size" "$(cat "$calls")"
rm -f "$TMPDIR/img-medium.jpg"
pass "the picture done notification reports the output size"

# With no FAKE_OUT_BYTES the stub creates nothing, stat fails inside
# output_size_label, and the body degrades to the plain sentence -- the run
# still exits 0 and no size is ever fabricated.
run_transcode "$TMPDIR/in.mov" mp4 1080p medium
grep 'notification:' "$calls" | grep -F 'Transcoded to 1080p mp4' |
  grep -E 'Saved and copied to clipboard\.$' >/dev/null ||
  fail "a missing output degrades the done notification to the plain body" "$(cat "$calls")"
if grep 'notification:' "$calls" | grep -F 'Transcoded to' | grep -F ' MB)' >/dev/null; then
  fail "a missing output never fabricates a size" "$(cat "$calls")"
fi
pass "a missing output degrades to the plain body without lying"

# A failed encode aborts before the done notification under set -e. The
# Transcoding start notification legitimately preceded the encode attempt,
# but zero "Transcoded to" lines may appear -- the notification can never
# claim a size for an output that does not exist.
if FAKE_ENCODE_RC=1 run_transcode "$TMPDIR/in.mov" mp4 1080p medium; then
  fail "a failed encode exits non-zero"
fi
grep -F 'Transcoding video' "$calls" >/dev/null ||
  fail "a failed encode still records the start notification" "$(cat "$calls")"
if grep 'notification:' "$calls" | grep -F 'Transcoded to' >/dev/null; then
  fail "a failed encode never sends the done notification" "$(cat "$calls")"
fi
pass "a failed encode sends zero done notifications"

# The gif arm shares main()'s video tail, so the size reaches it too -- a
# cheap pin that no arm is left on the plain body.
FAKE_OUT_BYTES=39845888 run_transcode "$TMPDIR/in.mov" gif 720p low
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p gif' |
  grep -F 'Saved and copied to clipboard (40 MB).' >/dev/null ||
  fail "the gif done notification reports the output size" "$(cat "$calls")"
rm -f "$TMPDIR/in-720p-low.gif"
pass "the gif done notification reports the output size"

# A deduped output reports the size of the file actually written: $output
# resolved to -2 before the notifications, so stat measures in-1080p-2.mp4 --
# never the pre-existing collision fixture.
touch "$TMPDIR/in-1080p.mp4"
FAKE_OUT_BYTES=39845888 run_transcode "$TMPDIR/in.mov" mp4 1080p medium
grep -Fx "out=$TMPDIR/in-1080p-2.mp4" "$calls" >/dev/null ||
  fail "an existing output dedupes to -2 with FAKE_OUT_BYTES set" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 1080p mp4' |
  grep -F 'Saved and copied to clipboard (40 MB).' >/dev/null ||
  fail "a deduped output reports its own size" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4" "$TMPDIR/in-1080p-2.mp4"
pass "a deduped output reports the size of the file actually written"

# A non-empty output under 1 MB reads "(<1 MB)", never "(0 MB)" -- a zero
# size on a real file would read as a lie next to the ~1 MB estimate floor.
FAKE_OUT_BYTES=200000 run_transcode "$TMPDIR/in.mov" mp4 1080p medium
grep 'notification:' "$calls" | grep -F 'Transcoded to 1080p mp4' |
  grep -F 'Saved and copied to clipboard (<1 MB).' >/dev/null ||
  fail "a sub-1 MiB output reports <1 MB, not 0 MB" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p.mp4"
pass "a sub-1 MiB output reports <1 MB"

# Sub-10 MB estimates round instead of flooring (WR-01): 18 s at 720p with
# 192k audio is 6.1/3.8/2.0 MB -- %.0f renders ~6/~4/~2 where the old %d
# floored to ~5/~3/~1. All three sit far below the 120 MiB fixture, so no
# larger-than-source degrade interferes.
FAKE_DURATION=18 FAKE_PICK=$'medium\tCRF 23 · ~4 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 720p
for row in $'\thigh\tCRF 18 · ~6 MB' $'\tmedium\tCRF 23 · ~4 MB' $'\tlow\tCRF 28 · ~2 MB'; do
  grep -F "$row" "$calls" >/dev/null ||
    fail "an 18 s 720p clip offers a $row row" "$(cat "$calls")"
done
pass "sub-10 MiB estimates round instead of flooring"

# --- --target: happy path -------------------------------------------------
# 25M over a 60 s clip with 192k audio derives 25000000*8/60/1000*0.98-192 =
# 3074k, so 1080p holds its 800k floor and the run two-passes at the derived
# rate: pass 1 stats-only to /dev/null, pass 2 the real encode -- with
# -vf/-c:v/-preset/-b:v byte-identical across passes and no -crf anywhere.
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M

[[ $(grep -c '^ffmpeg ' "$calls") -eq 2 ]] ||
  fail "a --target run records exactly two ffmpeg lines" "$(cat "$calls")"
pass1_line=$(grep -m1 ' -pass 1 ' "$calls")
pass2_line=$(grep -m1 ' -pass 2 ' "$calls")
[[ -n $pass1_line && -n $pass2_line ]] ||
  fail "a --target run records a pass 1 and a pass 2 line" "$(cat "$calls")"
for frag in '-pass 1' '-passlogfile' '-an' '-f null /dev/null' '-b:v 3074k' \
    'scale=-2:1080' '-c:v libx264' '-preset fast'; do
  grep -F -- "$frag" <<<"$pass1_line" >/dev/null ||
    fail "pass 1 carries $frag" "$pass1_line"
done
for frag in '-crf' '-movflags' '-c:a'; do
  if grep -F -- "$frag" <<<"$pass1_line" >/dev/null; then
    fail "pass 1 never carries $frag" "$pass1_line"
  fi
done
for frag in '-pass 2' '-passlogfile' '-b:v 3074k' '-c:a aac' '-b:a 192k' \
    '-movflags +faststart'; do
  grep -F -- "$frag" <<<"$pass2_line" >/dev/null ||
    fail "pass 2 carries $frag" "$pass2_line"
done
if grep -F -- '-crf' <<<"$pass2_line" >/dev/null; then
  fail "pass 2 never carries -crf" "$pass2_line"
fi
for field in '-vf' '-c:v' '-preset' '-b:v'; do
  v1=$(grep -o -- "$field [^ ]*" <<<"$pass1_line")
  v2=$(grep -o -- "$field [^ ]*" <<<"$pass2_line")
  [[ -n $v1 && $v1 == "$v2" ]] ||
    fail "$field is identical across passes" "pass1: $v1 / pass2: $v2"
done
grep -Fx "out=$TMPDIR/in-1080p-25M.mp4" "$calls" >/dev/null ||
  fail "a --target run writes the -25M output name" "$(cat "$calls")"
pass "a --target run two-passes at the derived bitrate with byte-identical shared flags"

# The start toast carries -p so the pass-2 update replaces it in place on the
# stub's id 7, and it still precedes the first ffmpeg call.
grep 'notification:' "$calls" | grep -F -- '-p ' | grep -F 'pass 1/2' >/dev/null ||
  fail "the --target start toast prints an id and names pass 1/2" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F -- '-r 7' | grep -F 'pass 2/2' >/dev/null ||
  fail "the pass-2 toast replaces the start toast in place" "$(cat "$calls")"
notify_line=$(grep -n 'Transcoding' "$calls" | head -n1 | cut -d: -f1 || true)
ffmpeg_line=$(grep -n '^ffmpeg ' "$calls" | head -n1 | cut -d: -f1 || true)
[[ -n $notify_line && -n $ffmpeg_line ]] ||
  fail "a --target run records the start toast and an ffmpeg call" "$(cat "$calls")"
(( notify_line < ffmpeg_line )) ||
  fail "the --target start toast precedes the encode" "$(cat "$calls")"
pass "a --target run scopes its toast per pass on one notification id"

# --target probes exactly twice (duration + audio presence) -- the positive
# twin of the tier run's never-probes pin.
[[ $(grep -c '^ffprobe:' "$calls") -eq 2 ]] ||
  fail "a --target run probes exactly twice" "$(cat "$calls")"
pass "a --target run probes exactly twice"

# All four slots supplied plus --target: zero menus, and the quality menu in
# particular is skipped entirely.
if grep -q 'Select quality' "$calls" || grep -q '^menu-select:' "$calls"; then
  fail "a fully-positional --target run never prompts" "$(cat "$calls")"
fi
pass "a fully-positional --target run skips the quality menu"

# Parse accepts: 25m / 25MB / bare 25 all canonicalize to the -25M filename
# token; 1.5G carries -1.5G. Each plans fine at 60 s/1080p -- the 1.5G row
# needs a 2G sparse source because a 1.5G target would refuse as >= source on
# the 120 MiB fixture.
for target in 25m 25MB 25; do
  FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target "$target"
  grep -Fx "out=$TMPDIR/in-1080p-25M.mp4" "$calls" >/dev/null ||
    fail "--target $target canonicalizes to the -25M filename token" "$(cat "$calls")"
done
truncate -s 2G "$TMPDIR/big.mov"
FAKE_DURATION=60 run_transcode "$TMPDIR/big.mov" mp4 1080p --target 1.5G
grep -Fx "out=$TMPDIR/big-1080p-1.5G.mp4" "$calls" >/dev/null ||
  fail "--target 1.5G canonicalizes to the -1.5G filename token" "$(cat "$calls")"
rm -f "$TMPDIR/big.mov"
# 500K is accepted by the parser but cannot fit at 60 s -- the accept signal
# is reaching the planner (probe lines + the floor refusal), not an output.
if FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 500K; then
  fail "a 500K target at 60 s refuses below every floor"
fi
grep -q '^ffprobe:' "$calls" ||
  fail "--target 500K parses and reaches the planner probes" "$(cat "$calls")"
grep -F 'smallest achievable' "$TMPDIR/stderr" >/dev/null ||
  fail "--target 500K refuses naming the achievable minimum" "$(cat "$TMPDIR/stderr")"
pass "size forms 25m/25MB/25/1.5G/500K parse and canonicalize"

# A missing --target value exits 2 on stderr before any side effect.
status=0
run_transcode "$TMPDIR/in.mov" mp4 1080p --target || status=$?
[[ $status -eq 2 ]] ||
  fail "a missing --target value exits 2" "exit=$status"
grep -F 'Missing value for --target' "$TMPDIR/stderr" >/dev/null ||
  fail "a missing --target value reports on stderr" "$(cat "$TMPDIR/stderr")"
if [[ -s $calls ]]; then
  fail "a missing --target value precedes every side effect" "$(cat "$calls")"
fi
pass "a missing --target value exits 2 with an empty call log"

# Step-down: a 4k request on a 10M/60s budget derives 1114k -- below the 4k
# floor (2000k) but above 1080p's (800k) -- so the run steps to 1080p and the
# filename and toasts all name the effective rung with the disclosure.
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target 10M
grep -Fx "out=$TMPDIR/in-1080p-10M.mp4" "$calls" >/dev/null ||
  fail "a 10M target at 4k steps down to the -1080p-10M name" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F 'scale=-2:1080' >/dev/null ||
  fail "a stepped-down run encodes at 1080p" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F -- '-b:v 1114k' >/dev/null ||
  fail "a stepped-down run derives -b:v 1114k" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F '1080p' |
  grep -F 'stepped down from 4k' | grep -F '10M' >/dev/null ||
  fail "the start toast names the effective rung, the step-down, and the target" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 1080p mp4' >/dev/null ||
  fail "the done toast names the effective rung too" "$(cat "$calls")"
pass "a 4k request on a 10M budget steps down to 1080p and says so"

# One rung further: 5M/60s derives 461k -- below 1080p's floor, above 720p's.
# numfmt --to=si canonicalizes exact-decimal targets at 3 significant figures,
# so 5M ships as the -5.0M token (the accepted 1.0M-style shape).
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target 5M
grep -Fx "out=$TMPDIR/in-720p-5.0M.mp4" "$calls" >/dev/null ||
  fail "a 5M target at 4k steps down to the -720p-5.0M name" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F 'scale=-2:720' >/dev/null ||
  fail "a 5M target encodes at 720p" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F -- '-b:v 461k' >/dev/null ||
  fail "a 5M target derives -b:v 461k" "$(cat "$calls")"
pass "a 4k request on a 5M budget steps down to 720p"

# Boundary: 25M/60s derives 3074k, at or above the 4k floor, so a 4k request
# stays at 4k on libx265 -preset slow.
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target 25M
grep ' -pass 2 ' "$calls" | grep -F 'scale=-2:2160' >/dev/null ||
  fail "a 25M target at 4k keeps the 4k scale" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F -- '-c:v libx265 -preset slow' >/dev/null ||
  fail "a 25M target at 4k keeps the x265 codec" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F -- '-b:v 3074k' >/dev/null ||
  fail "a 25M target at 4k derives -b:v 3074k" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-4k-25M.mp4" "$calls" >/dev/null ||
  fail "a 25M target at 4k writes the -4k-25M name" "$(cat "$calls")"
pass "a target at or above the 4k floor stays at 4k"

# --- --target: refusal matrix ---------------------------------------------
# Parse rejects die in the arg loop -- exit 2, the rejected input on stderr,
# and a provably empty call log (before media_type, any menu, or any toast).
for bad in abc -5M 0 25.5.2M ""; do
  status=0
  run_transcode "$TMPDIR/in.mov" mp4 1080p --target "$bad" || status=$?
  [[ $status -eq 2 ]] ||
    fail "--target $bad exits 2" "exit=$status"
  grep -F "Invalid target size: $bad" "$TMPDIR/stderr" >/dev/null ||
    fail "--target $bad names the rejected input" "$(cat "$TMPDIR/stderr")"
  if [[ -s $calls ]]; then
    fail "--target $bad precedes every side effect" "$(cat "$calls")"
  fi
done
pass "invalid --target values exit 2 before any side effect"

# --target and a positional quality tier are mutually exclusive: exit 1,
# stderr naming both, before every side effect.
status=0
run_transcode "$TMPDIR/in.mov" mp4 1080p low --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "--target plus a quality tier exits 1" "exit=$status"
grep -F -- '--target' "$TMPDIR/stderr" >/dev/null &&
  grep -F 'low' "$TMPDIR/stderr" >/dev/null ||
  fail "the conflict error names both --target and the tier" "$(cat "$TMPDIR/stderr")"
if [[ -s $calls ]]; then
  fail "--target plus a quality tier precedes every side effect" "$(cat "$calls")"
fi
pass "--target plus a quality tier refuses naming both"

# A positional gif under --target refuses before any notification or encode;
# the file stub writes no CALLS line, so the log stays fully empty here.
status=0
run_transcode "$TMPDIR/in.mov" gif 720p --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "--target gif exits 1" "exit=$status"
grep -F 'not supported for gif' "$TMPDIR/stderr" >/dev/null ||
  fail "--target gif reports the gif refusal" "$(cat "$TMPDIR/stderr")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "--target gif refuses before notification and encode" "$(cat "$calls")"
fi
pass "--target gif refuses pre-notification"

# A menu-picked gif under --target hits the same refusal -- after the format
# and resolution menus, but before the resolution case, so the error names
# gif (never "Invalid video resolution") and the log holds menu lines only.
status=0
FAKE_PICK=gif run_transcode "$TMPDIR/in.mov" --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "a menu-picked gif under --target exits 1" "exit=$status"
grep -F 'not supported for gif' "$TMPDIR/stderr" >/dev/null ||
  fail "a menu-picked gif reports the gif refusal" "$(cat "$TMPDIR/stderr")"
if grep -F 'Invalid video resolution' "$TMPDIR/stderr" >/dev/null; then
  fail "a menu-picked gif dies on the gif refusal, not the resolution case" \
    "$(cat "$TMPDIR/stderr")"
fi
grep -q '^menu-select:' "$calls" ||
  fail "a menu-picked gif run records its menu calls" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a menu-picked gif refuses after menus but before notification" "$(cat "$calls")"
fi
pass "a menu-picked gif under --target refuses pre-notification"

# Pictures refuse --target at the earliest point type is known -- before the
# format menu even -- with an empty call log.
status=0
run_transcode "$TMPDIR/img.png" jpg medium --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "--target on a picture exits 1" "exit=$status"
grep -F 'applies to videos only' "$TMPDIR/stderr" >/dev/null ||
  fail "--target on a picture reports the picture refusal" "$(cat "$TMPDIR/stderr")"
if [[ -s $calls ]]; then
  fail "--target on a picture precedes every side effect" "$(cat "$calls")"
fi
pass "--target on a picture refuses before any menu or notification"

# An unset resolution still prompts under --target -- the pick is the
# planner's ceiling, not a floor: a 4k pick on a 5M budget steps to 720p.
FAKE_PICK=4k FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 --target 5M
grep '^menu-select:' "$calls" | grep -F 'Select resolution' >/dev/null ||
  fail "an unset resolution still prompts under --target" "$(cat "$calls")"
grep -Fx "out=$TMPDIR/in-720p-5.0M.mp4" "$calls" >/dev/null ||
  fail "a 4k menu pick on a 5M budget steps down to -720p-5.0M" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F 'scale=-2:720' >/dev/null ||
  fail "a stepped-down menu pick encodes at 720p" "$(cat "$calls")"
pass "an unset resolution prompts as the planner ceiling under --target"

# Below every floor: 4M and 2M over 60 s derive 330k and 69k -- under 720p's
# 400k floor -- so both refuse naming the computed achievable minimum
# ((400+192)*60*125 = 4,440,000 B, rendered ~4 MB). The probes ran, but no
# notification or encode did.
for t in 4M 2M; do
  status=0
  FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target "$t" || status=$?
  [[ $status -eq 1 ]] ||
    fail "--target $t below every floor exits 1" "exit=$status"
  grep -F 'smallest achievable' "$TMPDIR/stderr" >/dev/null &&
    grep -F '4 MB' "$TMPDIR/stderr" >/dev/null ||
    fail "--target $t names the achievable minimum" "$(cat "$TMPDIR/stderr")"
  grep -q '^ffprobe:' "$calls" ||
    fail "--target $t refused after probing" "$(cat "$calls")"
  if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
    fail "--target $t refuses before notification and encode" "$(cat "$calls")"
  fi
done
pass "targets below every floor refuse naming the achievable minimum"

# 1M over 60 s leaves no room even for the 192k audio stream (the derived
# -61k rides the floor loop to the same refusal) -- and no negative, zero, or
# -nan -b:v ever reaches ffmpeg argv on any accumulated line.
status=0
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 720p --target 1M || status=$?
[[ $status -eq 1 ]] ||
  fail "a target below the audio floor exits 1" "exit=$status"
grep -F 'smallest achievable' "$TMPDIR/stderr" >/dev/null ||
  fail "a target below the audio floor names the achievable minimum" "$(cat "$TMPDIR/stderr")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a target below the audio floor refuses before the encode" "$(cat "$calls")"
fi
if grep -E -- '-b:v -|-b:v 0k|-nan' "$ffmpeg_calls" >/dev/null; then
  fail "no ffmpeg line ever carries a negative, zero, or NaN bitrate" "$(cat "$ffmpeg_calls")"
fi
pass "a target too small for audio alone refuses; no bad -b:v reaches argv"

# A target at or above the source refuses before even probing -- naming both
# sizes and pointing at the tier path for format-conversion intent.
status=0
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 200M || status=$?
[[ $status -eq 1 ]] ||
  fail "a target at or above the source exits 1" "exit=$status"
grep -F '200M' "$TMPDIR/stderr" >/dev/null &&
  grep -F '126M' "$TMPDIR/stderr" >/dev/null &&
  grep -F 'quality' "$TMPDIR/stderr" >/dev/null ||
  fail "a >=source refusal names both sizes and the tier path" "$(cat "$TMPDIR/stderr")"
if grep -q '^ffprobe:' "$calls"; then
  fail "a >=source refusal precedes the probes" "$(cat "$calls")"
fi
pass "a target at or above the source refuses before probing"

# A failed or degenerate duration probe refuses the same pre-notification way
# -- no qualitative fallback exists under --target. The probe line proves the
# run got past parsing and the >=source check.
status=0
run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "a failed duration probe exits 1" "exit=$status"
grep -F 'Cannot determine duration' "$TMPDIR/stderr" >/dev/null ||
  fail "a failed duration probe refuses" "$(cat "$TMPDIR/stderr")"
grep -q '^ffprobe:' "$calls" ||
  fail "a failed duration probe still records the probe" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a failed duration probe refuses before notification" "$(cat "$calls")"
fi

status=0
FAKE_DURATION=N/A run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "an N/A duration exits 1" "exit=$status"
grep -F 'Cannot determine duration' "$TMPDIR/stderr" >/dev/null ||
  fail "an N/A duration refuses" "$(cat "$TMPDIR/stderr")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "an N/A duration refuses before notification" "$(cat "$calls")"
fi

status=0
FAKE_DURATION=0 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M || status=$?
[[ $status -eq 1 ]] ||
  fail "a zero duration exits 1" "exit=$status"
grep -F 'Cannot determine duration' "$TMPDIR/stderr" >/dev/null ||
  fail "a zero duration refuses" "$(cat "$TMPDIR/stderr")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a zero duration refuses before notification" "$(cat "$calls")"
fi
pass "failed, N/A, and zero durations all refuse before any notification"

# The probed audio term actually moves the math: a proven-audio-less source
# drops the 192k term, so 5M/60s at a 4k request derives 653k (not 461k).
FAKE_AUDIO=no FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target 5M
grep ' -pass 2 ' "$calls" | grep -F 'scale=-2:720' >/dev/null ||
  fail "a no-audio 5M target still steps to 720p" "$(cat "$calls")"
grep ' -pass 2 ' "$calls" | grep -F -- '-b:v 653k' >/dev/null ||
  fail "a no-audio 5M target derives -b:v 653k" "$(cat "$calls")"
pass "a proven-audio-less source drops the 192k term from the math"

# The never-probes pin holds: a four-positional tier run never calls
# plan_target, so no ffprobe or menu lines appear.
run_transcode "$TMPDIR/in.mov" mp4 1080p medium
if grep -q '^ffprobe:' "$calls" || grep -q '^menu-select:' "$calls"; then
  fail "a tier run still never probes or prompts" "$(cat "$calls")"
fi
pass "a four-positional tier run still never probes or prompts"

# --- --target: overshoot retry and passlog hygiene --------------------------
# One byte over triggers exactly one pass-2-only retry: 50M/60s derives 6341k,
# the first pass-2 output measures 52428801 B, so the retry bitrate is
# 6341*50000000/52428801 truncated to 6047k. The retry encodes to a passdir
# sibling and mv's onto $output, so the done toast and stat report the retry
# file's real ~4 MB. FAKE_OUT_BYTES feeds pass-2 #1, FAKE_OUT_BYTES2 #2; the
# knob-created files are this row's fixtures -- rm -f after asserting.
FAKE_OUT_BYTES=52428801 FAKE_OUT_BYTES2=4194304 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 50M
[[ $(grep -c '^ffmpeg ' "$calls") -eq 3 ]] ||
  fail "an overshoot run makes exactly three ffmpeg calls" "$(cat "$calls")"
[[ $(grep -c '^ffmpeg .*retry\.mp4' "$calls") -eq 1 ]] ||
  fail "an overshoot triggers exactly one retry" "$(cat "$calls")"
grep '^ffmpeg .*retry\.mp4' "$calls" | grep -F -- '-b:v 6047k' >/dev/null ||
  fail "the retry tightens to -b:v 6047k" "$(cat "$calls")"
grep '^ffmpeg .*retry\.mp4' "$calls" | grep -F 'scale=-2:720' >/dev/null ||
  fail "the retry keeps the 720p resolution" "$(cat "$calls")"
grep '^ffmpeg .*retry\.mp4' "$calls" | grep -F -- '-c:v libx264 -preset fast' >/dev/null ||
  fail "the retry keeps the codec and preset" "$(cat "$calls")"
grep '^ffmpeg .*retry\.mp4' "$calls" |
  grep -F -- '-c:a aac -b:a 192k -movflags +faststart' >/dev/null ||
  fail "the retry keeps the audio and faststart flags" "$(cat "$calls")"
[[ $(grep '^ffmpeg ' "$calls" | grep -o 'passlogfile [^ ]*' | sort -u | wc -l) -eq 1 ]] ||
  fail "all three calls share one passlogfile" "$(cat "$calls")"
[[ $(stat -c %s "$TMPDIR/in-720p-50M.mp4") -eq 4194304 ]] ||
  fail "the retry result lands on the output path" "$(stat -c %s "$TMPDIR/in-720p-50M.mp4")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p mp4' |
  grep -F '(4 MB)' >/dev/null ||
  fail "the done toast reports the retry's real size" "$(cat "$calls")"
grep '^ffmpeg ' "$calls" | head -n1 |
  grep -o 'passlogfile [^ ]*' | grep -F "passlogfile $TMPDIR" >/dev/null ||
  fail "the passlog lives under the exported TMPDIR" "$(cat "$calls")"
if find "$TMPDIR" -name '*2pass*' -print -quit | grep -q .; then
  fail "a successful retry leaves no passlog artifacts" \
    "$(find "$TMPDIR" -name '*2pass*')"
fi
rm -f "$TMPDIR/in-720p-50M.mp4"
pass "a byte-over target retries pass-2 once at the tightened bitrate"

# At or under target: no retry at all. The boundary is inclusive -- exactly
# 90000000 B against a 90M target is a hit, and 79999999 B against 80M is a
# hit by one byte.
FAKE_OUT_BYTES=90000000 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 90M
[[ $(grep -c '^ffmpeg ' "$calls") -eq 2 ]] ||
  fail "an exactly-at-target run makes two ffmpeg calls" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p mp4' |
  grep -F '(90 MB)' >/dev/null ||
  fail "an at-target run reports its real size" "$(cat "$calls")"
rm -f "$TMPDIR/in-720p-90M.mp4"

FAKE_OUT_BYTES=79999999 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 80M
[[ $(grep -c '^ffmpeg ' "$calls") -eq 2 ]] ||
  fail "a one-byte-under run makes two ffmpeg calls" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p mp4' |
  grep -F '(80 MB)' >/dev/null ||
  fail "an under-target run reports its real size" "$(cat "$calls")"
rm -f "$TMPDIR/in-720p-80M.mp4"
pass "an at-or-under target never retries"

# A retry that lands over target still moves into place and the run stops --
# never a second retry, and the honest overshot size is what gets reported.
FAKE_OUT_BYTES=62914561 FAKE_OUT_BYTES2=62914561 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 60M
[[ $(grep -c '^ffmpeg ' "$calls") -eq 3 ]] ||
  fail "a still-over retry makes exactly three ffmpeg calls" "$(cat "$calls")"
[[ $(grep -c '^ffmpeg .*retry\.mp4' "$calls") -eq 1 ]] ||
  fail "a still-over result never triggers a second retry" "$(cat "$calls")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p mp4' |
  grep -F '(63 MB)' >/dev/null ||
  fail "a still-over retry reports the real overshot size" "$(cat "$calls")"
rm -f "$TMPDIR/in-720p-60M.mp4"
pass "an overshoot retries at most once"

# A failed retry preserves the overshot-but-playable first output: no mv, the
# over-target file stays put, and the done toast still reports its real size.
FAKE_OUT_BYTES=73400321 FAKE_PASS2_RC="0 1" FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 70M
[[ $(grep -c '^ffmpeg .*retry\.mp4' "$calls") -eq 1 ]] ||
  fail "a failed retry still records its ffmpeg call" "$(cat "$calls")"
[[ -f $TMPDIR/in-720p-70M.mp4 ]] &&
  [[ $(stat -c %s "$TMPDIR/in-720p-70M.mp4") -eq 73400321 ]] ||
  fail "a failed retry preserves the first output" "$(ls -l "$TMPDIR")"
grep 'notification:' "$calls" | grep -F 'Transcoded to 720p mp4' |
  grep -F '(73 MB)' >/dev/null ||
  fail "a failed retry still reports the real size" "$(cat "$calls")"
if find "$TMPDIR" -name '*2pass*' -print -quit | grep -q .; then
  fail "a failed retry leaves no passlog artifacts" \
    "$(find "$TMPDIR" -name '*2pass*')"
fi
rm -f "$TMPDIR/in-720p-70M.mp4"
pass "a failed retry preserves the overshot first output"

# A pass-1 failure aborts the run: exit 1, the start toast fired but the
# pass-2 replacement and done toast never did, and the EXIT trap still
# reaps the passdir.
status=0
FAKE_PASS1_RC=1 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 55M || status=$?
[[ $status -eq 1 ]] ||
  fail "a pass-1 failure exits 1" "exit=$status"
[[ $(grep -c '^ffmpeg ' "$calls") -eq 1 ]] ||
  fail "a pass-1 failure makes exactly one ffmpeg call" "$(cat "$calls")"
if grep -q ' -pass 2 ' "$calls"; then
  fail "a pass-1 failure never reaches pass 2" "$(cat "$calls")"
fi
[[ $(grep -c 'notification:' "$calls") -eq 1 ]] ||
  fail "a pass-1 failure sends only the start toast" "$(cat "$calls")"
if find "$TMPDIR" -name '*2pass*' -print -quit | grep -q .; then
  fail "a pass-1 failure leaves no passlog artifacts" \
    "$(find "$TMPDIR" -name '*2pass*')"
fi
pass "a pass-1 failure aborts before pass 2 with a clean passdir"

# A pass-2 failure aborts after the replacement toast: exit 1, two ffmpeg
# calls, no retry, no done toast, passdir reaped.
status=0
FAKE_PASS2_RC=1 FAKE_DURATION=60 \
  run_transcode "$TMPDIR/in.mov" mp4 720p --target 45M || status=$?
[[ $status -eq 1 ]] ||
  fail "a pass-2 failure exits 1" "exit=$status"
[[ $(grep -c '^ffmpeg ' "$calls") -eq 2 ]] ||
  fail "a pass-2 failure makes exactly two ffmpeg calls" "$(cat "$calls")"
[[ $(grep -c 'notification:' "$calls") -eq 2 ]] ||
  fail "a pass-2 failure sends the two pass toasts only" "$(cat "$calls")"
if grep 'notification:' "$calls" | grep -F 'Transcoded to' >/dev/null; then
  fail "a pass-2 failure never sends the done toast" "$(cat "$calls")"
fi
if find "$TMPDIR" -name '*2pass*' -print -quit | grep -q .; then
  fail "a pass-2 failure leaves no passlog artifacts" \
    "$(find "$TMPDIR" -name '*2pass*')"
fi
pass "a pass-2 failure aborts with no done toast and a clean passdir"

# Dedupe composes with --target: a pre-existing in-1080p-25M.mp4 sends the
# target run to -2 -- the token joins the name before the dedupe counter.
touch "$TMPDIR/in-1080p-25M.mp4"
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M
grep -Fx "out=$TMPDIR/in-1080p-25M-2.mp4" "$calls" >/dev/null ||
  fail "a colliding target output dedupes to -2" "$(cat "$calls")"
rm -f "$TMPDIR/in-1080p-25M.mp4"
pass "a --target output dedupes with the size token in place"

# usage() documents the flag: --help renders it on stdout with status 0.
run_transcode --help
grep -F -- '--target' "$TMPDIR/stdout" >/dev/null ||
  fail "--help documents --target" "$(cat "$TMPDIR/stdout")"
pass "--help documents the --target flag"

# --- Custom size… -------------------------------------------------------------
# The mp4 menu carries a fourth, last row whose label doubles as the sentinel
# key: the pick returns "Custom size…\t<subtext>", the strip hands the label to
# the sentinel branch, and the typed answer rides the exact --target path, so
# the ffmpeg argv and toast text are cmp-identical to `mp4 1080p --target 25M`
# modulo the per-run mktemp passdir that -passlogfile logs (sed-normalized on
# both greps). Rows after the first two runs read the saved copies only --
# run_transcode truncates $calls and rewrites $TMPDIR/stderr on every
# invocation.
FAKE_INPUT=25M FAKE_DURATION=60 FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
cp "$calls" "$TMPDIR/calls-custom"
cp "$TMPDIR/stderr" "$TMPDIR/stderr-custom"
grep '^menu-select: ' "$TMPDIR/calls-custom" | grep -F 'Select quality' >/dev/null ||
  fail "a Custom pick records the Select quality menu call" "$(cat "$TMPDIR/calls-custom")"
grep '^menu-select: ' "$TMPDIR/calls-custom" |
  grep -F $'\tCustom size…\tEnter a size like 25M -- --default-index 1' >/dev/null ||
  fail "the Custom size row sits last with its subtext and medium stays pre-highlighted" \
    "$(cat "$TMPDIR/calls-custom")"
pass "the mp4 menu offers Custom size… last with a subtext and medium pre-highlighted"

# The CLI twin of the parity pin: --target 25M never prompts and pays only the
# planner's two probes.
rm -f "$TMPDIR/in-1080p-25M.mp4"
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 1080p --target 25M
grep -E '^(ffmpeg |notification:)' "$calls" |
  sed 's|transcode-2pass\.[^/ ]*|transcode-2pass.X|' >"$TMPDIR/parity-cli"
[[ $(grep -c '^ffprobe:' "$calls") -eq 2 ]] ||
  fail "the --target baseline probes exactly twice" "$(cat "$calls")"
if grep -q '^menu-select:' "$calls" || grep -q '^menu-input:' "$calls"; then
  fail "the --target baseline never prompts" "$(cat "$calls")"
fi
pass "a --target 25M run never prompts and probes exactly twice"

# The Custom run's encode is byte-identical to the CLI run's -- same two-pass
# argv, same toast text; only the menu plumbing and the two menu-estimate
# probes differ upstream of it.
grep -E '^(ffmpeg |notification:)' "$TMPDIR/calls-custom" |
  sed 's|transcode-2pass\.[^/ ]*|transcode-2pass.X|' >"$TMPDIR/parity-menu"
if ! cmp -s "$TMPDIR/parity-cli" "$TMPDIR/parity-menu"; then
  fail "a Custom size pick produces the --target run's argv and toasts" \
    "$(diff -u "$TMPDIR/parity-cli" "$TMPDIR/parity-menu")"
fi
grep -Fx "out=$TMPDIR/in-1080p-25M.mp4" "$TMPDIR/calls-custom" >/dev/null ||
  fail "a Custom pick writes the -25M output name" "$(cat "$TMPDIR/calls-custom")"
[[ $(grep -c '^menu-input:' "$TMPDIR/calls-custom") -eq 1 ]] ||
  fail "a Custom pick fires the input prompt exactly once" "$(cat "$TMPDIR/calls-custom")"
grep -Fx 'menu-input: Target size (e.g. 25M)' "$TMPDIR/calls-custom" >/dev/null ||
  fail "the input prompt carries its locked text" "$(cat "$TMPDIR/calls-custom")"
[[ $(grep -c '^ffprobe:' "$TMPDIR/calls-custom") -eq 4 ]] ||
  fail "a Custom run probes 4 times (2 menu estimates + 2 planner)" \
    "$(cat "$TMPDIR/calls-custom")"
pass "a Custom size pick encodes byte-identically to --target 25M"

# The sentinel label and the target: mint never reach the encoder, the output
# name, or the tier case -- the strip-plus-branch stays the only chokepoint.
if grep -E '^(ffmpeg |out=)' "$TMPDIR/calls-custom" | grep -F 'Custom' >/dev/null; then
  fail "the Custom label never reaches an ffmpeg or out= line" \
    "$(cat "$TMPDIR/calls-custom")"
fi
if grep -E '^(ffmpeg |out=)' "$TMPDIR/calls-custom" | grep -F 'target:' >/dev/null; then
  fail "the target: sentinel never reaches an ffmpeg or out= line" \
    "$(cat "$TMPDIR/calls-custom")"
fi
if grep -F 'Invalid video quality' "$TMPDIR/stderr-custom" >/dev/null; then
  fail "the Custom pick never reaches the tier case" "$(cat "$TMPDIR/stderr-custom")"
fi
# A plain tier pick on the same menu never fires the input prompt at all.
FAKE_DURATION=60 FAKE_PICK=$'medium\tCRF 23 · ~24 MB' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
if grep -q '^menu-input:' "$calls"; then
  fail "a tier pick never fires the input prompt" "$(cat "$calls")"
fi
pass "the sentinel label and the target: mint never leak to argv or the tier case"

# An empty submit is exit-0-with-empty, NOT a cancel: it rides through
# parse_target_size like any garbage and buys exactly one hinted re-prompt.
FAKE_INPUT="" FAKE_INPUT2=25M FAKE_DURATION=60 \
  FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
[[ $(grep -c '^menu-input:' "$calls") -eq 2 ]] ||
  fail "an empty submit re-prompts exactly once" "$(cat "$calls")"
grep '^menu-input:' "$calls" | tail -n1 |
  grep -F 'Invalid size — e.g. 25M' >/dev/null ||
  fail "the re-prompt carries the Invalid size hint" "$(cat "$calls")"
grep -q '^ffmpeg ' "$calls" ||
  fail "an empty-then-valid run still encodes" "$(cat "$calls")"
pass "an empty submit re-prompts once with the hint, then accepts"

# Unparseable input gets the same single hinted re-prompt.
FAKE_INPUT=bogus FAKE_INPUT2=25M FAKE_DURATION=60 \
  FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p
[[ $(grep -c '^menu-input:' "$calls") -eq 2 ]] ||
  fail "an unparseable answer re-prompts exactly once" "$(cat "$calls")"
grep '^menu-input:' "$calls" | tail -n1 |
  grep -F 'Invalid size — e.g. 25M' >/dev/null ||
  fail "the unparseable re-prompt carries the hint" "$(cat "$calls")"
grep -F 'Invalid target size: bogus' "$TMPDIR/stderr" >/dev/null ||
  fail "the parse failure still reaches stderr" "$(cat "$TMPDIR/stderr")"
grep -q '^ffmpeg ' "$calls" ||
  fail "a garbage-then-valid run still encodes" "$(cat "$calls")"
pass "an unparseable answer re-prompts once with the hint, then accepts"

# The for 1 2 bound caps the budget at one re-prompt: a second bad answer
# cancels like Esc -- nonzero, pre-notification, never a third prompt.
status=0
FAKE_INPUT=bogus FAKE_INPUT2=still-bogus FAKE_DURATION=60 \
  FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p || status=$?
[[ $status -ne 0 ]] ||
  fail "two bad answers cancel the run" "exit=$status"
[[ $(grep -c '^menu-input:' "$calls") -eq 2 ]] ||
  fail "the re-prompt budget never exceeds two prompts" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "an exhausted re-prompt budget cancels before the notification" "$(cat "$calls")"
fi
pass "a second bad answer cancels like Esc, before the notification"

# Esc at the re-prompt cancels through the same chain as Esc at the first.
status=0
FAKE_INPUT=bogus FAKE_DURATION=60 \
  FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p || status=$?
[[ $status -ne 0 ]] ||
  fail "Esc at the re-prompt cancels the run" "exit=$status"
[[ $(grep -c '^menu-input:' "$calls") -eq 2 ]] ||
  fail "Esc at the re-prompt still records both prompts" "$(cat "$calls")"
grep '^menu-input:' "$calls" | tail -n1 |
  grep -F 'Invalid size — e.g. 25M' >/dev/null ||
  fail "the Esc'd re-prompt carried the hint" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "Esc at the re-prompt cancels before the notification" "$(cat "$calls")"
fi
pass "Esc at the hinted re-prompt cancels before the notification"

# Esc at the first input prompt aborts pre-notification like every sibling:
# the two estimate probes ran but the planner never did, and nothing else
# fired.
status=0
FAKE_DURATION=60 FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 1080p || status=$?
[[ $status -ne 0 ]] ||
  fail "Esc at the input prompt cancels the run" "exit=$status"
[[ $(grep -c '^menu-input:' "$calls") -eq 1 ]] ||
  fail "Esc at the first prompt records exactly one input call" "$(cat "$calls")"
[[ $(grep -c '^ffprobe:' "$calls") -eq 2 ]] ||
  fail "an input-prompt Esc aborts before the planner probes" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "Esc at the input prompt cancels before the notification" "$(cat "$calls")"
fi
pass "Esc at the first input prompt cancels before the notification"

# D-01: a parseable-below-floor answer refuses byte-identically to the CLI --
# the re-prompt budget wraps the parser only, never plan_target.
status=0
FAKE_DURATION=60 run_transcode "$TMPDIR/in.mov" mp4 4k --target 4M || status=$?
[[ $status -ne 0 ]] ||
  fail "the --target 4M baseline refuses" "exit=$status"
cp "$TMPDIR/stderr" "$TMPDIR/stderr-cli-4M"
status=0
FAKE_INPUT=4M FAKE_DURATION=60 FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" mp4 4k || status=$?
[[ $status -ne 0 ]] ||
  fail "a below-floor Custom answer refuses" "exit=$status"
grep -F 'smallest achievable' "$TMPDIR/stderr" >/dev/null &&
  grep -F '4 MB' "$TMPDIR/stderr" >/dev/null ||
  fail "a below-floor Custom answer names the achievable minimum" "$(cat "$TMPDIR/stderr")"
if ! cmp -s "$TMPDIR/stderr-cli-4M" "$TMPDIR/stderr"; then
  fail "the Custom refusal is byte-identical to --target 4M" \
    "$(diff -u "$TMPDIR/stderr-cli-4M" "$TMPDIR/stderr")"
fi
[[ $(grep -c '^menu-input:' "$calls") -eq 1 ]] ||
  fail "a planner refusal never spends a re-prompt" "$(cat "$calls")"
if grep -q 'notification:' "$calls" || grep -q '^ffmpeg ' "$calls"; then
  fail "a below-floor Custom answer refuses before the notification" "$(cat "$calls")"
fi
pass "a below-floor Custom answer refuses byte-identically to --target 4M"

# The accumulated ffmpeg argv across every run carries no overwrite flag --
# dedupe and the passdir-sibling retry make -y and -n unnecessary.
if grep -E '(^|[[:space:]])-[yn]([[:space:]]|$)' "$ffmpeg_calls" >/dev/null; then
  fail "no ffmpeg line ever carries -y or -n" "$(cat "$ffmpeg_calls")"
fi
pass "no ffmpeg line carries -y or -n"
