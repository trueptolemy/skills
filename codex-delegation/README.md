# codex-delegation: Claude plans and accepts, Codex executes

A Claude Code skill that keeps Claude in the **planner and acceptor** role and
hands implementation and post-planning investigation to the OpenAI Codex CLI
(`codex exec`). Each task runs in its own git worktree; the main session runs
the gates independently, gives round-numbered feedback, applies explicit
circuit breakers and fast-forwards accepted work without pushing. It is also a
token-economy protocol: both sides exchange only bounded artifacts (task file,
80-line report, gate summary, targeted diffs).

It was distilled from real delegations, first seven implementation tasks and
thirteen Codex rounds, then a program of about thirty tasks with real-system
stages, trial branches and combined integration gates. The traps met along
the way are in [reference/pitfalls.md](reference/pitfalls.md).

## Layout

Paths are relative to this directory (`codex-delegation/` in the skill
repository); `install.sh` is shared at the repository root.

```
SKILL.md                 when to delegate, flows, task modes, token economy, acceptance, breakers
README.md                this file
tests/
  selftest.sh            run every script against a temporary repo and a fake codex
scripts/
  doctor.sh              check git, Codex CLI version and flags, and the project setup (no model call);
                         --smoke makes one paid call with the round arguments
  new-task.sh            worktree, branch and task directory (space and inode checks, setup hook,
                         per-worktree .tmp/, clean check)
  run-codex.sh           start, resume or continue Codex in the background with the same
                         arguments every round; mode sandbox, round breaker, report shape,
                         applied sandbox, model and effort drift, token count, and a
                         repository guard (refs, branches, shared git files, other checkouts)
  run-gates.sh           mode checks, guard, scope, full or focused gates with CHANGED_FILES,
                         at most MAX_PARALLEL_GATES runs at once, suppressions, skip markers;
                         summary ends with DONE
  pipeline.sh            one background round: Codex, then gates and diff checks
  finish-task.sh         require PASS, check the message, commit, deliver, remove the worktree
  ledger.sh              full-read breaker, guard-ack, void (environment-failed rounds),
                         and per-task rounds, tokens, guard and gate state
  lib.sh                 shared configuration and helpers
templates/
  codex-delegation.conf  per-project configuration
  presets/               python, go, rust, java, javascript, cpp pattern defaults and gate hints
  modes/                 Codex instructions and report formats for implement, refactor, docs,
                         investigate and operate (authorized real-system stages)
  gates.example          full gate list examples
  focused.example        focused gate list example (changed files and their consumers)
  quiet.md               appended for `Quiet: yes` tasks: no test or build runs
  setup-worktree.example.sh  symlink hook for untracked dependencies
  common.md              rules sent to Codex with every task (adapt once per project)
  task.md                task template: contract, unknowns, properties, exceptions
  feedback.md            acceptance feedback template
  commit-msg.txt         commit message template
  ledger.md              ledger and Codex quality assessment
reference/
  pitfalls.md            trap / root cause / fix
  review-checklist.md    per-round acceptance checklist
```

## Requirements

- Claude Code
- OpenAI Codex CLI (`codex`) authenticated for its configured provider
- bash and git (the setup-hook example's `--path-format` needs git 2.31 or later)

Verified on Linux with bash 5.2 and GNU coreutils; macOS is untested.

## Install

```bash
git clone <this-repo> ~/skill && cd ~/skill
./codex-delegation/tests/selftest.sh                       # optional: offline self-test, no model calls
./install.sh --skill codex-delegation                      # user level: ~/.claude/skills/codex-delegation
./install.sh --skill codex-delegation --project /path/repo # or project level: /path/repo/.claude/skills/
./install.sh --skill codex-delegation --link               # symlink to this checkout while editing the skill
./install.sh --skill codex-delegation --force              # replace an installed copy
./install.sh --skill codex-delegation --uninstall          # remove it
./install.sh --skill codex-delegation --dry-run            # validate and print the actions only
```

Start a new Claude Code session to load the skill. Invoke it with
`/codex-delegation`, or ask Claude to hand the work to Codex while it only
plans and reviews.

## One-time setup per project

```bash
mkdir -p /path/repo-tasks && cd /path/repo-tasks
cp ~/.claude/skills/codex-delegation/templates/codex-delegation.conf .
cp ~/.claude/skills/codex-delegation/templates/gates.example gates.txt
cp ~/.claude/skills/codex-delegation/templates/common.md .
# Edit the three files: REPO, BASE_BRANCH, PRESET, GATE_ENV, SETUP_HOOK,
# DELIVERY and the breaker limits; every required project gate; the bracketed
# parts of common.md (rule files, forbidden actions, environment).
export CDL_CONF=/path/repo-tasks/codex-delegation.conf
~/.claude/skills/codex-delegation/scripts/doctor.sh   # no model call; --smoke makes one tiny paid call
```

Validate the acceptance harness first by running the gates on a clean worktree
of the base. These scripts are long jobs: in Claude Code, run them with
`run_in_background`.

```bash
S=~/.claude/skills/codex-delegation/scripts
$S/new-task.sh baseline check/baseline
$S/run-gates.sh baseline r0      # read /path/repo-tasks/baseline/gates-r0/summary.txt
```

## Task modes and delivery

The first lines of each `task.md` declare `Mode:` (implement, refactor, docs,
investigate or operate) and optionally `Allowed paths:` globs, `Sandbox:` and
`Quiet: yes`.
- Investigate tasks run in a read-only sandbox and deliver their report.
- Operate tasks run an authorized real-system stage with an explicit sandbox,
  change no repository file and deliver their report.
- Refactor tasks may not edit existing tests.
- Docs tasks may change only documentation.
- Any staged file outside `Allowed paths` fails acceptance.
- Quiet tasks run no tests while a measurement uses the host. `DELIVERY` in the configuration
selects ff-merge, branch-only (for pull requests; pushing still needs
authorization) or patch.

## One task loop (summary)

```bash
$S/new-task.sh T1 codex/t1-foo                 # chained task: --from codex/t0-bar
# edit /path/repo-tasks/T1/task.md
$S/pipeline.sh start T1                        # background: Codex, then the full gates and diff checks
$S/pipeline.sh resume T1 feedback-x.md --focused   # intermediate round: focused gates only
$S/ledger.sh void T1 r2 "provider HTTP 500"    # after an API error: close Codex, run
                                               # `codex app-server daemon restart`, void the round
$S/run-codex.sh continue T1                    # a round stopped before its report: finish it
$S/run-gates.sh T1 r3                          # full gates alone; read only T1/gates-r3/summary.txt
$S/finish-task.sh T1 commit-msg.txt            # on success: commit, deliver, remove worktree
$S/ledger.sh status                            # rounds, tokens, report and gate state per task
```

The full workflow, acceptance checklist, BLOCKED/PARTIAL handling and circuit
breakers are in [SKILL.md](SKILL.md).

## Safety boundaries

- Write modes run in the sandbox that `CODEX_SANDBOX` names, and every round
  runs with approval policy `never`. The configuration template uses
  `danger-full-access` and sets `ALLOW_FULL_ACCESS=yes`; without that opt-in,
  the scripts refuse full access outside operate tasks. Investigate tasks run
  read-only. SKILL.md ("Permissions") lists what replaces the sandbox's
  guarantees: the repository guard, rules in `common.md`, and no ssh agent and
  no git over ssh outside operate tasks. The main session commits.
- After every round a guard compares the repository's refs, worktree
  branches, shared git files and other checkouts with their state before the
  round. Any change outside the task's worktree fails acceptance and delivery.
- The scripts never push, never use sudo, and call no model except the
  configured Codex in `run-codex.sh`.
- `finish-task.sh` commits only when the newest gate summary says
  `RESULT PASS`, and merges only with `--ff-only`.
- Paid sessions, real-system work and pushes need separate user
  authorization; the skill grants no permission.
