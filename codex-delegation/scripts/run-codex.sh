#!/usr/bin/env bash
# Run Codex for one task in its worktree; the orchestrator reads only reports.
# Usage:
#   run-codex.sh start  <task-id> [--dry-run]
#   run-codex.sh resume <task-id> <feedback.md> [--dry-run]
#   run-codex.sh continue <task-id> [--dry-run]
#
# Launch this command in the background (Claude Code: Bash run_in_background)
# and wait for its completion notification. Do not poll the log and do not use
# `&` plus `pgrep -f`: a waiter whose command line contains the pattern matches
# itself and never exits.
#
# The task.md header selects the mode (implement, refactor, docs, investigate,
# operate) and therefore the sandbox: write modes use CODEX_SANDBOX,
# investigate runs read-only and operate names its own. Every round runs with
# approval policy never; outside operate tasks it also runs without an ssh
# agent and with git over ssh refused (codex_env in lib.sh). The prompt is
# task.md + common.md + the mode instructions, plus quiet.md when the task
# header says `Quiet: yes` (a measurement on the same host forbids test runs).
# start  writes report.md and codex.log.
# resume continues the recorded session with a feedback file and writes
#        report-rN.md and codex-rN.log. It refuses once the task has used
#        MAX_ROUNDS rounds, or the `Max rounds:` of its task.md (the per-task
#        circuit breaker); rounds voided with ledger.sh void do not count. The
#        index is unstaged first because the gate runner stages it.
# continue resumes with a standard "finish the work and write the report"
#        message. Use it when a round stopped early: its report has no STATUS
#        line, or it is a progress note. If the log tail shows an API error,
#        first close Codex (stop the round's job; no `codex exec` of the task
#        may be left) and run `codex app-server daemon restart`.
# A feedback file may already be named feedback-rN.md inside the task
# directory; it is not copied onto itself.
# Every round passes the same arguments (codex_args in lib.sh): the sandbox as
# -c sandbox_mode, CODEX_MODEL, CODEX_EFFORT and CODEX_EXTRA_ARGS. Only start
# adds -C; `codex exec resume` has no --cd, so a resumed round runs from the
# worktree.
# --dry-run prints the Codex command and writes nothing.
# On completion it prints `REPORT STATUS=<status> lines=<n>` and
# `CODEX model=... effort=... sandbox=... tokens=...`, with warnings for a
# malformed report, a sandbox other than the one requested, or model or effort
# drift: a value other than CODEX_MODEL / CODEX_EFFORT, or, when those are
# unset, other than round 1's. Read those lines first.
# Every round is guarded (see lib.sh): it snapshots the repository's refs,
# worktree branches, shared git files and other checkouts before and after
# Codex runs and prints `GUARD PASS` or one `GUARD FAIL` line per change made
# outside the task's own worktree. A GUARD FAIL exits 5 (unless Codex itself
# failed) and stops acceptance until it is resolved; it is a forbidden action
# unless the planner made that change itself (ledger.sh guard-ack).

source "$(dirname "$0")/lib.sh"
cdl_load

mode=${1:-}; tid=${2:-}
[[ $mode == start || $mode == resume || $mode == continue ]] && [[ -n $tid ]] ||
  die "usage: run-codex.sh start <task-id> | resume <task-id> <feedback.md> | continue <task-id> [--dry-run]"
task_paths "$tid"
[[ -d $WT ]] || die "worktree $WT does not exist; run new-task.sh first"
[[ -d $TD ]] || die "task directory $TD does not exist"
command -v codex >/dev/null || die "codex CLI not found on PATH"
task_header
sandbox=$(task_sandbox)
codex_args "$sandbox"
codex_env
instructions=$(mode_file "$TASK_MODE")
[[ -s $instructions ]] || die "mode instructions $instructions are missing"
dry=0
[[ ${*: -1} == --dry-run ]] && dry=1
(( dry )) || task_tmp
stamp() { date -u +%FT%TZ; }
show() { printf 'DRY-RUN:'; printf ' %q' "$@"; echo; }
# Model and effort every round must report: the configured values, otherwise
# what round 1 recorded, so a resumed round cannot drift unnoticed.
expected() {  # field (model|effort), configured value
  local value=$2
  if [[ -z $value && -f $TD/rounds.log ]]; then
    value=$(grep -m1 '^round 1 CODEX ' "$TD/rounds.log" | sed -n "s/.* $1=\([^ ]*\).*/\1/p")
    [[ $value != unknown ]] || value=""
  fi
  echo "$value"
}
finish_round() {  # round, report, log
  local model effort
  model=$(expected model "$CODEX_MODEL"); effort=$(expected effort "$CODEX_EFFORT")
  echo "round $1 exit rc=$rc $(stamp)" >> "$TD/rounds.log"
  echo "codex rc=$rc mode=$TASK_MODE"
  { report_check "$2" || true; codex_meta "$3" "$sandbox" "$model" "$effort"; cat "$TD/guard-r$1.txt"; } |
    sed "s/^/round $1 /" | tee -a "$TD/rounds.log"
}
# One round: the start line first, so the guard counts this task as busy and
# leaves its own worktree alone; then snapshot, Codex, snapshot and verdict.
# The command runs from the worktree because resume has no --cd.
run_round() {  # round, report, log, stdin file, start line, command...
  local n=$1 report=$2 log=$3 input=$4 line=$5
  shift 5
  guard_settle
  echo "$line $(stamp)" >> "$TD/rounds.log"
  guard_snapshot "$TD/guard-r$n.before"
  set +e
  (cd "$WT" && "$@" < "$input") > "$log" 2>&1
  rc=$?
  set -e
  guard_check "$n"
  finish_round "$n" "$report" "$log"
  if grep -q '^GUARD FAIL' "$TD/guard-r$n.txt"; then
    echo "BREAKER: round $n of $TID changed state outside its worktree (GUARD FAIL above). Treat it as a forbidden action and stop all work; only if you made that change yourself, record it with ledger.sh guard-ack $TID r$n \"<what you changed>\"."
    (( rc != 0 )) || rc=5
  fi
  exit "$rc"
}

