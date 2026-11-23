
# Mode: refactor

Restructure code without changing observable behavior. Existing tests are the
specification: do not modify or delete any existing test file. You may add
tests that pin behavior before restructuring it. Acceptance fails on any change
to an existing test file and on any behavior change the gates detect.

Report, in this order:

```
STATUS: DONE | PARTIAL | BLOCKED
SUMMARY: at most 5 lines, including what was restructured and why it is safe
FILES: one line per changed or new file with +added/-removed lines
BEHAVIOR EVIDENCE: the commands and tests that show behavior is unchanged
TESTS ADDED: one line per pinning test: name — behavior it pins
GATES: one line per check you ran (focused tests, static checks): PASS or FAIL with a one-line reason
INVESTIGATION FINDINGS: facts you established for the listed unknowns, file:line
DEVIATIONS FROM CONTRACT: none, or each deviation and reason
OPEN QUESTIONS: anything the planner must decide
```
