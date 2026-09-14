#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
eval_out="$test_tmp/hyprctl-eval"
home_dir="$test_tmp/home"
monitor_lua="$home_dir/.config/hypr/monitors.lua"
scale_log="$home_dir/.local/state/omarchy/monitor-scaling.log"

mkdir -p "$stub_bin" "$home_dir/.config/hypr"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  internal=$(printf '{"name":"eDP-1","focused":true,"scale":%s,"width":%s,"height":%s,"refreshRate":120.0,"x":0,"y":0,"description":"%s","make":"%s","model":"%s","serial":"%s"}' \
    "${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    "${OMARCHY_TEST_MONITOR_WIDTH:-2880}" \
    "${OMARCHY_TEST_MONITOR_HEIGHT:-1800}" \
    "${OMARCHY_TEST_MONITOR_DESCRIPTION:-BOE NE180WUM}" \
    "${OMARCHY_TEST_MONITOR_MAKE:-BOE}" \
    "${OMARCHY_TEST_MONITOR_MODEL:-NE180WUM}" \
    "${OMARCHY_TEST_MONITOR_SERIAL:-0x00000001}")
  if [[ ${OMARCHY_TEST_EXTERNAL_MONITOR:-0} == "1" ]]; then
    printf '[%s,%s]' "$internal" \
      '{"name":"HDMI-A-1","focused":false,"scale":1.6,"width":1920,"height":1080,"refreshRate":144.0,"x":-1200,"y":0,"description":"Samsung C27JG5x","make":"Samsung","model":"C27JG5x","serial":"H4ZM800123"}'
  else
    printf '[%s]' "$internal"
  fi
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

write_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
LUA
}

# The shipped pairing: the generic catch-all handing omarchy_monitor_scale to
# unlisted outputs, plus a named rule for the internal panel. Persistence must
# rewrite the named rule in place and leave the catch-all and variable alone.
write_named_rule_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })
LUA
}

# A named rule that hands its scale to the shared variable: targeting pins the
# rule to a literal while the variable itself is left alone.
write_named_var_rule_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1.5
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA
}

# The nwg-displays shape: a rule spread over several lines. Only the scale
# line may change; every other line stays byte-identical.
write_multiline_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "auto",
  scale = 1.5
})
LUA
}

# A transform-only rule names no scale at all, so one is inserted inside the
# closing brace rather than appended as a new rule.
write_scaleless_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", transform = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# A rule keyed by a desc: selector (with stray spaces, as Hyprland tolerates)
# that prefix-matches the stubbed monitor description.
write_desc_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "desc:  Acme  ", mode = "preferred", position = "auto", scale = 1.5 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# A rule that only exists inside a line comment is not a rule.
write_commented_rule_config() {
  cat >"$monitor_lua" <<'LUA'
-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# Nor is one fenced inside a multi-line --[[ ]] block comment.
write_block_comment_rule_config() {
  cat >"$monitor_lua" <<'LUA'
--[[
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })
]]
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# Nor is one fenced inside a levelled --[==[ ]==] block comment, which Lua
# treats exactly like --[[ ]] but only closes on the matching ]==].
write_levelled_comment_rule_config() {
  cat >"$monitor_lua" <<'LUA'
--[==[
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })
]==]
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# Nor is one sitting inside a levelled [=[ ]=] long string.
write_levelled_string_rule_config() {
  cat >"$monitor_lua" <<'LUA'
local s = [=[ hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 9 }) ]=]
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# A scale key inside a nested table is not the scale of the rule: only the
# top-level scale may be rewritten.
write_nested_scale_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", extra = { scale = 99, top = 24 }, scale = 1.5 })
LUA
}

# An output selector inside a nested table does not make the rule belong to
# that output either.
write_nested_output_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ extra = { output = "eDP-1" }, output = "DP-2", scale = 1.5 })
LUA
}

# A scale handed an expression is replaced whole: truncating at the comma
# inside the call would splice invalid Lua into the file.
write_expression_scale_rule_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = math.max(1, 1.5) })
LUA
}

