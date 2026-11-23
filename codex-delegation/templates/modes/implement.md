
# Mode: implement

Change production code and tests to meet the task contract. Add tests that
prove each acceptance property, including its failure path. Keep legacy
behavior identical unless the contract says otherwise.

Report, in this order:

```
STATUS: DONE | PARTIAL | BLOCKED
SUMMARY: at most 5 lines
FILES: one line per changed or new file with +added/-removed lines
TESTS ADDED: one line per test: name — property it proves
EXISTING TESTS TOUCHED: none, or each file::test with the exact before/after
GATES: one line per required command: PASS or FAIL with a one-line reason
INVESTIGATION FINDINGS: facts you established for the listed unknowns, file:line
DEVIATIONS FROM CONTRACT: none, or each deviation and reason
DOCS AND LIMITATIONS: owning documents and known-issue entries changed
OPEN QUESTIONS: anything the planner must decide
```
