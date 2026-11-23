#!/usr/bin/env bash
# Install the Claude Code skills in this repository.
#
# Usage:
#   ./install.sh                     install for the current user (~/.claude/skills)
#   ./install.sh --project <dir>     install into <dir>/.claude/skills
#   ./install.sh --dest <skills-dir> install into an explicit skills directory
# Options:
#   --skill <name>   install one skill (default: every directory with SKILL.md)
#   --link           symlink instead of copying (for editing this checkout)
#   --force          replace an existing installation of the same skill
#   --uninstall      remove the installed skill(s) instead
#   --dry-run        validate and print actions without changing anything
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dest="$HOME/.claude/skills"; only=""; link=0; force=0; uninstall=0; dry=0

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "install: $*" >&2; exit 1; }
act() { if (( dry )); then echo "would: $*"; else "$@"; fi; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) dest="$(cd "${2:?--project needs a directory}" && pwd)/.claude/skills"; shift 2 ;;
    --dest) dest=${2:?--dest needs a directory}; shift 2 ;;
    --skill) only=${2:?--skill needs a name}; shift 2 ;;
    --link) link=1; shift ;;
    --force) force=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

# A skill directory is valid when SKILL.md opens with frontmatter whose name
# equals the directory name and which has a description.
validate() {
  local dir=$1 name; name=$(basename "$dir")
  [[ -f $dir/SKILL.md ]] || die "$dir has no SKILL.md"
  [[ $(head -n 1 "$dir/SKILL.md") == "---" ]] || die "$dir/SKILL.md must start with '---' frontmatter"
  local front; front=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$dir/SKILL.md")
  grep -qx "name: $name" <<<"$front" || die "$dir/SKILL.md frontmatter name must be '$name'"
  grep -q '^description: .\+' <<<"$front" || die "$dir/SKILL.md frontmatter needs a description"
  local len; len=$(grep '^description:' <<<"$front" | cut -d' ' -f2- | wc -m)
  (( len <= 1024 )) || die "$dir/SKILL.md description is $len characters (max 1024)"
}

skills=()
for dir in "$here"/*/; do
  dir=${dir%/}
  [[ -f $dir/SKILL.md ]] || continue
  [[ -z $only || $(basename "$dir") == "$only" ]] || continue
  skills+=("$dir")
done
(( ${#skills[@]} )) || die "no skill found${only:+ named $only} under $here"

act mkdir -p "$dest"
for dir in "${skills[@]}"; do
  name=$(basename "$dir"); target=$dest/$name
  if (( uninstall )); then
    if [[ -L $target || -f $target/SKILL.md ]]; then
      act rm -rf "$target"; (( dry )) || echo "removed $target"
    else
      echo "not installed: $target"
    fi
    continue
  fi
  validate "$dir"
  if [[ -e $target || -L $target ]]; then
    (( force )) || die "$target exists; rerun with --force to replace it"
    [[ -L $target || -f $target/SKILL.md ]] || die "$target is not a skill installation; refusing to replace it"
    act rm -rf "$target"
  fi
  if (( link )); then
    act ln -s "$dir" "$target"
  else
    act cp -R "$dir" "$target"
    act find "$target" -name '*.sh' -exec chmod +x {} +
  fi
  (( dry )) || echo "installed $name -> $target$( (( link )) && echo ' (symlink)')"
done

(( uninstall )) && exit 0
echo
command -v git >/dev/null && echo "git:   $(git --version)" || echo "git:   NOT FOUND (required)"
if command -v codex >/dev/null; then
  echo "codex: $(codex --version 2>/dev/null | head -n 1)"
else
  echo "codex: NOT FOUND - install the OpenAI Codex CLI before delegating tasks"
fi
echo "Start a new Claude Code session to load the skill; invoke it with /codex-delegation"
echo "or ask Claude to delegate work to Codex. Per-project setup: see README.md."
