# Traps observed in practice (trap / root cause / fix)

Every entry happened, or was caught in acceptance, during real Codex
delegations: first seven implementation tasks and thirteen Codex rounds, then
a program of about thirty tasks that included real-system stages, trial
branches and combined integration gates.

## Waiting and background work

**A waiter never exits.**
- Trap: gates were started with `cmd &` and awaited with
  `while pgrep -f "run-gates.sh <wt>"; do sleep; done`. The gates had long
  finished, but the wait never returned.
- Root cause: the waiter's own command line contains the matched string, so
  `pgrep -f` always matches itself. A process started with `&` inside a tool
  call is also orphaned and produces no completion notification.
- Fix: start long jobs with `run_in_background` and wait for the notification.
  If polling is unavoidable, check only whether the summary's last line is
  `DONE`.

**"Is it stuck?"**
- Fix: do not read the log body. Check, in order:
  1. whether the process is alive and its `etime`;
  2. whether the log grows between two samples;
  3. the worktree's change count;
  4. whether the report file exists.

**A filtered failure looks silent.**
- Trap: a background launcher filtered the script output to
  `REPORT|CODEX|WARN`, and two refusals (a reused task directory, a feedback
  copy error) came back as a bare `rc=1` or an old report.
- Root cause: the scripts print refusals as `error: ...` on stderr, and the
  filter removed them.
- Fix: keep `error:`, `BREAKER` and `HINT` lines in every filter
  (`pipeline.sh` does).

**A round stops before its report.**
- Trap: twice a round ended with a one-line progress note as its "report"
  (`REPORT STATUS=UNKNOWN`), and once a provider HTTP 500 ended the first
  request of a long run.
- Fix: check the log tail for an API error. If there is one, close Codex
  (stop the round's background job and check that no `codex exec` of the
  task is left), run `codex app-server daemon restart`, then restart Codex
  with `run-codex.sh continue <id>`, which sends a standard "finish and write
  the report" message into the same session. Without an API error, run
  `continue` directly. The procedure is in "API errors" in SKILL.md.

**Environment failures use up the round limit.**
- Trap: API errors and an exhausted `/tmp` ended rounds whose work was not at
  fault, and each of them counted toward `MAX_ROUNDS`. The limit was then
  raised by hand to continue, which left no record of why.
- Fix: void such a round with `ledger.sh void <id> r<N> "<reason>"`; it stops
  counting toward the breaker, and its reason stays in `void.log`. A task the
  user approved as larger sets `Max rounds:` in its task.md instead of a
  global change.

**A background job reads a worktree whose branch changed.**
- Trap: a verification job ran from a worktree in which the planner then
  checked out another branch and cherry-picked commits. The job could load
  modules from an intermediate tree, so its result was void.
- Fix: never switch branches or rewrite history in a worktree that a running
  job uses; create a separate worktree for history work.

## Token economy

**Polling burns turns.**
- Trap: checking a running job every few minutes costs a model turn each
  time and adds nothing.
- Fix: wait for completion notifications. Note typical durations (a Codex
  round 30 to 90 minutes, a large gate suite about 25 minutes) so that
  "stuck" is judged against data.

**Code mapping floods the main context.**
- Trap: reading many files to write the plan fills the planner's context with
  dumps.
- Fix: map in parallel read-only exploration subagents that return bounded
  reports with file:line. After planning, give every remaining question to
  Codex as an Unknown.

**A failing gate tempts a full log read.**
- Fix: climb the diagnosis ladder: summary, then its FAIL lines (copied there
  by `run-gates.sh`), then `grep` one log for a pattern. Only a whole-log or
  whole-diff view counts as a full read toward the breaker.

**Restarting Codex instead of resuming.**
- Trap: a fresh session re-reads the repository and rules for every round.
- Fix: send `feedback.md` into the recorded session with `run-codex.sh resume`.

**Codex searches the web.**
- Trap: a Codex configuration can enable web search (`web_search = "live"`),
  spending tokens on material the repository already holds.
- Fix: `common.md` forbids it. That is an instruction, not enforcement, so
  also check the Codex configuration you run with.

