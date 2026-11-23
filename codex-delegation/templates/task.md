# <TASK-ID>: <one-line goal>

Mode: implement
Allowed paths: src/<area>/*, tests/<area>/*, docs/<owning-document>.md

<!-- Header fields are read by the scripts from the first 30 lines.
     Mode: implement | refactor | docs | investigate (investigate runs read-only).
     Allowed paths: optional comma-separated globs; `*` also matches '/'. A staged
     file outside them fails acceptance. Remove the line to disable the check.
     Sandbox: optional read-only | workspace-write override. -->

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

## Notes from earlier tasks

<Names, pins, constants and limitations established by earlier reports.>