# The literal catch-all only: the scale belongs on an appended named rule, not
# on the rule every unlisted output shares.
write_literal_catch_all_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

# A rule for a different monitor plus the catch-all, while the target is
# unlisted: only the append may happen.
write_other_monitor_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "-1200x0", scale = 1.6 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

run_scaling() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-2}" \
    OMARCHY_TEST_MONITOR_DESCRIPTION="${OMARCHY_TEST_MONITOR_DESCRIPTION:-}" \
    OMARCHY_TEST_MONITOR_MAKE="${OMARCHY_TEST_MONITOR_MAKE:-}" \
    OMARCHY_TEST_MONITOR_MODEL="${OMARCHY_TEST_MONITOR_MODEL:-}" \
    OMARCHY_TEST_MONITOR_SERIAL="${OMARCHY_TEST_MONITOR_SERIAL:-}" \
    OMARCHY_TEST_EXTERNAL_MONITOR="${OMARCHY_TEST_EXTERNAL_MONITOR:-0}" \
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
}

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling up
grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling up reaches 3x"
grep -F 'position = "0x0"' "$eval_out" >/dev/null || fail "monitor scaling up keeps the live position"
! grep -F 'position = "auto"' "$eval_out" >/dev/null || fail "monitor scaling up never emits auto position"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 3 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling up persists 3x on an appended eDP-1 rule"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling up leaves the shared scale variable alone"
grep -F $'requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1' "$scale_log" >/dev/null || fail "monitor scaling up writes audit log"
pass "monitor scaling up reaches 3x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=3 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down recovers 3x to 2x"
grep -F 'position = "0x0"' "$eval_out" >/dev/null || fail "monitor scaling down keeps the live position"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down persists 2x from 3x"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down leaves the shared scale variable alone"
pass "monitor scaling down recovers 3x to 2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=3.0000000000000004 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down snaps floating point 3x to 2x"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down persists 2x from floating point 3x"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down leaves the shared scale variable alone"
pass "monitor scaling down snaps floating point 3x to 2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 3
grep -F 'scale = 3' "$eval_out" >/dev/null || fail "monitor scaling explicit 3x remains available"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 3 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling explicit 3x persists"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling explicit 3x leaves the shared scale variable alone"
grep -Fx 'local omarchy_gdk_scale = 3' "$monitor_lua" >/dev/null || fail "monitor scaling explicit 3x persists GDK scale"
pass "monitor scaling explicit 3x remains available"

# GTK only honors integer GDK_SCALE, so fractional monitor scales persist a
# rounded GDK scale.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -F 'scale = 1.6' "$eval_out" >/dev/null || fail "monitor scaling explicit 1.6x remains available"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling explicit 1.6x persists"
grep -Fx 'local omarchy_gdk_scale = 2' "$monitor_lua" >/dev/null || fail "monitor scaling 1.6x persists integer GDK scale 2"
pass "monitor scaling 1.6x persists integer GDK scale 2"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.25
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 1.25 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling explicit 1.25x persists"
grep -Fx 'local omarchy_gdk_scale = 1' "$monitor_lua" >/dev/null || fail "monitor scaling 1.25x persists integer GDK scale 1"
pass "monitor scaling 1.25x persists integer GDK scale 1"

scale=$(OMARCHY_TEST_MONITOR_SCALE=3 run_scaling)
[[ $scale == "3" ]] || fail "monitor scaling reports explicit 3x scale" "actual: $scale"
pass "monitor scaling reports explicit 3x scale"

scale=$(OMARCHY_TEST_MONITOR_SCALE=3.2 run_scaling)
[[ $scale == "3.2" ]] || fail "monitor scaling reports the actual non-preset scale" "actual: $scale"
pass "monitor scaling reports the actual non-preset scale"

