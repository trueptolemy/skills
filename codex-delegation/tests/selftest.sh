#!/usr/bin/env bash
# Exercise every codex-delegation script against a throwaway repository and a
# fake `codex`. Calls no model and touches nothing outside a temporary
# directory. Usage: codex-delegation/tests/selftest.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)   # the skill directory
scripts=$here/scripts
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
ok() { pass=$((pass + 1)); echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
expect_fail() { if "$@" > "$tmp/last.out" 2>&1; then fail "expected failure: $*"; fi; }
summary() { cat "$tasks/$1/gates-$2/summary.txt"; }
task() {  # id mode [allowed]
  { echo "# $1: selftest task"; echo; echo "Mode: $2"
    [[ -z ${3:-} ]] || echo "Allowed paths: $3"
    echo; echo "Do the selftest change."; } > "$tasks/$1/task.md"
}

# A fake codex that prints a codex-cli style header (model, approval, sandbox,
# reasoning effort, session id) and a final `tokens used` count. It honours -m
# and the -c keys the scripts pass. `exec` edits the worktree unless
# FAKE_NO_EDIT is set; FAKE_SANDBOX and FAKE_MODEL make the header lie;
# FAKE_BAD_REPORT writes a report without STATUS that is too long;
# FAKE_DURING is a shell command run during the round (FAKE_WT = worktree).
mkdir -p "$tmp/bin"
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == --version ]] && { echo "codex-cli 0.0.0-fake"; exit 0; }
[[ ${1:-} == exec ]] || exit 64
shift
if [[ ${1:-} == --help ]]; then
  echo "-c, --config <key=value>  -m, --model <MODEL>  -C, --cd <DIR>  -s, --sandbox <MODE> [read-only, workspace-write, danger-full-access]  -o, --output-last-message <FILE>  -p, --profile <P>"; exit 0
fi
if [[ ${1:-} == resume && ${2:-} == --help ]]; then
  echo "-c, --config <key=value>  -m, --model <MODEL>  -o, --output-last-message <FILE>"; exit 0
fi
report=""; wt=$PWD; resume=0; sandbox=unknown; model=fake-default; effort=medium; approval=on-request
stdin=0; prompt=""
while [[ $# -gt 0 ]]; do
  case $1 in
    resume) resume=1; shift ;;
    -C) wt=$2; shift 2 ;;
    -s) sandbox=$2; shift 2 ;;
    -m) model=$2; shift 2 ;;
    -c) value=${2#*=}; value=${value//\"/}
        case $2 in
          sandbox_mode=*) sandbox=$value ;;
          approval_policy=*) approval=${FAKE_APPROVAL:-$value} ;;
          model_reasoning_effort=*) effort=$value ;;
        esac
        shift 2 ;;
    -o) report=$2; shift 2 ;;
    -) stdin=1; shift ;;
    -*) shift ;;
    *) prompt=$1; shift ;;
  esac
done
(( ! stdin )) || cat > /dev/null
[[ -z ${FAKE_DURING:-} ]] || FAKE_WT=$wt bash -c "$FAKE_DURING"
printf 'OpenAI Codex v0.0.0-fake\n--------\nworkdir: %s\nmodel: %s\nprovider: fake\napproval: %s\nsandbox: %s [workdir]\nreasoning effort: %s\nsession id: 0123abcd-1111-2222-3333-444455556666\n--------\n' \
  "$wt" "${FAKE_MODEL:-$model}" "$approval" "${FAKE_SANDBOX:-$sandbox}" "$effort"
if [[ $prompt == *"exactly the word OK"* ]]; then echo OK > "$report"; printf 'tokens used\n12\n'; exit 0; fi
if [[ -z ${FAKE_NO_EDIT:-} ]]; then
  if (( resume )); then echo "second" >> "$wt/feature.txt"; else echo "first" > "$wt/feature.txt"; fi
fi
if [[ -n ${FAKE_BAD_REPORT:-} ]]; then seq 1 90 > "$report"; else printf 'STATUS: DONE\nSUMMARY: fake round\n' > "$report"; fi
printf 'tokens used\n1,234\n'
EOF
chmod +x "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH"

repo=$tmp/repo
git init -q -b main "$repo"
git -C "$repo" config user.name "Self Test"
git -C "$repo" config user.email "selftest@example.com"
mkdir -p "$repo/src" "$repo/tests" "$repo/docs"
echo hello > "$repo/README.md"
echo "print('app')" > "$repo/src/app.py"
echo "def test_old(): pass" > "$repo/tests/test_old.py"
echo "# Guide" > "$repo/docs/guide.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m "init"

tasks=$tmp/repo-tasks
mkdir -p "$tasks"
cat > "$tasks/codex-delegation.conf" <<EOF
REPO=$repo
BASE_BRANCH=main
WT_ROOT=$tmp/repo-wt
TASKS_ROOT=$tasks
GATES_FILE=$tasks/gates.txt
PRESET=python
MIN_FREE_GB=0
MIN_FREE_INODES=0
CODEX_MODEL=fake-model
CODEX_EFFORT=high
GATE_ENV='MARKER=\$WT/marker'
MSG_FILE_CHECK='grep -q "^Co-Authored-By: " {file}'
MSG_COMMIT_CHECK='git log -1 --format=%B {rev} | grep -q "^Co-Authored-By: "'
EOF
export CDL_CONF=$tasks/codex-delegation.conf
cat > "$tasks/gates.txt" <<'EOF'
# harness check: gates run inside the task worktree with GATE_ENV applied
harness | test "$PWD" = "$WT" && test "$MARKER" = "$WT/marker" && test "$TMPDIR" = "$WT/.tmp" && test "$PYTEST_DEBUG_TEMPROOT" = "$WT/.tmp" && test -d "$TMPDIR"
readme  | grep -q hello README.md
EOF
printf 'feat: x\n\nCo-Authored-By: Fake <f@example.com>\n' > "$tmp/msg.txt"

