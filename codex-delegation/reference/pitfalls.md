# Traps observed in practice (trap / root cause / fix)

Every entry happened, or was caught in acceptance, during a real Codex
delegation of seven implementation tasks and thirteen Codex rounds.

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

**Reverting a file after a gate run does nothing.**
- Root cause: the gate runner staged the tree, and `git checkout -- <file>`
  restores the staged copy, not the committed one.
- Fix: restore from the commit with `git checkout HEAD -- <file>` (or
  `git restore --source=HEAD --staged --worktree <file>`). `run-codex.sh resume`
  unstages first, so Codex sees its changes against HEAD.

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

**Codex cannot commit.**
- The workspace-write sandbox cannot write the shared `.git`. That is good: the
  planner commits.
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
- Fix: `run-codex.sh` reads the `sandbox:` line of the Codex log header and
  warns when it differs from the request; check it before accepting.

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
