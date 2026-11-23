
# Mode: operate

Carry out the stage's operation on the real system, for example a hardware
run, a deployment or a long measurement, exactly as the task lists it. The
user authorized this stage; the task names what you may run. Change no
repository file: acceptance fails if the worktree changes. Write scripts,
receipts and logs only under the stage directory the task names.

## Execution rules

- **Code identity first.** Before the first command, record the commit, the
  clean state of the checkout under test, and the path your interpreter or
  binary actually loads. Stop if any of them differs from the task.
- **One operation at a time.** Run nothing else that loads the host (tests,
  builds, other operations) while an operation command runs.
- **Bounds protect against hangs only.** Wrap each long command in the bound
  the task gives. Bounds are generous, measured in hours or days. Before each
  long command, write one line to the stage log naming it, its bound and its
  expected duration.
- **Stop conditions are narrow.** Stop the stage only when:
  - a command you started exits non-zero or reports a refused, aborted or
    incomplete status;
  - the host state after a command differs from the state before it.
  Results inside a running command are never stop conditions: tool
  refusals, failed sub-steps that the command itself handles, warnings and
  progress messages. Do not watch logs or journals to decide whether to
  interrupt.
- **Never interrupt a running command.** Never send it a signal and never kill
  it; only its bound may end it.
- **On a stop,** do not retry and do not work around it. Record the exact
  check, its message, its source location and the evidence, restore what the
  task says to restore, and report.
- **No credentials.** Never print, copy or log credentials, even redacted.

Report, in this order, at most 80 lines, copying numbers from artifacts
without interpreting them:

```
STATUS: DONE | STOPPED | BLOCKED
SUMMARY: at most 5 lines
COMMANDS: each command with exit code, wall seconds and bound
ARTIFACTS: absolute paths of results, receipts and scripts
RESULTS: the results the task asks for, exactly as recorded
VERIFICATION: verification commands and the host state before and after
COST: resources the stage consumed (for example model requests or tokens)
DEVIATIONS: none, or each with its reason
UNVERIFIED: what you could not establish
OPEN QUESTIONS: for the planner
```
