# <TASK-ID>: <one-line goal>

Mode: implement
Allowed paths: src/<area>/*, tests/<area>/*, docs/<owning-document>.md

<!-- Header fields are read by the scripts from the first 30 lines.
     Mode: implement | refactor | docs | investigate | operate
       investigate runs read-only; operate runs an authorized real-system stage
       and needs an explicit Sandbox line.
     Allowed paths: optional comma-separated globs; `*` also matches '/'. A staged
       file outside them fails acceptance. Cover the owning modules and their
       adjacent selection and entry modules; name sibling tasks' files to avoid
       instead of narrowing the list. Remove the line to disable the check.
     Sandbox: optional read-only | workspace-write | danger-full-access override;
       danger-full-access needs Mode: operate or ALLOW_FULL_ACCESS=yes.
     Quiet: yes when a measurement runs on the same host; Codex then runs no
       tests or builds and the pipeline runs no gates for that round.
     Max rounds: optional per-task round limit instead of MAX_ROUNDS, set when
       the user approves the plan; rounds voided with ledger.sh void do not
       count. -->

The common rules are appended below this task and bind it. This branch starts
from <base commit or previous task branch>. <What earlier tasks added that this
task must reuse, with module and function names.>

## Contract

```text
Goal:
  <The observable outcome that changes.>
Non-goals:
  <Explicit exclusions, especially work that later tasks own.>
Invariants affected:
  <What must remain true even if tests are updated: legacy bytes, replay,
  admission, defaults, security boundaries, refusal behavior.>
Owning modules and documents:
  <Files to change and the documents that own the changed facts.>
Acceptance evidence:
  The tests below and every required gate.
```

## Unknowns to investigate and report

1. <A question the planner did not verify; Codex answers it with file:line.>
2. <Where an input lives, which consumers depend on a structure, ...>

## Required design points

- <Constraints that are decisions, not research: reuse X instead of a second
  implementation; bound Y and disclose the remainder; refuse Z loudly.>

## Acceptance properties

Each test docstring states the cost of failure.

- `test_<property_name>`: <the property it proves, including the failure path>.
- `test_<legacy_property>`: <historical behavior that must stay identical>.

## Authorized exceptions

<None, or exactly which existing test may change and how, for example
"append the new file names to the enumerated set in tests/test_policy.py::
test_prompt_files; change nothing else in that test".>

<Optional standard clause, when the task deliberately changes a default or
retires a refusal: "Existing assertions that name the previous default
(version, pin, file name), the literal text of a message this task changes,
or a refusal this task deliberately removes may change only to the new
value or the new admitted behavior. Quote each before and after under
EXISTING TESTS TOUCHED. Nothing else in existing tests may change.">

## Notes from earlier tasks

<Names, pins, constants and limitations established by earlier reports.>
