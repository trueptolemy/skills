---
name: codex-delegation
description: Plan, delegate and independently accept multi-task code changes executed by the OpenAI Codex CLI (`codex exec`) in isolated git worktrees, with Claude acting only as planner and acceptor. Use when the user asks to hand implementation or investigation to Codex, wants Claude to only plan and review, asks to run codex exec in the background, or wants a Codex task loop with independent gates, feedback rounds and circuit breakers. Not for tasks Claude implements directly.
---

# Codex delegation: Claude plans and accepts, Codex executes

This workflow comes from real delegations: first seven implementation tasks
and thirteen Codex rounds, then a longer program of about thirty tasks,
including real-system stages, trial branches and combined integration gates.
Scripts are in `scripts/`, templates in `templates/`,
detailed traps in [reference/pitfalls.md](reference/pitfalls.md) and the
per-round acceptance checklist in
[reference/review-checklist.md](reference/review-checklist.md).

## Roles and authority

| Role | Owns | Does not do |
|---|---|---|
| Claude (this session) | Plan, task.md, launching Codex, reading reports, independent acceptance, feedback, commit and fast-forward, ledger; trivial merge-conflict resolution in documents or imports, followed by tests | Write product code; investigate after planning; read Codex's full log or full diff (except a counted diagnosis) |
| Codex | Implementation and all post-planning investigation (the task's Unknowns); operate stages the user authorized | Commit, push, call models, touch real systems outside an authorized operate stage |
| User | Approve the plan and ADRs, test-change exceptions, paid sessions, real-system work and pushes | — |

Authorization covers only what the user named. "Execute follow-up decisions"
covers decisions that arise during execution, not paid runs, real-system work
or pushes. State every decision you took under that authority in the final
summary.

## When to delegate, and how much ceremony

Delegation costs a task file, a Codex round (often 30 to 180 minutes), an
independent gate run and a review. Do the work directly when it is a few lines,
needs tight interactive iteration with the user, or its acceptance cannot be
checked independently. Choose the lightest flow that keeps acceptance honest:

| Flow | Use for | Artifacts |
|---|---|---|
| Lite | One self-contained task | `task.md`, gates, report, commit; no proposal or ADR. Breakers, gates and review still apply |
| Standard | Several related tasks | Plus a short plan with the task table and agreed exceptions |
| Strict | Changes to safety, measurement or persisted contracts | Plus change contract, ADR draft, golden fixtures and real-data checks |

## Task modes

The first lines of `task.md` declare the mode, optional scope globs, an
optional sandbox override, an optional quiet flag and an optional round
limit; the scripts read them:

```text
Mode: implement | refactor | docs | investigate | operate
Allowed paths: src/area/*, tests/area/*, docs/area.md
Sandbox: read-only | workspace-write | danger-full-access
Quiet: yes
Max rounds: 5
```

| Mode | Sandbox | Codex instructions and report | Mechanical acceptance (`run-gates.sh`) | Planner acceptance |
|---|---|---|---|---|
| implement | `CODEX_SANDBOX` | `templates/modes/implement.md` | scope, gates, suppressions | targeted review, evidence beyond gates |
| refactor | `CODEX_SANDBOX` | `refactor.md`: behavior evidence, pinning tests | no existing `TEST_PATHS` file modified or deleted; scope, gates | look for behavior change the tests cannot see |
| docs | `CODEX_SANDBOX` | `docs.md`: every claim cited | only `DOC_PATHS` files changed; gates | spot-check cited claims against the code |
| investigate | read-only | `investigate.md`: VERIFIED/INFERRED findings | worktree unchanged; no gates | spot-check VERIFIED findings; one wrong one fails the round |
| operate | explicit `Sandbox:` line required | `operate.md`: narrow stop rules, no signals, generous bounds | worktree unchanged; no gates | score results yourself; check host state and code identity |

`Allowed paths` makes "only the owning modules changed" a mechanical check; a
staged file outside the globs fails acceptance. A list narrower than the
change needs costs a whole BLOCKED round: cover the owning modules and their
adjacent selection, entry and policy modules, and name the files of parallel
sibling tasks that must not change. Use an investigate task for
post-planning questions whose answer decides later tasks; it costs no gate run
and cannot change the tree. Override a mode's instructions per project in
`<tasks>/modes/<mode>.md`.

`Quiet: yes` marks a task that runs while a timing-sensitive measurement or
operate stage uses the same host. `run-codex.sh` appends `templates/quiet.md`
(no tests, builds or benchmarks) and `pipeline.sh` runs no gates. Code written
this way usually fails its first focused check, so budget one more round.

## Permissions: full access and what replaces the sandbox

The configuration template runs the write modes (implement, refactor, docs)
with `CODEX_SANDBOX=danger-full-access` and `ALLOW_FULL_ACCESS=yes`. Every
round runs with approval policy `never`: Codex installs, builds, tests and
uses the network like a developer, and nothing waits for an approval nobody
can give. Without `ALLOW_FULL_ACCESS=yes` the scripts refuse full access
outside operate tasks, both as `CODEX_SANDBOX` and in a task's `Sandbox:`
line. Investigate tasks stay read-only unless their task.md says otherwise.
They must not write anything anyway.

`codex exec` is non-interactive and has no `--ask-for-approval` flag. The
scripts therefore pass `-c sandbox_mode="..."` and
`-c approval_policy="never"`, which `codex exec` and `codex exec resume` both
accept. `--dangerously-bypass-approvals-and-sandbox` would set both at once,
but it cannot keep investigate tasks read-only. After a CLI upgrade, run
`doctor.sh` and, with the user's approval, `doctor.sh --smoke`.

What the sandbox guaranteed, and what replaces it:

| workspace-write guarantee | Under danger-full-access |
|---|---|
| No commit, branch change or `.git` edit | The repository guard after every round (refs, branches, config, exclude, hooks) |
| The main checkout and other worktrees stay untouched | The repository guard (main checkout and idle task worktrees) |
| No ssh to real systems | `common.md` forbids it outside operate tasks. Those rounds also run without `SSH_AUTH_SOCK` and with git over ssh refused, but a key file that ssh reads directly is not blocked |
| No writes to the home directory (`~/.ssh`, tool configuration) | `common.md` only; not checked |
| No network for commands | `common.md` forbids network access from tests and scripts, and web search; not checked |

Set `CODEX_SANDBOX=workspace-write` for a project where the rows that rest on
rules alone are not acceptable.

## Gates: focused checks per round, one full gate per delivery

A full gate list can take hours. Run it once per delivery, not per round:

- Codex runs only focused tests and fast static checks for the files it
  changed (`common.md`).
- `pipeline.sh start|resume|continue <id>` runs Codex and then, when the
  report says DONE, the full gate list (`run-gates.sh <id> r<N>`) and the
  mechanical diff checks. With `--focused` it runs `FOCUSED_GATES_FILE`
  instead: use that for intermediate rounds and trial versions. Every gate
  sees `CHANGED_FILES` (paths changed against the merge base).
- A PARTIAL or BLOCKED report gets no gates: the tree is unfinished, and the
  next step is your decision on its OPEN QUESTIONS, not a suite run on a
  known-incomplete state. When the gate result itself decides that step, add
  `--gates-anyway`, for example to check whether a PARTIAL round's remaining
  failures equal the baseline's. It never runs gates for a quiet,
  investigate or operate task, or after a failed Codex run or a GUARD FAIL.
- Several focus-tested branches that are delivered together get one combined
  full gate on their stacked result. A failure there is usually an
  integration defect, so fix it in a dedicated integration task instead of
  reopening the original ones.
- The full gate before any delivery to the base branch cannot be skipped.
- At most `MAX_PARALLEL_GATES` gate runs of one configuration execute at once
  (default 1, 0 = no limit); a later run waits, and its summary shows `QUEUED`
  and then `SLOT`. Parallel runs are not free: they compete for CPU, memory
  and I/O, so each one takes longer and timing-sensitive tests fail at random,
  and they share whatever is not per worktree (ports, caches, services). The
  queue time is part of a round's wall time, so start the next round's work,
  not another gate run, while one runs.

## Token economy: the exchange protocol

The two sides exchange only bounded artifacts. Each one has an owner and a size
limit.

| Artifact | Direction | Bound |
|---|---|---|
| `task.md` + `common.md` | Claude to Codex, once per task | Contract, Unknowns and properties; reference repository documents by path instead of pasting them |
| `feedback.md` | Claude to Codex, per round | Findings with Required changes, sent into the recorded session with `resume`, so earlier context is not sent again |
| `report.md` | Codex to Claude | At most 80 lines, STATUS first, file:line instead of pasted code; `run-codex.sh` prints `REPORT STATUS=... lines=...` and warns on drift |
| `gates-rN/summary.txt` | script to Claude | One line per gate, plus up to ten `FAIL_PATTERN` lines for each failed gate |
| targeted diff | repository to Claude | `git diff --cached --stat`, then named files or hunks only |

Rules:

- Planning-phase code mapping runs in read-only exploration subagents with
  structured, bounded reports (for example at most 120 lines with file:line),
  several in parallel. The main context keeps conclusions, not file dumps.
  After planning, investigation belongs to Codex.
- Do not poll; every check costs a turn. Wait for completion notifications.
  Durations vary by project: Codex rounds took 30 to 180 minutes, and one full
  gate suite took 25 minutes in one project and about 110 in another. Record
  your project's numbers in the ledger.
- When you filter a script's output, keep its `error:` and `BREAKER` lines
  (for example `grep -E 'REPORT|CODEX|WARN|HINT|BREAKER|error'`): a filtered
  refusal looks like a silent failure.
- Diagnosis ladder: summary, then the FAIL lines in the summary, then a `grep`
  for a specific pattern in one gate log, and only then a full read. A full
  read is viewing a whole Codex log, a whole gate log or an unfiltered whole
  diff; it counts toward the circuit breaker. `--stat`, grep results and named
  hunks do not.
- Resume instead of restarting: a new session re-reads the repository and the
  rules, while a resumed one keeps its findings.
- Carry names, modules and constants forward in "Notes from earlier tasks" so
  neither side rediscovers them.
- Keep `common.md` stable across tasks. Forbid web search there; it is
  instruction-level only, so also check your Codex configuration.
- If `report_check` warns of an over-long report, ask for a conforming report
  in the next feedback instead of reading a malformed one in full. A report
  with no STATUS line that reads like a progress note means the round stopped
  early. Check the log tail for an API error; if there is one, follow
  "API errors" below, otherwise run `run-codex.sh continue <id>`.
- Track cost per task: `run-codex.sh` records each round's model, effort,
  applied sandbox and `tokens used` in `rounds.log`; `scripts/ledger.sh status`
  sums them with rounds, report status and gate result.
- Every round of a task, start and resume alike, passes the same Codex
  arguments: the sandbox, `CODEX_MODEL`, `CODEX_EFFORT` and `CODEX_EXTRA_ARGS`.
  A resumed round given fewer arguments silently falls back to the global
  Codex configuration. `run-codex.sh` warns of model or effort drift when a
  round reports values other than the configured ones, or, when none are
  configured, other than round 1's. Treat a drift warning like a sandbox
  warning: the round did not run as configured.

## Phase 0: preflight (no model calls)

1. Copy `templates/codex-delegation.conf` to `<repo>-tasks/`; set `REPO`,
   `BASE_BRANCH`, `PRESET` (python, go, rust, java, javascript, cpp), `GATE_ENV`,
   `SETUP_HOOK`, `DELIVERY`, `MAX_ROUNDS` and `MAX_FULL_READS`; then
   `export CDL_CONF=...`. Copy `templates/gates.example` to `gates.txt` and list
   every required gate from the project's development process, starting with a
   harness check (for example that the imported package path lies inside
   `$WT`); the preset file lists suggested gates for its ecosystem. Copy
   `templates/focused.example` to `focused.txt` and adapt it: the tests for
   `CHANGED_FILES` and their consumers, plus fast static checks.
2. Run `scripts/doctor.sh`. It checks git, the Codex CLI version against the
   verified list and the exec/resume flags the scripts use, that every
   `CODEX_EXTRA_ARGS` flag is accepted by both `codex exec` and
   `codex exec resume`, and the project configuration, without calling a
   model. An unverified Codex version means the scripts' assumptions about its
   flags and log format are untested.
3. Authentication: `codex login status` reflects only an OpenAI account. With
   another provider configured in `~/.codex/config.toml` (for example Bedrock),
   "Not logged in" can be normal. Inspect the provider name without printing
   secrets. After the user approves, run `scripts/doctor.sh --smoke`: one tiny
   paid call with the arguments every round uses (read-only sandbox). It
   proves the model ID and effort the tasks will run and verifies the log
   lines the scripts parse.
4. **Validate the acceptance harness itself.** Run `new-task.sh baseline
   baseline-check`, then `run-gates.sh baseline r0` in the background. If the
   baseline is not green, either fix it as task T0 or agree with the user that
   the failing set must equal the baseline exactly. A clean checkout often
   exposes tests that depend on untracked local files.
5. Adapt the bracketed parts of `templates/common.md` (project rule files,
   forbidden actions, environment) into `<repo>-tasks/common.md`. Keep it
   stable across tasks.

## Phase 1: plan (do not start Codex before the user confirms)

For the lite flow, the plan is the `task.md` itself: show it to the user, and
start Codex only after they confirm it.

- Write a proposal: the evidence for the problem (only verified facts), a
  change contract (Goal / Non-goals / Invariants affected / Owning modules and
  documents / Acceptance evidence), a task table with each task's acceptance
  test names and the property each proves, and deferred items with reasons.
  Add an ADR draft when the project requires one.
- Agree up front on narrow test-change exceptions (for example "append-only
  additions to an enumerated allowlist"), circuit breakers (`MAX_ROUNDS`, `MAX_FULL_READS`), delivery (`DELIVERY`:
  ff-merge, branch-only for pull requests, or patch; never push without
  authorization), and commit author and co-author.
- After confirmation, land the plan documents as the first commit.

## Phase 2: decompose

- Serial by default. Run tasks in parallel only when their file sets are fully
  disjoint, including shared documents such as contracts, TODO and README.
- One worktree and branch per task, from the latest base:
  `new-task.sh <id> <branch>`.
- When a new abstraction gets its consumer only in a later task, chain the
  branches (`new-task.sh T2 ... --from <T1 branch>`), finish the earlier tasks
  with `finish-task.sh --no-merge`, and fast-forward them together once the
  first consumer passes.
- Split large tasks early, for example "shared machinery plus the first
  consumer" and "the second consumer".
- Every task needs falsifiable acceptance properties (test name plus property)
  and explicit legacy invariants (historical bytes, replay, defaults).

## Phase 3: one task loop

1. `scripts/new-task.sh <id> <branch> [--from <ref>]`. It refuses on low disk
   space or inodes (worktree root, `TMPDIR`, `/tmp`), refuses a task directory
   that already holds an earlier task, runs the setup hook, creates the
   worktree's temporary directory `.tmp/` and checks that the worktree is
   clean. Pick an unused id.
2. Write `<tasks>/<id>/task.md` from `templates/task.md`, starting with its
   Mode and Allowed paths header. `new-task.sh` does not create the file, so
   write it as a new file without reading a placeholder first;
   `run-codex.sh start` refuses a missing one or one that still holds the
   template's placeholders. Append names,
   constants and limits from earlier reports under "Notes from earlier tasks",
   list the questions Codex must investigate as Unknowns, and spell out every
   authorized exception.
3. Start Codex with Bash `run_in_background`:
   `scripts/pipeline.sh start <id>` (Codex, then gates and diff checks), or
   `scripts/run-codex.sh start <id>` for Codex alone. Wait for the completion
   notification.
4. Read the `REPORT STATUS=... lines=...`,
   `CODEX model=... effort=... sandbox=... tokens=...` and `GUARD` lines
   printed by `run-codex.sh` (a sandbox, model or effort warning means the
   round did not run as configured; a GUARD FAIL is a forbidden action, see
   "Repository guard"), then `report.md` (at most 80 lines).
5. Accept, following [review-checklist.md](reference/review-checklist.md):
   - read the gate summary `pipeline.sh` printed, or run
     `scripts/run-gates.sh <id> r<N>` in the background and read only
     `gates-r<N>/summary.txt`: the last line `DONE` means finished, the line
     before it `RESULT PASS` means passed;
   - inspect `git diff --cached --stat` and do targeted review of risky hunks.
     The gate runner stages the tree, so use `--cached`, and only after the
     summary shows its STAGED line; a plain diff during staging looks empty;
   - review for over-defensive code (checklist section 4): checks of values
     that are already guaranteed, branches for impossible states, catch-all
     handlers, silent fallbacks and options nobody asked for. Every gate
     passes them, so send each back as a finding that names what to delete
     and why it is unnecessary. Accepting the simpler implementation is the
     default;
   - add the evidence Codex cannot produce: run new producers on real data,
     pure-replay real historical archives, recompute golden fixtures with the
     pre-change code.
6. If it fails, write a feedback file from `templates/feedback.md` (one
   concrete Required change per finding, the files that may change, the
   focused checks to rerun, same report format) and run
   `scripts/pipeline.sh resume <id> <feedback>` in the background. The script
   unstages the tree, finds the session id and numbers the round.
7. If it passes, write the commit message from `templates/commit-msg.txt` with
   only fresh evidence and the unexercised parts. Codex's draft often says
   "tests not run" and may use another subject convention; rewrite its
   evidence with your own fresh gate results. Then run
   `scripts/finish-task.sh <id> msg.txt`. It requires a PASS summary, runs the
   message checks, commits and delivers per `DELIVERY`, then removes the clean
   worktree. An investigate or operate task commits nothing:
   `finish-task.sh <id>` checks the tree is unchanged and its report is the
   deliverable.
8. Update your copy of `templates/ledger.md`; `scripts/ledger.sh status` gives
   the rounds, tokens and gate state to copy.

## Repository guard

Codex may change only the files of its own worktree. `run-codex.sh`
snapshots the repository before and after every round and prints
`GUARD PASS`, or one `GUARD FAIL` line for each change outside the worktree:

- any ref except `refs/remotes` and `refs/prefetch`, which background fetches
  move: a commit, reset or stash, a branch created or deleted;
- the branch, or detached commit, of any worktree;
- the shared git `config`, `info/exclude` or hooks;
- tracked changes or untracked files in the main checkout, or in another task
  worktree whose own task ran no round or gate run in the meantime.

`new-task.sh` and `finish-task.sh` record the changes they make, so tasks
running in parallel do not trip each other's guard. A GUARD FAIL makes
`run-codex.sh` exit 5 and fails `run-gates.sh` and `finish-task.sh`. Treat it
as a forbidden action and stop all work. Only if you made that change
yourself while the round ran (for example a branch created by hand), record
it with `ledger.sh guard-ack <id> r<N> "<what you changed>"`; never
acknowledge a change you did not make. While rounds run, leave the main
checkout and idle worktrees alone: every change there is reported.

## BLOCKED and PARTIAL

- Codex stopping because of a forbidden action is correct behavior; it still
  counts as a round.
- Decide whether the expectation that must change belongs to guarded behavior
  this task **deliberately retires** (for example a "not yet supported, refuse"
  guard, or an intended change of representation).
  - Yes: grant a narrow exception naming the file, test and case, the property
    the replacement must still prove, that nothing else may change, and that
    the report quotes the exact before and after.
  - No: require an implementation fix, not a test change.
- Never authorize rewriting expectations, adding suppressions or moving
  existing tests off the production path in order to pass.
- Rounds are saved by authorizing the predictable cases in task.md up front
  (see the optional clause in `templates/task.md`): assertions of a default the
  task changes, of the literal text of a message it changes, or of a refusal
  it removes may change only to the new value. In one program four BLOCKED
  rounds were exactly these cases.

## API errors: close Codex, restart the daemon, relaunch

An API error (for example an HTTP 429 or 5xx status, a disconnected stream or
repeated reconnect attempts) either ends a round before its report or leaves
Codex retrying while its log stops growing. Check the round's log tail
(`tail -n 20`; this is not a full read). If it shows an API error:

1. Close Codex. Stop the background job that runs the round (Claude Code:
   TaskStop), then check with `pgrep -a codex` that no `codex exec` of this
   task is left; a resumed round runs in the worktree
   (`readlink /proc/<pid>/cwd`). In an operate stage, first check that no
   operation Codex started is still running.
2. Run `codex app-server daemon restart`.
3. Void the round the error broke, so it does not count toward the round
   breaker: `scripts/ledger.sh void <id> r<N> "<the error>"`.
4. Restart Codex in the same session, in the background:
   `scripts/pipeline.sh continue <id>` (or `run-codex.sh continue <id>`). It
   sends a standard "finish and write the report" message, so no feedback file
   is needed and the session keeps its findings.

If other Codex tasks run in parallel, check them after the restart and continue
any whose round stopped. If the same error returns after one restart, stop and
report it to the user: authentication, quota or the provider configuration is
then the likely cause, and further restarts will not fix it.

## Operate stages (real systems, only with the user's authorization)

An operate task runs a hardware measurement, a deployment or another long
real-system operation through Codex with `Mode: operate` and an explicit
`Sandbox:` line. Each lesson below cost a whole stage once:

- Before the stage, dry-check offline everything it will be refused for:
  admission of the exact parameters with the code under test, the presence of
  the configuration it names, and free disk space.
- List the differences from the last successful run, such as a worktree path
  instead of the main checkout or a new parameter value. Resolve each one
  before launching.
- Stop rules are narrow: a non-zero exit of a command the stage started, or a
  host-state difference. A refusal or error inside a running operation is
  that operation's own business. Codex never signals a running command.
- Bounds exist only against hangs. Set them in hours or days, never from the
  duration of an earlier run.
- Nothing else that loads the host runs during the stage: use `Quiet: yes` for
  parallel Codex tasks and do not run gates.
- Score the results yourself. Keep any known answers out of task.md,
  feedback and every prompt that the system under evaluation can see.

## Trial branches and history

- Iterations that must not reach the base branch (for example trial versions
  of a prompt or a tuning parameter) live on a trial branch as commits.
  Intermediate versions get focused checks only. Squash the final version into
  one commit for delivery, then run the full gate on the result.
- After rewriting history, prove that the new head is tree-identical to the
  commit that passed the gate (`git diff <gated> HEAD` is empty) before you
  deliver it.
- Never switch branches or rewrite history in a worktree that a running
  background job uses: the job can load files from an intermediate state.
  Use a separate worktree.

## Circuit breakers (defaults; the user may override)

- A forbidden action (including a GUARD FAIL you did not cause), cheating to
  pass (rewritten expectations, suppressions) or a gate regression the
  planner cannot explain: **stop all work**.
- `MAX_ROUNDS` (default 3) Codex rounds for one task without acceptance: stop
  that task without committing. `run-codex.sh resume` and `continue` refuse a
  further round with exit code 3. A task whose size the user approved with
  the plan may set its own limit with `Max rounds:` in task.md. Do not raise
  a limit while a task runs.
- A round that failed because of the environment, not its work (an API
  error, a full disk or exhausted inodes, a provider outage), does not count
  once you record it with `scripts/ledger.sh void <id> r<N> "<reason>"`. The
  reason is kept in `<id>/void.log` and `ledger.sh status` counts the voids.
  Never void a round whose code or report was wrong, and list every void in
  the final summary.
- More than `MAX_FULL_READS` (default 3) full log or full diff reads for
  diagnosis: stop all work. Record each one first with
  `scripts/ledger.sh full-read <id> <what>`, which refuses with exit code 3 once
  the limit would be exceeded; do not perform a refused read.
- On any stop, keep the worktrees and give a status report.

## Waiting, background work and hygiene

- Run every long job (Codex, gates, replays) with `run_in_background` and wait
  for its notification. **Never** use `cmd &` plus `pgrep -f`: the waiter's own
  command line matches the pattern and never exits. If polling is unavoidable,
  check for the `DONE` line in the summary.
- When asked whether something is stuck: check that the process is alive and
  its elapsed time, whether the log grows between two samples, the worktree's
  change count and whether the report exists. Do not read the log body.
- Remove each worktree as soon as its task is merged; every worktree is a full
  checkout, and nine of them once filled the disk.
- Make gates import the worktree's code (`GATE_ENV`) and link untracked
  dependencies with `SETUP_HOOK`.
- Codex and every gate get `TMPDIR` and `PYTEST_DEBUG_TEMPROOT` pointing to
  the worktree's own `.tmp/` (ignored through the shared `info/exclude`), so
  parallel runs neither fill a shared `/tmp` nor remove each other's
  directories, and the files go with the worktree. Delete scratch directories
  left elsewhere (for example by real-data checks) once the round is accepted.

## Final summary

Per task: Codex rounds, voided rounds with their reasons, your own gate
failures, planner decisions, failures Codex reported, and the cumulative count
of full reads for diagnosis. Add your
own mistakes (for example harness errors), an assessment of Codex quality (rule
compliance, investigation depth, test design, test-integrity problems caught
only in review, over-defensive code and over-engineering, overly conservative
constants), every
unexercised item, and the next steps that need separate authorization.
