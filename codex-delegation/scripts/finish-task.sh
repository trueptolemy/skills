#!/usr/bin/env bash
# Deliver an accepted task and clean up.
# Usage: finish-task.sh <task-id> [<commit-message-file>] [--no-merge] [--keep-worktree]
#
# Refuses unless the newest gates summary of the task ends with RESULT PASS and
# DONE, so a failing or unfinished run cannot be delivered by mistake. An
# investigate or operate task needs no gates summary: it only has to leave its
# worktree unchanged. Every mode refuses while a round's guard reports a change
# outside the worktree that ledger.sh guard-ack has not recorded. Its own
# changes (commit, fast-forward, worktree removal) are recorded for the guard
# of rounds running in parallel.
#
# investigate and operate tasks deliver their report: nothing is committed, and the clean
# worktree is removed. Other modes commit on the task branch; MSG_FILE_CHECK runs
# before the commit with {file} replaced by the message path and
# MSG_COMMIT_CHECK after it with {rev} replaced by the new commit. DELIVERY then
# decides what happens to the commit:
#   ff-merge     fast-forward BASE_BRANCH in the main checkout (default)
#   branch-only  keep the commit on its branch; print, never run, a push command
#   patch        write the commit as a patch under the task directory
# Nothing is ever pushed. --no-merge keeps a chained task's commit on its branch
# whatever DELIVERY says; finishing the later task delivers every chained commit.

source "$(dirname "$0")/lib.sh"
cdl_load

tid=${1:-}
[[ -n $tid ]] || die "usage: finish-task.sh <task-id> [<message-file>] [--no-merge] [--keep-worktree]"
shift
msg=""; merge=1; keep=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-merge) merge=0; shift ;;
    --keep-worktree) keep=1; shift ;;
    -*) die "unknown option $1" ;;
    *) [[ -z $msg ]] || die "unexpected argument $1"; msg=$1; shift ;;
  esac
done
task_paths "$tid"
[[ -d $WT ]] || die "worktree $WT does not exist"
task_header
guard_settle
guard=$(guard_failures)
[[ -z $guard ]] || die "a round of $TID changed state outside its worktree; stop, or record your own change with ledger.sh guard-ack:"$'\n'"$guard"
planner_begin

remove_worktree() {
  if (( keep )); then echo "kept worktree $WT"; return; fi
  if [[ -z $(git -C "$WT" status --porcelain) ]]; then
    git -C "$REPO" worktree remove "$WT" && echo "removed worktree $WT"
  else
    echo "kept worktree $WT: it is not clean"
  fi
}

if [[ $TASK_MODE == investigate || $TASK_MODE == operate ]]; then
  [[ -z $(git -C "$WT" status --porcelain) ]] || die "$TASK_MODE task $TID changed its worktree; nothing may be delivered"
  echo "$TASK_MODE task $TID delivers its report: $(ls -t "$TD"/report*.md | head -n 1)"
  remove_worktree
  exit 0
fi

latest=$(ls -td "$TD"/gates-*/ 2>/dev/null | head -n 1 || true)
[[ -n $latest ]] || die "no gates summary under $TD; run run-gates.sh first"
summary=${latest%/}/summary.txt
[[ $(tail -n 1 "$summary") == DONE ]] || die "$summary has not finished (no DONE line)"
[[ $(tail -n 2 "$summary" | head -n 1) == "RESULT PASS" ]] || die "$summary did not pass"



[[ -n $msg && -s $msg ]] || die "commit message file is missing or empty"
msg=$(cd "$(dirname "$msg")" && pwd)/$(basename "$msg")
substitute() { local template=$1 key=$2 value=$3; echo "${template//\{$key\}/$(printf '%q' "$value")}"; }
if [[ -n $MSG_FILE_CHECK ]]; then
  (cd "$REPO" && bash -c "$(substitute "$MSG_FILE_CHECK" file "$msg")") || die "message check failed for $msg"
fi

branch=$(git -C "$WT" symbolic-ref --short HEAD)
git -C "$WT" add -A
git -C "$WT" diff --cached --quiet && die "nothing staged in $WT"
git -C "$WT" commit -q --file "$msg"
rev=$(git -C "$WT" rev-parse HEAD)
if [[ -n $MSG_COMMIT_CHECK ]]; then
  (cd "$REPO" && bash -c "$(substitute "$MSG_COMMIT_CHECK" rev "$rev")") ||
    die "recorded commit $rev failed the message check; amend it on $branch before delivering"
fi
echo "committed $(git -C "$WT" log --oneline -1) on $branch"

(( merge )) || { echo "kept on $branch for a later chained delivery"; exit 0; }
case $DELIVERY in
  ff-merge)
    current=$(git -C "$REPO" symbolic-ref --short HEAD)
    [[ $current == "$BASE_BRANCH" ]] || die "main checkout is on $current, not $BASE_BRANCH; merge manually"
    [[ -z $(git -C "$REPO" status --porcelain --untracked-files=no) ]] || die "main checkout has uncommitted changes"
    git -C "$REPO" merge --ff-only -q "$branch" || die "fast-forward of $BASE_BRANCH to $branch is not possible"
    echo "fast-forwarded $BASE_BRANCH to $(git -C "$REPO" log --oneline -1)"
    remove_worktree
    ;;
  branch-only)
    echo "delivered on branch $branch; pushing needs separate authorization:"
    echo "  git -C $REPO push <remote> $branch"
    remove_worktree
    ;;
  patch)
    mkdir -p "$TD/patches"
    git -C "$WT" format-patch -q -o "$TD/patches" "$BASE_BRANCH..$branch"
    echo "wrote $(( $(ls "$TD/patches" | wc -l) )) patch file(s) to $TD/patches"
    remove_worktree
    ;;
esac
