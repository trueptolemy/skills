
# Mode: docs

Change documentation only. Every factual claim must be verified against the
current code, configuration or a command you ran; cite file:line for it. Do not
change source, configuration or tests: acceptance fails on any non-documentation
file. If a document and the code disagree, report it instead of changing code.

Report, in this order:

```
STATUS: DONE | PARTIAL | BLOCKED
SUMMARY: at most 5 lines
FILES: one line per changed document with +added/-removed lines
CLAIMS VERIFIED: one line per changed factual claim — evidence file:line or command
CODE/DOC DISAGREEMENTS: none, or each disagreement found and left unresolved
GATES: one line per check you ran (focused tests, static checks): PASS or FAIL with a one-line reason
OPEN QUESTIONS: anything the planner must decide
```
