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
  GUARD_PLANNER=$TASKS_ROOT/guard-planner.log
  GATES_FILE=${GATES_FILE:-$TASKS_ROOT/gates.txt}
  FOCUSED_GATES_FILE=${FOCUSED_GATES_FILE:-$TASKS_ROOT/focused.txt}
  SETUP_HOOK=${SETUP_HOOK:-}
  MIN_FREE_GB=${MIN_FREE_GB:-3}
  MIN_FREE_INODES=${MIN_FREE_INODES:-100000}
  CODEX_SANDBOX=${CODEX_SANDBOX:-workspace-write}
  ALLOW_FULL_ACCESS=${ALLOW_FULL_ACCESS:-no}
  case $ALLOW_FULL_ACCESS in yes|no) ;; *) die "ALLOW_FULL_ACCESS must be yes or no (got $ALLOW_FULL_ACCESS)" ;; esac
  case $CODEX_SANDBOX in
    read-only|workspace-write) ;;
    danger-full-access)
      [[ $ALLOW_FULL_ACCESS == yes ]] ||
        die "CODEX_SANDBOX=danger-full-access needs ALLOW_FULL_ACCESS=yes in $conf (see SKILL.md, Permissions)" ;;
    *) die "CODEX_SANDBOX must be read-only, workspace-write or danger-full-access (got $CODEX_SANDBOX)" ;;
  esac
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
#   Sandbox: read-only|workspace-write|danger-full-access   (optional override;
#            operate requires it; danger-full-access needs operate mode or
#            ALLOW_FULL_ACCESS=yes)
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
      [[ $TASK_MODE == operate || $ALLOW_FULL_ACCESS == yes ]] ||
        die "task.md Sandbox danger-full-access needs Mode: operate or ALLOW_FULL_ACCESS=yes in the configuration"
      TASK_SANDBOX=$value ;;
    *) die "task.md Sandbox '$value' must be read-only, workspace-write or danger-full-access" ;;
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

# Free inodes of the filesystem that holds a path or its parent, or "unknown"
# when df reports none (some filesystems allocate inodes on demand). `df -i`
# output differs between systems, so the column is found by its header.
free_inodes() {
  local path=$1
  while [[ ! -e $path ]]; do path=$(dirname "$path"); done
  { df -Pi "$path" 2>/dev/null || df -i "$path" 2>/dev/null || true; } | awk '
    NR == 1 { for (i = 1; i <= NF; i++) { h = tolower($i); if (h == "ifree") f = i; if (h == "iused") u = i }; next }
    NR == 2 && f && $f ~ /^[0-9]+$/ && $f + (u ? $u : 0) > 0 { print $f; found = 1 }
    END { if (!found) print "unknown" }'
}

# Check the filesystems tasks write to, one PASS or FAIL line each, and return
# 1 on any failure: the worktree root holds every checkout and, through
# TMPDIR=$WT/.tmp, the temporary files of Codex and the gates (MIN_FREE_GB
# and MIN_FREE_INODES); the caller's TMPDIR and /tmp, which some tools use
# whatever TMPDIR says, need MIN_FREE_INODES. A small /tmp can run out of
# inodes long before the disk runs out of space.
storage_check() {
  local rc=0 path mount seen=" " free inodes first=1
  for path in "$WT_ROOT" "${TMPDIR:-/tmp}" /tmp; do
    while [[ ! -e $path ]]; do path=$(dirname "$path"); done
    mount=$(df -P "$path" | awk 'NR == 2 { print $NF }')
    if [[ $seen == *" $mount "* ]]; then first=0; continue; fi
    seen+="$mount "
    if (( first )); then
      free=$(free_gb "$path")
      if (( free >= MIN_FREE_GB )); then echo "PASS  ${free} GiB free under $path"
      else echo "FAIL  only ${free} GiB free under $path (MIN_FREE_GB=$MIN_FREE_GB)"; rc=1; fi
      first=0
    fi
    inodes=$(free_inodes "$path")
    if [[ $inodes == unknown ]]; then echo "PASS  free inodes under $path: not reported by df"
    elif (( inodes >= MIN_FREE_INODES )); then echo "PASS  $inodes inodes free under $path"
    else echo "FAIL  only $inodes inodes free under $path (MIN_FREE_INODES=$MIN_FREE_INODES)"; rc=1; fi
  done
  return "$rc"
}

