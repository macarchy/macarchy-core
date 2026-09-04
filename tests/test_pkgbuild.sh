#!/bin/bash
# tests/test_pkgbuild.sh — the package must carry what install.sh carries.
#
# macarchy-core splits: the commands, units and udev rule go system-wide, and
# everything that belongs under $HOME (theme hooks, shell plugins, the Hypr key
# file, the starter configs) ships as templates under /usr/share because pacman
# may not write there. That split is honest only while the scriptlet names every
# destination — so this checks both halves. macarchy-install#17.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
check() { local name=$1; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); fi; }
# Comments name every artefact, so a whole-file grep passes even when the install
# line is gone. Read the code.
code() { grep -v '^[[:space:]]*#' PKGBUILD; }

check "every command install.sh ships is packaged" \
  bash -c 'for s in style/* hardware/*; do [ -f "$s" ] && [ -x "$s" ] || continue; grep -q "style/\* hardware/\*" <(grep -v "^[[:space:]]*#" PKGBUILD) || exit 1; done'
check "the units are packaged"          grep -q 'systemd/\*.service' <(code)
check "the timers are packaged"         grep -q 'systemd/\*.timer' <(code)
check "the udev rule is packaged"       grep -q '90-battery-charge-limit.rules' <(code)
check "the user half ships as templates" grep -q 'cp -r hooks keys examples shell-plugins' <(code)

# The units point at $HOME for install.sh's benefit; verbatim that is 203/EXEC.
check "units are repointed off %h"      grep -q "sed 's|%h/" <(code)
check "and the rewrite is checked"      grep -q "grep -q '\^ExecStart=/usr/bin/'" <(code)
check "the shipped unit really says %h" grep -q '%h/' systemd/macarchy-auto-appearance.service

# The split is only honest if the scriptlet names where each piece goes.
check "there is a scriptlet"            grep -q 'install=macarchy-core.install' <(code)
for dest in "hooks/theme-set.d" "omarchy/plugins" "hypr/macarchy-keys.lua" "examples"; do
  check "scriptlet names $dest"         grep -q "$dest" macarchy-core.install
done
check "scriptlet admits it is partial"  grep -q "pacman cannot write" macarchy-core.install

# The workflow lessons from macarchy-install#16, each a real failure there.
WF=.github/workflows/release-please.yml
check "no standalone package workflow"  [ ! -e .github/workflows/package.yml ]
check "the job hangs off release_created" grep -q 'release_created' "$WF"
check "not a release: published trigger"  bash -c '! grep -q "types: \[published\]" '"$WF"
check "pkgver is rewritten from the tag" grep -q 'pkgver=\${TAG#v}' "$WF"
check "and the rewrite is verified"      grep -q 'grep -q "\^pkgver=\${TAG#v}\$" PKGBUILD' "$WF"
check "extra-files is not used"          bash -c '! grep -q "extra-files" release-please-config.json'
check "the upload globs"                 grep -q '\*.pkg.tar.\*' "$WF"
check "the upload clobbers"              grep -q -- '--clobber' "$WF"
check "gh is installed in the container" grep -q 'github-cli' "$WF"

(( fails == 0 )) && echo "all ok" || echo "$fails failed"
exit $(( fails > 0 ))
