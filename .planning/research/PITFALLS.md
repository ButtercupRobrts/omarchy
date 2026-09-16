# Pitfalls Research

**Domain:** Shell-script media transcoding UX — adding `--target <size>` two-pass encoding, bitrate derivation, resolution auto-step-down, and a `Custom size…` free-text menu row to `bin/omarchy-transcode` (supersedes the v1.1 pitfalls document, preserved in git history)
**Researched:** 2026-09-16
**Confidence:** HIGH (source-verified against `bin/omarchy-transcode` HEAD, `test/shell.d/transcode-quality-test.sh`, `bin/omarchy-menu-select`, `bin/omarchy-menu-input`, `shell/plugins/menu/Menu.qml`, and PROJECT.md v1.2 scope)

Severity legend: **FATAL** = wrong/corrupt output, data loss, hang, or silent abort the user cannot diagnose. **DEGRADING** = feature works but lies, misleads, or misleads-by-omission. **COSMETIC** = polish debt.

## Critical Pitfalls

### Pitfall 1: Passlog artifacts leak into the user's video directory — and a stale one silently corrupts the next run

**What goes wrong:**
`ffmpeg -pass 2 -passlogfile <prefix>` reads whatever `<prefix>-0.log` exists. If the passlog prefix is derived from the output path in the input's directory (the natural "keep it next to the output" instinct), three things go wrong at once: (a) pass-2 failure or Ctrl-C under `set -e` abandons `out.mp4-0.log` and `out.mp4-0.log.mbtree` (x264) / `.log.cutree` (x265 slow) permanently in `~/Videos`; (b) a *stale* passlog from an aborted earlier run matches the prefix on the next run and pass 2 silently encodes against statistics from a different source — no error, just a wrong-bitrate file; (c) the artifact count is 2–3 files per run, not one, so a single `rm -f "$log"` misses siblings.

**Why it happens:**
`bin/omarchy-transcode` has no `trap` at all today (contrast `omarchy-menu-select` line 84 and `omarchy-menu-input` line 35, which both `trap ... EXIT` their tempfiles). Single-pass ffmpeg writes exactly one file — the output — so nothing in the current code models mid-run scratch state.

**How to avoid:**
`pass_dir=$(mktemp -d)` per run and `-passlogfile "$pass_dir/pass"`; `trap 'rm -rf "$pass_dir"' EXIT` for the abort path *plus* an explicit `rm -rf` after pass 2 so a successful run doesn't wait for script exit. Never point `-passlogfile` at the output dir or at `"$output"`. The unique tempdir also makes stale-passlog reuse impossible by construction.

**Warning signs:**
- `*-0.log*` files visible in `~/Videos` after any aborted or failed run
- Second `--target` run on the same input produces a wildly different size than the first
- Cleanup code that names `.log` but not `.mbtree`/`.cutree`

**Severity:** FATAL (stale passlog → silently wrong encode; leak → permanent litter)

---

### Pitfall 2: Pass-1 argv drifts from pass-2 — the two encodes measure different things

**What goes wrong:**
Two-pass rate control is only valid if pass 1 analyzes the same stream pass 2 encodes. Drift modes specific to this codebase: (a) the mp4 arm currently emits `-crf N` — leaving `-crf` in a `-b:v` command line is contradictory (ffmpeg resolves last-option-wins, so argument *ordering* silently decides which mode actually ran); (b) forgetting `-an` on pass 1 wastes an audio encode and can fail on odd audio streams; (c) pass 1's last positional must be a null target (`-f null /dev/null`), not `"$output"` — getting the output path into pass 1 clobbers/creates the real file twice and breaks the dedupe contract; (d) `-movflags +faststart` on pass 1 is dead weight (null muxer ignores it); (e) a step-down decision computed *between* the passes gives pass 2 a different `-vf scale=` than pass 1 measured.

**Why it happens:**
`transcode_video` (lines 107–148) builds each arm as a single inline command. Adding a second invocation invites "copy the line, tweak two flags" — and every flag not re-examined becomes drift.

**How to avoid:**
Build the shared argv once (an array: input, `-vf`, `-c:v`, `-preset`, `-b:v`, `-passlogfile`) and let each pass append only its deltas: pass 1 → `-pass 1 -an -f null /dev/null`; pass 2 → `-pass 2 -c:a aac -b:a 192k -movflags +faststart "$output"`. Keep `-crf` out of the target path entirely — it belongs to the tier arms only.

**Warning signs:**
- Both `-crf` and `-b:v` on one ffmpeg line
- Pass-1 line ending in `.mp4` instead of a null muxer
- `-vf` or `-c:v` differing between the two recorded lines