# --- configuration and presets ------------------------------------------------
fp=$(bash -c "source '$scripts/lib.sh'; cdl_load; echo \"\$FAIL_PATTERN\"")
[[ $fp == *FAILED* ]] || fail "python preset FAIL_PATTERN"
sed 's/^PRESET=python$/PRESET=go/' "$CDL_CONF" > "$tmp/go.conf"
echo "SUPPRESSION_PATTERN='project-wins'" >> "$tmp/go.conf"
got=$(CDL_CONF=$tmp/go.conf bash -c "source '$scripts/lib.sh'; cdl_load; echo \"\$FAIL_PATTERN|\$SUPPRESSION_PATTERN\"")
[[ $got == *'--- FAIL:'*'|project-wins' ]] || fail "go preset and project precedence: $got"
sed 's/^PRESET=python$/PRESET=cobol/' "$CDL_CONF" > "$tmp/bad.conf"
expect_fail env CDL_CONF="$tmp/bad.conf" "$scripts/new-task.sh" X x
grep -q "unknown PRESET" "$tmp/last.out" || fail "unknown preset message"
ok "presets fill unset values, project values win, unknown presets refuse"

expect_fail "$scripts/doctor.sh"
grep -q "FAIL .*common.md is missing" "$tmp/last.out" || fail "doctor must fail without common.md"
cp "$here/templates/common.md" "$tasks/common.md"
"$scripts/doctor.sh" > "$tmp/doctor.out" || fail "doctor should pass: $(cat "$tmp/doctor.out")"
grep -q "WARN  common.md still contains template placeholders" "$tmp/doctor.out" || fail "doctor placeholder warning"
grep -q "WARN  codex 0.0.0 is not in the verified list" "$tmp/doctor.out" || fail "doctor version warning"
grep -q "PASS  codex exec resume supports --config" "$tmp/doctor.out" || fail "doctor resume probe"
grep -q "PASS  gates file" "$tmp/doctor.out" || fail "doctor project checks"
grep -q "WARN  focused gates file .* is missing" "$tmp/doctor.out" || fail "doctor focused-gates warning"
grep -qF 'PASS  every round passes: -c sandbox_mode=\"workspace-write\" -c approval_policy=\"never\" -m fake-model -c model_reasoning_effort=\"high\"' "$tmp/doctor.out" || fail "doctor round arguments"
ok "doctor probes CLI flags, flags an unverified version and placeholders, and fails on a missing common.md"

{ cat "$CDL_CONF"; echo "CODEX_EXTRA_ARGS='-p fast'"; } > "$tmp/profile.conf"
expect_fail env CDL_CONF="$tmp/profile.conf" "$scripts/doctor.sh"
grep -q "FAIL  CODEX_EXTRA_ARGS flag -p is not accepted by codex exec resume" "$tmp/last.out" || fail "doctor resume-flag check"
"$scripts/doctor.sh" --smoke < /dev/null > "$tmp/smoke.out" || fail "doctor smoke: $(cat "$tmp/smoke.out")"
grep -q "smoke CODEX model=fake-model effort=high sandbox=read-only" "$tmp/smoke.out" && grep -q "PASS  log reports the model CODEX_MODEL=fake-model" "$tmp/smoke.out" || fail "smoke arguments: $(cat "$tmp/smoke.out")"
FAKE_MODEL=other expect_fail "$scripts/doctor.sh" --smoke < /dev/null
grep -q "FAIL  the run reports another model than CODEX_MODEL=fake-model" "$tmp/last.out" || fail "smoke model check"
ok "doctor refuses extra flags resume lacks; smoke runs with the round arguments and proves the model"

# --- implement mode, rounds, breakers ------------------------------------------
"$scripts/new-task.sh" T1 feat/t1 > /dev/null
[[ -d $tmp/repo-wt/T1 && -d $tasks/T1 && ! -e $tasks/T1/task.md && -f $tasks/common.md ]] || fail "new-task layout"
expect_fail "$scripts/run-codex.sh" start T1 --dry-run
grep -q "task.md is missing or empty; write it from .*templates/task.md" "$tmp/last.out" || fail "missing task.md"
cp "$here/templates/task.md" "$tasks/T1/task.md"
expect_fail "$scripts/run-codex.sh" start T1 --dry-run
grep -q "still holds template placeholders" "$tmp/last.out" || fail "template task.md"
[[ -d $tmp/repo-wt/T1/.tmp ]] && grep -qxF '/.tmp/' "$repo/.git/info/exclude" || fail "per-worktree temporary directory"
expect_fail "$scripts/new-task.sh" T1 feat/t1
ok "new-task creates worktree, branch, task directory and an ignored .tmp/ but no task.md, refuses a duplicate; start needs a written task.md"

