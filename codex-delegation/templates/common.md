
# Common rules for every Codex task

<!-- Planner: adapt the bracketed parts once per project, then keep this file
     stable across tasks. run-codex.sh appends it after each task.md. -->

You are implementing one task of an approved plan in this git worktree. The
planner reviews your result independently and reads only your final report.
You do all investigation the task needs; report what you established.

## Read first, in this order

1. The repository's agent rules: [AGENTS.md / CLAUDE.md]. Every rule applies.
2. The development process: [docs/DEVELOPMENT.md or equivalent], completely,
   including required gates and test-design rules.
3. The approved plan and decision records: [paths].
4. The owning code, tests and documents named in the task, and the known-issue
   list [TODO.md section].

## Forbidden

You may run without a sandbox. These rules are then the only boundary. After
every round the planner checks the repository's refs, worktree branches,
shared git files and other checkouts, and any change there fails the task.

- [Real-system work: deployments, hardware runs, production databases, ...].
- `ssh`, `scp`, `rsync` over ssh or any other remote access to another host,
  in particular [the real systems: systems under test, production hosts],
  unless this is an operate task that names the host and the commands.
- `sudo` or any privilege escalation.
- `git commit`, `git push`, `git merge`, `git rebase`, `git stash`,
  `git reset`, `git checkout` or `git switch` of another branch or commit,
  `git worktree`, `git config`, installing git hooks, or any other edit under
  `.git`. Leave every change in the working tree.
- Writing outside this worktree: other worktrees, the main checkout, the home
  directory (`~/.ssh`, shell profiles, tool and Codex configuration) or
  system locations.
- Installing, upgrading or removing packages or tools, in a shared
  environment or globally. Report a missing dependency under OPEN QUESTIONS.
- Any model or provider call, nested agent session, or network access from
  tests and scripts. Do not use web search: the repository, its documents and
  this task contain what you need; ask under OPEN QUESTIONS instead.
- Reading, writing or referencing [private paths, operator config files,
  real data directories]. Build every fixture synthetically.
- Changing an existing test's expected value, deleting or weakening an
  assertion, or deleting a test, unless the task names the exact test and
  change as an authorized exception. If you believe another one must change,
  stop and explain it under OPEN QUESTIONS.
- Changing shared test helpers or fixtures in a way that moves existing tests
  off the production path (autouse fixtures, monkeypatching internals,
  conditional defaults) without stating it under EXISTING TESTS TOUCHED.
- Any suppression or pragma (`noqa`, `type: ignore`, lint disables, coverage
  exclusions) or relaxing project tool policy.
- Changing defaults, historical versions or replay of existing data unless
  the task says so explicitly.

## How to write the code

Implement directly: write the simplest code that meets the contract, and reuse
what the repository already has. The planner reviews for over-defensive code
and sends it back.

- Validate untrusted input once, where it enters (user input, files, network,
  external tools). Inside the program, trust the callers, the types and the
  checks that already ran; do not check them again.
- No branches for states that cannot occur, no catch-all exception handlers,
  and no silent fallbacks or defaults that turn an error into plausible
  output. A state that should be impossible fails loudly.
- No options, parameters, wrappers or abstraction layers the task does not
  ask for.
- A branch that no test can reach without faking an impossible state is
  dead code: delete it instead of writing such a test.

## Environment

- [Interpreter and how to make it import this worktree, for example
  `PYTHONPATH="$PWD/src" /path/.venv/bin/python`, with the check command.]
- [Untracked dependencies are symlinked; do not reinstall them.]
- Temporary files: `TMPDIR` and `PYTEST_DEBUG_TEMPROOT` point to `.tmp/` in
  this worktree, which git ignores. Keep every scratch file there, not under
  `/tmp` or the home directory, and do not change these variables.
- Run focused checks while working and before reporting: the tests for every
  file you changed and their direct consumers, plus the fast static checks on
  the changed files. Do not run the full test suite; the planner runs the full
  gate list once, independently, after your round. New untracked files are not
  seen by tracked-file checks; list them in the report instead of staging them.

## Report

Your final message is the report, at most 80 lines, starting with the STATUS
line. Its sections are defined by the mode instructions appended below.

Report only results of commands you actually ran in this session. Name
anything you did not exercise. Do not paste code, diffs or logs into the
report: cite file:line, test names and one-line command outcomes. The planner
reads only this report, so a finding that is not in it does not exist.

Reuse the names, modules and constants listed in the task's "Notes from earlier
tasks" instead of rediscovering them. When feedback arrives in this same
session, change only what it asks for and keep your earlier findings.

Stopping with BLOCKED is correct when the task cannot be completed without
breaking a rule.