**Severity:** FATAL (mode ambiguity and pass mismatch produce output unrelated to the target)

---

### Pitfall 3: Free-text size parsing is the widest new input surface — and bash has no floats

**What goes wrong:**
The `Custom size…` row returns raw `filterText` (Menu.qml line 766 — `applyDmenuSelection(root.filterText)`, verbatim, unvalidated). The parser must decide, for every string: `"25M"`, `"8mb"`, `"0.5G"`, `"25"`, `"25MB"`, `"1K"`, `"10G"`, `"abc"`, `"-5M"`, `" 25M "`, `"25 M"`, `"0"`, `"25.5.2M"`, `""`. Failure modes: decimal targets need `awk` (bash arithmetic is integer-only); a bare `"25"` needs an explicit unit policy (25 MB is the only sane reading for video — 25 bytes is never intended); leading/trailing whitespace and embedded spaces; case (`k`/`K`/`m`/`M`/`g`/`G`, optional `b`/`B`); and **unit-base drift**: `estimate_label` (line 231) uses decimal kbps (`kbps * 125` bytes/s) while displaying MiB — parsing `"25M"` as 25 MiB then deriving bitrate with decimal-kbps math, or vice versa, bakes in a systematic ~5% error on top of container overhead.

**Why it happens:**
Every prior input to this script was whitelisted vocabulary (`high|medium|low`, `mp4|gif`). Free text is the first unbounded value that flows all the way to an ffmpeg numeric argument and into the output filename.

**How to avoid:**
- One canonical regex, e.g. `^[0-9]+(\.[0-9]+)?[kKmMgG][bB]?$` plus an explicit bare-number arm; reject everything else with a message naming the input
- Parse to integer *bytes* in `awk` immediately; every downstream consumer sees one canonical value, never the raw string
- Pick the unit base (recommend MiB to match `estimate_label`/`output_size_label`) and use it identically in the bitrate derivation
- Bound it: refuse below a floor where even 720p + minimum video bitrate + audio can't fit, and handle `target >= source size` explicitly (refuse with "already smaller than target" or warn — decide, don't silently proceed to a pointless re-encode)
- Canonicalize for the filename: if the output name carries the target, use the normalized form (`8mb` → `-8M`), never raw user text — a literal `.` or space in the stem is legal but ugly, and a tab or `/` is a bug

**Warning signs:**
- `"25MB"` rejected while `"25M"` works (or vice versa) — regex drift between documented and tested forms
- Derived `-b:v` of `0k`, negative, or `nan` reaching ffmpeg
- Output filename containing the user's raw input string

**Severity:** FATAL for unvalidated values reaching argv; DEGRADING for inconsistent accept/reject sets

---

### Pitfall 4: The bitrate derivation divides by probed duration — N/A, zero, and tiny durations produce `inf`/`nan` bitrates or absurd `-b:v`

**What goes wrong:**
`video_duration` (lines 162–168) already fails cleanly on `N/A`/probe errors — but in target mode there is *no qualitative fallback*: duration is a hard dependency, unlike the estimate subtexts where failure degrades to "Best quality". If the failing call is captured as `local duration=$(video_duration ...)`, `local` masks the nonzero status (returns 0 with empty output) and the math runs on `""`. Then `target*8/duration` in awk yields `inf` or `-nan`, which becomes `-b:v -nan` or a giga-bitrate — ffmpeg either errors cryptically *after* the start notification or accepts a nonsense rate. Duration `0` or near-zero (sub-second clips, `0.033`) produces Mbps-scale `-b:v` values x264 caps invisibly. Note the existing gate `^[0-9.]+$` also accepts `"1.2.3"` and `"..."` — awk parses a numeric prefix, so it mostly works, but the gate is looser than it looks.

**Why it happens:**
v1.1 trained the pattern "probe failure → degrade to text fallback." Target mode has no fallback to degrade to; it must *refuse*, which is a different code path the existing helpers don't model.

**How to avoid:**
- `duration=$(video_duration "$input") || { echo "...cannot determine duration" >&2; return 1; }` — capture on its own line, never inside `local`
- After math, regex-gate the derived kbps (`^[0-9]+$`, nonzero, sane ceiling) before it touches the argv array — the same "validate inside the helper, before the boundary" discipline `select_quality` uses
- Refusal message goes to stderr *before* the `Transcoding` notification; probe-failure refusal in target mode is honest, not a regression
- For huge derived bitrates (huge target / tiny duration) let it ride — undershoot is the safe direction; ffmpeg/libx264 cap internally. The fatal direction is only the too-small one

