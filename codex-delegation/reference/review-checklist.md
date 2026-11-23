# Per-round acceptance checklist

Read only the report, the gate summary and the targeted information below.
Count every full log or full diff read made for diagnosis.

## 1. Report and gates

- [ ] Read the `REPORT STATUS=... lines=...` line from `run-codex.sh` first; a
      warning there means asking for a conforming report, not reading it in
      full.
- [ ] The report STATUS is DONE. For PARTIAL or BLOCKED, read OPEN QUESTIONS
      first and decide per "BLOCKED and PARTIAL" in SKILL.md.
- [ ] The report is at most 80 lines, and its gate results come only from
      commands Codex ran in this session.
- [ ] My independent `gates-rN/summary.txt` ends with `DONE`, and the line
      before it is `RESULT PASS`. Its `GATESET` line names the full list
      before any delivery; a focused list suffices only for intermediate
      rounds and trial versions.
- [ ] A report with no STATUS line is a stopped round: check the log tail for
      an API error and use `run-codex.sh continue`, not a new feedback. After
      an API error, first close Codex and run
      `codex app-server daemon restart`.
- [ ] The first gate (harness or import-path check) passed, so the run tested
      this worktree.
- [ ] `SUPPRESSIONS added=0`, and generated output (build artifacts) matches
      the commit.
- [ ] The failing set equals the baseline, if a baseline failure was agreed.
- [ ] On failure, climb the diagnosis ladder: the summary's `fail:` lines, then
      `grep` one gate log. Record a whole-log or whole-diff view with
      `ledger.sh full-read` before doing it; a refusal stops all work.

## 2. Mode-specific acceptance

- [ ] The summary's `MODE` line matches the task, and the `CODEX ... sandbox=`
      line in `rounds.log` shows the requested sandbox.
- [ ] implement: targeted review below, plus evidence beyond the gates.
- [ ] refactor: no `TESTEDIT` lines; read the BEHAVIOR EVIDENCE section and
      look for behavior the tests cannot observe (timing, ordering, logging,
      error text).
- [ ] docs: no `NONDOC` lines; spot-check at least three CLAIMS VERIFIED
      entries against the cited file:line.
- [ ] operate: `UNCHANGED` in the summary; the report records code identity,
      every command with its exit code and bound, and host state before and
      after; score the results yourself against preregistered criteria.
- [ ] investigate: `UNCHANGED` in the summary; spot-check at least three
      VERIFIED findings with targeted reads or grep. A wrong VERIFIED finding
      fails the round; an INFERRED one must not be used as fact downstream.
- [ ] `WARNING ... test-skip markers`: each added skip is justified in the
      report, or it is a finding.

## 3. Scope of the change

- [ ] No `SCOPE` lines when the task declares Allowed paths; otherwise
      `git diff --cached --stat` shows only the contract's owning modules and no
      leftover temporary files.
- [ ] EXISTING TESTS TOUCHED in the report matches the authorization exactly.
      Check only the relevant hunks with `git diff --cached -- tests/<file>`.
- [ ] Changes to shared test helpers, fixtures or conftest: look for autouse
      fixtures, monkeypatched internals or conditional defaults that move
      existing tests off the production path.

## 4. Targeted review of risky changes

- [ ] Lines removed from legacy-path modules:
      `git diff --cached -U2 -- <module> | grep '^-'`; confirm legacy behavior
      is unchanged.
- [ ] Admission, policy and security-boundary changes: read hunk by hunk;
      the old path must be equivalent, and the new path either stricter or
      active only behind the new switch.
- [ ] New assertions that compare a result with itself: require a literal or
      an independent source.
- [ ] Golden or historical-bytes fixtures: recompute with the pre-change code
      and compare.
- [ ] Text sent to a model or outside (errors, prompts, logs): bounded in
      length, with no input values, secrets or process state.
- [ ] Prompt or evaluation assets: grep for the development case's
      identifiers and numbers; no leak and no bias toward one answer. Grep
      task.md and feedback for them too, before launching.
- [ ] Module line counts, complexity and contract file sizes are not
      approaching project limits.

## 5. Evidence beyond the gates (the planner supplies what Codex cannot)

- [ ] Run new producers or views on real data and compare with an
      independent analysis.
- [ ] Pure-replay or compatibility-check real historical archives; their
      verdicts must not change.
- [ ] Record what remains unexercised in the commit message and the final
      summary.

## 6. Decision

- [ ] Pass: write the commit message with fresh evidence only (rewrite
      Codex's "not run" evidence with your gate results), then run
      `finish-task.sh`.
- [ ] Stacked or rewritten history: one combined full gate on the stacked
      result, and `git diff <gated> HEAD` empty after any rewrite.
- [ ] Fail: write `feedback.md` with a concrete Required change per finding,
      run `run-codex.sh resume`, and increment the round count.
- [ ] Update the ledger: rounds, my gate failures, planner decisions, full
      reads.
