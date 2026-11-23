#!/usr/bin/env bash
# Shared configuration and helpers for the codex-delegation scripts.
# Every script sources this file; it never runs Codex or mutates a repository.

set -euo pipefail

SKILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODES="implement refactor docs investigate operate"
VERIFIED_CODEX_VERSIONS="0.162.1"

die() { echo "error: $*" >&2; exit 2; }

# Load the per-project configuration. CDL_CONF overrides the default
# ./codex-delegation.conf so one machine can drive several repositories.
# Precedence: the project file, then PRESET defaults, then built-in defaults.
cdl_load() {
  local conf=${CDL_CONF:-./codex-delegation.conf}
  [[ -f $conf ]] || die "configuration $conf not found; copy $SKILL_DIR/templates/codex-delegation.conf and set CDL_CONF"
  # shellcheck disable=SC1090
  source "$conf"
  if [[ -n ${PRESET:-} ]]; then
    local preset=$SKILL_DIR/templates/presets/$PRESET.conf
    [[ -f $preset ]] || die "unknown PRESET '$PRESET'; see $SKILL_DIR/templates/presets"
    # shellcheck disable=SC1090
    source "$preset"
  fi
  [[ -n ${REPO:-} ]] || die "REPO is not set in $conf"
  REPO=$(cd "$REPO" && pwd)
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "REPO=$REPO is not a git repository"
  BASE_BRANCH=${BASE_BRANCH:-$(git -C "$REPO" symbolic-ref --short HEAD)}
  WT_ROOT=${WT_ROOT:-${REPO}-wt}
  TASKS_ROOT=${TASKS_ROOT:-${REPO}-tasks}
  GATES_FILE=${GATES_FILE:-$TASKS_ROOT/gates.txt}
  FOCUSED_GATES_FILE=${FOCUSED_GATES_FILE:-$TASKS_ROOT/focused.txt}
  SETUP_HOOK=${SETUP_HOOK:-}
  MIN_FREE_GB=${MIN_FREE_GB:-3}
  CODEX_SANDBOX=${CODEX_SANDBOX:-workspace-write}
  CODEX_MODEL=${CODEX_MODEL:-}
  CODEX_EFFORT=${CODEX_EFFORT:-}
  CODEX_EXTRA_ARGS=${CODEX_EXTRA_ARGS:-}
  SUPPRESSION_PATTERN=${SUPPRESSION_PATTERN:-'noqa|type: ignore|pylint: disable|pragma: no cover|eslint-disable|@ts-ignore|@ts-expect-error|NOLINT|@SuppressWarnings|#\[allow\(|//nolint'}
  SKIP_PATTERN=${SKIP_PATTERN:-'\.skip\(|pytest\.mark\.skip|t\.Skip\(|#\[ignore\]|@Disabled|@Ignore|DISABLED_'}
  FAIL_PATTERN=${FAIL_PATTERN:-'^(FAILED|ERROR)[ :]'}
  TEST_PATHS=${TEST_PATHS:-'(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$|Tests?\.java$'}
  DOC_PATHS=${DOC_PATHS:-'\.(md|rst|txt|adoc)$|(^|/)docs?/'}
  REPORT_MAX_LINES=${REPORT_MAX_LINES:-80}
  MAX_ROUNDS=${MAX_ROUNDS:-3}
  MAX_FULL_READS=${MAX_FULL_READS:-3}
  DELIVERY=${DELIVERY:-ff-merge}
  case $DELIVERY in ff-merge|branch-only|patch) ;; *) die "DELIVERY must be ff-merge, branch-only or patch (got $DELIVERY)" ;; esac
  MSG_FILE_CHECK=${MSG_FILE_CHECK:-}
  MSG_COMMIT_CHECK=${MSG_COMMIT_CHECK:-}
  GATE_ENV=${GATE_ENV:-}
}

