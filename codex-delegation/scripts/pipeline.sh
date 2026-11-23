#!/usr/bin/env bash
# One background command per round: Codex, then (when its report says DONE) the
# gates and the planner's mechanical diff checks. Prints conclusion lines only.
# Usage:
#   pipeline.sh start    <task-id>                [--focused | --no-gates]
#   pipeline.sh resume   <task-id> <feedback.md>  [--focused | --no-gates]
#   pipeline.sh continue <task-id>                [--focused | --no-gates]
#
# Launch it in the background (Claude Code: Bash run_in_background) and read
# only its output and the files it names. Gate policy:
#   default     the full gate list, the acceptance evidence before delivery
#   --focused   FOCUSED_GATES_FILE, for intermediate rounds and trial versions
#   --no-gates  Codex only; also implied by investigate and operate modes and
#               by a `Quiet: yes` task header
# Codex itself runs only focused checks (common.md); the full list runs once,
# here, so a round never pays for the full suite twice.

source "$(dirname "$0")/lib.sh"
cdl_load
here=$(cd "$(dirname "$0")" && pwd)

mode=${1:-}; tid=${2:-}
usage="usage: pipeline.sh start <id> | resume <id> <feedback.md> | continue <id> [--focused | --no-gates]"
[[ -n $tid ]] || die "$usage"
case $mode in
  start|continue) cargs=("$mode" "$tid"); shift 2 ;;
  resume) cargs=(resume "$tid" "${3:?$usage}"); shift 3 ;;
  *) die "$usage" ;;
esac
gateset=full
while [[ $# -gt 0 ]]; do
  case $1 in
    --focused) gateset=focused; shift ;;
    --no-gates) gateset=none; shift ;;
    *) die "unknown option $1" ;;
  esac
done
task_paths "$tid"
task_header

set +e
out=$("$here/run-codex.sh" "${cargs[@]}" 2>&1)
rc=$?
set -e
grep -E 'REPORT|CODEX|GUARD|WARN|HINT|BREAKER|error' <<< "$out" | cut -c1-300 || true
echo "PIPELINE codex rc=$rc"
(( rc == 0 )) || exit "$rc"

report=$(ls -t "$TD"/report*.md 2>/dev/null | head -n 1 || true)
status=$(head -n 5 "$report" 2>/dev/null | grep -m1 -oE 'STATUS: *[A-Z]+' | awk '{print $2}' || true)
[[ $status == DONE ]] || { echo "PIPELINE stop: report status ${status:-UNKNOWN}"; exit 0; }
case $TASK_MODE in investigate|operate) echo "PIPELINE $TASK_MODE: no gates"; exit 0 ;; esac
if [[ $TASK_QUIET == yes || $gateset == none ]]; then
  echo "PIPELINE gates skipped (quiet task or --no-gates)"; exit 0
fi

n=$(ls "$TD"/report*.md | wc -l)
label=r$n; gate_args=()
if [[ $gateset == focused ]]; then label=f$n; gate_args=(--focused); fi
set +e
"$here/run-gates.sh" "$tid" "$label" "${gate_args[@]}" > "$TD/gates-$label.out" 2>&1
set -e
sum=$TD/gates-$label/summary.txt
[[ -f $sum ]] || { echo "PIPELINE gates produced no summary; see $TD/gates-$label.out"; exit 2; }
grep -E 'fail:|SCOPE|GUARD r|SUPPRESS|TESTEDIT|NONDOC|NOGATES|BADLINE|WARNING|rc=[1-9]' "$sum" | head -n 12 | cut -c1-200 || true
tail -n 2 "$sum"

cd "$WT"
echo "DIFF $(git diff --cached --stat | tail -n 1)"
tests=$(git diff --cached --name-only | grep -E "$TEST_PATHS" || true)
existing=$(git diff --cached --name-status | awk '$1 ~ /^(M|D|R)/ {print $2}' | grep -E "$TEST_PATHS" || true)
echo "TESTS modified-existing: $(echo $existing)"
removed=0
[[ -z $tests ]] || removed=$(git diff --cached -U0 -- $tests | grep -cE '^-[^-]' || true)
echo "TESTS removed-lines=$removed"