# 1280x800 approximates the 3x preset as 3.2x.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling 3
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling approximates explicit 3x as 3.2x"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "1280x800@120.0", position = "0x0", scale = 3.2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling persists approximated 3.2x"
pass "monitor scaling approximates explicit 3x as 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling up
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling up reaches approximated 3.2x"
pass "monitor scaling up reaches approximated 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=4 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling down
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling down reaches approximated 3.2x"
pass "monitor scaling down reaches approximated 3.2x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=6016 OMARCHY_TEST_MONITOR_HEIGHT=3384 run_scaling 1.25
grep -F 'scale = 1.33333' "$eval_out" >/dev/null || fail "monitor scaling approximates explicit 1.25x"
pass "monitor scaling approximates explicit 1.25x"

write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=2 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=800 run_scaling 3.2
grep -F 'scale = 3.2' "$eval_out" >/dev/null || fail "monitor scaling accepts displayed approximate values"
pass "monitor scaling accepts displayed approximate values"

# On a mode where both 3x and 4x resolve to 4x, the duplicate is one step.
write_monitor_config
OMARCHY_TEST_MONITOR_SCALE=4 OMARCHY_TEST_MONITOR_WIDTH=1280 OMARCHY_TEST_MONITOR_HEIGHT=804 run_scaling down
grep -F 'scale = 2' "$eval_out" >/dev/null || fail "monitor scaling down skips duplicate 4x approximation"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "1280x804@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down persists 2x after skipping duplicate approximation"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling down leaves the shared scale variable alone"
pass "monitor scaling down skips duplicate approximation"

# A monitor with its own hl.monitor() rule gets the scale rewritten in place:
# no appended line, and neither the catch-all nor the variable is touched.
write_named_rule_config
run_scaling 2
grep -F 'position = "0x0"' "$eval_out" >/dev/null || fail "monitor scaling a named rule keeps the live position"
! grep -F 'position = "auto"' "$eval_out" >/dev/null || fail "monitor scaling a named rule never emits auto position"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling rewrites the monitor's own rule in place"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 2 )) ||
  fail "monitor scaling rewrites in place rather than appending a second rule"
grep -Fx 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the catch-all rule untouched"
grep -Fx 'local omarchy_monitor_scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the shared scale variable alone"
pass "monitor scaling rewrites the monitor's own hl.monitor rule"

# A named rule that references the shared variable gets the literal new scale;
# the variable itself is not the persistence target anymore.
write_named_var_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling pins a variable-referencing rule to the new scale"
grep -Fx 'local omarchy_monitor_scale = 1.5' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the shared scale variable alone"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 1 )) ||
  fail "monitor scaling rewrites in place rather than appending a second rule"
pass "monitor scaling pins a variable-referencing rule to the new scale"

# A multi-line rule is rewritten inside its block; every other line stays
# byte-identical.
write_multiline_rule_config
run_scaling 2
grep -Fx '  scale = 2' "$monitor_lua" >/dev/null ||
  fail "monitor scaling rewrites the scale line inside a multi-line rule"
grep -Fx '  output = "eDP-1",' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the other lines of a multi-line rule alone"
grep -Fx 'hl.monitor({' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the opening line of a multi-line rule alone"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 1 )) ||
  fail "monitor scaling rewrites a multi-line rule in place"
pass "monitor scaling rewrites a multi-line rule in place"

# A rule without a scale key gets one inserted inside the closing brace, not
# appended as a separate line.
write_scaleless_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", transform = 1, scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling inserts scale into a rule that has none"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 2 )) ||
  fail "monitor scaling inserts into the rule rather than appending a new line"
pass "monitor scaling inserts scale into a rule that has none"

# A desc:-keyed rule whose trimmed selector prefix-matches the monitor
# description is rewritten in place, selector preserved.
write_desc_rule_config
OMARCHY_TEST_MONITOR_DESCRIPTION="Acme Display 3000" run_scaling 2
grep -Fx 'hl.monitor({ output = "desc:  Acme  ", mode = "preferred", position = "auto", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling rewrites a desc:-keyed rule in place"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 2 )) ||
  fail "monitor scaling rewrites a desc: rule rather than appending"
pass "monitor scaling rewrites a desc:-keyed rule in place"

# A rule that only exists inside a line comment is not a rule: it is left
# alone and the monitor gets an appended named line instead.
write_commented_rule_config
run_scaling 2
grep -Fx -- '-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a commented-out rule alone"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule when only a comment names the output"
pass "monitor scaling ignores a commented-out rule and appends"

