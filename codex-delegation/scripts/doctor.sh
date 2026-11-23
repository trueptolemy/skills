#!/usr/bin/env bash
# Check that this machine and project can run the delegation scripts.
# Usage: doctor.sh [--smoke]
#
# Without --smoke no model is called: it checks git, the Codex CLI version and
# the exec/resume flags the scripts depend on, and, when a configuration is
# found (CDL_CONF or ./codex-delegation.conf), the repository, gates, common
# rules, setup hook and free disk space.
# --smoke additionally runs one tiny paid Codex call and verifies the log shape
# the scripts parse (`session id:`, `sandbox:`, `tokens used`). Ask the user
# before using it.

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
  for flag in --cd --sandbox --output-last-message; do
    grep -q -- "$flag" <<< "$help" && pass "codex exec supports $flag" || fail "codex exec lacks $flag"
  done
  for value in read-only workspace-write; do
    grep -q -- "$value" <<< "$help" && pass "codex sandbox mode $value exists" || fail "codex sandbox mode $value is missing"
  done
  rhelp=$(codex exec resume --help 2>&1 || true)
  for flag in --config --output-last-message; do
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
  if [[ -s $TASKS_ROOT/common.md ]]; then
    echo "PASS  common rules $TASKS_ROOT/common.md"
    if grep -qE '\[(AGENTS|Real-system|private paths|Interpreter)' "$TASKS_ROOT/common.md"; then
      echo "WARN  common.md still contains template placeholders"
    fi
  else
    echo "FAIL  $TASKS_ROOT/common.md is missing"
  fi
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
  dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
  echo "smoke one paid Codex call (read-only, ephemeral)..."
  if (cd "$dir" && codex exec -s read-only --skip-git-repo-check --ephemeral \
        -o "$dir/last.txt" "Reply with exactly the word OK and nothing else." > "$dir/log.txt" 2>&1); then
    grep -q '^session id:' "$dir/log.txt" && pass "log has a 'session id:' line" || fail "log lacks 'session id:'"
    grep -q '^sandbox: read-only' "$dir/log.txt" && pass "log reports the requested read-only sandbox" || fail "log does not report sandbox: read-only"
    grep -q '^tokens used' "$dir/log.txt" && pass "log has a 'tokens used' line" || warn "log lacks 'tokens used'; cost accounting will show unknown"
    grep -qx 'OK' "$dir/last.txt" && pass "-o captured the final message" || fail "-o did not capture the final message"
  else
    fail "smoke call failed; check authentication for the configured provider"
  fi
fi

echo "doctor: $fails failure(s), $warns warning(s)"
(( fails == 0 ))