inodes=$(bash -c "source '$scripts/lib.sh'; free_inodes '$tmp'")
[[ $inodes == unknown || $inodes =~ ^[0-9]+$ ]] || fail "free_inodes: $inodes"
{ cat "$CDL_CONF"; echo "MIN_FREE_GB=999999999"; } > "$tmp/space.conf"
expect_fail env CDL_CONF="$tmp/space.conf" "$scripts/new-task.sh" S1 s/s1
grep -q "FAIL  only .* GiB free under .*MIN_FREE_GB=999999999" "$tmp/last.out" || fail "space refusal: $(cat "$tmp/last.out")"
if [[ $inodes != unknown ]]; then
  { cat "$CDL_CONF"; echo "MIN_FREE_INODES=$((inodes * 1000 + 1000))"; } > "$tmp/inodes.conf"
  expect_fail env CDL_CONF="$tmp/inodes.conf" "$scripts/new-task.sh" S1 s/s1
  grep -q "FAIL  only .* inodes free under" "$tmp/last.out" || fail "inode refusal: $(cat "$tmp/last.out")"
fi
[[ ! -d $tmp/repo-wt/S1 ]] || fail "a refused new-task must not create the worktree"
ok "new-task refuses low space or inodes where tasks write (inodes: $inodes)"
task T1 implement "feature.txt, src/*"

"$scripts/run-codex.sh" start T1 --dry-run | grep -qE 'codex exec -C [^ ]+ -c sandbox_mode=\\"workspace-write\\" -c approval_policy=\\"never\\" -m fake-model -c model_reasoning_effort=\\"high\\" -o ' || fail "dry run"
[[ ! -e $tasks/T1/prompt.md ]] || fail "dry run wrote files"
"$scripts/run-codex.sh" start T1 > "$tmp/start.out"
grep -q "REPORT STATUS=DONE lines=2" "$tmp/start.out" || fail "report check"
grep -q "CODEX model=fake-model effort=high sandbox=workspace-write tokens=1234" "$tmp/start.out" || fail "codex meta"
grep -q "# Mode: implement" "$tasks/T1/prompt.md" || fail "mode instructions in prompt"
grep -q "round 1 GUARD PASS" "$tmp/start.out" || fail "a plain round passes the guard"
expect_fail "$scripts/run-codex.sh" start T1
ok "run-codex start appends mode instructions and records report shape, sandbox and tokens"

"$scripts/run-gates.sh" T1 r1 > /dev/null
[[ $(tail -n 1 "$tasks/T1/gates-r1/summary.txt") == DONE ]] && summary T1 r1 | grep -qx "RESULT PASS" || fail "gates pass"
summary T1 r1 | grep -q "SCOPE    all staged files are within Allowed paths" || fail "scope ok line"
ok "run-gates passes in scope and ends its summary with DONE"

echo "x" > "$tmp/repo-wt/T1/stray.txt"
expect_fail "$scripts/run-gates.sh" T1 r2
summary T1 r2 | grep -q "^SCOPE stray.txt" || fail "scope violation"
rm "$tmp/repo-wt/T1/stray.txt"
echo "fail | echo 'FAILED tests/test_x.py::test_y - boom'; false" >> "$tasks/gates.txt"
expect_fail "$scripts/run-gates.sh" T1 r3
summary T1 r3 | grep -q "fail: FAILED tests/test_x.py::test_y" || fail "fail-line extraction"
expect_fail "$scripts/finish-task.sh" T1 "$tmp/msg.txt"
grep -q "did not pass" "$tmp/last.out" || fail "finish blocked by failing summary"
sed -i.bak '/^fail | /d' "$tasks/gates.txt" && rm "$tasks/gates.txt.bak"
ok "out-of-scope files and failing gates fail, FAILED lines are copied, finish refuses"

echo "x = 1  # noqa" > "$tmp/repo-wt/T1/src/cheat.py"
expect_fail "$scripts/run-gates.sh" T1 r4
summary T1 r4 | grep -q "SUPPRESSIONS added=1" || fail "suppression scan"
rm "$tmp/repo-wt/T1/src/cheat.py"
printf 'import pytest\n@pytest.mark.skip\ndef test_new(): pass\n' > "$tmp/repo-wt/T1/src/skipper.py"
"$scripts/run-gates.sh" T1 r5 > /dev/null || fail "skip markers must only warn"
summary T1 r5 | grep -q "WARNING  added=1 test-skip markers" || fail "skip warning"
rm "$tmp/repo-wt/T1/src/skipper.py"
ok "suppressions fail acceptance; test-skip markers are flagged for review"