# Same for a rule fenced inside a multi-line --[[ ]] block comment.
write_block_comment_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a block-commented rule alone"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule when only a block comment names the output"
pass "monitor scaling ignores a block-commented rule and appends"

# Same for a rule fenced inside a levelled --[==[ ]==] block comment: it is
# dead text, left byte-identical, and a named rule is appended for the
# monitor.
write_levelled_comment_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a levelled-comment rule alone"
grep -Fx -- ']==]' "$monitor_lua" >/dev/null ||
  fail "monitor scaling keeps the levelled comment's closing bracket"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule when only a levelled comment names the output"
pass "monitor scaling ignores a levelled-comment rule and appends"

# Same for a rule inside a levelled [=[ ]=] long string: string contents are
# not keys, so the line is left alone and a named rule is appended.
write_levelled_string_rule_config
run_scaling 2
grep -Fx 'local s = [=[ hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 9 }) ]=]' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves a levelled long string byte-identical"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule when only a long string names the output"
pass "monitor scaling ignores a levelled-string rule and appends"

# A scale key inside a nested table is not the scale of the rule: the
# top-level scale is rewritten and the nested one stays byte-identical.
write_nested_scale_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", extra = { scale = 99, top = 24 }, scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling rewrites only the top-level scale of the rule"
(( $(grep -c 'hl\.monitor' "$monitor_lua") == 1 )) ||
  fail "monitor scaling rewrites a nested-scale rule in place"
pass "monitor scaling rewrites only the top-level scale of the rule"

# An output selector inside a nested table does not make the rule belong to
# eDP-1: the DP-2 rule stays byte-identical and a named rule is appended.
write_nested_output_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ extra = { output = "eDP-1" }, output = "DP-2", scale = 1.5 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling does not take a nested output key as the selector of the rule"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule when only a nested table names the output"
pass "monitor scaling ignores a nested table output selector"

# A scale handed an expression is replaced whole: the comma inside the call
# must not truncate the value and leave invalid Lua behind.
write_expression_scale_rule_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling replaces an expression-valued scale whole"
! grep -F '1.5)' "$monitor_lua" >/dev/null ||
  fail "monitor scaling does not leave the tail of an expression scale behind"
pass "monitor scaling replaces an expression-valued scale whole"

# A literal catch-all is never the persistence target either: the named
# append wins over it and the catch-all stays byte-identical.
write_literal_catch_all_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a named rule over a literal catch-all"
grep -Fx 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the literal catch-all byte-identical"
pass "monitor scaling appends a named rule over a literal catch-all"

# An unlisted target with another monitor's rule present appends only; the
# other rule stays byte-identical.
write_other_monitor_config
run_scaling 2
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.0", position = "0x0", scale = 2 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling appends a rule for the unlisted target"
grep -Fx 'hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "-1200x0", scale = 1.6 })' "$monitor_lua" >/dev/null ||
  fail "monitor scaling leaves the other monitor's rule byte-identical"
pass "monitor scaling appends a rule for the unlisted target"

# Every write leaves a timestamped backup of the pre-run content.
write_named_rule_config
rm -f "$monitor_lua".bak.*
cp -- "$monitor_lua" "$test_tmp/pre-run.lua"
run_scaling 2
backup=$(compgen -G "$monitor_lua.bak.*") ||
  fail "monitor scaling writes a timestamped backup"
(( $(compgen -G "$monitor_lua.bak.*" | wc -l) == 1 )) ||
  fail "monitor scaling writes exactly one backup per run"
cmp -s "$backup" "$test_tmp/pre-run.lua" ||
  fail "monitor scaling backup preserves the pre-run content"
pass "monitor scaling backs up monitors.lua before writing"

# A symlinked monitors.lua stays a symlink and the write lands through it.
write_named_rule_config
real_lua="$home_dir/.config/hypr/monitors-real.lua"
mv "$monitor_lua" "$real_lua"
ln -s "$real_lua" "$monitor_lua"
run_scaling 2
[[ -L $monitor_lua ]] || fail "monitor scaling keeps a symlinked monitors.lua a symlink"
grep -Fx 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })' "$real_lua" >/dev/null ||
  fail "monitor scaling writes through the symlink to the real file"
