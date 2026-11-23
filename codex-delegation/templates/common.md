
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

- [Real-system work: deployments, hardware runs, production databases, ...].
- `sudo` or any privilege escalation.
- `git commit`, `git push`, `git merge`, `git rebase`, `git stash`, branch
  changes, or edits under `.git`. Leave every change in the working tree.
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

## Environment

- [Interpreter and how to make it import this worktree, for example
  `PYTHONPATH="$PWD/src" /path/.venv/bin/python`, with the check command.]
- [Untracked dependencies are symlinked; do not reinstall them.]
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