printf 'Round finding.\n' > "$tmp/feedback.md"
"$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" --dry-run | grep -q 'codex exec resume -c sandbox_mode=\\"workspace-write\\" -c approval_policy=\\"never\\" -m fake-model -c model_reasoning_effort=\\"high\\" -o ' || fail "resume dry run: same arguments as start"
"$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" > /dev/null
[[ -f $tasks/T1/report-r2.md && $(wc -l < "$tmp/repo-wt/T1/feature.txt") -eq 2 ]] || fail "resume round"
[[ -z $(git -C "$tmp/repo-wt/T1" diff --cached --name-only) ]] || fail "resume should unstage"
FAKE_BAD_REPORT=1 "$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" > "$tmp/bad.out"
grep -q "no STATUS line" "$tmp/bad.out" && grep -q "90 lines exceed 80" "$tmp/bad.out" || fail "report drift warnings"
grep -q "REPORT HINT: .*run-codex.sh continue T1" "$tmp/bad.out" || fail "truncated-report recovery hint"
expect_fail "$scripts/run-codex.sh" resume T1 "$tmp/feedback.md"
grep -q "BREAKER: T1 already used 3 of 3 rounds (MAX_ROUNDS; 0 voided" "$tmp/last.out" || fail "round breaker"
ok "resume continues the session, warns on report drift and stops at MAX_ROUNDS"

"$scripts/run-gates.sh" T1 r6 > /dev/null
printf 'feat: no co-author\n' > "$tmp/bad.txt"
expect_fail "$scripts/finish-task.sh" T1 "$tmp/bad.txt"
grep -q "message check failed" "$tmp/last.out" || fail "message check"
"$scripts/finish-task.sh" T1 "$tmp/msg.txt" > /dev/null
[[ $(git -C "$repo" log -1 --format=%s main) == "feat: x" && ! -d $tmp/repo-wt/T1 ]] || fail "ff delivery"
ok "finish-task checks the message, commits, fast-forwards and removes the worktree"

expect_fail "$scripts/new-task.sh" T1 feat/t1-again
grep -q "already holds an earlier task" "$tmp/last.out" || fail "reused task directory must refuse"
ok "new-task refuses a task directory that holds an earlier task"

# --- voided rounds and a per-task limit -------------------------------------------
"$scripts/new-task.sh" V1 feat/v1 > /dev/null
{ echo "# V1: limit"; echo; echo "Mode: implement"; echo "Max rounds: 1"; } > "$tasks/V1/task.md"
"$scripts/run-codex.sh" start V1 > /dev/null
expect_fail "$scripts/run-codex.sh" continue V1
grep -q "BREAKER: V1 already used 1 of 1 rounds (Max rounds in task.md; 0 voided" "$tmp/last.out" || fail "per-task limit: $(cat "$tmp/last.out")"
expect_fail "$scripts/ledger.sh" void V1 r2 "no such round"
expect_fail "$scripts/ledger.sh" void V1 r1 ""
"$scripts/ledger.sh" void V1 r1 "provider HTTP 500 before any work" | grep -q "VOID V1 r1 recorded" || fail "void"
expect_fail "$scripts/ledger.sh" void V1 r1 "again"
"$scripts/run-codex.sh" continue V1 > /dev/null || fail "a voided round must not count"
expect_fail "$scripts/run-codex.sh" continue V1
grep -q "1 of 1 rounds (Max rounds in task.md; 1 voided" "$tmp/last.out" || fail "void count in breaker: $(cat "$tmp/last.out")"
sed -i.bak 's/^Max rounds: 1$/Max rounds: 0/' "$tasks/V1/task.md" && rm "$tasks/V1/task.md.bak"
expect_fail "$scripts/run-codex.sh" continue V1 --dry-run
grep -q "Max rounds '0' must be a positive integer" "$tmp/last.out" || fail "Max rounds validation"
ok "Max rounds in task.md overrides MAX_ROUNDS; ledger void records an environment failure that then does not count"

# --- feedback naming and continue ------------------------------------------------
"$scripts/new-task.sh" T2 feat/t2 > /dev/null
task T2 implement
"$scripts/run-codex.sh" start T2 > /dev/null
printf 'Named like the archive copy.\n' > "$tasks/T2/feedback-r2.md"
"$scripts/run-codex.sh" resume T2 "$tasks/T2/feedback-r2.md" > "$tmp/same.out" || fail "same-name feedback must resume"
[[ -f $tasks/T2/report-r2.md ]] || fail "same-name feedback round"
"$scripts/run-codex.sh" continue T2 --dry-run | grep -q 'stdin: .*/continue-r3.md' || fail "continue dry run"
"$scripts/run-codex.sh" continue T2 > /dev/null
[[ -f $tasks/T2/report-r3.md && -f $tasks/T2/continue-r3.md && -f $tasks/T2/feedback-r3.md ]] || fail "continue round"
grep -q "write the complete report" "$tasks/T2/feedback-r3.md" || fail "continue message"
ok "resume accepts a feedback file already named like its archive copy; continue sends the standard finish message"

grep -v '^CODEX_MODEL=\|^CODEX_EFFORT=' "$CDL_CONF" > "$tmp/nomodel.conf"
CDL_CONF=$tmp/nomodel.conf "$scripts/new-task.sh" M1 feat/m1 > /dev/null
task M1 implement
CDL_CONF=$tmp/nomodel.conf "$scripts/run-codex.sh" start M1 > "$tmp/m1.out"
grep -q "CODEX model=fake-default effort=medium" "$tmp/m1.out" || fail "default model round"
FAKE_MODEL=other CDL_CONF=$tmp/nomodel.conf "$scripts/run-codex.sh" resume M1 "$tmp/feedback.md" > "$tmp/m1b.out"
grep -q "CODEX WARNING: model drift: expected fake-default but the run reports other" "$tmp/m1b.out" || fail "drift against round 1"
ok "a resumed round reporting another model than round 1 warns of drift"

