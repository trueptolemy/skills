#!/usr/bin/env bash
# Create one task's isolated worktree, branch and task directory.
# Usage: new-task.sh <task-id> <branch> [--from <ref>] [--reuse-branch] [--reuse-task]
#
# The worktree starts from the latest base branch unless --from names another
# ref (for example the previous task's branch in a chained delivery). The
# command refuses when free disk space under WT_ROOT is below MIN_FREE_GB, or
# free inodes under WT_ROOT, TMPDIR or /tmp are below MIN_FREE_INODES: every
# worktree is a full checkout, a full disk once broke a checkout halfway, and a
# small /tmp once ran out of inodes during the gates. It creates the worktree's
# temporary directory .tmp/ (task_tmp in lib.sh). It also refuses
# an existing task directory that already holds rounds or reports: reusing an
# old identifier once made run-codex.sh return the previous task's report
# instead of starting Codex. Pass --reuse-task only to continue that task.
# It does not create task.md: the planner writes it as a new file from
# templates/task.md, which needs no Read of a placeholder first.

source "$(dirname "$0")/lib.sh"
cdl_load

tid=${1:-}; branch=${2:-}
[[ -n $tid && -n $branch ]] || die "usage: new-task.sh <task-id> <branch> [--from <ref>] [--reuse-branch] [--reuse-task]"
shift 2
from=$BASE_BRANCH; reuse=0; reuse_task=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --from) from=${2:?--from needs a ref}; shift 2 ;;
    --reuse-branch) reuse=1; shift ;;
    --reuse-task) reuse_task=1; shift ;;
    *) die "unknown option $1" ;;
  esac
done
task_paths "$tid"

[[ ! -e $WT ]] || die "worktree $WT already exists"
if (( ! reuse_task )) && { [[ -e $TD/rounds.log ]] || compgen -G "$TD/report*.md" > /dev/null; }; then
  die "task directory $TD already holds an earlier task; choose a new task id (or pass --reuse-task to continue it)"
fi
mkdir -p "$WT_ROOT" "$TASKS_ROOT"
planner_begin   # record the new branch and worktree for the guard of running rounds
storage=$(storage_check) || die "not enough room for a new task; remove merged worktrees or free the filesystem:"$'\n'"$(grep '^FAIL' <<< "$storage")"

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
task_tmp
dirty=$(git -C "$WT" status --porcelain | wc -l)
(( dirty == 0 )) || die "fresh worktree $WT is not clean after setup ($dirty entries); exclude setup artifacts in .git/info/exclude"

mkdir -p "$TD"
[[ -e $TASKS_ROOT/common.md ]] || cp "$SKILL_DIR/templates/common.md" "$TASKS_ROOT/common.md"

echo "worktree  $WT  ($(git -C "$WT" log --oneline -1))"
echo "branch    $branch from $from"
echo "task dir  $TD"
echo "next      write $TD/task.md from $SKILL_DIR/templates/task.md, then run pipeline.sh start $tid in the background"