pass "monitor scaling writes through a symlinked monitors.lua"

# A named target monitor gets the live apply and the persisted append keyed to
# its own name and live position, and the audit log records it.
write_monitor_config
rm -f "$eval_out" "$scale_log"
OMARCHY_TEST_EXTERNAL_MONITOR=1 run_scaling 2.5 HDMI-A-1
grep -F 'output = "HDMI-A-1"' "$eval_out" >/dev/null || fail "targeted scaling evals the named monitor"
grep -F 'position = "-1200x0"' "$eval_out" >/dev/null || fail "targeted scaling replays the target's live position"
grep -Fx 'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@144.0", position = "-1200x0", scale = 2.5 })' "$monitor_lua" >/dev/null ||
  fail "targeted scaling persists an appended rule for the named monitor"
! grep -F 'output = "eDP-1"' "$monitor_lua" >/dev/null ||
  fail "targeted scaling does not write a rule for the focused monitor"
grep -F 'monitor=HDMI-A-1' "$scale_log" >/dev/null || fail "targeted scaling audits the named monitor"
pass "monitor scaling targets a named monitor"

# Stepping a named monitor reads that monitor's scale (1.6 -> 2), not the
# focused monitor's (2 -> 3).
write_monitor_config
rm -f "$eval_out"
OMARCHY_TEST_EXTERNAL_MONITOR=1 run_scaling up HDMI-A-1
grep -F 'output = "HDMI-A-1"' "$eval_out" >/dev/null || fail "targeted stepping evals the named monitor"
grep -F 'scale = 2 ' "$eval_out" >/dev/null || fail "targeted stepping reads the target's scale, not the focused one"
! grep -F 'scale = 3 ' "$eval_out" >/dev/null || fail "targeted stepping does not step the focused monitor"
pass "monitor scaling steps the named monitor's scale"

# A monitor arg absent from hyprctl fails before any eval or write.
write_named_rule_config
rm -f "$eval_out"
cp -- "$monitor_lua" "$test_tmp/pre-run.lua"
set +e
run_scaling 2 DP-9 >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "monitor scaling rejects an unknown monitor name"
[[ ! -e $eval_out ]] || fail "an unknown monitor is never eval'd"
cmp -s "$monitor_lua" "$test_tmp/pre-run.lua" || fail "an unknown monitor leaves monitors.lua untouched"
pass "monitor scaling rejects an unknown monitor"

# A monitor arg with Lua metacharacters fails the same way: no eval, no write.
write_named_rule_config
rm -f "$eval_out"
cp -- "$monitor_lua" "$test_tmp/pre-run.lua"
set +e
run_scaling 2 'eDP-1" })os.execute("calc")--' >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "monitor scaling rejects a monitor arg with Lua metacharacters"
[[ ! -e $eval_out ]] || fail "an unsafe monitor arg is never eval'd"
cmp -s "$monitor_lua" "$test_tmp/pre-run.lua" || fail "an unsafe monitor arg leaves monitors.lua untouched"
pass "monitor scaling refuses an unsafe monitor name"

# More than two arguments is a usage error.
write_monitor_config
rm -f "$eval_out"
set +e
run_scaling 2 eDP-1 extra 2>"$test_tmp/stderr"
status=$?
set -e
(( status != 0 )) || fail "monitor scaling rejects more than two arguments"
grep -F 'Usage:' "$test_tmp/stderr" >/dev/null || fail "monitor scaling prints usage for extra arguments"
[[ ! -e $eval_out ]] || fail "extra arguments are never eval'd"
pass "monitor scaling rejects extra arguments"

# The bare invocation keeps the monitor-state contract: exactly the focused
# monitor's scale on stdout.
scale=$(run_scaling)
[[ $scale == "2" ]] || fail "bare scaling still reports the focused monitor's scale" "actual: $scale"
pass "monitor scaling bare call reports the focused scale"