**Warning signs:**
- `--target` run on a no-duration file either hangs at the notification or exits with an ffmpeg usage error instead of a clean refusal
- `-b:v` values like `-nan`, `inf`, `0k`, or nine-digit kbps in the recorded argv

**Severity:** FATAL

---

### Pitfall 5: Target smaller than the audio stream alone — fixed 192k audio eats the whole budget

**What goes wrong:**
`-b:a 192k` is hardcoded (lines 135, 137). On a 10-minute clip, audio alone is ~14 MB — a `10M` target yields a *negative* video bitrate. Passing `-b:v -500` or `-b:v 0k` to ffmpeg fails or clamps unpredictably. Even positive-but-tiny budgets hit the encoder's practical floor: x264 will not actually encode at 50 kbps — it undershoots the *request* but the output still exceeds the target, so the file "misses" with no warning.

**Why it happens:**
The derivation `video_kbps = target_kbps − audio_kbps` assumes audio is small relative to target — true for the intended use case, false exactly when users push the feature hardest (tiny targets, long clips).

**How to avoid:**
- Floor-check *before* encoding: compute `min_feasible = (audio_kbps + video_floor_kbps) * duration * 125` and refuse below it, naming the smallest achievable size — PROJECT.md already commits to "honest refusal below every floor"
- Decide the tiny-target audio policy deliberately: keep 192k and refuse earlier (simplest, honest), or scale `-b:a` down (96k/64k/mono) — but if `-b:a` varies, the *math* must use the same value the flag uses; one constant, single source
- Reuse `video_audio_kbps` (172–178) for the audio term: it returns 0 for proven-no-audio and the conservative 192 on probe failure — over-estimating audio is the safe direction

**Warning signs:**
- `-b:v` below ~100k or negative in argv
- Target runs that "succeed" but produce files 2–3× the target
- `--target 5M` accepted on an hour-long source

**Severity:** FATAL (negative bitrate → broken run; floored bitrate → guaranteed overshoot presented as success)

---

### Pitfall 6: Systematic overshoot — container overhead, VBR rate-control error, and audio estimate error all push the same direction

**What goes wrong:**
Two-pass VBR hits the *average* bitrate, not the byte size; mp4 container overhead is ~1–3%; the audio term is an estimate (real AAC at `-b:a 192k` lands close but not exact); at very low video bitrates the encoder's floor dominates. All error terms push *upward*: a "25M" target routinely delivers 26–28 MB — which fails the actual use case (upload caps like Discord's). Undershoot never happens the other way at these rates.

**Why it happens:**
The naive formula budgets 100% of target to streams. Nothing in the pipeline reserves margin.

**How to avoid:**
- Budget streams to ~90–95% of target (e.g. `usable = target_bytes * 95 / 100`), or subtract a fixed overhead estimate — pick one policy and pin it in tests
- After pass 2, `stat` the output and compare: the done notification already reports actual size (SIZE-02); on miss beyond tolerance, make the notification honest — e.g. "Saved (28 MB, over 25M target)" — rather than silently reporting a size that reads as success. Decide once whether overshoot is warn-only or triggers a retry at lower res; warn-only is the defensible default
- Do not chase byte-exactness by re-encoding: diminishing returns, and the retry loop is where set -e edge cases breed

**Warning signs:**
- Every target run lands a few percent over, never under
- Overshoot scales with clip length (audio estimate error) or with *shortness* (header overhead)

**Severity:** DEGRADING (lies by omission — the headline feature silently misses its only promise)

---

### Pitfall 7: Resolution step-down decided after `output_path` → the filename and notification lie about resolution

