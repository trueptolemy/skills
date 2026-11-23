#!/usr/bin/env bash
# Exercise every codex-delegation script against a throwaway repository and a
# fake `codex`, then exercise install.sh. Calls no model and touches nothing
# outside a temporary directory. Usage: ./selftest.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
scripts=$here/codex-delegation/scripts
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

# A fake codex that prints a codex-cli style header (sandbox, model, session
# id) and a final `tokens used` count. `exec` edits the worktree unless
# FAKE_NO_EDIT is set; FAKE_SANDBOX makes the header lie about the sandbox;
# FAKE_BAD_REPORT writes a report without STATUS that is too long.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == --version ]] && { echo "codex-cli 0.0.0-fake"; exit 0; }
[[ ${1:-} == exec ]] || exit 64
shift
if [[ ${1:-} == --help ]]; then
  echo "-C, --cd <DIR>  -s, --sandbox <MODE> [read-only, workspace-write]  -o, --output-last-message <FILE>"; exit 0
fi
if [[ ${1:-} == resume && ${2:-} == --help ]]; then
  echo "-c, --config <key=value>  -o, --output-last-message <FILE>"; exit 0
fi
report=""; wt=$PWD; resume=0; sandbox=unknown
while [[ $# -gt 0 ]]; do
  case $1 in
    resume) resume=1; shift ;;
    -C) wt=$2; shift 2 ;;
    -s) sandbox=$2; shift 2 ;;
    -c) sandbox=$(echo "$2" | sed -n 's/^sandbox_mode="\(.*\)"$/\1/p'); shift 2 ;;
    -m) shift 2 ;;
    -o) report=$2; shift 2 ;;
    *) shift ;;
  esac
done
cat > /dev/null
printf 'OpenAI Codex v0.0.0-fake\n--------\nworkdir: %s\nmodel: fake-model\nsandbox: %s [workdir]\nsession id: 0123abcd-1111-2222-3333-444455556666\n--------\n' \
  "$wt" "${FAKE_SANDBOX:-$sandbox}"
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
GATE_ENV='MARKER=\$WT/marker'
MSG_FILE_CHECK='grep -q "^Co-Authored-By: " {file}'
MSG_COMMIT_CHECK='git log -1 --format=%B {rev} | grep -q "^Co-Authored-By: "'
EOF
export CDL_CONF=$tasks/codex-delegation.conf
cat > "$tasks/gates.txt" <<'EOF'
# harness check: gates run inside the task worktree with GATE_ENV applied
harness | test "$PWD" = "$WT" && test "$MARKER" = "$WT/marker"
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
cp "$here/codex-delegation/templates/common.md" "$tasks/common.md"
"$scripts/doctor.sh" > "$tmp/doctor.out" || fail "doctor should pass: $(cat "$tmp/doctor.out")"
grep -q "WARN  common.md still contains template placeholders" "$tmp/doctor.out" || fail "doctor placeholder warning"
grep -q "WARN  codex 0.0.0 is not in the verified list" "$tmp/doctor.out" || fail "doctor version warning"
grep -q "PASS  codex exec resume supports --config" "$tmp/doctor.out" || fail "doctor resume probe"
grep -q "PASS  gates file" "$tmp/doctor.out" || fail "doctor project checks"
grep -q "WARN  focused gates file .* is missing" "$tmp/doctor.out" || fail "doctor focused-gates warning"
ok "doctor probes CLI flags, flags an unverified version and placeholders, and fails on a missing common.md"

# --- implement mode, rounds, breakers ------------------------------------------
"$scripts/new-task.sh" T1 feat/t1 > /dev/null
[[ -d $tmp/repo-wt/T1 && -f $tasks/T1/task.md && -f $tasks/common.md ]] || fail "new-task layout"
expect_fail "$scripts/new-task.sh" T1 feat/t1
ok "new-task creates worktree, branch and task files and refuses a duplicate"
task T1 implement "feature.txt, src/*"