# Resolve the worktree and task directory of one task identifier.
task_paths() {
  TID=${1:?task id required}
  [[ $TID =~ ^[A-Za-z0-9._-]+$ ]] || die "task id '$TID' may contain only letters, digits, '.', '_' and '-'"
  WT=$WT_ROOT/$TID
  TD=$TASKS_ROOT/$TID
}

# Read the task header fields from the first 30 lines of task.md:
#   Mode: implement|refactor|docs|investigate|operate (default implement)
#   Allowed paths: src/foo/*, tests/test_foo*      (optional scope globs)
#   Sandbox: read-only|workspace-write             (optional override;
#            operate requires it and also accepts danger-full-access)
#   Quiet: yes                                     (no test runs; see quiet.md)
task_header() {
  local file=$TD/task.md value
  TASK_MODE=implement; TASK_ALLOWED=""; TASK_SANDBOX=""; TASK_QUIET=no
  [[ -f $file ]] || return 0
  value=$(head -n 30 "$file" | sed -n 's/^Mode:[[:space:]]*//p' | head -n 1 | xargs || true)
  [[ -z $value ]] || TASK_MODE=$value
  [[ " $MODES " == *" $TASK_MODE "* ]] || die "task.md Mode '$TASK_MODE' is not one of: $MODES"
  TASK_ALLOWED=$(head -n 30 "$file" | sed -n 's/^Allowed paths:[[:space:]]*//p' | head -n 1 || true)
  value=$(head -n 30 "$file" | sed -n 's/^Quiet:[[:space:]]*//p' | head -n 1 | xargs || true)
  case $value in
    ""|no) ;;
    yes) TASK_QUIET=yes ;;
    *) die "task.md Quiet '$value' must be yes or no" ;;
  esac
  value=$(head -n 30 "$file" | sed -n 's/^Sandbox:[[:space:]]*//p' | head -n 1 | xargs || true)
  case $value in
    "") ;;
    read-only|workspace-write) TASK_SANDBOX=$value ;;
    danger-full-access)
      [[ $TASK_MODE == operate ]] || die "task.md Sandbox danger-full-access is allowed only in operate mode"
      TASK_SANDBOX=$value ;;
    *) die "task.md Sandbox '$value' must be read-only, workspace-write or (operate only) danger-full-access" ;;
  esac
  # An operate task acts on a real system; its sandbox is always an explicit,
  # user-authorized choice, never a default.
  if [[ $TASK_MODE == operate && -z $TASK_SANDBOX ]]; then
    die "operate mode requires an explicit Sandbox: line in task.md"
  fi
}

# The sandbox a task runs in: investigate is read-only unless overridden, and
# operate always names its own.
task_sandbox() {
  if [[ -n $TASK_SANDBOX ]]; then echo "$TASK_SANDBOX"
  elif [[ $TASK_MODE == investigate ]]; then echo read-only
  else echo "$CODEX_SANDBOX"; fi
}

# The Codex instructions for a mode: a project override in TASKS_ROOT/modes,
# otherwise the packaged one.
mode_file() {
  local own=$TASKS_ROOT/modes/$1.md
  if [[ -f $own ]]; then echo "$own"; else echo "$SKILL_DIR/templates/modes/$1.md"; fi
}

# Whether a repository path matches one comma-separated glob list. In these
# patterns `*` also matches '/', so `src/foo/*` covers the whole subtree.
path_allowed() {
  local path=$1 list=$2 glob
  IFS=',' read -ra globs <<< "$list"
  for glob in "${globs[@]}"; do
    glob=$(echo "$glob" | xargs)
    [[ -n $glob ]] || continue
    # shellcheck disable=SC2053
    [[ $path == $glob ]] && return 0
  done
  return 1
}

# Free space, in whole GiB, of the filesystem that holds a path or its parent.
free_gb() {
  local path=$1
  while [[ ! -e $path ]]; do path=$(dirname "$path"); done
  df -Pk "$path" | awk 'NR == 2 { printf "%d", $4 / 1048576 }'
}

