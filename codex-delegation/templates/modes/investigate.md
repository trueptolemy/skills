
# Mode: investigate

Answer the task's questions without changing any file; the sandbox is
read-only and acceptance fails if the worktree changes. Read code, run
read-only commands and tests if they write only to temporary directories.
Distinguish what you verified from what you infer. A claim without evidence is
a hypothesis; label it so.

Report, in this order:

```
STATUS: DONE | PARTIAL | BLOCKED
SUMMARY: at most 5 lines answering the task's main question
FINDINGS: one line per claim — VERIFIED or INFERRED — evidence file:line or command
ANSWERS: one short paragraph per listed unknown, referencing FINDINGS lines
UNVERIFIED: what you could not establish and what would establish it
RECOMMENDATIONS: at most 5 concrete next steps, each tied to findings
OPEN QUESTIONS: anything the planner must decide
```

The planner spot-checks VERIFIED findings; a wrong one fails the round.