# The repository's common git directory, shared by all its worktrees.
git_common_dir() { (cd "$REPO" && cd "$(git rev-parse --git-common-dir)" && pwd); }

# Create the task's temporary directory, $WT/.tmp, which Codex and the gates
# get as TMPDIR and PYTEST_DEBUG_TEMPROOT. Every worktree has its own, so
# parallel runs cannot fill or clean each other's, and it goes with the
# worktree. /.tmp/ is ignored through the info/exclude all worktrees share.
task_tmp() {
  local exclude
  exclude=$(git_common_dir)/info/exclude
  grep -qxF '/.tmp/' "$exclude" 2>/dev/null || { mkdir -p "${exclude%/*}"; echo '/.tmp/' >> "$exclude"; }
  mkdir -p "$WT/.tmp"
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
# The approval policy is always never: `codex exec` cannot ask anyone, and it
# has no --ask-for-approval flag, so the policy is passed with -c like the
# sandbox.
# Only flags that both `codex exec` and `codex exec resume` accept belong here
# (doctor.sh checks CODEX_EXTRA_ARGS against both); the start round adds -C,
# and resume, which has no --cd, runs from the worktree instead.
codex_args() {  # sandbox
  local extra=()
  read -ra extra <<< "$CODEX_EXTRA_ARGS"
  CODEX_ARGS=(-c "sandbox_mode=\"$1\"" -c 'approval_policy="never"')
  [[ -z $CODEX_MODEL ]] || CODEX_ARGS+=(-m "$CODEX_MODEL")
  [[ -z $CODEX_EFFORT ]] || CODEX_ARGS+=(-c "model_reasoning_effort=\"$CODEX_EFFORT\"")
  CODEX_ARGS+=("${extra[@]}")
}

# The environment prefix of every Codex round, in CODEX_ENV: the task's own
# temporary directory (task_tmp), and outside operate tasks no ssh agent and
# a git that refuses ssh transport, so a round
# cannot reach a real system or push through keys the agent holds. This does
# not stop ssh with a key file it reads directly; common.md forbids that.
codex_env() {  # env options (-u) must precede its assignments
  CODEX_ENV=(env)
  [[ $TASK_MODE == operate ]] ||
    CODEX_ENV+=(-u SSH_AUTH_SOCK 'GIT_SSH_COMMAND=echo "codex-delegation: ssh is disabled outside operate tasks" >&2; false')
  CODEX_ENV+=("TMPDIR=$WT/.tmp" "PYTEST_DEBUG_TEMPROOT=$WT/.tmp")
}

# Extract the run header and token count from one Codex log. codex-cli prints
# a header between two `--------` lines (`model:`, `sandbox:`, `reasoning
# effort:`, `session id:`, ...) and `tokens used` followed by the count last.
# A line the CLI does not print reads `unknown`. Warn when the applied
# sandbox, model or effort differs from the expected one; an empty
# expectation is not checked.
codex_meta() {  # log, sandbox, [model], [effort]
  local log=$1 want_sandbox=$2 want_model=${3:-} want_effort=${4:-} header sandbox model effort approval tokens
  header=$(head -n 40 "$log" | awk '/^--------$/ { if (++n == 2) exit } { print }')
  sandbox=$(sed -n 's/^sandbox:[[:space:]]*\([a-z-]*\).*/\1/p' <<< "$header" | head -n 1)
  model=$(sed -n 's/^model:[[:space:]]*//p' <<< "$header" | head -n 1)
  effort=$(sed -n 's/^reasoning effort:[[:space:]]*//p' <<< "$header" | head -n 1)
  approval=$(sed -n 's/^approval:[[:space:]]*//p' <<< "$header" | head -n 1)
  tokens=$(grep -A1 '^tokens used' "$log" | tail -n 1 | tr -dc '0-9' || true)
  echo "CODEX model=${model:-unknown} effort=${effort:-unknown} sandbox=${sandbox:-unknown} tokens=${tokens:-unknown}"
  if [[ -n $sandbox && $sandbox != "$want_sandbox" ]]; then
    echo "CODEX WARNING: requested sandbox $want_sandbox but the run reports $sandbox"
  fi
  if [[ -n $approval && $approval != never ]]; then
    echo "CODEX WARNING: requested approval policy never but the run reports $approval"
  fi
  if [[ -n $want_model && -n $model && $model != "$want_model" ]]; then
    echo "CODEX WARNING: model drift: expected $want_model but the run reports $model"
  fi
  if [[ -n $want_effort && -n $effort && $effort != "$want_effort" ]]; then
    echo "CODEX WARNING: effort drift: expected $want_effort but the run reports $effort"
  fi
}

# --- Repository guard ------------------------------------------------------------
# A round may change only the files of its own worktree. guard_snapshot writes,
# one `key<TAB>value` line each, what a round must leave alone:
#   ref:<name>     every ref except refs/remotes and refs/prefetch, which
#                  background fetches move: commits, resets, stashes, branches
#   head:<path>    the branch, or the detached commit, of every worktree
#   git:<name>     the shared config, info/exclude and hooks
#   status:<path>  the changes in the main checkout and in each task worktree,
#                  after the activity of the worktree's own task
# guard_check compares a round's two snapshots. A difference passes only when
# a planner script recorded it (new-task.sh and finish-task.sh call
# planner_begin) or, for a task worktree, when its own task ran a round or a
# gate run in between, which changes that worktree legitimately.

# Whether a task's latest round has started and not yet exited.
round_running() {  # task directory
  local last
  last=$(grep -E '^round [0-9]+ (start|resume|exit) ' "$1/rounds.log" 2>/dev/null | tail -n 1 || true)
  [[ -n $last && $last != *" exit "* ]]
}

# "busy" while a task's round or gate run is in progress, otherwise a hash of
# its round and gate records, which changes with every round or gate run.
task_activity() {  # task directory
  local td=$1 sum
  round_running "$td" && { echo busy; return; }
  for sum in "$td"/gates-*/summary.txt; do
    [[ ! -f $sum || $(tail -n 1 "$sum") == DONE ]] || { echo busy; return; }
  done
  { cat "$td/rounds.log" "$td"/gates-*/summary.txt 2>/dev/null || true; } | git hash-object --stdin
}

guard_snapshot() {  # output file
  local common wt_root path branch real kind first=1 f
  common=$(git_common_dir)
  wt_root=$(cd "$WT_ROOT" 2>/dev/null && pwd -P || echo "$WT_ROOT")
    {
    printf '#planner\t%s\n' "$( [[ -f $GUARD_PLANNER ]] && wc -l < "$GUARD_PLANNER" | tr -d ' ' || echo 0)"
    git -C "$REPO" for-each-ref --format='ref:%(refname)%09%(objectname)' |
      grep -vE '^ref:refs/(remotes|prefetch)/' || true
    for f in config info/exclude; do
      printf 'git:%s\t%s\n' "$f" "$( [[ -f $common/$f ]] && git hash-object --no-filters "$common/$f" || echo absent)"
    done
    printf 'git:hooks\t%s\n' "$( { cd "$common" && find hooks -type f 2>/dev/null | LC_ALL=C sort |
      while IFS= read -r f; do echo "$(git hash-object --no-filters "$f") $f"; done; } | git hash-object --stdin)"
    git -C "$REPO" worktree list --porcelain | awk -v OFS='\t' '
      /^worktree / { path = substr($0, 10) }
      /^HEAD / { head = $2 }
      /^branch / { branch = $2 }
      /^detached/ { branch = "detached " head }
      /^$/ { if (path != "") print path, branch; path = branch = "" }
      END { if (path != "") print path, branch }' |
    while IFS=$'\t' read -r path branch; do
      real=$(cd "$path" 2>/dev/null && pwd -P || echo "$path")
      printf 'head:%s\t%s\n' "$real" "$branch"
      if (( first )); then kind=main
      elif [[ ${real%/*} == "$wt_root" ]]; then kind=$(task_activity "$TASKS_ROOT/${real##*/}")
      else kind=""; fi
      first=0
      [[ -n $kind ]] || continue
      printf 'status:%s\t%s %s\n' "$real" "$kind" "$( { GIT_OPTIONAL_LOCKS=0 git -C "$path" status --porcelain -uall &&
        git -C "$path" diff HEAD --binary; } 2>/dev/null | git hash-object --stdin)"
    done
  } > "$1"
}

