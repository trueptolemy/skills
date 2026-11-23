#!/usr/bin/env bash
# Mechanical ledger for the token-economy rules and circuit breakers.
# Usage:
#   ledger.sh full-read <task-id> <what>        record a full log/diff read BEFORE doing it
#   ledger.sh guard-ack <task-id> r<N> <what>   record that a GUARD FAIL of round N was
#                                               the planner's own change
#   ledger.sh void <task-id> r<N> <reason>      void round N: it failed because of the
#                                               environment and does not count toward
#                                               the round breaker
#   ledger.sh status                             rounds, tokens, report, guard and gate state
#
# full-read exits 3 once the count would exceed MAX_FULL_READS: do not perform
# that read; stop all work and report. Targeted reads (summary lines, grep
# results, `--stat`, named hunks) are not full reads and are not recorded.
# guard-ack is only for a change you made yourself while the round ran (for
# example a branch created by hand); a change Codex made is a forbidden action.
# void is only for a round the environment broke (an API error, a full disk or
# exhausted inodes, a provider outage), never for a round whose work was
# wrong. Each void is kept with its reason in <task>/void.log and counted in
# status; list them in the final summary.

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
  guard-ack)
    tid=${2:-}; round=${3:-}; what=${4:-}
    [[ -n $tid && $round =~ ^r[0-9]+$ && -n $what ]] || die "usage: ledger.sh guard-ack <task-id> r<N> <what you changed>"
    task_paths "$tid"
    grep -q '^GUARD FAIL' "$TD/guard-$round.txt" 2>/dev/null || die "$TID $round has no GUARD FAIL to acknowledge"
    echo "$(date -u +%FT%TZ) $what" > "$TD/guard-$round.ack"
    echo "GUARD $TID $round recorded as a planner change: $what"
    ;;
  void)
    tid=${2:-}; round=${3:-}; why=${4:-}
    [[ -n $tid && $round =~ ^r[0-9]+$ && -n $why ]] || die "usage: ledger.sh void <task-id> r<N> <environment failure>"
    task_paths "$tid"
    grep -qE "^round ${round#r} (start|resume) " "$TD/rounds.log" 2>/dev/null || die "$TID has no round ${round#r}"
    if [[ -f $TD/void.log ]] && cut -f1 "$TD/void.log" | grep -qx "$round"; then die "$TID $round is already void"; fi
    printf '%s\t%s\t%s\n' "$round" "$(date -u +%FT%TZ)" "$why" >> "$TD/void.log"
    echo "VOID $TID $round recorded ($(voided_rounds) voided in total): $why"
    ;;
  status)
    printf '%-14s %-12s %6s %4s %12s  %-10s %-5s %s\n' TASK MODE ROUNDS VOID TOKENS REPORT GUARD GATES
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
      guard=-
      compgen -G "$TD/guard-r*.txt" > /dev/null && guard=ok
      compgen -G "$TD/guard-r*.ack" > /dev/null && guard=ack
      [[ -z $(guard_failures) ]] || guard=FAIL
      total=$((total + tokens))
      printf '%-14s %-12s %6s %4s %12s  %-10s %-5s %s\n' "$tid" "${mode:-?}" "$rounds" "$(voided_rounds)" "$tokens" "${status:-?}" "$guard" "$gates"
    done
    used=$( [[ -f $reads ]] && wc -l < "$reads" || echo 0)
    echo "TOTAL tokens=$total full-reads=$used/$MAX_FULL_READS"
    ;;
  *) die "usage: ledger.sh full-read <task-id> <what> | guard-ack <task-id> r<N> <what> | void <task-id> r<N> <reason> | status" ;;
esac
