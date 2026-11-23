#!/usr/bin/env bash
# Independently run every acceptance check of one task worktree.
# Usage: run-gates.sh <task-id> <round-label> [--gates FILE] [--base REF]
#        e.g. run-gates.sh T3 r2            the full gate list (GATES_FILE)
#             run-gates.sh T3 f2 --focused  the focused list (FOCUSED_GATES_FILE)
#
# Run it in the background (Claude Code: Bash run_in_background) and read only
# <task-dir>/gates-<label>/summary.txt. The last line is always DONE; the line
# before it is RESULT PASS or RESULT FAIL. Full per-gate logs stay beside it for
# a counted diagnosis.
#
# Checks depend on the task.md Mode:
#   investigate  the worktree must be unchanged; no gates run
#   operate      the same: an operation stage changes no repository file
#   docs         every changed file must match DOC_PATHS
#   refactor     no existing file matching TEST_PATHS may be modified or deleted
#   all others   optional "Allowed paths" scope, then every gate
# In every mode, a round whose guard reported a change outside the worktree
# (GUARD FAIL, see run-codex.sh) fails acceptance until ledger.sh guard-ack
# records it as the planner's own change.
# Added lines matching SUPPRESSION_PATTERN fail; SKIP_PATTERN matches are
# reported as warnings for review.
#
# Gate lists: the full list (GATES_FILE) is the acceptance evidence before a
# delivery. The focused list (FOCUSED_GATES_FILE, selected with --focused) is
# for intermediate rounds and trial versions: tests for changed files and their
# consumers plus fast static checks. Every gate sees CHANGED_FILES, the
# space-separated paths changed against the merge base with --base (default
# BASE_BRANCH), including staged new files.
# Gate lines are `name | shell command`; lines starting with '#' are
# comments. Each command reads /dev/null, so it cannot consume the list. Commands
# run in the worktree with WT exported, TMPDIR and PYTEST_DEBUG_TEMPROOT set to
# the worktree's own .tmp/ (parallel runs then neither fill a shared /tmp nor
# clean each other's directories), and GATE_ENV applied after them, for
# example GATE_ENV='PYTHONPATH=$WT/src' when an editable install points
# elsewhere.
# Put a harness check first, such as asserting the imported package path is
# inside $WT. The worktree is staged with `git add -A` so path checks see new
# files; review the change afterwards with `git diff --cached`, and only once the
# summary shows its STAGED line (plain `git diff` races with the staging).
# For a failing gate, up to ten log lines matching FAIL_PATTERN are copied into
# the summary, so the first diagnosis needs no full log read.

source "$(dirname "$0")/lib.sh"
cdl_load

tid=${1:-}; label=${2:-}
[[ -n $tid && -n $label ]] || die "usage: run-gates.sh <task-id> <round-label> [--gates FILE | --focused] [--base REF]"
shift 2
gates=$GATES_FILE; base=$BASE_BRANCH
while [[ $# -gt 0 ]]; do
  case $1 in
    --gates) gates=${2:?--gates needs a file}; shift 2 ;;
    --focused) gates=$FOCUSED_GATES_FILE; shift ;;
    --base) base=${2:?--base needs a ref}; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done
task_paths "$tid"
[[ -d $WT ]] || die "worktree $WT does not exist"
task_header
guard_settle
out=$TD/gates-$label
mkdir -p "$out"
summary=$out/summary.txt
: > "$summary"
trap 'echo "RESULT FAIL (runner interrupted)" >> "$summary"; echo DONE >> "$summary"' INT TERM
note() { echo "$*" >> "$summary"; }

export WT
task_tmp
export TMPDIR=$WT/.tmp PYTEST_DEBUG_TEMPROOT=$WT/.tmp
if [[ -n $GATE_ENV ]]; then eval "export $GATE_ENV"; fi
cd "$WT"
git add -A
note "WORKTREE $WT"
note "HEAD     $(git log --oneline -1)"
note "MODE     $TASK_MODE"
note "STAGED   $(git diff --cached --name-only | wc -l) files"
note "GATESET  $gates"
merge_base=$(git merge-base "$base" HEAD 2>/dev/null || git rev-parse "$base")
CHANGED_FILES=$( { git diff --name-only --diff-filter=AMR "$merge_base" HEAD; git diff --cached --name-only --diff-filter=AMR; } |
  sort -u | tr '\n' ' ')