if [[ $mode == start ]]; then
  [[ -s $TD/task.md ]] || die "$TD/task.md is missing or empty; write it from $SKILL_DIR/templates/task.md"
  ! grep -qE '<TASK-ID>|<one-line goal>' "$TD/task.md" || die "$TD/task.md still holds template placeholders (<TASK-ID>, <one-line goal>)"
  [[ -s $TASKS_ROOT/common.md ]] || die "$TASKS_ROOT/common.md is missing"
  [[ ! -e $TD/report.md ]] || die "$TD/report.md exists; use resume, or move it away to restart"
  cmd=("${CODEX_ENV[@]}" codex exec -C "$WT" "${CODEX_ARGS[@]}" -o "$TD/report.md" -)
  if (( dry )); then
    show "${cmd[@]}"; echo "stdin: task.md + common.md + $instructions"; exit 0
  fi
  quiet=()
  [[ $TASK_QUIET == no ]] || quiet=("$SKILL_DIR/templates/quiet.md")
  cat "$TD/task.md" "$TASKS_ROOT/common.md" "$instructions" "${quiet[@]}" > "$TD/prompt.md"
  run_round 1 "$TD/report.md" "$TD/codex.log" "$TD/prompt.md" \
    "round 1 start mode=$TASK_MODE sandbox=$sandbox" "${cmd[@]}"
fi

[[ -f $TD/codex.log ]] || die "$TD/codex.log is missing; nothing to resume"
n=$(next_round)
if [[ $mode == continue ]]; then
  feedback=$TD/continue-r$n.md
  if (( ! dry )); then
    cat > "$feedback" <<'MSG'
# Continue and finish

Your previous round ended before its final report. Continue from the current
working tree: finish the task as specified, run the checks the task requires,
and write the complete report in the required format, starting with the STATUS
line. Do not restart work that is already done.
MSG
  fi
else
  feedback=${3:-}
  [[ -s $feedback ]] || die "feedback file '$feedback' is missing or empty"
fi
sid=$(grep -m1 -oiE 'session id: [0-9a-f-]{8,}' "$TD/codex.log" | awk '{print $3}' || true)
[[ -n $sid ]] || die "no 'session id:' line in $TD/codex.log"
voided=$(voided_rounds)
used=$((n - 1 - voided))
if (( used >= TASK_MAX_ROUNDS )); then
  echo "BREAKER: $TID already used $used of $TASK_MAX_ROUNDS rounds ($TASK_MAX_FROM; $voided voided as environment failures)." >&2
  echo "Stop this task without committing, keep its worktree and report its state." >&2
  exit 3
fi
cmd=("${CODEX_ENV[@]}" codex exec resume "${CODEX_ARGS[@]}" -o "$TD/report-r$n.md" "$sid" -)
if (( dry )); then show "${cmd[@]}"; echo "cwd: $WT; stdin: $feedback; round $n"; exit 0; fi
target=$TD/feedback-r$n.md
if [[ $(cd "$(dirname "$feedback")" && pwd -P)/$(basename "$feedback") != "$(cd "$TD" && pwd -P)/feedback-r$n.md" ]]; then
  cp "$feedback" "$target"
fi
git -C "$WT" reset -q
run_round "$n" "$TD/report-r$n.md" "$TD/codex-r$n.log" "$TD/feedback-r$n.md" \
  "round $n resume $sid mode=$TASK_MODE sandbox=$sandbox" "${cmd[@]}"