**What goes wrong:**
`output_path` (lines 49–73) is computed once in `main()` (line 415) from the *requested* resolution, before the encode. If auto-step-down lives inside `transcode_video` (the natural place — it's an encoding concern), a 4k request that steps to 720p still writes `in-4k.mp4` and notifies "Transcoded to 4k mp4". Silent downgrade is worse than refused downgrade: the user asked for 4k, got 720p, and the tool insists it's 4k.

**Why it happens:**
Step-down needs the derived bitrate, which needs duration — all of which is knowable *before* `output_path`. But the tiered-encode structure invites doing it lazily inside the encode function.

**How to avoid:**
- Resolve the full plan — effective resolution, `-b:v`, `-b:a` — in `main()` *before* `output_path`, so the filename, start notification, and argv all carry the stepped resolution. This mirrors the v1.1 fix that hoisted format/resolution validation ahead of the notification (c1947f8d)
- The step-down floor table (min acceptable kbps per resolution) is a new locked constants table — give it the same treatment as `quality_kbps` (218–223): explicit, commented, test-pinned at each boundary
- Notify the step: the start notification or done notification should say "1080p (stepped down from 4k)" or equivalent — a silent step is a UX bug even when the filename is right
- At 720p with still-insufficient budget: refuse (per PROJECT.md), don't invent a 480p tier outside the locked vocabulary — `output_path`, usage text, and `case` arms all assume {4k,1080p,720p}

**Warning signs:**
- Output named `-4k.mp4` containing a 720p stream
- Start notification naming a resolution the encode didn't use
- A new resolution token appearing in `output_path` names but rejected by the `case` arms

**Severity:** FATAL as a lie (filename/notification); the downgrade itself is legitimate if disclosed

---

### Pitfall 8: The `Custom size…` row dies inside `select_quality`'s whitelist — or worse, reaches ffmpeg as a "quality"

**What goes wrong:**
`select_quality` (lines 279–285) re-validates the stripped label against exactly `high | medium | low` and returns 1 otherwise — that guard is doing its job and will reject `Custom size…` unless the code branches *before* the case. The naive fix (adding `custom` to the case) then leaks a non-tier token toward `transcode_video`'s quality case and `output_path`'s suffix logic. Also: picking the row must summon a *second* menu (`omarchy-menu-input` exists — mode `"input"` is already wired in Menu.qml lines 765–766), and its return is raw text needing Pitfall 3's full validation; empty input means Esc → exit 1 → silent abort under `set -e`, consistent with sibling prompts.

**Why it happens:**
The row is visually part of the quality menu but semantically switches the entire encoding strategy — it changes which *kind* of answer the menu produces, and every downstream consumer (`output_path` naming, `transcode_video` branching, the quality case) assumed tier vocabulary.

**How to avoid:**
- Branch on the custom label immediately after the `${selection%%$'\t'*}` strip, before the tier `case` — then prompt `omarchy-menu-input "Target size (e.g. 25M)"`, validate to canonical bytes, and set the same internal `target` variable `--target` sets (one code path for both entry points)
- Give the row a subtext (`"Enter a size like 25M"`) — v1.1 established that mixed subtext/no-subtext rows produce uneven heights that look broken
- Never offer the row for gif (Pitfall 10) — the row set must differ per format
- Re-prompt vs reject on bad input: a single clear error and abort matches the script's fail-fast posture; a re-prompt loop is nicer but adds a loop that must also honor Esc

**Warning signs:**
- Picking `Custom size…` exits with `Invalid video quality: Custom size…`
- The input prompt never appears, or its output is used unvalidated
- gif's quality menu grows a size row

**Severity:** FATAL (dead menu row / unvalidated input to argv)

---

### Pitfall 9: `--target` interacts with every existing arg — quality positional, gif, pictures, `--` — and each pairing needs a verdict

**What goes wrong:**
The flag parser (lines 305–331) currently knows `--path`, `--help`, `--`. Adding `--target <size>` raises a matrix: `--target` + 4th-positional quality (two competing encode intents — must be rejected, not last-wins); `--target` on a picture input (mirror the existing "quality applies to videos only" rejection at 349–352); `--target` + gif (palette encode ignores `-b:v` — refuse per PROJECT.md); `--target` + empty value (`--target` last arg → missing-value error like `--path` at 309); `--target` after `--` (lands in positionals — a stray `--target` as positional[4]+ is silently dropped today, see deferred issue); `--target` while quality is unset interactively (must skip `select_quality` entirely — don't prompt for a tier then ignore it, and don't prompt for size twice if the user picks `Custom size…` anyway).

**Why it happens:**
Each pairing is individually small; the matrix is emergent. The existing code's discipline — all validation in `main()` before menus and the start notification — is exactly where these checks must live.

**How to avoid:**
- Write the accept/reject matrix down in the plan before coding; one `case` block validating `--target` against `type`, `format`, and `quality` presence
- When `--target` is set, skip `select_quality` (line 411–413 gates on `-z $quality` — target mode needs its own gate)
- Sync `usage()`, `# omarchy:args=`, `# omarchy:examples=`, the skill doc, and the manual in the same commit — `test/cli` metadata assertions pin the header shape

**Warning signs:**
- `omarchy transcode in.mov mp4 1080p low --target 25M` silently encoding one mode or the other
- `--target` + gif producing a normal gif run
- Interactive target run still firing the quality menu

**Severity:** FATAL for the intent-conflict pairings; COSMETIC for docs drift (but test/cli will catch the header)

---

### Pitfall 10: gif + target is a dead combination, and "refuse" must happen before the notification

**What goes wrong:**
gif output is a palette-quantized image sequence — `-b:v` does nothing. Accepting `--target` on a gif run produces a file whose size has no relationship to the request. PROJECT.md already says refuse; the pitfall is *where*: the format is known only after format selection (interactive) or positional parse, and the refusal must precede the `Transcoding` toast (line 418) — the orphan-toast bug v1.1 fixed (c1947f8d) is the exact shape of this mistake.

**Why it happens:**
Interactive gif flow prompts format *then* resolution *then* quality — a `--target` rejection can be checked as soon as `format` resolves; `Custom size…` must simply not appear in gif's row set.

**How to avoid:**
Validate `target` × `format` in the same block that validates format/resolution (lines 379–409), before `select_quality` and before the notification. Error message names the combination: `--target applies to mp4 only`.

**Warning signs:**
- `omarchy transcode in.mov gif 720p --target 25M` running a full palette encode
- Start notification appearing, then the refusal

**Severity:** DEGRADING (wasted work + broken promise), FATAL-adjacent if it ships the orphan toast

---

### Pitfall 11: Test-harness traps — an unstubbed `omarchy-menu-input` hangs the suite forever; the ffmpeg stub isn't pass-aware

**What goes wrong:**
Four distinct harness landmines, all in `transcode-quality-test.sh`:

1. **`omarchy-menu-input` is not stubbed.** A test row that picks `Custom size…` makes the real script invoke the real `omarchy-menu-input`, which calls `omarchy-shell shell summon` then spins `while [[ ! -e $done_file ]]; sleep 0.05` (lines 50–52) — an infinite wait. The suite doesn't fail; it *hangs*. Fatal for CI.
2. **The ffmpeg stub writes `"${!#}"` (last positional) as the output.** Pass 1's last positional is `/dev/null` → `truncate -s "$FAKE_OUT_BYTES" /dev/null` errors inside the stub → stub exits nonzero → reads as "encode failed". The `out=` line for pass 1 records `/dev/null`, polluting `out=` assertions. The stub must dispatch on `-pass`/`passlogfile` presence, synthesize the passlog files (so cleanup assertions have artifacts to check), and only `truncate` on pass 2.
3. **`FAKE_ENCODE_RC` applies to every invocation.** Can't express "pass 1 ok, pass 2 fails" — the exact scenario that exercises passlog cleanup-on-abort. Need per-pass knobs (e.g. stub exits `${FAKE_PASS2_RC:-${FAKE_ENCODE_RC:-0}}` when argv contains `-pass 2`).
4. **Two `^ffmpeg ` lines per run.** Existing patterns like `grep '^ffmpeg ' "$calls" >file` capture both passes; `cmp` against a single-line expected argv fails; `head -n1` picks pass 1, not the pass that matters. `run_transcode`'s env doesn't export `TMPDIR`, so a script-side `mktemp -d` lands in real `/tmp` — passlog cleanup is then unobservable inside the sandbox.

**Why it happens:**
The harness's core assumption — one encoder invocation per run, output always last positional — is broken by two-pass in exactly the dimensions the stubs hardcoded.

**How to avoid:**
- Stub `omarchy-menu-input` with a `FAKE_INPUT` knob (empty = Esc → exit 1, matching the menu-select stub's `FAKE_PICK` semantics) and a `menu-input:` call-log line — do this in the *same* commit that adds the menu row, not later
- Make the ffmpeg stub inspect argv: `[[ " $* " == *" -pass 1 "* ]]` → log line, create `"$FAKE_PASSLOG"-0.log{,.mbtree}` or just touch passlog-path-derived files, write nothing else; `-pass 2` → `truncate` the real output
- Export `TMPDIR="$TMPDIR"` in `run_transcode`'s env so script-side `mktemp -d` is sandbox-observable (also keeps test passlogs out of real `/tmp`)
- Add a per-run assertion mode that greps `^ffmpeg .* -pass 2` specifically; pin *both* pass argvs literally (the file's own style — expected-argv files at lines 143–148 — extends naturally to two files)
- Assert post-conditions on artifacts: after a `FAKE_PASS2_RC=1` run, zero `*-0.log*` files remain under the sandbox `TMPDIR` — that single assertion catches Pitfall 1's whole class

**Warning signs:**
- Suite hangs rather than fails when the `Custom size…` path is exercised
- `truncate` errors or `out=/dev/null` in the call log
- Tests green while real runs leak passlogs — artifacts invisible because `TMPDIR` wasn't exported

**Severity:** FATAL (hanging suite; green-tests-over-broken-behavior)

---

### Pitfall 12: Two passes, one notification, zero progress — doubled encode time reads as a hang

**What goes wrong:**
The single "Transcoding video…" toast (line 418) precedes what is now 2× the encode time — and at 4k the x265 arm uses `-preset slow`, so `--target` + 4k can run tens of minutes with one static notification. Via the detached menu path there's no terminal, no stderr progress, nothing. Users will kill it or report it hung. (v1.1's performance table already flagged single-pass 4k/high as borderline.)

**Why it happens:**
Notifications are per-run, not per-phase; nothing in the current tail (417–422) models progress between start and done.

**How to avoid:**
- Minimum viable: pass-scoped notifications — "Transcoding video (pass 1/2)…", then "(pass 2/2)" — cheap, honest
- Or one notification whose body sets expectations: "two-pass encode, ~2× normal time, target 25M"
- Decide x265-at-4k deliberately: two slow x265 passes is the worst case; forcing x264 or a faster preset in target mode is a legitimate scope decision, but it changes the codec the user gets vs tier mode — document whichever is chosen
- Keep the done notification's actual-size report (SIZE-02) — in target mode it doubles as the hit/miss report (Pitfall 6)

**Warning signs:**
- Dogfooding: 4k target run appears dead for minutes
- Notifications identical whether one pass or two are running

**Severity:** DEGRADING (UX) — encode still completes

---

## Technical Debt Patterns

|| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
||----------|-------------------|----------------|-----------------|
|| Passlog prefix = output path in output dir | No tempdir code | Stale-passlog corruption + permanent `-0.log` litter; cleanup-by-name misses `.mbtree`/`.cutree` | Never — `mktemp -d` + trap is ~3 lines |
|| Reuse tier `-crf` line, append `-b:v` | Small diff | Last-option-wins ambiguity; which mode ran depends on argument order | Never — separate argv construction |
|| Parse size with `numfmt --from=auto` | One-liner | `numfmt`'s accept set (units, `B` suffixes, decimals, lowercase) isn't the documented one; error handling under `set -e` is fuzzier than a pinned regex | Only if tests pin numfmt's exact accept/reject set |
|| Keep 192k audio always, floor-check later | No new audio policy | Math and flag can silently disagree if `-b:a` is ever lowered for tiny targets | Acceptable iff the kbps constant is shared by math and argv |
|| Step-down inside `transcode_video` | Encoding logic stays together | `output_path` already ran → filename lies about resolution | Never — plan in `main()`, execute in `transcode_video` |
|| Byte-exact retry loop on overshoot | "Really hits target" | Re-encode loop + set -e edge cases; VBR won't converge byte-exact anyway | Never — margin + honest miss report instead |
|| New 480p/360p floor below 720p | Fewer refusals | New resolution vocabulary ripples into `output_path`, usage, `case` arms, tests | Only as its own scoped change |

## Integration Gotchas

|| Integration | Common Mistake | Correct Approach |
||-------------|----------------|------------------|
|| ffmpeg `-pass` | Assuming one `-0.log` artifact | x264: `-0.log` + `-0.log.mbtree`; x265 slow: adds `.cutree`. Tempdir glob-free cleanup beats name math |
|| ffmpeg pass 1 | Reusing the real output path | `-f null /dev/null`, `-an`, no `-movflags`; shared argv array + per-pass deltas |
|| `-crf` vs `-b:v` | Both flags on one line | ffmpeg resolves last-wins; keep them in disjoint branches |
|| `ffprobe` duration | Reusing `select_quality`'s degrade-to-text habit | Target mode has no fallback — refuse cleanly, stderr, before notification |
|| `omarchy-menu-input` | Treating its return like a menu pick | It's raw `filterText`: unbounded, unvalidated, empty-on-Esc. Full regex validation before it touches anything |
|| `omarchy-menu-select` row for `Custom size…` | Adding it to the tier `case` | Branch on the label *before* the whitelist; also give it a subtext (uniform row heights) |
|| `mktemp -d` in script | Test sandbox can't see artifacts | `mktemp` honors `TMPDIR`; harness must export it in `run_transcode`'s env |
|| `output_path` | Passing raw user text ("25 MB") as a name component | Canonicalize first (`-25M`); dedupe still handles collisions |
|| `omarchy-notification-send` | One start toast for two passes | Pass-scoped or expectations-setting body; glyph arg unchanged |
|| Nautilus `transcode.py` | Forgetting it's a consumer | Path-only invocation → interactive flow gets one more possible round-trip (quality menu → input menu); acceptable, note it |
|| `test/cli` metadata | Editing `usage()` only | `# omarchy:args=`/`# omarchy:examples=` headers asserted separately — sync all three in the same commit |

## Performance Traps

|| Trap | Symptoms | Prevention | When It Breaks |
||------|----------|------------|----------------|
|| x265 `-preset slow` two-pass at 4k | 2× an already multi-minute encode; notification frozen | Decide codec/preset policy for target mode explicitly; at minimum warn in the start toast | Any 4k source on laptop CPU |
|| Duration probe now on the non-interactive path | `--target` run does an extra ffprobe before encoding | Required for the math — it's ~ms locally; only compute when target is set (never probe for tier runs, preserving the four-positional no-probe pin at test line 417) | Network/FUSE mounts only |
|| Pass 1 encoding audio | +1 wasted stream encode | `-an` on pass 1 | Weird audio inputs can also fail pass 1 outright |
|| Refusal checks after probing | Slow-fail on inputs that were always going to be refused | Order: parse target → validate format/type → probe → math → floors | Only latency, never correctness |

## Security / Input-Safety Mistakes

|| Mistake | Risk | Prevention |
||---------|------|------------|
|| Raw size string into output filename | `/`, tab, `..` in stem | Canonicalize to bytes/normalized label before `output_path`; never interpolate raw input |
|| Raw size string into ffmpeg args | `-b:v` built from unvalidated text | Only the awk-derived integer kbps may reach argv — regex-gate the derived value too |
|| `eval`/string-built commands for size math | Injection via crafted input | awk assignment args (`-v`), exactly as `estimate_label` already does (lines 230–239) |
|| ffprobe output as arithmetic input | Crafted container → weird duration | Existing regex gate + the new `duration > 0` check before dividing |
|| Passlog tempdir cleanup | `rm -rf "$var"` footgun if var empty under `set -u` | `mktemp -d` can't return empty on success; guard anyway: `[[ -n $pass_dir && -d $pass_dir ]]` in the trap |

## UX Pitfalls

|| Pitfall | User Impact | Better Approach |
||---------|-------------|-----------------|
|| Silent resolution step-down | Asked 4k, got 720p, tool says 4k | Plan before `output_path`; name the effective res in filename + both notifications |
|| "Target hit but unwatchable" | 25M on a 3-hour clip = smeared mush | Floors + honest refusal ("smallest achievable: ~XM at 720p") beat compliant garbage |
|| Refusing with no explanation | Feature feels broken | Refusal names *why* (audio floor / below all floors / exceeds source) |
|| Target ≥ source size | Pointless re-encode, quality loss | Refuse or warn explicitly — v1.1's `larger than source` degrade is the precedent |
|| Overshoot reported as success | "25M" → 28 MB, no mention | Done notification states miss honestly; margin budgeting shrinks how often |
|| Bare `25` ambiguity | 25 bytes? 25 MB? | Pick MB, document in usage/error text, test-pin |
|| Prompt fatigue (quality → input → per-file in Nautilus) | Interactive flow lengthens again | `--target` skips the quality menu entirely; `Custom size…` is opt-in |
|| Esc on size input | Silent abort | Consistent with sibling prompts; acceptable |

## "Looks Done But Isn't" Checklist

- [ ] **Passlog cleanup on abort:** `FAKE_PASS2_RC=1` (or pass-1 failure) leaves zero `*-0.log*` under sandboxed `TMPDIR` — and the done notification never fires
- [ ] **Pass argv pin:** pass 1 carries `-pass 1 -an -f null /dev/null` and no `-crf`, no output path, no `-movflags`; pass 2 carries `-pass 2`, `-b:v Nk`, `-c:a aac -b:a 192k`, `+faststart`, the deduped output — `-vf`/`-c:v` identical across passes
- [ ] **Duration refusal:** `FAKE_DURATION=N/A` + `--target` exits nonzero with a stderr message *before* the start notification — no qualitative fallback invented
- [ ] **Size-parse matrix:** pins for `25M`, `8mb`, `0.5G`, `25`, `25MB`, `1K`, `10G`, `abc`, `-5M`, `0`, ` 25M` — accept set and per-rejection stderr text both pinned
- [ ] **Audio-floor refusal:** target below `(audio + video floor) × duration` refuses naming the achievable minimum; no negative/zero `-b:v` ever recorded
- [ ] **Step-down honesty:** a 4k request under budget steps to a lower res — output filename and notifications carry the *stepped* resolution
- [ ] **Floor refusal at 720p:** insufficient budget at the lowest tier refuses, no new resolution tokens appear anywhere
- [ ] **`--target` × quality conflict:** `--target 25M ... low` (either order) exits nonzero naming the conflict; `--target` + gif/picture rejected pre-notification
- [ ] **Interactive parity:** `Custom size…` pick → input stub value `25M` produces byte-identical argv to `--target 25M`; Esc on the input aborts before the notification
- [ ] **Tier path untouched:** all existing pins still pass — four-positional runs never probe (no `^ffprobe:` line), medium argv byte-identical, no overwrite flag on any ffmpeg line including both passes
- [ ] **Harness hygiene:** `omarchy-menu-input` stubbed (no hang), `TMPDIR` exported, `out=` assertions filter to the pass-2 line

## Recovery Strategies

|| Pitfall | Recovery Cost | Recovery Steps |
||---------|---------------|----------------|
|| Leaked passlogs in user dirs | LOW | `rm` the `-0.log*` files; switch to tempdir |
|| Stale passlog corrupted an encode | LOW | Re-run after cleanup; file is just wrong-sized |
|| Step-down filename lie shipped | MEDIUM | Rename doesn't fix the wrong res — re-encode; fix planning order |
|| Size parser too strict/loose | LOW | Adjust regex; pins document intent |
|| Overshoot beyond margin | LOW | Shrink margin constant or tighten audio estimate; user re-runs with smaller target |
|| Unstubbed menu-input hang | LOW | Kill test shell; add stub — no code damage |
|| Orphan toast on target refusal | LOW | Move check above notification line — v1.1 fixed this exact shape (c1947f8d) |

## Pitfall-to-Phase Mapping

Phases aren't written yet; map by feature surface.

|| Pitfall | Prevention lands with | Verification |
||---------|----------------------|--------------|
|| 1. Passlog lifecycle | First commit that adds `-pass` | Abort mid-run → no artifacts; stale-passlog reuse impossible (tempdir) |
|| 2. Pass-1/2 argv drift | Same | Literal two-argv pin; `-vf`/`-c:v` identical, `-crf` absent |
|| 3. Free-text parse | `--target` flag commit | Full accept/reject matrix pinned, incl. bare number + decimals + bounds |
|| 4. Duration dependency | Same | N/A/zero-duration refusal before notification |
|| 5. Audio floor | Bitrate-derivation commit | Below-floor refusal names achievable min; no bad `-b:v` |
|| 6. Overshoot margin | Same | Post-encode size check; honest miss notification |
|| 7. Step-down ordering | Step-down commit | Filename + notifications carry effective resolution |
|| 8. `Custom size…` row | Menu-row commit | Branch before whitelist; input stubbed; interactive ≡ `--target` argv |
|| 9. Flag matrix | `--target` flag commit | Each pairing's verdict pinned (quality-conflict, gif, picture, missing value) |
|| 10. gif refusal | Same | Rejection precedes notification |
|| 11. Harness traps | Same commit as the feature — not a follow-up | Suite can't hang; per-pass RC knobs; `TMPDIR` exported |
|| 12. Progress/2× time | Two-pass commit | Pass-scoped or expectation-setting notifications |

## Sources

- `bin/omarchy-transcode` (full read — arg parser 305–331, `output_path` 49–73, `transcode_video` 107–148, `video_duration` 162–168, `video_audio_kbps` 172–178, `select_quality` whitelist 279–285, validation-before-notification structure, no `trap` anywhere)
- `test/shell.d/transcode-quality-test.sh` (full read — stub writes `"${!#}"`, `FAKE_ENCODE_RC`/`FAKE_OUT_BYTES`/`FAKE_PICK`/`FAKE_DURATION` knobs, `run_transcode` env at 123–132 lacks `TMPDIR` export, single-ffmpeg-line assumptions throughout)
- `bin/omarchy-menu-input` (full read — raw-text return, `done_file` spin-wait that hangs when unstubbed, `trap ... EXIT` pattern)
- `bin/omarchy-menu-select` (full read — post-`--` arg pattern, `trap` pattern, label⇥subtext return contract)
- `shell/plugins/menu/Menu.qml` — input mode already wired: `mode === "input"` returns `filterText` verbatim (line 766), no row cursor in input mode (726)
- `.planning/PROJECT.md` v1.2 scope — "honest refusal below every floor", gif refuses `--target`, `Custom size…` row via Menu.qml input mode
- `.planning/milestones/v1.1-ROADMAP.md` — deferred issues (TOCTOU dedupe, `positional[5]+` dropped) and fixed-issue shapes to reuse (orphan toast c1947f8d, `%.0f` rounding, `<1 MB` band)
- ffmpeg two-pass semantics — `-passlogfile` artifact naming (`-0.log`, `.mbtree`, `.cutree`), pass-1 `-an -f null /dev/null`, `-crf`/`-b:v` last-wins, encoder rate floors, container overhead
- Omarchy `AGENTS.md` — `[[ ]]`/`(( ))`, atomic commits, `#!/bin/bash`, `(( ))` status-1-on-zero footgun under `set -e`

---
*Pitfalls research for: `--target` two-pass size targeting in omarchy-transcode (v1.2)*
*Researched: 2026-09-16*