# --- pipeline, focused gates and quiet tasks ------------------------------------
cat > "$tasks/focused.txt" <<'GATES'
changed | case " $CHANGED_FILES " in *" feature.txt "*) ;; *) echo "missing: $CHANGED_FILES"; false ;; esac
GATES
"$scripts/new-task.sh" T3 feat/t3 > /dev/null
task T3 implement
"$scripts/pipeline.sh" start T3 > "$tmp/p1.out" || fail "pipeline start"
grep -q "PIPELINE codex rc=0" "$tmp/p1.out" && grep -qx "RESULT PASS" "$tmp/p1.out" && grep -q "^DIFF " "$tmp/p1.out" || fail "pipeline full gates: $(cat "$tmp/p1.out")"
summary T3 r1 | grep -q "GATESET  $tasks/gates.txt" || fail "full gate set recorded"
"$scripts/pipeline.sh" resume T3 "$tmp/feedback.md" --focused > "$tmp/p2.out" || fail "pipeline focused"
grep -qx "RESULT PASS" "$tmp/p2.out" && summary T3 f2 | grep -q "GATESET  $tasks/focused.txt" || fail "focused gates and CHANGED_FILES: $(cat "$tmp/p2.out")"
ok "pipeline runs Codex then the full or focused gate list; gates see CHANGED_FILES"

"$scripts/new-task.sh" T4 feat/t4 > /dev/null
{ echo "# T4: quiet task"; echo; echo "Mode: implement"; echo "Quiet: yes"; echo; echo "Edit."; } > "$tasks/T4/task.md"
"$scripts/pipeline.sh" start T4 > "$tmp/p3.out" || fail "pipeline quiet"
grep -q "PIPELINE gates skipped" "$tmp/p3.out" && grep -q "# Quiet task" "$tasks/T4/prompt.md" || fail "quiet task: $(cat "$tmp/p3.out")"
[[ ! -d $tasks/T4/gates-r1 ]] || fail "quiet task must not run gates"
ok "a Quiet task gets the no-test instructions and the pipeline runs no gates"

# --- repository guard -----------------------------------------------------------
"$scripts/new-task.sh" G1 guard/g1 > /dev/null
task G1 implement
rc=0
FAKE_DURING='git -C "$FAKE_WT" commit -q --allow-empty -m sneaky' "$scripts/run-codex.sh" start G1 > "$tmp/g1.out" 2>&1 || rc=$?
(( rc == 5 )) && grep -q "GUARD FAIL ref:refs/heads/guard/g1 " "$tmp/g1.out" || fail "a commit by Codex must fail the guard (rc=$rc): $(cat "$tmp/g1.out")"
grep -q "BREAKER: round 1 of G1 changed state outside its worktree" "$tmp/g1.out" || fail "guard breaker line"
expect_fail "$scripts/run-gates.sh" G1 r1
summary G1 r1 | grep -q "^GUARD r1 ref:refs/heads/guard/g1 " || fail "gates must report the guard failure"
expect_fail "$scripts/finish-task.sh" G1 "$tmp/msg.txt"
grep -q "changed state outside its worktree" "$tmp/last.out" || fail "finish must refuse a guard failure"
ok "a commit made during a round fails the guard, the gates and delivery"

"$scripts/new-task.sh" G2 guard/g2 > /dev/null
task G2 implement
hook=$repo/.git/hooks/pre-commit
FAKE_DURING="echo stray >> '$repo/README.md'; echo x > '$tmp/repo-wt/T2/other.txt'; printf '#!/bin/sh\n' > '$hook'" \
  "$scripts/run-codex.sh" start G2 > "$tmp/g2.out" 2>&1 || true
grep -q "GUARD FAIL status:$(cd "$repo" && pwd -P) changed" "$tmp/g2.out" || fail "main checkout change: $(cat "$tmp/g2.out")"
grep -q "GUARD FAIL status:$(cd "$tmp/repo-wt/T2" && pwd -P) changed" "$tmp/g2.out" || fail "idle worktree change: $(cat "$tmp/g2.out")"
grep -q "GUARD FAIL git:hooks changed" "$tmp/g2.out" || fail "hook change: $(cat "$tmp/g2.out")"
git -C "$repo" checkout -q README.md; rm "$tmp/repo-wt/T2/other.txt" "$hook"
"$scripts/new-task.sh" G3 guard/g3 > /dev/null
task G3 implement
FAKE_DURING="git -C '$repo' branch by-hand" "$scripts/run-codex.sh" start G3 > "$tmp/g3.out" 2>&1 || true
grep -q "GUARD FAIL ref:refs/heads/by-hand absent -> " "$tmp/g3.out" || fail "new branch: $(cat "$tmp/g3.out")"
expect_fail "$scripts/ledger.sh" guard-ack T3 r1 "nothing to acknowledge"
"$scripts/ledger.sh" guard-ack G3 r1 "planner created branch by-hand" > /dev/null
"$scripts/run-gates.sh" G3 r1 > /dev/null || fail "an acknowledged planner change passes: $(summary G3 r1)"
ok "changes to the main checkout, an idle worktree, hooks or refs fail the guard; guard-ack records the planner's own change"

