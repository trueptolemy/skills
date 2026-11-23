#!/usr/bin/env bash
# Run every skill's own self-test (<skill>/tests/selftest.sh), then exercise
# install.sh against temporary directories. Calls no model and touches nothing
# outside temporary directories. Usage: ./selftest.sh [skill ...]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL $*" >&2; exit 1; }

skills=()
if (( $# )); then
  skills=("$@")
else
  for d in "$here"/*/; do [[ -f $d/SKILL.md ]] && skills+=("$(basename "$d")"); done
fi
for s in "${skills[@]}"; do
  [[ -f $here/$s/SKILL.md ]] || fail "no skill named $s"
  if [[ -x $here/$s/tests/selftest.sh ]]; then
    echo "== $s"
    "$here/$s/tests/selftest.sh"
  else
    echo "== $s: no tests/selftest.sh"
  fi
done

# --- install.sh (generic: every skill directory) ---------------------------------
echo "== install.sh"
all=()
for d in "$here"/*/; do [[ -f $d/SKILL.md ]] && all+=("$(basename "$d")"); done
dest=$tmp/skills
"$here/install.sh" --dest "$dest" > /dev/null
for s in "${all[@]}"; do
  [[ -f $dest/$s/SKILL.md ]] || fail "install copy of $s"
  [[ ! -e $dest/$s/tests ]] || fail "install must not copy $s/tests"
  if [[ -d $dest/$s/scripts ]]; then
    nx=$(find "$dest/$s/scripts" -type f \( -name '*.sh' -o -name '*.py' \) ! -perm -u+x | head -n 1)
    [[ -z $nx ]] || fail "install must make $nx executable"
  fi
done
if "$here/install.sh" --dest "$dest" > /dev/null 2>&1; then fail "install must refuse to overwrite"; fi
"$here/install.sh" --dest "$dest" --force --link > /dev/null
for s in "${all[@]}"; do [[ -L $dest/$s ]] || fail "install link of $s"; done
"$here/install.sh" --dest "$dest" --uninstall > /dev/null
for s in "${all[@]}"; do [[ ! -e $dest/$s ]] || fail "uninstall of $s"; done
one=${all[-1]}
"$here/install.sh" --dest "$dest" --skill "$one" > /dev/null
for s in "${all[@]}"; do
  if [[ $s == "$one" ]]; then [[ -f $dest/$s/SKILL.md ]] || fail "install --skill $one"
  else [[ ! -e $dest/$s ]] || fail "install --skill $one must not install $s"; fi
done
mkdir -p "$tmp/proj"
"$here/install.sh" --project "$tmp/proj" > /dev/null
for s in "${all[@]}"; do [[ -f $tmp/proj/.claude/skills/$s/SKILL.md ]] || fail "project install of $s"; done
echo "ok   install.sh copies without tests, makes scripts executable, refuses overwrite, links with --force, uninstalls, installs one skill and per project"
echo "selftest: all skills passed"
