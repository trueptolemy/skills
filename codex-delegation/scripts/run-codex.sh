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
# The task.md header selects the mode (implement, refactor, docs, investigate)
# and therefore the sandbox: investigate runs read-only. The prompt is
# task.md + common.md + the mode instructions, plus quiet.md when the task
# header says `Quiet: yes` (a measurement on the same host forbids test runs).
# start  writes report.md and codex.log.
# resume continues the recorded session with a feedback file and writes
#        report-rN.md and codex-rN.log. It refuses beyond MAX_ROUNDS (the
#        per-task circuit breaker). The index is unstaged first because the
#        gate runner stages it.
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
instructions=$(mode_file "$TASK_MODE")
[[ -s $instructions ]] || die "mode instructions $instructions are missing"
dry=0
[[ ${*: -1} == --dry-run ]] && dry=1
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
  { report_check "$2" || true; codex_meta "$3" "$sandbox" "$model" "$effort"; } |
    sed "s/^/round $1 /" | tee -a "$TD/rounds.log"
}

if [[ $mode == start ]]; then
  [[ -s $TD/task.md ]] || die "$TD/task.md is empty"
  [[ -s $TASKS_ROOT/common.md ]] || die "$TASKS_ROOT/common.md is missing"
  [[ ! -e $TD/report.md ]] || die "$TD/report.md exists; use resume, or move it away to restart"
  cmd=(codex exec -C "$WT" "${CODEX_ARGS[@]}" -o "$TD/report.md" -)
  if (( dry )); then
    show "${cmd[@]}"; echo "stdin: task.md + common.md + $instructions"; exit 0
  fi
  quiet=()
  [[ $TASK_QUIET == no ]] || quiet=("$SKILL_DIR/templates/quiet.md")
  cat "$TD/task.md" "$TASKS_ROOT/common.md" "$instructions" "${quiet[@]}" > "$TD/prompt.md"
  echo "round 1 start mode=$TASK_MODE sandbox=$sandbox $(stamp)" >> "$TD/rounds.log"
  set +e
  "${cmd[@]}" < "$TD/prompt.md" > "$TD/codex.log" 2>&1
  rc=$?
  set -e
  finish_round 1 "$TD/report.md" "$TD/codex.log"
  exit "$rc"
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
if (( n > MAX_ROUNDS )); then
  echo "BREAKER: $TID already used $((n - 1)) of MAX_ROUNDS=$MAX_ROUNDS rounds." >&2
  echo "Stop this task without committing, keep its worktree and report its state." >&2
  exit 3
fi
cmd=(codex exec resume "${CODEX_ARGS[@]}" -o "$TD/report-r$n.md" "$sid" -)
if (( dry )); then show "${cmd[@]}"; echo "cwd: $WT; stdin: $feedback; round $n"; exit 0; fi
target=$TD/feedback-r$n.md
if [[ $(realpath -m "$feedback") != "$(realpath -m "$target")" ]]; then
  cp "$feedback" "$target"
fi
git -C "$WT" reset -q
echo "round $n resume $sid mode=$TASK_MODE sandbox=$sandbox $(stamp)" >> "$TD/rounds.log"
set +e
(cd "$WT" && "${cmd[@]}" < "$TD/feedback-r$n.md") > "$TD/codex-r$n.log" 2>&1
rc=$?
set -e
finish_round "$n" "$TD/report-r$n.md" "$TD/codex-r$n.log"
exit "$rc"
