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
optional sandbox override and an optional quiet flag; the scripts read them:

```text
Mode: implement | refactor | docs | investigate | operate
Allowed paths: src/area/*, tests/area/*, docs/area.md
Sandbox: read-only | workspace-write | danger-full-access (operate only)
Quiet: yes
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

## Gates: focused checks per round, one full gate per delivery

A full gate list can take hours. Run it once per delivery, not per round:

- Codex runs only focused tests and fast static checks for the files it
  changed (`common.md`).
- `pipeline.sh start|resume|continue <id>` runs Codex and then, when the
  report says DONE, the full gate list (`run-gates.sh <id> r<N>`) and the
  mechanical diff checks. With `--focused` it runs `FOCUSED_GATES_FILE`
  instead: use that for intermediate rounds and trial versions. Every gate
  sees `CHANGED_FILES` (paths changed against the merge base).
- Several focus-tested branches that are delivered together get one combined
  full gate on their stacked result. A failure there is usually an
  integration defect, so fix it in a dedicated integration task instead of
  reopening the original ones.
- The full gate before any delivery to the base branch cannot be skipped.

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
- Track cost per task: `run-codex.sh` records each round's model, applied
  sandbox and `tokens used` in `rounds.log`; `scripts/ledger.sh status` sums
  them with rounds, report status and gate result. Optional cost lever:
  per-task model or effort through `CODEX_EXTRA_ARGS`.

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
   verified list and the exec/resume flags the scripts use, and the project
   configuration, without calling a model. An unverified Codex version means
   the scripts' assumptions about its flags and log format are untested.
3. Authentication: `codex login status` reflects only an OpenAI account. With
   another provider configured in `~/.codex/config.toml` (for example Bedrock),
   "Not logged in" can be normal. Inspect the provider name without printing
   secrets. After the user approves, run `scripts/doctor.sh --smoke`: one tiny
   paid call that also verifies the log lines the scripts parse.
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
   space, refuses a task directory that already holds an earlier task, runs
   the setup hook and checks that the worktree is clean. Pick an unused id.
2. Write `<tasks>/<id>/task.md` from `templates/task.md`, starting with its
   Mode and Allowed paths header. Append names,
   constants and limits from earlier reports under "Notes from earlier tasks",
   list the questions Codex must investigate as Unknowns, and spell out every
   authorized exception.
3. Start Codex with Bash `run_in_background`:
   `scripts/pipeline.sh start <id>` (Codex, then gates and diff checks), or
   `scripts/run-codex.sh start <id>` for Codex alone. Wait for the completion
   notification.
4. Read the `REPORT STATUS=... lines=...` and `CODEX ... sandbox=... tokens=...`
   lines printed by `run-codex.sh` (a sandbox warning means the run did not get
   the requested isolation), then `report.md` (at most 80 lines).
5. Accept, following [review-checklist.md](reference/review-checklist.md):
   - read the gate summary `pipeline.sh` printed, or run
     `scripts/run-gates.sh <id> r<N>` in the background and read only
     `gates-r<N>/summary.txt`: the last line `DONE` means finished, the line
     before it `RESULT PASS` means passed;
   - inspect `git diff --cached --stat` and do targeted review of risky hunks.
     The gate runner stages the tree, so use `--cached`, and only after the
     summary shows its STAGED line; a plain diff during staging looks empty;
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
3. Restart Codex in the same session, in the background:
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

- A forbidden action, cheating to pass (rewritten expectations, suppressions)
  or a gate regression the planner cannot explain: **stop all work**.
- `MAX_ROUNDS` (default 3) Codex rounds for one task without acceptance: stop
  that task without committing. `run-codex.sh resume` refuses a further round
  with exit code 3.
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
- Delete scratch directories that Codex's real-data checks leave under `/tmp`
  once the round is accepted, and stale test temporary directories only while
  no gate runs.

## Final summary

Per task: Codex rounds, your own gate failures, planner decisions, failures
Codex reported, and the cumulative count of full reads for diagnosis. Add your
own mistakes (for example harness errors), an assessment of Codex quality (rule
compliance, investigation depth, test design, test-integrity problems caught
only in review, over-engineering or overly conservative constants), every
unexercised item, and the next steps that need separate authorization.