**Reports drift from the protocol.**
- Trap: a report wrapped in a code fence or grown past the limit costs more to
  read and hides the STATUS.
- Fix: `run-codex.sh` prints `REPORT STATUS=... lines=...` and warns; ask for a
  conforming report in the feedback instead of reading a malformed one in full.

## The acceptance harness itself

**The gates test another checkout.**
- Trap: pytest in a worktree tested the main checkout's code.
- Root cause: an editable install's `.pth` put the main checkout's `src` on
  `sys.path`.
- Fix: set `PYTHONPATH=$WT/src` in `GATE_ENV` and make "the imported package
  path lies inside `$WT`" the first gate.

**A worktree lacks dependencies.**
- Trap: untracked installed trees such as `node_modules` do not exist in a new
  worktree.
- Fix: symlink them and add the path to the shared `info/exclude`. A
  `node_modules/` `.gitignore` rule (with the slash) matches only directories,
  not a symlink, so without the exclude entry the worktree shows as dirty.

**The disk fills up.**
- Trap: nine coexisting worktrees (each a full checkout of about 1.2 GB) filled
  `/home`, and the next checkout stopped halfway.
- Fix: remove each worktree once its task is merged and clean. `new-task.sh`
  refuses below `MIN_FREE_GB`.

**Temporary files fill a small `/tmp`.**
- Trap: on a host whose `/tmp` was a tmpfs with a limited number of inodes,
  the temporary files of gate runs and of Codex's checks used up its inodes
  while the disk still had space. Gate runs in parallel shared `/tmp` and also
  removed each other's temporary directories.
- Root cause: the space check looked only at the worktree root, and every run
  used the system temporary directory.
- Fix: Codex and every gate get `TMPDIR` and `PYTEST_DEBUG_TEMPROOT` set to the
  worktree's own `.tmp/`, which the shared `info/exclude` ignores and which is
  removed with the worktree. `new-task.sh` and `doctor.sh` check free space
  and inodes of the worktree root, of `TMPDIR` and of `/tmp`; `df` reports no
  inode count on some filesystems, and the check then says so.

**The baseline is not green.**
- Trap: in a clean checkout one test read an untracked operator configuration
  file and failed; the main checkout had the file, so it had always passed.
- Fix: run every gate on a clean worktree of the base before starting. If it is
  not green, either fix it as T0 or agree with the user that the failing set
  must equal the baseline exactly.

**`git diff` is empty.**
- Root cause: the gate runner ran `git add -A`, so every change is staged. A
  plain `git diff` taken just after starting the gates races with the staging.
- Fix: review with `git diff --cached` once the summary shows its STAGED line.
  Unstage with `git reset -q` before resuming Codex; `run-codex.sh resume` does
  this.

**An old task id is reused.**
- Trap: a task id from an earlier program still had its directory, with
  `rounds.log` and `report.md`. `new-task.sh` reused it, and `run-codex.sh start`
  refused because `report.md` existed. The filtered output showed only the
  old report, which looked like the new result, and the planner overwrote the
  old `task.md`.
- Fix: `new-task.sh` now refuses such a directory unless `--reuse-task` is
  given. Check `ls <tasks>/<id>` before choosing an id.

**A feedback file named like its archive copy.**
- Trap: `run-codex.sh resume` copies the feedback to `feedback-rN.md`; a file
  already named that way was copied onto itself and the round never started.
- Fix: the script now skips a same-path copy. Prefer descriptive feedback
  names (`feedback-coverage.md`) anyway.

**Every round paid for the full suite twice.**
- Trap: Codex ran every gate before reporting and the planner ran them again;
  with a two-hour suite each round cost four hours of gates, and trial versions
  paid the same.
- Fix: Codex runs focused checks only; `pipeline.sh` runs the full list once
  per delivery and `--focused` for intermediate rounds (see SKILL.md, Gates).

**Tests run while a measurement uses the same host.**
- Fix: mark parallel tasks `Quiet: yes`. Codex then writes code without running
  anything heavy, and the planner runs the focused checks after the
  measurement. Expect that round's code to fail its first check.