# Check a report's protocol shape so the planner can read the STATUS line
# first and notice drift without opening a malformed report in full.
report_check() {
  local report=$1 lines status
  if [[ ! -s $report ]]; then echo "REPORT MISSING $report"; return 1; fi
  lines=$(wc -l < "$report")
  status=$(head -n 5 "$report" | grep -m1 -oE 'STATUS: *[A-Z]+' | awk '{print $2}' || true)
  echo "REPORT STATUS=${status:-UNKNOWN} lines=$lines $report"
  if [[ -z $status ]]; then
    echo "REPORT WARNING: no STATUS line in the first 5 lines"
    echo "REPORT HINT: the round may have stopped early; check the log tail for an API error; if there is one, close Codex and run codex app-server daemon restart; then run run-codex.sh continue $TID"
  fi
  (( lines <= REPORT_MAX_LINES )) || echo "REPORT WARNING: $lines lines exceed $REPORT_MAX_LINES"
}

# The Codex arguments of every round of a task, start and resume alike, in
# CODEX_ARGS. A resumed round given fewer arguments falls back to the global
# Codex configuration, so it silently runs another model, effort or sandbox.
# Only flags that both `codex exec` and `codex exec resume` accept belong here
# (doctor.sh checks CODEX_EXTRA_ARGS against both); the start round adds -C,
# and resume, which has no --cd, runs from the worktree instead.
codex_args() {  # sandbox
  local extra=()
  read -ra extra <<< "$CODEX_EXTRA_ARGS"
  CODEX_ARGS=(-c "sandbox_mode=\"$1\"")
  [[ -z $CODEX_MODEL ]] || CODEX_ARGS+=(-m "$CODEX_MODEL")
  [[ -z $CODEX_EFFORT ]] || CODEX_ARGS+=(-c "model_reasoning_effort=\"$CODEX_EFFORT\"")
  CODEX_ARGS+=("${extra[@]}")
}

# Extract the run header and token count from one Codex log. codex-cli prints
# a header between two `--------` lines (`model:`, `sandbox:`, `reasoning
# effort:`, `session id:`, ...) and `tokens used` followed by the count last.
# A line the CLI does not print reads `unknown`. Warn when the applied
# sandbox, model or effort differs from the expected one; an empty
# expectation is not checked.
codex_meta() {  # log, sandbox, [model], [effort]
  local log=$1 want_sandbox=$2 want_model=${3:-} want_effort=${4:-} header sandbox model effort tokens
  header=$(head -n 40 "$log" | awk '/^--------$/ { if (++n == 2) exit } { print }')
  sandbox=$(sed -n 's/^sandbox:[[:space:]]*\([a-z-]*\).*/\1/p' <<< "$header" | head -n 1)
  model=$(sed -n 's/^model:[[:space:]]*//p' <<< "$header" | head -n 1)
  effort=$(sed -n 's/^reasoning effort:[[:space:]]*//p' <<< "$header" | head -n 1)
  tokens=$(grep -A1 '^tokens used' "$log" | tail -n 1 | tr -dc '0-9' || true)
  echo "CODEX model=${model:-unknown} effort=${effort:-unknown} sandbox=${sandbox:-unknown} tokens=${tokens:-unknown}"
  if [[ -n $sandbox && $sandbox != "$want_sandbox" ]]; then
    echo "CODEX WARNING: requested sandbox $want_sandbox but the run reports $sandbox"
  fi
  if [[ -n $want_model && -n $model && $model != "$want_model" ]]; then
    echo "CODEX WARNING: model drift: expected $want_model but the run reports $model"
  fi
  if [[ -n $want_effort && -n $effort && $effort != "$want_effort" ]]; then
    echo "CODEX WARNING: effort drift: expected $want_effort but the run reports $effort"
  fi
}

# The next unused round number for a task, counting report.md as round 1.
next_round() {
  local n=2
  while [[ -e $TD/report-r$n.md ]]; do n=$((n + 1)); done
  echo "$n"
}