"$scripts/new-task.sh" G4 guard/g4 > /dev/null
task G4 implement
FAKE_DURING="'$scripts/new-task.sh' G5 guard/g5 && '$scripts/run-gates.sh' T4 r1 && '$scripts/finish-task.sh' T4 '$tmp/msg.txt'" \
  "$scripts/run-codex.sh" start G4 > "$tmp/g4.out" || fail "parallel planner work: $(cat "$tmp/g4.out")"
grep -q "round 1 GUARD PASS" "$tmp/g4.out" && [[ ! -d $tmp/repo-wt/T4 ]] || fail "parallel planner work must pass the guard: $(cat "$tmp/g4.out")"
"$scripts/ledger.sh" status > "$tmp/gstatus.out"
grep -qE '^G1 .* FAIL ' "$tmp/gstatus.out" && grep -qE '^G3 .* ack ' "$tmp/gstatus.out" && grep -qE '^G4 .* ok ' "$tmp/gstatus.out" || fail "ledger guard column: $(cat "$tmp/gstatus.out")"
ok "new-task, gates and delivery of other tasks during a round pass the guard"

# --- parallel gate runs ------------------------------------------------------------
slots=$tasks/.gate-slots
mkdir -p "$slots"
sleep 0 & dead=$!; wait "$dead"
ln -s "$dead" "$slots/slot-1"
"$scripts/run-gates.sh" T2 q1 > /dev/null || fail "gates with a stale slot: $(summary T2 q1)"
summary T2 q1 | grep -q "^SLOT     1 of 1 after" && [[ ! -e $slots/slot-1 ]] || fail "stale slot reclaim and release: $(summary T2 q1)"
sleep 60 & holder=$!
ln -s "$holder" "$slots/slot-1"
"$scripts/run-gates.sh" T2 q2 > /dev/null & runner=$!
for _ in $(seq 1 50); do grep -q '^QUEUED' "$tasks/T2/gates-q2/summary.txt" 2>/dev/null && break; sleep 0.2; done
summary T2 q2 | grep -q "^QUEUED" && ! summary T2 q2 | grep -q "^harness" || fail "a taken slot must queue the run: $(summary T2 q2)"
kill "$holder"; wait "$holder" 2>/dev/null || true
wait "$runner" || fail "queued run: $(summary T2 q2)"
summary T2 q2 | grep -qx "RESULT PASS" || fail "queued run result: $(summary T2 q2)"
MAX_PARALLEL_GATES=0 "$scripts/run-gates.sh" T2 q3 > /dev/null
! summary T2 q3 | grep -q "^SLOT" || fail "MAX_PARALLEL_GATES=0 takes no slot"
printf 'slow | sleep 2\nafter | true\n' > "$tmp/slow.txt"
"$scripts/run-gates.sh" T2 q4 --gates "$tmp/slow.txt" > /dev/null 2>&1 & runner=$!
for _ in $(seq 1 50); do grep -q '^SLOT' "$tasks/T2/gates-q4/summary.txt" 2>/dev/null && break; sleep 0.2; done
kill -TERM "$runner"; wait "$runner" 2>/dev/null || true
[[ $(tail -n 2 "$tasks/T2/gates-q4/summary.txt" | head -n 1) == "RESULT FAIL (runner interrupted)" && $(tail -n 1 "$tasks/T2/gates-q4/summary.txt") == DONE ]] &&
  ! summary T2 q4 | grep -q "^after" && [[ ! -e $slots/slot-1 ]] || fail "an interrupted run must stop and release its slot: $(summary T2 q4)"
ok "gate runs queue for MAX_PARALLEL_GATES slots, reclaim a dead owner's slot, stop on interrupt, and 0 disables the limit"

# --- investigate mode ----------------------------------------------------------
"$scripts/new-task.sh" Q1 inv/q1 > /dev/null
task Q1 investigate
"$scripts/run-codex.sh" start Q1 --dry-run | grep -qF 'sandbox_mode=\"read-only\"' || fail "investigate sandbox"
FAKE_NO_EDIT=1 "$scripts/run-codex.sh" start Q1 > "$tmp/q1.out"
grep -q "sandbox=read-only" "$tmp/q1.out" || fail "investigate applied sandbox"
grep -q "# Mode: investigate" "$tasks/Q1/prompt.md" || fail "investigate instructions"
FAKE_NO_EDIT=1 FAKE_SANDBOX=workspace-write "$scripts/run-codex.sh" resume Q1 "$tmp/feedback.md" > "$tmp/q1b.out"
grep -q "requested sandbox read-only but the run reports workspace-write" "$tmp/q1b.out" || fail "sandbox mismatch warning"
"$scripts/run-gates.sh" Q1 r1 > /dev/null
summary Q1 r1 | grep -q "^UNCHANGED" && ! summary Q1 r1 | grep -q "^harness" || fail "investigate runs no gates"
echo "oops" > "$tmp/repo-wt/Q1/notes.txt"
expect_fail "$scripts/run-gates.sh" Q1 r2
summary Q1 r2 | grep -q "^CHANGED notes.txt" || fail "investigate change detection"
rm "$tmp/repo-wt/Q1/notes.txt"
"$scripts/run-gates.sh" Q1 r3 > /dev/null
before=$(git -C "$repo" rev-parse main)
"$scripts/finish-task.sh" Q1 > "$tmp/q1f.out"
[[ $(git -C "$repo" rev-parse main) == "$before" && ! -d $tmp/repo-wt/Q1 ]] || fail "investigate delivery"
grep -q "delivers its report" "$tmp/q1f.out" || fail "investigate report delivery"
ok "investigate runs read-only, warns on a sandbox mismatch, must not change files and commits nothing"