# key<TAB>before<TAB>after for every key whose value differs ("absent" when
# a key exists on one side only).
guard_diff() {  # before, after
  awk -F'\t' -v OFS='\t' '
    /^#/ { next }
    FILENAME == ARGV[1] { a[$1] = $2; next }
    { b[$1] = $2 }
    END {
      for (k in a) if (!(k in b)) print k, a[k], "absent"; else if (a[k] != b[k]) print k, a[k], b[k]
      for (k in b) if (!(k in a)) print k, "absent", b[k]
    }' "$1" "$2" | LC_ALL=C sort
}

# Planner scripts that change refs, worktrees or shared git files record their
# own differences, so a round running in parallel does not report them.
planner_begin() {
  PLANNER_BEFORE=$TASKS_ROOT/.planner-$$.before
  guard_snapshot "$PLANNER_BEFORE"
  trap planner_end EXIT
}
planner_end() {
  guard_snapshot "$TASKS_ROOT/.planner-$$.after"
  guard_diff "$PLANNER_BEFORE" "$TASKS_ROOT/.planner-$$.after" | cut -f1,3 >> "$GUARD_PLANNER"
  rm -f "$PLANNER_BEFORE" "$TASKS_ROOT/.planner-$$.after"
}

guard_short() {  # abbreviate a commit id, alone or after "detached "
  if [[ $1 =~ ^(detached )?([0-9a-f]{12})[0-9a-f]{28,}$ ]]; then echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; else echo "$1"; fi
}