**Branches that passed alone fail together.**
- Trap: two features that each passed their focused tests broke six tests
  once stacked: a retention check classified the other feature's legitimately
  imported files as missing.
- Fix: run one combined full gate on the stacked branches and repair failures
  in a dedicated integration task.

**Reverting a file after a gate run does nothing.**
- Root cause: the gate runner staged the tree, and `git checkout -- <file>`
  restores the staged copy, not the committed one.
- Fix: restore from the commit with `git checkout HEAD -- <file>` (or
  `git restore --source=HEAD --staged --worktree <file>`). `run-codex.sh resume`
  unstages first, so Codex sees its changes against HEAD.

## Operate stages (real systems)

**A stop rule killed a live operation.**
- Trap: the stage said "stop if a runtime check refuses". Six and a half hours
  into a model-driven investigation, a calculation tool refused one call, and
  the model had already corrected the call. Codex interrupted the run.
- Fix: stop only on a non-zero exit of a command the stage started, or on a
  host-state difference; never signal a running command (`operate.md`).

**A bound sized from an earlier run.**
- Trap: a seven-hour bound, chosen because an earlier run took seven hours,
  ended a longer run in its fourth experiment.
- Fix: bounds protect against hangs only. Use hours or days.

**The runtime environment differed from the last good run.**
- Trap: the first run from a worktree failed at once, because the guest
  executed a helper from the host asset path, and that path pointed into the
  worktree.
- Fix: before launching, list the differences from the last successful run
  and resolve each one; here, point the asset root at the main checkout after
  checking that the assets are identical.

**Refusals that a dry check would have caught.**
- Trap: two stages refused at preflight: a benchmark missing from an
  allowlist, then an odd worker count.
- Fix: run the admission function with the exact parameters on the code under
  test before every stage. Prefer deleting refusals that protect nothing.

**Answers leak into the evaluation.**
- Fix: keep known answers out of task.md, feedback and every prompt the
  evaluated system can see; grep them for the case's identifiers before
  launching.

## Codex CLI

**"Not logged in" does not mean unusable.**
- Root cause: `codex login status` reflects only an OpenAI account. With
  Bedrock or another provider, authentication comes from the environment.
- Fix: read `model_provider` in `~/.codex/config.toml` without printing
  secrets, and run one-line smoke call after the user approves.

**Resume rejects flags.**
- Root cause: `codex exec resume` has no `-s` or `-C` flag.
- Fix: pass the sandbox with `-c sandbox_mode="workspace-write"`, run from the
  worktree, and take the session id from the first round log's `session id:`
  line.

**A resumed round runs another model.**
- Trap: the first round passed `CODEX_EXTRA_ARGS` (a model and a reasoning
  effort) but resume did not, so every later round ran the global default
  model and effort. Nothing failed, and the smoke call, which also ignored
  `CODEX_EXTRA_ARGS`, had verified a model no task used.
- Fix: every round and the smoke call build their arguments from one list
  (`codex_args`); set the model and effort with `CODEX_MODEL` and
  `CODEX_EFFORT`. `run-codex.sh` compares each round's `model:` and
  `reasoning effort:` header lines with them (or with round 1) and warns of
  drift. Extra flags must be ones `codex exec resume` accepts too; `doctor.sh`
  checks them.

**`codex exec` rejects `--ask-for-approval`.**
- Trap: `codex exec --ask-for-approval never` (or `-a never`) fails with
  "unexpected argument". The flag belongs to the interactive CLI;
  `codex exec` never asks for approval.
- Fix: pass `-c approval_policy="never"`, which `codex exec` and
  `codex exec resume` both accept, as the scripts do for every round.

**Who may commit.**
- Under workspace-write, Codex cannot write the shared `.git`. Under
  danger-full-access it can, and only `common.md` and the repository guard
  stop it. The planner commits.
- Consequence: tracked-file checks do not see files Codex created, so stage the
  tree before running gates in acceptance.

## Test integrity: invisible to gates, caught only in review

**Self-referential assertions.**
- Trap: a configuration was compared with its own class defaults, so a commit
  that changed both the model default and a gate default still passed.
- Fix: pin literal values, state in the docstring that a deliberate change must
  update the pin, and keep a negative control.