export CHANGED_FILES
failed=0

# Report at most twenty offending paths, then a count.
offenders() {  # label, newline-separated paths
  local label=$1 list=$2 count
  [[ -n $list ]] || return 0
  count=$(printf '%s\n' "$list" | wc -l)
  printf '%s\n' "$list" | head -n 20 | sed "s/^/$label /" >> "$summary"
  (( count <= 20 )) || note "$label ... and $((count - 20)) more"
  failed=1
}

changed=$(git diff --cached --name-only)
case $TASK_MODE in
  investigate|operate)
    offenders "CHANGED" "$changed"
    [[ -n $changed ]] || note "UNCHANGED worktree has no changes, as $TASK_MODE mode requires"
    ;;
  docs)
    offenders "NONDOC" "$(printf '%s\n' "$changed" | grep -vE "$DOC_PATHS" | grep . || true)"
    ;;
  refactor)
    offenders "TESTEDIT" "$(git diff --cached --name-status | awk '$1 ~ /^(M|D|R)/ {print $2}' |
      grep -E "$TEST_PATHS" || true)"
    ;;
esac

if [[ -n $TASK_ALLOWED && $TASK_MODE != investigate && $TASK_MODE != operate ]]; then
  outside=""
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    path_allowed "$path" "$TASK_ALLOWED" || outside+="$path"$'\n'
  done <<< "$changed"
  offenders "SCOPE" "${outside%$'\n'}"
  [[ -n $outside ]] || note "SCOPE    all staged files are within Allowed paths"
fi

guard=$(guard_failures)
if [[ -n $guard ]]; then
  offenders "GUARD" "$guard"
else
  note "GUARD    no round changed refs, worktree branches, shared git files or idle checkouts"
fi

count=0
if [[ $TASK_MODE != investigate && $TASK_MODE != operate ]]; then
  [[ -f $gates ]] || die "gates file $gates not found"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    [[ $line == *"|"* ]] || { note "BADLINE  $line"; failed=1; continue; }
    name=$(echo "${line%%|*}" | xargs)
    cmd=${line#*|}
    [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || { note "BADNAME  $name"; failed=1; continue; }
    count=$((count + 1))
    start=$SECONDS
    set +e
    bash -c "$cmd" < /dev/null > "$out/$name.log" 2>&1
    rc=$?
    set -e
    (( rc == 0 )) || failed=1
    printf '%-16s rc=%-3d %5ds | %s\n' "$name" "$rc" $((SECONDS - start)) \
      "$(tail -n 1 "$out/$name.log" | cut -c1-140)" >> "$summary"
    if (( rc != 0 )); then
      grep -E "$FAIL_PATTERN" "$out/$name.log" | head -n 10 | cut -c1-160 |
        sed 's/^/    fail: /' >> "$summary" || true
    fi
  done < "$gates"
  (( count > 0 )) || { note "NOGATES  $gates has no gate lines"; failed=1; }
fi

added_lines=$(git diff --cached -U0 | grep -E '^\+[^+]' || true)
suppressions=$(printf '%s\n' "$added_lines" | grep -cE "$SUPPRESSION_PATTERN" || true)
skips=$(printf '%s\n' "$added_lines" | grep -cE "$SKIP_PATTERN" || true)
note "SUPPRESSIONS added=$suppressions"
(( suppressions == 0 )) || failed=1
(( skips == 0 )) || note "WARNING  added=$skips test-skip markers; review them before accepting"

trap - INT TERM
if (( failed )); then note "RESULT FAIL"; else note "RESULT PASS"; fi
note "DONE"
exit "$failed"
