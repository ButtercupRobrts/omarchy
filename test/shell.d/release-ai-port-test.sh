#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const text = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')
const rows = Object.fromEntries(text.split('\n').filter(line => /^  "/.test(line)).map(line => {
  const object = JSON.parse('{' + line.trim().replace(/,$/, '') + '}')
  return Object.entries(object)[0]
}))
assert(rows['remove.ai'] && !rows['remove.ai'].action, 'selected AI removers have a reachable parent')
assert(rows['remove.dictation'] && !rows['remove.ai.dictation'], 'Dictation retains its baseline location')
const selected = {'t3-code': '\ue908', hermes: '\ue90a', openclaw: '\ue90c', perplexity: '\ue90b'}
for (const [id, glyph] of Object.entries(selected)) {
  const install = rows[`install.ai.${id}`], remove = rows[`remove.ai.${id}`]
  assert(install && remove, `${id} has install and remove entries`)
  assert(install.disabled, `${id} install row dims when the app is already installed`)
  assert(remove.when, `${id} removal is gated on the app being present`)
  assertEqual(install.icon, glyph, `${id} install uses selected glyph`)
  assertEqual(remove.icon, glyph, `${id} remove uses selected glyph`)
  assertEqual(install.iconFont, 'omarchy', `${id} uses the packaged icon font`)
  assert(fs.existsSync(path.join(root, `bin/omarchy-remove-ai-${id}`)), `${id} remover exists`)
}
assert(!fs.existsSync(path.join(root, 'bin/omarchy-theme-set-openclaw')), 'deferred OpenClaw theming is absent')
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export TEST_CALLS="$test_tmp/calls"
cat >"$test_tmp/bin/mise" <<'SH'
#!/bin/bash
printf 'mise:%s\n' "$*" >>"$TEST_CALLS"
SH
cat >"$test_tmp/bin/omarchy-mise-install" <<'SH'
#!/bin/bash
printf 'stub:%s\n' "$*" >>"$TEST_CALLS"
SH
cat >"$test_tmp/bin/omarchy-install-hermes-cli" <<'SH'
#!/bin/bash
printf 'hermes:%s\n' "$*" >>"$TEST_CALLS"
exit 1
SH
chmod +x "$test_tmp/bin"/*
PATH="$test_tmp/bin:$PATH" bash -eE "$ROOT/install/user/mise.sh"
# The no-pruning setting ships in /etc/mise/conf.d now, not a runtime call:
# etc/mise/conf.d/omarchy.toml is installed into the user's global mise conf.d
# path, so new installs keep running mise versions without a user config write.
grep -qx 'upgrade.auto_prune = false' "$ROOT/etc/mise/conf.d/omarchy.toml" ||
  fail "the packaged mise conf.d retains running versions"
grep -qx 'mise:reshim --system' "$TEST_CALLS" || fail "mise setup builds the system shims"
grep -qx 'mise:reshim' "$TEST_CALLS" || fail "mise setup builds the user shims"
! grep -Eq '^(hermes|stub):' "$TEST_CALLS" || fail "mise setup installs no agent CLIs"
pass "baseline mise setup ships no-pruning via conf.d and only builds shims"
: >"$TEST_CALLS"
PATH="$test_tmp/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787215483.sh" >/dev/null
grep -qx 'mise:settings set upgrade.auto_prune false' "$TEST_CALLS" || fail "existing users retain running mise versions"
pass "mise migration applies the same no-pruning setting"

# Exercise the documented font workflow, not just fontconfig's charset reader.
# Work on a disposable copy: adding a fixture must never edit the source font.
python3 - "$ROOT" "$test_tmp" <<'PY'
import pathlib
import runpy
import shutil
import struct
import subprocess
import sys

root, temporary = map(pathlib.Path, sys.argv[1:])
tool = root / 'bin/omarchy-dev-font'
font = temporary / 'omarchy.ttf'
shutil.copyfile(root / 'default/fonts/omarchy/omarchy.ttf', font)
api = runpy.run_path(str(tool))

def snapshot():
    data, tables, count = api['load_font'](str(font))
    offsets = api['read_loca'](data, tables, count)
    names = api['read_names'](data, tables['post'][0], count)
    cmap = api['read_cmap'](data, tables['cmap'][0])
    start = tables['glyf'][0]
    glyphs = [data[start + offsets[i]:start + offsets[i + 1]].rstrip(b'\0') for i in range(count)]
    metrics = data[tables['hmtx'][0]:sum(tables['hmtx'])]
    assert struct.unpack_from('>I', data, tables['post'][0])[0] == 0x20000
    return names, cmap, glyphs, metrics

before = snapshot()
assert before[0][before[1][0xE90D]] == 'cursor'
next_codepoint = max(before[1]) + 1
listing = subprocess.check_output([sys.executable, str(tool), 'list', '--font', str(font)], text=True)
for cp, name, _ in api['glyph_list'](str(font)):
    assert f'U+{cp:04X}' in listing and name in listing
assert 'U+E90D' in listing and 'cursor' in listing
print('ok - the shipped font lists its named Cursor mark through the real font tool')

svg = temporary / 'fixture.svg'
svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M2 2 L22 2 L22 22 L2 22 Z"/></svg>')
subprocess.run([sys.executable, str(tool), 'add', 'release-fixture', str(svg), '--font', str(font)], check=True, stdout=subprocess.DEVNULL)
after = snapshot()
assert after[0] == before[0] + ['release-fixture']
assert after[1] == before[1] | {next_codepoint: len(before[0])}
assert after[2][:-1] == before[2]
assert after[3].startswith(before[3])
print('ok - adding a local SVG preserves every existing name, codepoint, outline and metric')
listing = subprocess.check_output([sys.executable, str(tool), 'list', '--font', str(font)], text=True)
assert f'U+{next_codepoint:04X}' in listing and 'release-fixture' in listing and 'cursor' in listing
print('ok - the real font tool lists the newly added disposable glyph')
unchanged = font.read_bytes()
result = subprocess.run([sys.executable, str(tool), 'add', 'collision', str(svg), '--codepoint', 'E90D', '--font', str(font)], capture_output=True, text=True)
assert result.returncode != 0 and 'already used' in result.stderr
assert font.read_bytes() == unchanged
print('ok - adding over Cursor is rejected without changing the font')
PY