**An autouse fixture moves existing tests off the production path.**
- Trap: an autouse fixture for a whole test module monkeypatched an internal
  function, so existing tests ran on a configuration production can no longer
  reach. No assertion changed and every gate passed.
- Fix:
  - run every existing test unmodified on the production configuration first;
  - let only tests whose property concerns the earlier interface opt in
    explicitly, with a stated reason;
  - report any test that fails on the production configuration instead of
    editing it.

**Golden fixtures for "historical bytes unchanged".**
- Risk: expected values generated by the new code prove nothing.
- Fix: recompute the fixture's expected bytes with the pre-change code (for
  example the main checkout) and compare them byte for byte.

**Assertions after a projection change.**
- Risk: comparing a projection with the same projection function is
  self-referential.
- Fix: add at least one independently derived check, such as the ID set
  matching the store or a limitation roster derived separately.

## Planning and scale

**Tasks are too large.**
- Fix: split early into "shared machinery plus the first consumer" and "the
  second consumer". When a new abstraction gets its consumer only later, chain
  the branches (T2 from T1, T3 from T2) and fast-forward them together after
  the first consumer passes.

**Allowed paths narrower than the change.**
- Trap: two rounds ended BLOCKED because the change also had to touch an
  adjacent entry or policy module outside the list.
- Fix: cover the owning modules and their selection, entry and policy
  neighbours; name sibling tasks' files to avoid instead.

**Predictable test-change questions.**
- Trap: four rounds ended BLOCKED to ask whether an assertion of the old
  default, an old message or a retired refusal could change.
- Fix: authorize exactly these cases in task.md up front (the template's
  optional clause), always with quoted before and after.

**Simplification removes little.**
- Trap: two rounds asking to "delete defensive branches" removed 78 net lines
  out of several thousand added.
- Fix: require an inventory first (each branch, why normal data never reaches
  it, its dedicated tests) and a measurable target. Accept diminishing returns
  instead of spending further rounds. Large reductions need a design change.

**Overly conservative constants.**
- Trap: under a byte bound, Codex reduced an overview to a single row, which
  made it nearly useless.
- Fix: check key constants against the purpose during acceptance. If needed,
  make enlarging them part of a later task's scope instead of editing existing
  tests.

**A module approaches its size limit.**
- Fix: tell the next task in task.md to put new contracts in another module.

**Codex cannot reach the real data.**
- Fix: the planner runs new producers on real data and pure-replays real
  archives. This is the most valuable acceptance evidence beyond the gates.

**Prompts or evaluation assets leak the answer.**
- Fix: grep new prompts for the development case's identifiers and numbers, and
  keep checklists balanced and unranked.

## Generality

**The requested sandbox is not the applied one.**
- Trap: a wrong flag, a configuration default or a CLI change can run a task
  with more write access than its mode allows.
- Fix: `run-codex.sh` reads the `sandbox:` and `approval:` lines of the Codex
  log header and warns when they differ from the request; check them before
  accepting.

**Tests are skipped instead of fixed.**
- Trap: adding a skip marker turns a failing test into a passing gate without
  any suppression comment.
- Fix: each preset's `SKIP_PATTERN` flags added skip markers in the summary for
  review; the report must justify each one.

**The CLI changed under the scripts.**
- Trap: the scripts parse Codex flags and log lines verified on one version;
  a newer CLI can rename them silently.
- Fix: `doctor.sh` checks the version against the verified list and probes the
  flags; `doctor.sh --smoke` (paid, ask first) verifies the parsed log lines.

**One heavy process for every task.**
- Trap: a proposal, ADR and multi-round review for a twenty-line fix costs more
  than doing it.
- Fix: choose the lite, standard or strict flow in SKILL.md, or do the work
  directly.

## Rule conflicts

**Codex stops as BLOCKED because of a forbidden action.**
- This is correct behavior.
- Decide whether the expectation belongs to guarded behavior this task
  deliberately retires (for example a "not yet supported, refuse" guard).
  - Yes: grant a narrow exception naming the test and case, with the property
    the replacement must prove.
  - No: require an implementation fix.
- Never authorize changing expectations in order to pass.
