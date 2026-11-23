#!/usr/bin/env bash
# Check that this machine and project can run the delegation scripts.
# Usage: doctor.sh [--smoke]
#
# Without --smoke no model is called: it checks git, the Codex CLI version and
# the exec/resume flags the scripts depend on, and, when a configuration is
# found (CDL_CONF or ./codex-delegation.conf), the repository, gates, common
# rules, setup hook and free disk space.
# --smoke additionally runs one tiny paid Codex call with the arguments every
# task round uses (CODEX_MODEL, CODEX_EFFORT, CODEX_EXTRA_ARGS; read-only
# sandbox) and verifies the log shape the scripts parse (`session id:`,
# `sandbox:`, `model:`, `tokens used`), so it proves the model ID the tasks will
# really run. Ask the user before using it.

source "$(dirname "$0")/lib.sh"
smoke=0
[[ ${1:-} == --smoke ]] && smoke=1
fails=0; warns=0
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; warns=$((warns + 1)); }
fail() { echo "FAIL  $*"; fails=$((fails + 1)); }

echo "bash  $BASH_VERSION (verified: 5.2)"
if command -v git >/dev/null; then
  pass "$(git --version)"
else
  fail "git not found"
fi

if command -v codex >/dev/null; then
  version=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
  if [[ " $VERIFIED_CODEX_VERSIONS " == *" $version "* ]]; then
    pass "codex $version is a verified version"
  else
    warn "codex ${version:-unknown} is not in the verified list ($VERIFIED_CODEX_VERSIONS); run with --smoke once"
  fi
  help=$(codex exec --help 2>&1 || true)
  for flag in --cd --config --model --output-last-message; do
    grep -q -- "$flag" <<< "$help" && pass "codex exec supports $flag" || fail "codex exec lacks $flag"
  done
  for value in read-only workspace-write danger-full-access; do
    grep -q -- "$value" <<< "$help" && pass "codex sandbox mode $value exists" || fail "codex sandbox mode $value is missing"
  done
  rhelp=$(codex exec resume --help 2>&1 || true)
  for flag in --config --model --output-last-message; do
    grep -q -- "$flag" <<< "$rhelp" && pass "codex exec resume supports $flag" || fail "codex exec resume lacks $flag"
  done
  if grep -q -- "--sandbox" <<< "$rhelp"; then
    warn "codex exec resume now has --sandbox; the -c sandbox_mode form still applies, but review run-codex.sh"
  fi
else
  fail "codex CLI not found on PATH"
fi

conf=${CDL_CONF:-./codex-delegation.conf}
project_checks() {
  cdl_load
  echo "conf  $conf (REPO=$REPO, BASE_BRANCH=$BASE_BRANCH, PRESET=${PRESET:-none}, DELIVERY=$DELIVERY)"
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
    echo "PASS  base branch $BASE_BRANCH exists"
  else
    echo "FAIL  base branch $BASE_BRANCH not found"
  fi
  if [[ -f $GATES_FILE ]] && grep -qE '^[^#[:space:]][^|]*\|' "$GATES_FILE"; then
    echo "PASS  gates file $GATES_FILE has gate lines"
  else
    echo "FAIL  gates file $GATES_FILE is missing or has no gate lines"
  fi
  if [[ -f $FOCUSED_GATES_FILE ]] && grep -qE '^[^#[:space:]][^|]*\|' "$FOCUSED_GATES_FILE"; then
    echo "PASS  focused gates file $FOCUSED_GATES_FILE has gate lines"
  else
    echo "WARN  focused gates file $FOCUSED_GATES_FILE is missing; --focused rounds will refuse (see templates/focused.example)"
  fi
  if [[ -s $TASKS_ROOT/common.md ]]; then
    echo "PASS  common rules $TASKS_ROOT/common.md"
    if grep -qE '\[(AGENTS|Real-system|the real systems|private paths|Interpreter)' "$TASKS_ROOT/common.md"; then
      echo "WARN  common.md still contains template placeholders"
    fi
  else
    echo "FAIL  $TASKS_ROOT/common.md is missing"
  fi
  # Every round passes the same arguments, so each extra flag must be one
  # that both `codex exec` and `codex exec resume` accept.
  local extra=() flag
  read -ra extra <<< "$CODEX_EXTRA_ARGS"
  for flag in "${extra[@]}"; do
    [[ $flag == -* && -n ${help:-} ]] || continue
    flag=${flag%%=*}
    grep -qE -- "(^|[[:space:],])$flag([[:space:],=]|$)" <<< "$help" ||
      echo "FAIL  CODEX_EXTRA_ARGS flag $flag is not accepted by codex exec"
    grep -qE -- "(^|[[:space:],])$flag([[:space:],=]|$)" <<< "$rhelp" ||
      echo "FAIL  CODEX_EXTRA_ARGS flag $flag is not accepted by codex exec resume; resumed rounds use the same arguments and would fail"
  done
  codex_args "$CODEX_SANDBOX"
  echo "PASS  every round passes:$(printf ' %q' "${CODEX_ARGS[@]}")"
  echo "PASS  sandbox: write modes $CODEX_SANDBOX (ALLOW_FULL_ACCESS=$ALLOW_FULL_ACCESS), investigate read-only, operate per task"
  if [[ -n $SETUP_HOOK && ! -x $SETUP_HOOK ]]; then
    echo "FAIL  setup hook $SETUP_HOOK is not executable"
  fi
  local free; free=$(free_gb "$WT_ROOT")
  if (( free >= MIN_FREE_GB )); then
    echo "PASS  ${free} GiB free under $WT_ROOT"
  else
    echo "FAIL  only ${free} GiB free under $WT_ROOT (MIN_FREE_GB=$MIN_FREE_GB)"
  fi
}
if [[ -f $conf ]]; then
  report=$( (project_checks) 2>&1 || true)
  echo "$report"
  fails=$((fails + $(grep -c '^FAIL\|^error:' <<< "$report" || true)))
  warns=$((warns + $(grep -c '^WARN' <<< "$report" || true)))
