# Delegation ledger

Breakers: rule violation, cheating (rewritten expectations, suppressions) or
an unexplained gate regression stops all work; MAX_ROUNDS Codex rounds without
acceptance stop one task without committing (run-codex.sh resume enforces it);
more than MAX_FULL_READS full log/diff reads for diagnosis stop all work
(ledger.sh full-read enforces it). Keep worktrees on any stop. Fill the table
from `scripts/ledger.sh status`.

| Task | Mode | Branch / commit | Codex rounds | Tokens | My gate failures | Planner decisions | Full reads | Notes |
|---|---|---|---|---|---|---|---|---|
| T0 | | | | | | | | |

Full log/diff reads for diagnosis: 0 / MAX_FULL_READS

## Codex quality notes

- Rule compliance (stopped as BLOCKED/PARTIAL instead of working around rules):
- Investigation depth (file:line findings, verified claims):
- Test design (golden data from pre-change code, negative controls):
- Test integrity problems caught only in review:
- Over-engineering or overly conservative constants:
