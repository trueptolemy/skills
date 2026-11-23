# codex-delegation: Claude plans and accepts, Codex executes

A Claude Code skill that keeps Claude in the **planner and acceptor** role and
hands implementation and post-planning investigation to the OpenAI Codex CLI
(`codex exec`). Each task runs in its own git worktree; the main session runs
the gates independently, gives round-numbered feedback, applies explicit
circuit breakers and fast-forwards accepted work without pushing. It is also a
token-economy protocol: both sides exchange only bounded artifacts (task file,
80-line report, gate summary, targeted diffs).

It was distilled from a real delegation of seven implementation tasks and
thirteen Codex rounds; the traps met along the way are in
`codex-delegation/reference/pitfalls.md`.

## Layout

```
install.sh                 install into Claude Code (user or project level)
selftest.sh                run every script against a temporary repo and a fake codex
codex-delegation/
  SKILL.md                 when to delegate, flows, task modes, token economy, acceptance, breakers
  scripts/
    doctor.sh              check git, Codex CLI version and flags, and the project setup (no model call)
    new-task.sh            worktree, branch and task directory (disk check, setup hook, clean check)
    run-codex.sh           start or resume Codex in the background; mode sandbox, round breaker,
                           report shape, applied sandbox and token count
    run-gates.sh           mode checks, scope, gates, suppressions, skip markers; summary ends with DONE
    finish-task.sh         require PASS, check the message, commit, deliver, remove the worktree
    ledger.sh              full-read breaker and per-task rounds, tokens and gate state
    lib.sh                 shared configuration and helpers
  templates/
    codex-delegation.conf  per-project configuration
    presets/               python, go, rust, java, javascript, cpp pattern defaults and gate hints
    modes/                 Codex instructions and report formats for implement, refactor, docs, investigate
    gates.example          gate list examples
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
./selftest.sh                       # optional: offline self-test, no model calls
./install.sh                        # user level: ~/.claude/skills/codex-delegation
./install.sh --project /path/repo   # or project level: /path/repo/.claude/skills/codex-delegation
./install.sh --link                 # symlink to this checkout while editing the skill
./install.sh --force                # replace an installed copy
./install.sh --uninstall            # remove it
./install.sh --dry-run              # validate and print the actions only
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

The first lines of each `task.md` declare `Mode:` (implement, refactor, docs or
investigate) and optionally `Allowed paths:` globs. Investigate tasks run in a
read-only sandbox and deliver their report; refactor tasks may not edit
existing tests; docs tasks may change only documentation; any staged file
outside `Allowed paths` fails acceptance. `DELIVERY` in the configuration
selects ff-merge, branch-only (for pull requests; pushing still needs
authorization) or patch.

## One task loop (summary)

```bash
$S/new-task.sh T1 codex/t1-foo                 # chained task: --from codex/t0-bar
# edit /path/repo-tasks/T1/task.md
$S/run-codex.sh start T1                       # background; read only T1/report.md
$S/run-gates.sh T1 r1                          # background; read only T1/gates-r1/summary.txt
$S/run-codex.sh resume T1 feedback.md          # on failure: resume with feedback
$S/finish-task.sh T1 commit-msg.txt            # on success: commit, deliver, remove worktree
$S/ledger.sh status                            # rounds, tokens, report and gate state per task
```

The full workflow, acceptance checklist, BLOCKED/PARTIAL handling and circuit
breakers are in `codex-delegation/SKILL.md`.

## Safety boundaries

- Codex runs in the `workspace-write` sandbox: writes only in the worktree, no
  network for its commands, and no write access to the shared `.git`, so it
  cannot commit. The main session commits.
- The scripts never push, never use sudo, and call no model except the
  configured Codex in `run-codex.sh`.
- `finish-task.sh` commits only when the newest gate summary says
  `RESULT PASS`, and merges only with `--ff-only`.
- Paid sessions, real-system work and pushes need separate user
  authorization; the skill grants no permission.
