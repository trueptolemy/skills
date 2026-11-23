#!/usr/bin/env bash
# Run Codex for one task in its worktree; the orchestrator reads only reports.
# Usage:
#   run-codex.sh start  <task-id> [--dry-run]
#   run-codex.sh resume <task-id> <feedback.md> [--dry-run]
#
# Launch this command in the background (Claude Code: Bash run_in_background)
# and wait for its completion notification. Do not poll the log and do not use
# `&` plus `pgrep -f`: a waiter whose command line contains the pattern matches
# itself and never exits.
#
# The task.md header selects the mode (implement, refactor, docs, investigate)
# and therefore the sandbox: investigate runs read-only. The prompt is
# task.md + common.md + the mode instructions.
# start  writes report.md and codex.log.
# resume continues the recorded session with a feedback file and writes
#        report-rN.md and codex-rN.log. It refuses beyond MAX_ROUNDS (the
#        per-task circuit breaker). `codex exec resume` has no --sandbox or --cd
#        flag, so the sandbox is passed with -c and the command runs from the
#        worktree. The index is unstaged first because the gate runner stages it.
# --dry-run prints the Codex command and writes nothing.
# On completion it prints `REPORT STATUS=<status> lines=<n>` and
# `CODEX model=... sandbox=... tokens=...`, with warnings for a malformed report
# or a sandbox other than the one requested. Read those lines first.

source "$(dirname "$0")/lib.sh"
cdl_load

mode=${1:-}; tid=${2:-}
[[ $mode == start || $mode == resume ]] && [[ -n $tid ]] ||
  die "usage: run-codex.sh start <task-id> | resume <task-id> <feedback.md> [--dry-run]"
task_paths "$tid"
[[ -d $WT ]] || die "worktree $WT does not exist; run new-task.sh first"
[[ -d $TD ]] || die "task directory $TD does not exist"
command -v codex >/dev/null || die "codex CLI not found on PATH"
task_header
sandbox=$(task_sandbox)
instructions=$(mode_file "$TASK_MODE")
[[ -s $instructions ]] || die "mode instructions $instructions are missing"
dry=0
[[ ${*: -1} == --dry-run ]] && dry=1
stamp() { date -u +%FT%TZ; }
show() { printf 'DRY-RUN:'; printf ' %q' "$@"; echo; }
finish_round() {  # round, report, log
  echo "round $1 exit rc=$rc $(stamp)" >> "$TD/rounds.log"
  echo "codex rc=$rc mode=$TASK_MODE"
  { report_check "$2" || true; codex_meta "$3" "$sandbox"; } | sed "s/^/round $1 /" | tee -a "$TD/rounds.log"
}

if [[ $mode == start ]]; then
  [[ -s $TD/task.md ]] || die "$TD/task.md is empty"
  [[ -s $TASKS_ROOT/common.md ]] || die "$TASKS_ROOT/common.md is missing"
  [[ ! -e $TD/report.md ]] || die "$TD/report.md exists; use resume, or move it away to restart"
  # shellcheck disable=SC2206
  cmd=(codex exec -C "$WT" -s "$sandbox" $CODEX_EXTRA_ARGS -o "$TD/report.md" -)
  if (( dry )); then
    show "${cmd[@]}"; echo "stdin: task.md + common.md + $instructions"; exit 0
  fi
  cat "$TD/task.md" "$TASKS_ROOT/common.md" "$instructions" > "$TD/prompt.md"
  echo "round 1 start mode=$TASK_MODE sandbox=$sandbox $(stamp)" >> "$TD/rounds.log"
  set +e
  "${cmd[@]}" < "$TD/prompt.md" > "$TD/codex.log" 2>&1
  rc=$?
  set -e
  finish_round 1 "$TD/report.md" "$TD/codex.log"
  exit "$rc"
fi

feedback=${3:-}
[[ -s $feedback ]] || die "feedback file '$feedback' is missing or empty"
[[ -f $TD/codex.log ]] || die "$TD/codex.log is missing; nothing to resume"
sid=$(grep -m1 -oiE 'session id: [0-9a-f-]{8,}' "$TD/codex.log" | awk '{print $3}' || true)
[[ -n $sid ]] || die "no 'session id:' line in $TD/codex.log"
n=$(next_round)
if (( n > MAX_ROUNDS )); then
  echo "BREAKER: $TID already used $((n - 1)) of MAX_ROUNDS=$MAX_ROUNDS rounds." >&2
  echo "Stop this task without committing, keep its worktree and report its state." >&2
  exit 3
fi
cmd=(codex exec resume -c "sandbox_mode=\"$sandbox\"" -o "$TD/report-r$n.md" "$sid" -)
if (( dry )); then show "${cmd[@]}"; echo "cwd: $WT; stdin: $feedback; round $n"; exit 0; fi
cp "$feedback" "$TD/feedback-r$n.md"
git -C "$WT" reset -q
echo "round $n resume $sid mode=$TASK_MODE sandbox=$sandbox $(stamp)" >> "$TD/rounds.log"
set +e
(cd "$WT" && "${cmd[@]}" < "$TD/feedback-r$n.md") > "$TD/codex-r$n.log" 2>&1
rc=$?
set -e
finish_round "$n" "$TD/report-r$n.md" "$TD/codex-r$n.log"
exit "$rc"
