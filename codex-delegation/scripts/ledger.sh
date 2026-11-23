#!/usr/bin/env bash
# Mechanical ledger for the token-economy rules and circuit breakers.
# Usage:
#   ledger.sh full-read <task-id> <what>   record a full log/diff read BEFORE doing it
#   ledger.sh status                        rounds, tokens, report and gate state per task
#
# full-read exits 3 once the count would exceed MAX_FULL_READS: do not perform
# that read; stop all work and report. Targeted reads (summary lines, grep
# results, `--stat`, named hunks) are not full reads and are not recorded.

source "$(dirname "$0")/lib.sh"
cdl_load
reads=$TASKS_ROOT/full-reads.log

case ${1:-} in
  full-read)
    tid=${2:-}; what=${3:-}
    [[ -n $tid && -n $what ]] || die "usage: ledger.sh full-read <task-id> <what>"
    task_paths "$tid"
    count=$(( $( [[ -f $reads ]] && wc -l < "$reads" || echo 0) + 1 ))
    if (( count > MAX_FULL_READS )); then
      echo "BREAKER: full read $count would exceed MAX_FULL_READS=$MAX_FULL_READS ($TID: $what)." >&2
      echo "Do not perform it. Stop all work, keep the worktrees and report the state." >&2
      exit 3
    fi
    echo "$(date -u +%FT%TZ) $TID $what" >> "$reads"
    echo "FULL READS $count/$MAX_FULL_READS recorded: $TID $what"
    ;;
  status)
    printf '%-14s %-12s %6s %12s  %-10s %s\n' TASK MODE ROUNDS TOKENS REPORT GATES
    total=0
    for dir in "$TASKS_ROOT"/*/; do
      [[ -f $dir/rounds.log ]] || continue
      TD=${dir%/}; tid=$(basename "$TD")
      mode=$(sed -n 's/^round 1 start mode=\([a-z]*\).*/\1/p' "$TD/rounds.log" | tail -n 1)
      rounds=$(grep -cE '^round [0-9]+ (start|resume)' "$TD/rounds.log" || true)
      tokens=$(grep -oE 'CODEX .*tokens=[0-9]+' "$TD/rounds.log" | sed 's/.*tokens=//' | awk '{s += $1} END {print s + 0}')
      status=$(grep -oE 'REPORT STATUS=[A-Z]+' "$TD/rounds.log" | tail -n 1 | cut -d= -f2)
      latest=$(ls -td "$TD"/gates-*/ 2>/dev/null | head -n 1 || true)
      gates=none
      if [[ -n $latest ]]; then
        gates="$(basename "$latest") $(grep -m1 -oE '^RESULT [A-Z]+' "${latest%/}/summary.txt" || echo RUNNING)"
      fi
      total=$((total + tokens))
      printf '%-14s %-12s %6s %12s  %-10s %s\n' "$tid" "${mode:-?}" "$rounds" "$tokens" "${status:-?}" "$gates"
    done
    used=$( [[ -f $reads ]] && wc -l < "$reads" || echo 0)
    echo "TOTAL tokens=$total full-reads=$used/$MAX_FULL_READS"
    ;;
  *) die "usage: ledger.sh full-read <task-id> <what> | ledger.sh status" ;;
esac