"$scripts/new-task.sh" Q2 inv/q2 > /dev/null
task Q2 investigate
FAKE_NO_EDIT=1 "$scripts/run-codex.sh" start Q2 > /dev/null
"$scripts/finish-task.sh" Q2 > "$tmp/q2f.out" || fail "investigate finish must not need a gates summary"
[[ ! -d $tmp/repo-wt/Q2 ]] && grep -q "delivers its report" "$tmp/q2f.out" || fail "investigate finish without gates"
ok "an investigate task finishes without a gates summary when its worktree is unchanged"

# --- operate mode ----------------------------------------------------------------
"$scripts/new-task.sh" O1 op/o1 > /dev/null
task O1 operate
expect_fail "$scripts/run-codex.sh" start O1 --dry-run
grep -q "operate mode requires an explicit Sandbox" "$tmp/last.out" || fail "operate sandbox must be explicit"
{ echo "# O1: stage"; echo; echo "Mode: operate"; echo "Sandbox: danger-full-access"; echo; echo "Run the stage."; } > "$tasks/O1/task.md"
"$scripts/run-codex.sh" start O1 --dry-run | grep -qF 'sandbox_mode=\"danger-full-access\"' || fail "operate sandbox"
FAKE_NO_EDIT=1 "$scripts/run-codex.sh" start O1 > /dev/null
grep -q "# Mode: operate" "$tasks/O1/prompt.md" || fail "operate instructions"
"$scripts/run-gates.sh" O1 r1 > /dev/null
summary O1 r1 | grep -q "^UNCHANGED" && ! summary O1 r1 | grep -q "^harness" || fail "operate runs no gates"
"$scripts/finish-task.sh" O1 > "$tmp/o1f.out" && grep -q "operate task O1 delivers its report" "$tmp/o1f.out" || fail "operate delivery"
{ echo "# T5: bad"; echo; echo "Mode: implement"; echo "Sandbox: danger-full-access"; } > "$tmp/t5.md"
"$scripts/new-task.sh" T5 feat/t5 > /dev/null
cp "$tmp/t5.md" "$tasks/T5/task.md"
expect_fail "$scripts/run-codex.sh" start T5 --dry-run
grep -q "needs Mode: operate or ALLOW_FULL_ACCESS=yes" "$tmp/last.out" || fail "full access outside operate must refuse without the opt-in"
ok "operate needs an explicit sandbox, may use full access, runs no gates and commits nothing; other modes need ALLOW_FULL_ACCESS"

# --- full access -------------------------------------------------------------------
{ cat "$CDL_CONF"; echo "CODEX_SANDBOX=danger-full-access"; } > "$tmp/full-noack.conf"
expect_fail env CDL_CONF="$tmp/full-noack.conf" "$scripts/run-codex.sh" start T5 --dry-run
grep -q "CODEX_SANDBOX=danger-full-access needs ALLOW_FULL_ACCESS=yes" "$tmp/last.out" || fail "full access needs the opt-in"
{ cat "$tmp/full-noack.conf"; echo "ALLOW_FULL_ACCESS=yes"; } > "$tmp/full.conf"
CDL_CONF=$tmp/full.conf "$scripts/run-codex.sh" start T5 --dry-run | grep -qF 'sandbox_mode=\"danger-full-access\" -c approval_policy=\"never\"' || fail "task full access with the opt-in"
CDL_CONF=$tmp/full.conf "$scripts/new-task.sh" F1 full/f1 > /dev/null
task F1 implement
CDL_CONF=$tmp/full.conf "$scripts/run-codex.sh" start F1 --dry-run | grep -q 'DRY-RUN: env -u SSH_AUTH_SOCK GIT_SSH_COMMAND=' || fail "ssh shield in the command"
SSH_AUTH_SOCK=/fake/agent FAKE_DURING="echo \"\${SSH_AUTH_SOCK-none}|\$(git ls-remote ssh://example.invalid/x 2>&1 | head -n 1)\" > '$tmp/f1.env'" \
  CDL_CONF=$tmp/full.conf "$scripts/run-codex.sh" start F1 > "$tmp/f1.out" || fail "full-access round: $(cat "$tmp/f1.out")"