# Write round N's verdict to guard-rN.txt: GUARD PASS, or one GUARD FAIL line
# per difference nobody accounted for. A round that ended without its second
# snapshot (a stopped job) is compared with the current state.
guard_check() {  # round
  local n=$1 before=$TD/guard-r$n.before after=$TD/guard-r$n.after out=$TD/guard-r$n.txt
  local offset recorded key old new
  [[ -f $after ]] || guard_snapshot "$after"
  offset=$(awk -F'\t' '$1 == "#planner" { print $2 }' "$before")
  recorded=$(tail -n +"$((${offset:-0} + 1))" "$GUARD_PLANNER" 2>/dev/null || true)
  : > "$out"
  while IFS=$'\t' read -r key old new; do
    if [[ $key == status:* ]]; then
      [[ $old != absent && $new != absent && ${old%% *} != busy && ${old%% *} == "${new%% *}" ]] || continue
    fi
    grep -qxF "$key"$'\t'"$new" <<< "$recorded" && continue
    case $key in
      ref:*|head:*) echo "GUARD FAIL $key $(guard_short "$old") -> $(guard_short "$new")" ;;
      *) echo "GUARD FAIL $key changed" ;;
    esac >> "$out"
  done < <(guard_diff "$before" "$after")
  [[ -s $out ]] || echo "GUARD PASS refs, worktree branches, shared git files and idle checkouts unchanged" > "$out"
}

# Give every round of the task that has no verdict yet its verdict.
guard_settle() {
  local f n
  for f in "$TD"/guard-r*.before; do
    [[ -f $f ]] || continue
    n=${f##*/guard-r}; n=${n%.before}
    [[ -f $TD/guard-r$n.txt ]] || guard_check "$n"
  done
}

# The task's GUARD FAIL lines that ledger.sh guard-ack has not acknowledged,
# as `rN <what changed>`.
guard_failures() {
  local f n
  for f in "$TD"/guard-r*.txt; do
    [[ -f $f ]] || continue
    n=${f##*/guard-r}; n=${n%.txt}
    [[ ! -f $TD/guard-r$n.ack ]] || continue
    sed -n "s/^GUARD FAIL /r$n /p" "$f"
  done
}

# The next unused round number for a task, counting report.md as round 1.
next_round() {
  local n=2
  while [[ -e $TD/report-r$n.md ]]; do n=$((n + 1)); done
  echo "$n"
}