"$scripts/run-codex.sh" start T1 --dry-run | grep -q 'codex exec -C .* -s workspace-write' || fail "dry run"
[[ ! -e $tasks/T1/prompt.md ]] || fail "dry run wrote files"
"$scripts/run-codex.sh" start T1 > "$tmp/start.out"
grep -q "REPORT STATUS=DONE lines=2" "$tmp/start.out" || fail "report check"
grep -q "CODEX model=fake-model sandbox=workspace-write tokens=1234" "$tmp/start.out" || fail "codex meta"
grep -q "# Mode: implement" "$tasks/T1/prompt.md" || fail "mode instructions in prompt"
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
"$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" --dry-run | grep -q 'codex exec resume -c sandbox_mode=\\"workspace-write\\"' || fail "resume dry run"
"$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" > /dev/null
[[ -f $tasks/T1/report-r2.md && $(wc -l < "$tmp/repo-wt/T1/feature.txt") -eq 2 ]] || fail "resume round"
[[ -z $(git -C "$tmp/repo-wt/T1" diff --cached --name-only) ]] || fail "resume should unstage"
FAKE_BAD_REPORT=1 "$scripts/run-codex.sh" resume T1 "$tmp/feedback.md" > "$tmp/bad.out"
grep -q "no STATUS line" "$tmp/bad.out" && grep -q "90 lines exceed 80" "$tmp/bad.out" || fail "report drift warnings"
grep -q "REPORT HINT: .*run-codex.sh continue T1" "$tmp/bad.out" || fail "truncated-report recovery hint"
expect_fail "$scripts/run-codex.sh" resume T1 "$tmp/feedback.md"
grep -q "BREAKER: T1 already used 3 of MAX_ROUNDS=3" "$tmp/last.out" || fail "round breaker"
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

# --- investigate mode ----------------------------------------------------------
"$scripts/new-task.sh" Q1 inv/q1 > /dev/null
task Q1 investigate
"$scripts/run-codex.sh" start Q1 --dry-run | grep -q -- '-s read-only' || fail "investigate sandbox"
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
"$scripts/run-codex.sh" start O1 --dry-run | grep -q -- '-s danger-full-access' || fail "operate sandbox"
FAKE_NO_EDIT=1 "$scripts/run-codex.sh" start O1 > /dev/null
grep -q "# Mode: operate" "$tasks/O1/prompt.md" || fail "operate instructions"
"$scripts/run-gates.sh" O1 r1 > /dev/null
summary O1 r1 | grep -q "^UNCHANGED" && ! summary O1 r1 | grep -q "^harness" || fail "operate runs no gates"
"$scripts/finish-task.sh" O1 > "$tmp/o1f.out" && grep -q "operate task O1 delivers its report" "$tmp/o1f.out" || fail "operate delivery"
{ echo "# T5: bad"; echo; echo "Mode: implement"; echo "Sandbox: danger-full-access"; } > "$tmp/t5.md"
"$scripts/new-task.sh" T5 feat/t5 > /dev/null
cp "$tmp/t5.md" "$tasks/T5/task.md"
expect_fail "$scripts/run-codex.sh" start T5 --dry-run
grep -q "allowed only in operate mode" "$tmp/last.out" || fail "full access outside operate must refuse"
ok "operate needs an explicit sandbox, may use full access, runs no gates and commits nothing; other modes refuse full access"

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
grep -qE '^T1 +implement +3 +3702' "$tmp/status.out" || fail "ledger rounds and tokens: $(cat "$tmp/status.out")"
grep -q "TOTAL tokens=16042 full-reads=3/3" "$tmp/status.out" || fail "ledger totals: $(cat "$tmp/status.out")"
ok "ledger enforces MAX_FULL_READS and sums rounds and tokens per task"

# --- install.sh ----------------------------------------------------------------------
skills=$tmp/skills
"$here/install.sh" --dest "$skills" > /dev/null
[[ -f $skills/codex-delegation/SKILL.md && -x $skills/codex-delegation/scripts/doctor.sh ]] || fail "install copy"
expect_fail "$here/install.sh" --dest "$skills"
"$here/install.sh" --dest "$skills" --force --link > /dev/null
[[ -L $skills/codex-delegation ]] || fail "install link"
"$here/install.sh" --dest "$skills" --uninstall > /dev/null
[[ ! -e $skills/codex-delegation ]] || fail "uninstall"
mkdir -p "$tmp/proj"
"$here/install.sh" --project "$tmp/proj" > /dev/null
[[ -f $tmp/proj/.claude/skills/codex-delegation/SKILL.md ]] || fail "project install"
ok "install.sh copies, refuses overwrite, links with --force, uninstalls and installs per project"

echo "selftest: $pass checks passed"
