---
phase: 09-interactive-custom-size-row
reviewed: 2026-09-17T12:44:53Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - bin/omarchy-transcode
  - test/shell.d/transcode-quality-test.sh
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: resolved
---

# Phase 9: Code Review Report

**Reviewed:** 2026-09-17T12:44:53Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** resolved — WR-01 fixed (sentinel branch mp4-gated, forged-pick pin added); IN-01 fixed (doc comment); IN-02 deferred — one defense-in-depth warning (sentinel branch accepts the `Custom size…` label on formats that never offer it), two info items

## Summary

Reviewed commit `1fd54ced` (`bin/omarchy-transcode` +43/−1, `test/shell.d/transcode-quality-test.sh` +204/−1) against the locked contract in `09-CONTEXT.md`, the must_haves in `09-01-PLAN.md`, and the §4 anti-pattern list in `09-PATTERNS.md`. The implementation is faithful to the plan and the core mechanics verify end to end:

- **Sentinel containment (mp4 path):** the row is appended last, mp4-gated (:279), single-sourced via `$custom_label`/`$custom_subtext` (:250), and the label is one U+2026 char (byte-verified `E2 80 A6`). The post-strip branch (:285-289) mints `target:<bytes>` straight to the return channel — the label never re-enters the whitelist, and the `bogus\tjunk` pin stays green.
- **`main()` unwrap** (:638-644): inside the `-z $quality && -z $target_bytes` gate, so a CLI `--target` run can never see a sentinel it did not mint. `quality=""` prevents `target:<n>` from reaching `output_path`'s suffix or `transcode_video`'s tier case; the `^[0-9]+$` guard is correct belt-and-braces (the mint is digits by construction — `prompt_target_size` only prints `parse_target_size` output).
- **Three-state semantics:** exit 1 (Esc) → `|| return 1` cancels pre-notification; exit-0-with-empty (empty submit) rides through `parse_target_size` and buys the one hinted re-prompt; valid → bytes. Matches the real binary's `[[ -s $selection_file ]]` contract (`bin/omarchy-menu-input:54-57`).
- **Re-prompt budget:** `for attempt in 1 2` is a hard bound — exactly one retry, hint `Invalid size — e.g. 25M` (U+2014, byte-verified identical in script and test greps) only after a failed parse, planner refusals never re-prompt (D-01).
- **No `local x=$(…)` masking** in new code (:250, :344 are plain declarations; captures ride `if` conditions or `||` chains), and no stray stdout in either `$( )` helper — `omarchy-menu-input` output is captured into `answer`, `parse_target_size` into `bytes`, only `printf` writes the return channel.
- **Stub fidelity:** `menu-input: %s` logged before the decision, `n=$(grep -c '^menu-input:')` counts off the just-logged line, `FAKE_INPUT`/`FAKE_INPUT$n` per-invocation knobs, unset = exit-1 Esc/tripwire, set-empty = exit-0 empty submit. A hypothetical 3rd prompt would hit an unset `FAKE_INPUT3` → exit 1 (cancel) and the `-eq 2` count assertions still catch it — no false-green vector found.
- **Byte-parity:** `sed 's|transcode-2pass\.[^/ ]*|transcode-2pass.X|'` applied identically on both greps before `cmp -s`; the `[^/ ]*` pattern covers the mktemp `XXXXXX` suffix and both runs share the same TMPDIR prefix. The checker-flagged saved-log hazard is handled via `cp` to `calls-custom`/`stderr-custom` immediately after the Custom run.
- **Additive-diff holds:** exactly one removed line per file (:250 locals; the `for bad in` loop). `usage()`/`args=`/`examples=`, `omarchy-menu-select`, `omarchy-menu-input`, and all QML untouched.

Verified green live: `bash -n` exits 0; `bash test/shell.d/transcode-quality-test.sh` → 92 `ok`, 0 `not ok`; `./test/cli` → exit 0.

## Warnings

### WR-01: The sentinel branch accepts `Custom size…` on formats that never offer the row

**File:** `bin/omarchy-transcode:285-289`
**Issue:** The sentinel row is appended only for mp4 (`[[ $format == "mp4" ]] && rows+=(…)` at :279), but the *acceptance* branch at :285 is not format-gated: `[[ $selection == "$custom_label" ]]` fires for gif runs too, since `select_quality` serves both formats. Verified live: a gif run whose menu returns `Custom size…` fires `omarchy-menu-input`, mints `target:<bytes>`, passes the `main()` unwrap, runs `plan_target`, and `transcode_video_target` writes libx264/mp4 content to `in-720p-25M.gif` while toasts claim "to gif" — an unexplained input prompt plus a format/content-mismatched output.

Reachability requires `omarchy-menu-select` to return a label that was never in its argv — not possible through the real pick-list UI today. But the phase's own threat model (T-09-01, rated high) treats the menu→strip boundary as untrusted, and the `bogus\tjunk` pin exists precisely because foreign labels are expected to die at the whitelist. As shipped, the sentinel branch is a side-door that whitelists `Custom size…` for every format the function serves, including ones where the label was never a legitimate choice. The fix is one condition and the gif pin at test:602-604 only proves the row isn't *offered* — nothing pins that a forged gif sentinel is *refused*.

**Fix:** Gate the branch on format so a forged sentinel on a non-mp4 run falls through to the `*)` whitelist arm like every other foreign label:

```bash
  if [[ $format == "mp4" && $selection == "$custom_label" ]]; then
    bytes=$(prompt_target_size) || return
    printf 'target:%s' "$bytes"
    return
  fi
```

And add the refusal pin to the gif block or the Custom section:

```bash
status=0
FAKE_PICK=$'Custom size…\tEnter a size like 25M' \
  run_transcode "$TMPDIR/in.mov" gif 720p || status=$?
[[ $status -ne 0 ]] || fail "a forged Custom pick on gif is refused" "exit=$status"
grep -F 'Invalid video quality' "$TMPDIR/stderr" >/dev/null ||
  fail "a forged gif sentinel dies at the whitelist" "$(cat "$TMPDIR/stderr")"
if grep -q '^menu-input:' "$calls"; then
  fail "a forged gif sentinel never fires the input prompt" "$(cat "$calls")"
fi
```

## Info

### IN-01: `select_quality`'s doc comment no longer describes the return contract

**File:** `bin/omarchy-transcode:243-247`
**Issue:** The comment block still says the function "prints the picked tier" and that "a foreign label dies inside the helper … never reaching output_path or ffmpeg." It never mentions the new third return shape — `target:<bytes>` minted for a Custom pick — which is the contract `main()`'s unwrap depends on. The sentinel branch's own inline comment (:277-278) covers the label-as-key mechanism but not the `target:` return channel.
**Fix:** Extend the header comment with one line noting the function prints either a tier name or `target:<bytes>` for the Custom size pick.

### IN-02: Mint-guard exit code diverges from the same error class at the `--target` arm

**File:** `bin/omarchy-transcode:640-641` vs `:515`
**Issue:** The `^[0-9]+$` guard prints `Invalid target size: <n>` and `return 1`; the identical message class from `--target` parse failures exits 2 (`|| return 2`). The guard is unreachable by construction — `prompt_target_size` only prints `parse_target_size` output, which is always digits — so this is a consistency note, not a live bug; exit 1 is also defensible since the path is a menu-internal contract violation, not a usage error.
**Fix:** Optional — if the message shape is intentionally mirrored, either match the exit code or leave a comment noting the path is unreachable defensive validation.

---

_Reviewed: 2026-09-17T12:44:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_

## REVIEW COMPLETE

- Critical: 0
- Warning: 1
- Info: 2
- Total: 3
