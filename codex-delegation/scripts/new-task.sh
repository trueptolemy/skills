#!/usr/bin/env bash
# Create one task's isolated worktree, branch and task directory.
# Usage: new-task.sh <task-id> <branch> [--from <ref>] [--reuse-branch]
#
# The worktree starts from the latest base branch unless --from names another
# ref (for example the previous task's branch in a chained delivery). The
# command refuses when free disk space is below MIN_FREE_GB: every worktree is a
# full checkout, and a full disk once broke a checkout halfway.

source "$(dirname "$0")/lib.sh"
cdl_load

tid=${1:-}; branch=${2:-}
[[ -n $tid && -n $branch ]] || die "usage: new-task.sh <task-id> <branch> [--from <ref>] [--reuse-branch]"
shift 2
from=$BASE_BRANCH; reuse=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --from) from=${2:?--from needs a ref}; shift 2 ;;
    --reuse-branch) reuse=1; shift ;;
    *) die "unknown option $1" ;;
  esac
done
task_paths "$tid"

[[ ! -e $WT ]] || die "worktree $WT already exists"
mkdir -p "$WT_ROOT" "$TASKS_ROOT"
free=$(free_gb "$WT_ROOT")
need=${MIN_FREE_GB}
(( free >= need )) || die "only ${free} GiB free under $WT_ROOT (need $need); remove merged worktrees first"

if git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch"; then
  (( reuse )) || die "branch $branch exists; pass --reuse-branch to check it out"
  git -C "$REPO" worktree add -q "$WT" "$branch"
else
  git -C "$REPO" worktree add -q -b "$branch" "$WT" "$from"
fi

if [[ -n $SETUP_HOOK ]]; then
  [[ -x $SETUP_HOOK ]] || die "SETUP_HOOK $SETUP_HOOK is not executable"
  "$SETUP_HOOK" "$WT"
fi
dirty=$(git -C "$WT" status --porcelain | wc -l)
(( dirty == 0 )) || die "fresh worktree $WT is not clean after setup ($dirty entries); exclude setup artifacts in .git/info/exclude"

mkdir -p "$TD"
[[ -e $TASKS_ROOT/common.md ]] || cp "$SKILL_DIR/templates/common.md" "$TASKS_ROOT/common.md"
[[ -e $TD/task.md ]] || cp "$SKILL_DIR/templates/task.md" "$TD/task.md"

echo "worktree  $WT  ($(git -C "$WT" log --oneline -1))"
echo "branch    $branch from $from"
echo "task dir  $TD"
echo "next      edit $TD/task.md, then run run-codex.sh start $tid in the background"