else
  warn "no configuration at $conf; project checks skipped"
fi

if (( smoke )) && command -v codex >/dev/null; then
  # The same arguments as every task round, with a read-only sandbox.
  : "${CODEX_MODEL:=}" "${CODEX_EFFORT:=}" "${CODEX_EXTRA_ARGS:=}"
  if [[ -f $conf ]] && (cdl_load) > /dev/null 2>&1; then cdl_load; fi
  codex_args read-only
  dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
  echo "smoke one paid Codex call (read-only, ephemeral) with:$(printf ' %q' "${CODEX_ARGS[@]}")"
  if (cd "$dir" && codex exec --skip-git-repo-check --ephemeral "${CODEX_ARGS[@]}" \
        -o "$dir/last.txt" "Reply with exactly the word OK and nothing else." < /dev/null > "$dir/log.txt" 2>&1); then
    meta=$(codex_meta "$dir/log.txt" read-only "$CODEX_MODEL" "$CODEX_EFFORT")
    echo "smoke $(head -n 1 <<< "$meta")"
    grep -q '^session id:' "$dir/log.txt" && pass "log has a 'session id:' line" || fail "log lacks 'session id:'"
    grep -q '^sandbox: read-only' "$dir/log.txt" && pass "log reports the requested read-only sandbox" || fail "log does not report sandbox: read-only"
    if [[ $meta == *"approval policy"* ]]; then fail "the run does not report approval policy never"; fi
    if [[ $meta == *"model=unknown "* ]]; then
      warn "log has no 'model:' line; model drift cannot be detected"
    elif [[ $meta == *"model drift"* ]]; then
      fail "the run reports another model than CODEX_MODEL=$CODEX_MODEL"
    else
      pass "log reports the model${CODEX_MODEL:+ CODEX_MODEL=$CODEX_MODEL}"
    fi
    if [[ -n $CODEX_EFFORT ]]; then
      if [[ $meta == *"effort=unknown "* ]]; then
        warn "log has no 'reasoning effort:' line; effort drift cannot be detected"
      elif [[ $meta == *"effort drift"* ]]; then
        fail "the run reports another effort than CODEX_EFFORT=$CODEX_EFFORT"
      else
        pass "log reports CODEX_EFFORT=$CODEX_EFFORT"
      fi
    fi
    grep -q '^tokens used' "$dir/log.txt" && pass "log has a 'tokens used' line" || warn "log lacks 'tokens used'; cost accounting will show unknown"
    grep -qx 'OK' "$dir/last.txt" && pass "-o captured the final message" || fail "-o did not capture the final message"
  else
    fail "smoke call failed; check authentication for the configured provider and the arguments above"
  fi
fi

echo "doctor: $fails failure(s), $warns warning(s)"
(( fails == 0 ))
