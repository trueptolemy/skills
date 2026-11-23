# <TASK-ID> acceptance feedback, round <N>

<Gates passed | Gates failed at: <gate> (<one-line reason from summary>)> in the
planner's clean run.

## Finding: <short title>

<What is wrong, why it matters (what it would let pass or hide), and where.>

Required change:

- <Concrete change.>
- <What must stay unchanged.>
- If <a legitimate obstacle>, do not work around it; report it under OPEN
  QUESTIONS with your diagnosis.

## Planner decision (only when the task stopped as BLOCKED or PARTIAL)

<Why the requested test change is a deliberate retirement of guarded behavior
and not a way to pass, and exactly which test, case and assertions may change,
with the property the replacement must still prove. Everything else stays
forbidden.>

No other file may change. Then rerun the focused tests and every gate, and send
the report in the same format, noting this round's change under SUMMARY and
quoting the exact before/after of any authorized test change.
<If this is the last allowed round: "This is the final review round for this
task.">