grep -q "sandbox=danger-full-access" "$tmp/f1.out" && grep -q "GUARD PASS" "$tmp/f1.out" && ! grep -q WARNING "$tmp/f1.out" || fail "full-access round output: $(cat "$tmp/f1.out")"
grep -q '^none|codex-delegation: ssh is disabled outside operate tasks' "$tmp/f1.env" || fail "ssh shield: $(cat "$tmp/f1.env")"
FAKE_DURING="echo \"\$TMPDIR|\$PYTEST_DEBUG_TEMPROOT\" > '$tmp/f1.tmp'" CDL_CONF=$tmp/full.conf "$scripts/run-codex.sh" continue F1 > /dev/null
[[ $(cat "$tmp/f1.tmp") == "$tmp/repo-wt/F1/.tmp|$tmp/repo-wt/F1/.tmp" ]] || fail "Codex temporary directory: $(cat "$tmp/f1.tmp")"
FAKE_APPROVAL=on-request CDL_CONF=$tmp/full.conf "$scripts/run-codex.sh" resume F1 "$tmp/feedback.md" > "$tmp/f1b.out" || true
grep -q "requested approval policy never but the run reports on-request" "$tmp/f1b.out" || fail "approval warning"
"$scripts/new-task.sh" O2 op/o2 > /dev/null
{ echo "# O2: stage"; echo; echo "Mode: operate"; echo "Sandbox: danger-full-access"; } > "$tasks/O2/task.md"
"$scripts/run-codex.sh" start O2 --dry-run > "$tmp/o2.out"
grep -q '^DRY-RUN: env TMPDIR=' "$tmp/o2.out" && ! grep -q SSH_AUTH_SOCK "$tmp/o2.out" || fail "operate tasks keep ssh: $(cat "$tmp/o2.out")"
ok "full access needs ALLOW_FULL_ACCESS=yes; rounds run with approval never, TMPDIR in the worktree, without an ssh agent and with git over ssh refused, except operate"

# --- refactor and docs modes ----------------------------------------------------
"$scripts/new-task.sh" R1 ref/r1 > /dev/null
task R1 refactor
echo "def test_old(): assert True" > "$tmp/repo-wt/R1/tests/test_old.py"
expect_fail "$scripts/run-gates.sh" R1 r1
summary R1 r1 | grep -q "^TESTEDIT tests/test_old.py" || fail "refactor test edit"
git -C "$tmp/repo-wt/R1" checkout -q HEAD -- tests/test_old.py
echo "def test_pin(): pass" > "$tmp/repo-wt/R1/tests/test_pin.py"
echo "print('app v2')" > "$tmp/repo-wt/R1/src/app.py"
"$scripts/run-gates.sh" R1 r2 > /dev/null || fail "refactor may add tests and change code"
ok "refactor mode rejects edits to existing tests and allows new pinning tests"

"$scripts/new-task.sh" D1 doc/d1 > /dev/null
task D1 docs
echo "print('changed')" > "$tmp/repo-wt/D1/src/app.py"
expect_fail "$scripts/run-gates.sh" D1 r1
summary D1 r1 | grep -q "^NONDOC src/app.py" || fail "docs non-doc change"
git -C "$tmp/repo-wt/D1" checkout -q HEAD -- src/app.py
echo "More." >> "$tmp/repo-wt/D1/docs/guide.md"
"$scripts/run-gates.sh" D1 r2 > /dev/null || fail "docs-only change should pass"
ok "docs mode accepts only documentation changes"

# --- delivery modes --------------------------------------------------------------
before=$(git -C "$repo" rev-parse main)
DELIVERY=patch "$scripts/finish-task.sh" D1 "$tmp/msg.txt" > /dev/null
[[ $(ls "$tasks/D1/patches" | wc -l) -eq 1 && $(git -C "$repo" rev-parse main) == "$before" ]] || fail "patch delivery"
DELIVERY=branch-only "$scripts/finish-task.sh" R1 "$tmp/msg.txt" > "$tmp/branch.out"
grep -q "pushing needs separate authorization" "$tmp/branch.out" || fail "branch-only delivery"
[[ $(git -C "$repo" rev-parse main) == "$before" ]] && git -C "$repo" rev-parse -q --verify ref/r1 > /dev/null || fail "branch kept"
expect_fail env DELIVERY=push "$scripts/finish-task.sh" R1 "$tmp/msg.txt"
ok "patch and branch-only delivery leave the base untouched; unknown delivery refuses"

"$scripts/new-task.sh" C1 chain/c1 > /dev/null
task C1 implement
echo "chained" > "$tmp/repo-wt/C1/chain.txt"
"$scripts/run-gates.sh" C1 r1 > /dev/null
"$scripts/finish-task.sh" C1 "$tmp/msg.txt" --no-merge > /dev/null
[[ -d $tmp/repo-wt/C1 && $(git -C "$repo" rev-parse main) != $(git -C "$repo" rev-parse chain/c1) ]] || fail "--no-merge"
ok "finish-task --no-merge commits a chained task without delivering it"

# --- ledger ------------------------------------------------------------------------
for i in 1 2 3; do "$scripts/ledger.sh" full-read T1 "log $i" > /dev/null; done
expect_fail "$scripts/ledger.sh" full-read T1 "log 4"
grep -q "BREAKER: full read 4 would exceed MAX_FULL_READS=3" "$tmp/last.out" || fail "full-read breaker"
"$scripts/ledger.sh" status > "$tmp/status.out"
grep -qE '^T1 +implement +3 +0 +3702' "$tmp/status.out" || fail "ledger rounds and tokens: $(cat "$tmp/status.out")"
grep -qE '^V1 +implement +2 +1 ' "$tmp/status.out" || fail "ledger void count: $(cat "$tmp/status.out")"
rounds=$(cat "$tasks"/*/rounds.log | grep -c "^round [0-9]* CODEX .*tokens=1234$")
grep -q "TOTAL tokens=$((rounds * 1234)) full-reads=3/3" "$tmp/status.out" || fail "ledger totals: $(cat "$tmp/status.out")"
ok "ledger enforces MAX_FULL_READS and sums rounds and tokens per task"

echo "codex-delegation selftest: $pass checks passed"
